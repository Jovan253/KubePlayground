"""
KubePlayground API — a read-mostly view of a Kubernetes cluster.

Runs in two modes, and the difference is the whole point of M3:

  * OUT-OF-CLUSTER (now)  — a process on your laptop, authenticating with your
    kubeconfig. It inherits *your* permissions, which are cluster-admin.
  * IN-CLUSTER (M3)       — a process in a Pod, authenticating with a token the
    kubelet mounts into the container. It inherits the permissions of its
    ServiceAccount, which you will deliberately keep minimal.

The application code is identical either way. Only `load_config()` below changes
behaviour, and it decides by looking for a file that only exists inside a Pod.
"""

from __future__ import annotations

import copy
import datetime as dt
import logging
import os
from typing import Any

from pathlib import Path

import yaml
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from kubernetes import client, config
from kubernetes.client.rest import ApiException
from pydantic import BaseModel, Field

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
log = logging.getLogger("kubeplayground")

# Refuse to start against anything but this context when running locally.
# Set KUBE_CONTEXT="" to disable the guard (don't).
#
# Was "rancher-desktop" until 2026-08-30; the local cluster is now Docker
# Desktop's built-in Kubernetes. The guard matters more, not less, once EKS
# is in this kubeconfig alongside the sandbox.
EXPECTED_CONTEXT = os.getenv("KUBE_CONTEXT", "docker-desktop")


def load_config() -> str:
    """Authenticate to the API server. Returns a human-readable mode string.

    In-cluster, the kubelet mounts a ServiceAccount token at
    /var/run/secrets/kubernetes.io/serviceaccount/. `load_incluster_config()`
    finds it and raises ConfigException if it isn't there — which is how we
    detect that we're running on a laptop instead.
    """
    try:
        config.load_incluster_config()
        log.info("authenticated in-cluster via ServiceAccount token")
        return "in-cluster"
    except config.ConfigException:
        pass

    contexts, active = config.list_kube_config_contexts()
    active_name = active["name"]

    # Safety rail. Originally because this kubeconfig also held the employer's
    # AKS cluster; that context is gone from this machine, but the guard stays
    # for when EKS lands next to the sandbox. Scaling a Deployment in the wrong
    # cluster via a stray API call would be a bad afternoon.
    if EXPECTED_CONTEXT and active_name != EXPECTED_CONTEXT:
        available = ", ".join(c["name"] for c in contexts)
        raise RuntimeError(
            f"Refusing to start: active kubeconfig context is {active_name!r}, "
            f"expected {EXPECTED_CONTEXT!r}. Available: {available}. "
            f"Run: kubectl config use-context {EXPECTED_CONTEXT}"
        )

    config.load_kube_config(context=EXPECTED_CONTEXT or None)
    log.info("authenticated out-of-cluster via kubeconfig context %r", active_name)
    return f"kubeconfig:{active_name}"


MODE = load_config()

# --------------------------------------------------------------------------
# Who am I?
#
# A container cannot work out its own Pod's name. The image is byte-identical
# across every replica, and the name is assigned by the API server at creation
# time — so there is nothing inside the container that distinguishes it.
#
# The DOWNWARD API is how a Pod is told facts about itself: the kubelet reads
# them off the Pod object and injects them, as env vars (here) or as files in a
# volume. Note the direction — this is the cluster describing the Pod to
# itself, not the app querying the API. It needs no RBAC at all.
#
# This is what lets the UI mark its own Pod. The app runs inside the cluster it
# is drawing, which is the entire point of the project, and without this it is
# invisible in its own output.
#
# All three are None when the manifest doesn't set them — running from a laptop,
# for instance — and the UI just omits the highlight.
# --------------------------------------------------------------------------
SELF = {
    "podName": os.getenv("POD_NAME"),
    "podNamespace": os.getenv("POD_NAMESPACE"),
    "nodeName": os.getenv("NODE_NAME"),
}

core_v1 = client.CoreV1Api()
apps_v1 = client.AppsV1Api()
version_api = client.VersionApi()

app = FastAPI(
    title="KubePlayground API",
    description="Reads a live Kubernetes cluster and exposes it to the browser.",
    version="0.1.0",
)

# Only needed while the frontend is opened as a local file. Once FastAPI serves
# the frontend itself (M5) this is same-origin and could be dropped.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# --------------------------------------------------------------------------
# Error handling
#
# Every kubernetes-client call can raise ApiException. The status code carries
# real meaning and you want it surfaced verbatim rather than swallowed:
#
#   403  RBAC says no. In M3 this is what a missing verb looks like.
#   404  the object doesn't exist.
#   409  conflict — something else changed it since you read it.
# --------------------------------------------------------------------------
def k8s_call(fn, *args, **kwargs):
    try:
        return fn(*args, **kwargs)
    except ApiException as exc:
        log.warning("kubernetes API error %s: %s", exc.status, exc.reason)
        raise HTTPException(
            status_code=exc.status,
            detail=f"Kubernetes API: {exc.reason}",
        ) from exc


def since(ts: dt.datetime | None) -> float | None:
    """Seconds elapsed since a server-set timestamp (which is always UTC)."""
    if ts is None:
        return None
    return (dt.datetime.now(dt.timezone.utc) - ts).total_seconds()


def age_seconds(obj: Any) -> float | None:
    """Seconds since the object was created."""
    return since(getattr(obj.metadata, "creation_timestamp", None))


# NOTE: these are `def`, not `async def`, on purpose. The kubernetes client is
# blocking; FastAPI runs plain `def` handlers in a threadpool so one slow API
# call doesn't stall the event loop. Making these `async def` would be a bug.


@app.get("/api/health")
def health() -> dict:
    """Liveness/readiness target. In M6 this becomes an actual probe."""
    return {"status": "ok", "mode": MODE}


@app.get("/api/cluster")
def cluster_info() -> dict:
    v = k8s_call(version_api.get_code)
    nodes = k8s_call(core_v1.list_node)
    return {
        "mode": MODE,
        "version": f"{v.major}.{v.minor}",
        "gitVersion": v.git_version,
        "platform": v.platform,
        "nodeCount": len(nodes.items),
        # Populated by the downward API — see SELF above.
        "self": SELF,
    }


@app.get("/api/namespaces")
def list_namespaces() -> list[dict]:
    ns = k8s_call(core_v1.list_namespace)
    return [
        {
            "name": n.metadata.name,
            "phase": n.status.phase,
            "labels": n.metadata.labels or {},
            "ageSeconds": age_seconds(n),
        }
        for n in ns.items
    ]


@app.get("/api/nodes")
def list_nodes() -> list[dict]:
    nodes = k8s_call(core_v1.list_node)
    out = []
    for n in nodes.items:
        conditions = {c.type: c.status for c in (n.status.conditions or [])}
        out.append(
            {
                "name": n.metadata.name,
                # A Node is Ready when its kubelet has posted a healthy status
                # recently. "Unknown" usually means the kubelet stopped reporting.
                "ready": conditions.get("Ready", "Unknown"),
                "roles": sorted(
                    k.split("/", 1)[1]
                    for k in (n.metadata.labels or {})
                    if k.startswith("node-role.kubernetes.io/")
                ),
                "kubeletVersion": n.status.node_info.kubelet_version,
                "os": n.status.node_info.os_image,
                "containerRuntime": n.status.node_info.container_runtime_version,
                "capacity": {
                    "cpu": n.status.capacity.get("cpu"),
                    "memory": n.status.capacity.get("memory"),
                    "pods": n.status.capacity.get("pods"),
                },
                "ageSeconds": age_seconds(n),
            }
        )
    return out


@app.get("/api/pods")
def list_pods(
    namespace: str | None = Query(
        None, description="Restrict to one namespace. Omit for all namespaces."
    ),
) -> list[dict]:
    if namespace:
        pods = k8s_call(core_v1.list_namespaced_pod, namespace)
    else:
        # Listing across all namespaces needs a ClusterRole in M3, not a Role.
        pods = k8s_call(core_v1.list_pod_for_all_namespaces)

    out = []
    for p in pods.items:
        statuses = p.status.container_statuses or []
        out.append(
            {
                "name": p.metadata.name,
                "namespace": p.metadata.namespace,
                "phase": p.status.phase,
                # `phase` and `ready` are different questions — a Pod can be
                # Running with 0/1 ready, and it receives no Service traffic.
                "ready": f"{sum(1 for c in statuses if c.ready)}/{len(statuses)}",
                "restarts": sum(c.restart_count for c in statuses),
                "podIP": p.status.pod_ip,
                "node": p.spec.node_name,
                "labels": p.metadata.labels or {},
                "images": [c.image for c in p.spec.containers],
                # ownerReferences is how the Pod records which ReplicaSet made
                # it — the ownership chain, as stored data rather than naming.
                "ownedBy": [
                    {"kind": o.kind, "name": o.name}
                    for o in (p.metadata.owner_references or [])
                ],
                "ageSeconds": age_seconds(p),
            }
        )
    return out


@app.get("/api/deployments")
def list_deployments(namespace: str | None = Query(None)) -> list[dict]:
    if namespace:
        deps = k8s_call(apps_v1.list_namespaced_deployment, namespace)
    else:
        deps = k8s_call(apps_v1.list_deployment_for_all_namespaces)

    return [
        {
            "name": d.metadata.name,
            "namespace": d.metadata.namespace,
            "desired": d.spec.replicas,
            "ready": d.status.ready_replicas or 0,
            "upToDate": d.status.updated_replicas or 0,
            "available": d.status.available_replicas or 0,
            "selector": (d.spec.selector.match_labels or {}),
            "images": [c.image for c in d.spec.template.spec.containers],
            "ageSeconds": age_seconds(d),
        }
        for d in deps.items
    ]


@app.get("/api/replicasets")
def list_replicasets(namespace: str | None = Query(None)) -> list[dict]:
    """The middle layer of the ownership chain.

    Without this the UI can't connect a Deployment to its Pods: a Pod's
    ownerReferences point at a ReplicaSet, and the ReplicaSet's point at the
    Deployment. Two hops, so both need to be readable.
    """
    if namespace:
        rs = k8s_call(apps_v1.list_namespaced_replica_set, namespace)
    else:
        rs = k8s_call(apps_v1.list_replica_set_for_all_namespaces)

    return [
        {
            "name": r.metadata.name,
            "namespace": r.metadata.namespace,
            "desired": r.spec.replicas or 0,
            "current": r.status.replicas or 0,
            "ready": r.status.ready_replicas or 0,
            # The Deployment stamps an incrementing revision on each ReplicaSet
            # it creates — this is what `kubectl rollout history` reads.
            "revision": (r.metadata.annotations or {}).get(
                "deployment.kubernetes.io/revision"
            ),
            "podTemplateHash": (r.metadata.labels or {}).get("pod-template-hash"),
            "images": [c.image for c in r.spec.template.spec.containers],
            "ownedBy": [
                {"kind": o.kind, "name": o.name}
                for o in (r.metadata.owner_references or [])
            ],
            "ageSeconds": age_seconds(r),
        }
        for r in rs.items
    ]


@app.get("/api/services")
def list_services(namespace: str | None = Query(None)) -> list[dict]:
    if namespace:
        svcs = k8s_call(core_v1.list_namespaced_service, namespace)
    else:
        svcs = k8s_call(core_v1.list_service_for_all_namespaces)

    return [
        {
            "name": s.metadata.name,
            "namespace": s.metadata.namespace,
            "type": s.spec.type,
            "clusterIP": s.spec.cluster_ip,
            "selector": s.spec.selector or {},
            "ports": [
                {"port": p.port, "targetPort": str(p.target_port), "protocol": p.protocol}
                for p in (s.spec.ports or [])
            ],
            "ageSeconds": age_seconds(s),
        }
        for s in svcs.items
    ]


@app.get("/api/pods/{namespace}/{name}/logs")
def pod_logs(namespace: str, name: str, tail: int = Query(200, ge=1, le=5000)) -> dict:
    # Reading logs goes through a *subresource*: pods/log. In M3 that needs its
    # own RBAC rule — "get pods" alone does not grant it.
    logs = k8s_call(
        core_v1.read_namespaced_pod_log, name=name, namespace=namespace, tail_lines=tail
    )
    return {"namespace": namespace, "name": name, "logs": logs}


@app.get("/api/events")
def list_events(
    kind: str = Query(..., description="involvedObject.kind, e.g. Pod or Deployment"),
    name: str = Query(...),
    namespace: str = Query(...),
) -> list[dict]:
    """Events about one object — the list at the bottom of `kubectl describe`.

    Events are their own objects in the core group, NOT part of the object they
    describe. That's why they need their own RBAC grant (`events`, in
    k8s/11-rbac.yaml) and why deleting a Pod doesn't delete its history.

    They're filtered server-side with a FIELD selector — matching on a value
    inside the object — rather than a LABEL selector, because events carry no
    useful labels. Two fields are matched, comma-separated, which the API server
    treats as AND:

        involvedObject.kind=Deployment,involvedObject.name=kubeplayground-api

    Both halves are needed because a name is only unique WITHIN a kind. This
    project has a Deployment and a Service both called `kubeplayground-api`;
    filtering on name alone would blend their events into one list.

    Note: events are garbage-collected after about an hour by default, so an
    empty list means "nothing happened recently", not "nothing ever happened".
    """
    events = k8s_call(
        core_v1.list_namespaced_event,
        namespace,
        field_selector=f"involvedObject.kind={kind},involvedObject.name={name}",
    )

    def when(e):
        return e.last_timestamp or e.event_time or e.first_timestamp

    items = sorted(
        events.items,
        key=lambda e: when(e).timestamp() if when(e) else 0,
        reverse=True,
    )
    return [
        {
            # "Normal" or "Warning" — Warning is what you scan for.
            "type": e.type,
            "reason": e.reason,
            "message": e.message,
            "count": e.count or 1,
            "source": (e.source.component if e.source else None),
            "ageSeconds": since(when(e)),
        }
        for e in items
    ]



# --------------------------------------------------------------------------
# Live manifests — "show me the YAML".
#
# Every object in a cluster is a document the API server stores in etcd. This
# endpoint hands one back verbatim, and it is the most useful teaching surface
# in the whole app: it needs NO new RBAC (`get` is already granted on all of
# these) and it makes two lessons visible at once.
#
# Two renderings are returned, and the DIFFERENCE between them is the point:
#
#   full   what etcd actually holds. Includes `status` — written by controllers,
#          never by you — plus every field the API server defaulted in during
#          admission, plus `managedFields` bookkeeping.
#   clean  the same object with the server's contributions stripped out:
#          roughly what a human would have typed to produce it.
#
# Read them side by side and "spec is your intent, status is system-written
# reality" stops being a slogan you repeat and becomes something you can see.
# `stripped` lists what was removed, so the removal is itself the lesson.
# --------------------------------------------------------------------------

# kind -> (apiVersion, is_namespaced, reader). The client's read_* methods
# return typed objects with api_version/kind left as None, so the apiVersion is
# carried here and stamped back on below.
#
# This map is deliberately limited to what k8s/11-rbac.yaml grants `get` on.
# Adding DaemonSets or Jobs here without adding the RBAC rule would produce a
# button that 403s — the UI must not promise more than the ServiceAccount can do.
_MANIFEST_KINDS: dict[str, tuple[str, bool, Any]] = {
    "Pod": ("v1", True, lambda ns, n: core_v1.read_namespaced_pod(n, ns)),
    "Service": ("v1", True, lambda ns, n: core_v1.read_namespaced_service(n, ns)),
    "Namespace": ("v1", False, lambda ns, n: core_v1.read_namespace(n)),
    "Node": ("v1", False, lambda ns, n: core_v1.read_node(n)),
    "Deployment": ("apps/v1", True, lambda ns, n: apps_v1.read_namespaced_deployment(n, ns)),
    "ReplicaSet": ("apps/v1", True, lambda ns, n: apps_v1.read_namespaced_replica_set(n, ns)),
}

# metadata keys the API server owns. You never write these; it writes them all.
_SERVER_METADATA = (
    "managedFields",     # which actor last owned which field — server-side apply
    "uid",               # assigned at creation, never reused
    "resourceVersion",   # etcd's optimistic-concurrency token; changes constantly
    "generation",        # bumped by the server each time spec changes
    "creationTimestamp",
    "selfLink",          # deprecated, still emitted by some versions
    "ownerReferences",   # written by the controller that created the object
)

# An annotation `kubectl apply` writes containing a full JSON copy of whatever
# you last submitted. Enormous, and a duplicate of the object it sits on.
_LAST_APPLIED = "kubectl.kubernetes.io/last-applied-configuration"


def clean_manifest(doc: dict) -> tuple[dict, list[str]]:
    """Strip what the server added. Returns (document, human-readable removals)."""
    doc = copy.deepcopy(doc)
    stripped: list[str] = []

    if doc.pop("status", None) is not None:
        stripped.append("status — written by controllers, never by you")

    meta = doc.get("metadata", {})
    for k in _SERVER_METADATA:
        if meta.pop(k, None) is not None:
            stripped.append(f"metadata.{k}")

    if meta.get("annotations", {}).pop(_LAST_APPLIED, None) is not None:
        stripped.append("the kubectl last-applied-configuration annotation")
    # Removing the only annotation leaves an empty map, which nobody would write.
    if meta.get("annotations") == {}:
        meta.pop("annotations")

    # The kubelet projects a ServiceAccount token into every Pod as a volume you
    # never declared. It is the mechanism behind in-cluster auth — the very
    # token this process authenticated with — but as YAML it is pure noise.
    spec = doc.get("spec", {})
    volumes = spec.get("volumes")
    if isinstance(volumes, list):
        injected = {
            v["name"] for v in volumes if str(v.get("name", "")).startswith("kube-api-access-")
        }
        if injected:
            spec["volumes"] = [v for v in volumes if v["name"] not in injected]
            if not spec["volumes"]:
                spec.pop("volumes")
            for c in spec.get("containers", []):
                mounts = [m for m in c.get("volumeMounts", []) if m.get("name") not in injected]
                if mounts:
                    c["volumeMounts"] = mounts
                else:
                    c.pop("volumeMounts", None)
            stripped.append("the projected ServiceAccount token volume — kubelet-injected")

    return doc, stripped


def kubectl_get_yaml(kind: str, name: str, namespace: str | None) -> str:
    """The command a human would type to see the same thing."""
    ns = f" -n {namespace}" if namespace else ""
    return f"kubectl get {kind.lower()} {name}{ns} -o yaml"


@app.get("/api/manifest")
def manifest(
    kind: str = Query(..., description="Pod, Service, Deployment, ReplicaSet, Node, Namespace"),
    name: str = Query(...),
    namespace: str | None = Query(None, description="Omitted for cluster-scoped kinds"),
) -> dict:
    """The live YAML for one object — `kubectl get <kind> <name> -o yaml`.

    Query parameters rather than a path like /api/manifest/{kind}/{ns}/{name}:
    cluster-scoped kinds have no namespace segment, so a path would need two
    routes and careful ordering against the catch-all static mount below.
    """
    entry = _MANIFEST_KINDS.get(kind)
    if entry is None:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported kind {kind!r}. Known: {', '.join(sorted(_MANIFEST_KINDS))}",
        )
    api_version, namespaced, read = entry
    if namespaced and not namespace:
        raise HTTPException(status_code=400, detail=f"{kind} is namespaced — namespace required")

    obj = k8s_call(read, namespace, name)

    # sanitize_for_serialization turns the typed object back into the plain dict
    # the API server actually sent: camelCase keys, None values dropped. This is
    # the same representation kubectl prints.
    doc = client.ApiClient().sanitize_for_serialization(obj)
    doc = {"apiVersion": api_version, "kind": kind, **doc}

    cleaned, stripped = clean_manifest(doc)

    def dump(d: dict) -> str:
        # sort_keys=False preserves apiVersion/kind/metadata/spec/status order,
        # which is the order everyone reads Kubernetes YAML in.
        return yaml.safe_dump(d, sort_keys=False, default_flow_style=False, width=100)

    return {
        "kind": kind,
        "name": name,
        "namespace": namespace,
        "kubectl": kubectl_get_yaml(kind, name, namespace),
        "full": dump(doc),
        "clean": dump(cleaned),
        "stripped": stripped,
    }


class ScaleRequest(BaseModel):
    replicas: int = Field(ge=0, le=20, description="Desired replica count")


@app.post("/api/deployments/{namespace}/{name}/scale")
def scale_deployment(namespace: str, name: str, body: ScaleRequest) -> dict:
    """Scale a Deployment.

    This patches the `scale` SUBRESOURCE (deployments/scale), which is a
    separate RBAC target from the Deployment itself. In M3 you will grant
    `patch` on `deployments/scale` without granting `patch` on `deployments`
    — so this app can change the replica count and nothing else.
    """
    scale = k8s_call(
        apps_v1.patch_namespaced_deployment_scale,
        name=name,
        namespace=namespace,
        body={"spec": {"replicas": body.replicas}},
    )
    return {
        "namespace": namespace,
        "name": name,
        "replicas": scale.spec.replicas,
    }


# --------------------------------------------------------------------------
# Static frontend.
#
# Mounted LAST, on purpose. Routes are matched in registration order, and this
# mount claims "/" — anything registered after it would be shadowed and never
# reached. In the image the frontend lands at /app/static; running from source
# it's ../frontend, so both work without a config flag.
# --------------------------------------------------------------------------
_here = Path(__file__).parent
for candidate in (_here / "static", _here.parent / "frontend"):
    if candidate.is_dir():
        app.mount("/", StaticFiles(directory=candidate, html=True), name="frontend")
        log.info("serving frontend from %s", candidate)
        break
else:
    log.warning("no frontend directory found — API only")
