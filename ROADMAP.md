# KubePlayground — Roadmap & Progress

An interactive web app that visualises a live Kubernetes cluster — Pods, Deployments, Services,
Nodes — and lets you scale and inspect workloads from the browser.

Two jobs at once: a **learning vehicle** for the KCNA exam, and an **interactive portfolio piece**.

> **Status legend:** ☐ not started · ◐ in progress · ☑ done

---

## The idea behind the design

KubePlayground is deployed **into the cluster it observes**. That's not just cute — it's the whole
teaching mechanism. Every feature drags a Kubernetes object in with it:

| The app needs to… | …so you must learn |
|---|---|
| read Pods from the API | ServiceAccount, Role/ClusterRole, RoleBinding, RBAC verbs |
| be reachable from a browser | Service (ClusterIP), Ingress, DNS, kube-proxy |
| have a "scale" button | Deployment ↔ ReplicaSet ↔ Pod ownership, the `scale` subresource |
| not fall over | liveness/readiness probes, resource requests & limits |
| have things to look at | a `playground` namespace of sample workloads |
| be configurable | ConfigMap, Secret, env vars |
| show CPU/memory | metrics-server, the metrics API |

The app's requirements *are* the curriculum.

## Target architecture

```
                 browser
                    │
                    ▼
        ┌───────────────────────┐
        │ Ingress (Traefik)     │   k3s ships Traefik by default
        └───────────┬───────────┘
                    ▼
        ┌───────────────────────┐
        │ Service (ClusterIP)   │  kubeplayground-api
        └───────────┬───────────┘
                    ▼
        ┌───────────────────────────────────────┐
        │ Deployment: kubeplayground-api        │
        │   Pod: FastAPI + kubernetes client    │
        │   ServiceAccount: kubeplayground-sa   │──┐
        └───────────────────────────────────────┘  │ RBAC:
                                                   │ get/list/watch pods,
                    ┌──────────────────────────────┘ deployments, services, nodes
                    ▼                                + patch deployments/scale
        ┌───────────────────────┐
        │ Kubernetes API server │
        └───────────┬───────────┘
                    ▼
        ┌───────────────────────────────────────┐
        │ namespace: playground                 │
        │   sample Deployments to view & scale  │
        └───────────────────────────────────────┘
```

**Namespaces:** `kubeplayground` (the app itself) · `playground` (sample workloads it manipulates).

## Stack

- **Backend:** Python 3.12, FastAPI, official `kubernetes` client
- **Frontend:** plain HTML/CSS/JS to start; React only if it earns its place
- **Cluster:** local k3s via Rancher Desktop (`rancher-desktop` context)
- **Packaging:** raw manifests first → Helm chart later

---

## ⚠️ Safety rule

The kubeconfig on this machine holds **two** contexts:

| context | what it is |
|---|---|
| `rancher-desktop` | the local k3s sandbox — safe |
| `SHAREDSERVICES-01-AKS` | **the employer's real AKS cluster** — never touch |

Every mutating command (`apply`, `delete`, `scale`, `edit`) gets an explicit
`--context rancher-desktop`. Check with `kubectl config current-context` before anything else.

---

## Milestones

### ☑ M0 — Environment & kickoff
- [x] Confirm a working local cluster (Rancher Desktop k3s v1.33.3, single node)
- [x] Confirm tooling: kubectl v1.36, helm, docker, Python 3.12
- [x] Decide stack and working mode
- [x] Write this roadmap

### ☑ M1 — kubectl fluency + core objects by hand
*Goal: never touch the app code until you can build and break these from memory.*
- [x] Contexts and namespaces: `config get-contexts`, `config current-context`, `get ns`
- [x] Create the `playground` + `kubeplayground` namespaces **from a YAML file**, not `kubectl create ns`
- [x] Validation habits: `--dry-run=client` vs `--dry-run=server` vs `kubectl diff`
- [x] Cluster-scoped vs namespaced objects (`kubectl api-resources --namespaced=false`)
- [x] Admission control: the server can modify what you submit (`kubernetes.io/metadata.name`)
- [x] Write a bare **Pod** manifest; `get`, `describe`, `logs`, `exec`, `port-forward` it
- [x] YAML list-item indentation rule (keys align under the first key after `- `)
- [x] Pod phase vs READY count; Pod IP is ephemeral (→ the reason Services exist)
- [x] `describe` → Events is the first debugging move
- [x] spec (your intent) vs status (system-written reality)
- [x] Write a **Deployment**; observe Deployment → ReplicaSet → Pod ownership
- [x] API groups: core (`v1`) vs `apps/v1`
- [x] Scale it, delete a Pod by hand, watch the ReplicaSet resurrect it
- [x] Rolling update: two ReplicaSets, `pod-template-hash`, `rollout status/history/undo`
- [x] Imperative `kubectl scale` causes drift from the file — the file is the source of truth
- [x] Write a **Service** (ClusterIP); reach it via `port-forward` and via DNS from another Pod
- [x] Service selector is a plain map, unlike a Deployment's `selector.matchLabels`
- [x] `port` vs `targetPort`; Pod CIDR vs Service CIDR; ClusterIP is virtual (kube-proxy rules)
- [x] EndpointSlice auto-populates from label matches — empty endpoints = selector bug
- [x] Cluster DNS: `<service>.<namespace>.svc.cluster.local`, short names via search domain
- [x] Write a **ConfigMap**; mount it as env vars and as a volume
- [x] Mounted ConfigMap volumes update live; env vars are frozen at container start
      (`rollout restart` to pick them up). `subPath` mounts never update — gotcha.
- [x] ConfigMaps are plaintext; Secrets are base64-encoded, **not encrypted**
- [x] Understand `kubectl apply` vs `create` (declarative vs imperative)

### ◐ M2 — Backend API, running locally
*Still outside the cluster — talks to it using your kubeconfig.*
- [x] Python venv + `fastapi`, `uvicorn`, `kubernetes` (`backend/requirements.txt`)
- [x] `GET /api/health`, `/api/cluster`, `/api/namespaces`, `/api/nodes`, `/api/pods`,
      `/api/deployments`, `/api/services`, `/api/pods/{ns}/{name}/logs`
- [x] `POST /api/deployments/{ns}/{name}/scale` — patches the `deployments/scale` subresource
- [x] Context guard: refuses to start unless the active context is `rancher-desktop`
- [x] Smoke-tested against the live cluster; scale up/down and the 404 path both verified
- [ ] **Jovan to review `backend/main.py`** — particularly `load_config()`
- [ ] Understand `load_kube_config()` vs `load_incluster_config()` — the seam that matters in M3

### ☑ M3 — Containerise and run it *in* the cluster
- [x] Dockerfile (non-root uid 10001, slim pinned base, deps layered before source)
- [x] Get the image into k3s (Rancher Desktop shares the docker daemon — no registry needed;
      requires `imagePullPolicy: IfNotPresent` since there's no registry to pull from)
- [x] **ServiceAccount** `kubeplayground-sa` (`k8s/10-serviceaccount.yaml`)
- [x] **Deployment** for the API, using `load_incluster_config()` (`k8s/12-api-deployment.yaml`)
- [x] Saw the baseline: a fresh SA can do *nothing* — Pod `1/1 Running` but every call 403s
- [x] **ClusterRole** + **ClusterRoleBinding** — least privilege (`k8s/11-rbac.yaml`)
- [x] Subresources are separate RBAC targets: `pods/log`, `deployments/scale`
- [x] `kubectl auth can-i --list --as=system:serviceaccount:<ns>:<name>`
- [x] **RBAC is additive — there are no deny rules.** Effective permissions are the union of
      every binding naming a subject; an absent rule protects nothing.
- [x] Prove RBAC works by *removing* a verb and watching it 403
- [x] Cross-namespace: ConfigMaps/Secrets/Ingress backends can only be referenced from the
      referencing object's own namespace — no cross-namespace references

### ☑ M4 — Expose it
- [x] **Service** (ClusterIP) in front of the Deployment (`k8s/13-api-service.yaml`) —
      `port: 80` → `targetPort: 8000`, the first time the two differ
- [x] **Ingress** via Traefik (`k8s/14-ingress.yaml`); reachable at `http://localhost/`
- [x] Understand the path: browser → Traefik → Ingress rule → Service → EndpointSlice → Pod
- [x] Ingress **resource** (rules in etcd) vs Ingress **controller** (the workload that acts
      on them). Rules with no controller silently route nothing.
- [x] Ingress YAML nesting: `rules`/`paths` are lists, `http`/`backend`/`service`/`port` are maps
- [x] `pathType` is required — `Prefix` / `Exact` / `ImplementationSpecific`

### ☐ M5 — The frontend
- [ ] Static HTML/JS served by FastAPI
- [ ] Live-updating grid of Pods with phase/status colouring
- [ ] Click a Pod → details, events, logs
- [ ] Scale buttons on Deployments; watch Pods appear and vanish live
- [ ] Polling first, then `watch` + WebSocket

### ☐ M6 — Make it production-shaped
- [ ] Liveness / readiness / startup probes — and break each on purpose to see the effect
- [ ] Resource requests & limits; trigger an OOMKill and a CPU throttle deliberately
- [ ] ConfigMap + Secret for app config
- [ ] **HorizontalPodAutoscaler** on a sample workload
- [ ] **NetworkPolicy** restricting who can reach the API
- [ ] Rolling update + `kubectl rollout undo`

### ☐ M7 — Observability
- [ ] metrics-server; `kubectl top`
- [ ] Surface CPU/memory in the UI
- [ ] Live cluster **Events** feed in the UI
- [ ] Structured logs; `/healthz` and `/metrics` endpoints
- [ ] Concepts: the difference between logs, metrics, traces (KCNA asks)

### ☐ M8 — Delivery & polish
- [ ] Package as a **Helm chart**
- [ ] README with architecture diagram and screenshots — the portfolio artefact
- [ ] *Optional, plays to existing strengths:* Terraform an AKS cluster and deploy there
- [ ] *Optional:* GitHub Actions / GitLab CI to build and deploy

---

## KCNA coverage tracker

Exam domains and weights — **verify against the current CNCF curriculum**, they do get revised:

| Domain | Weight | Covered by | Confidence |
|---|---|---|---|
| Kubernetes Fundamentals | 46% | M1, M3, M4, M6 | ☐ |
| Container Orchestration | 22% | M1, M3, M6 | ☐ |
| Cloud Native Architecture | 16% | M6, M8 | ☐ |
| Cloud Native Observability | 8% | M7 | ☐ |
| Cloud Native App Delivery | 8% | M8 | ☐ |

Note: the exam is broader than one project — it also covers things KubePlayground won't naturally
hit (CNCF landscape/governance, service mesh, serverless, GitOps, container runtimes & the CRI,
open standards like OCI/CNI/CSI). Those need reading alongside the build. Tracked here so they
don't get forgotten:

- [ ] CNCF landscape, project maturity levels (sandbox/incubating/graduated), governance
- [ ] Container runtimes, CRI, OCI; containerd vs Docker's role
- [ ] Service mesh concepts (Istio/Linkerd) — what problem it solves
- [ ] Serverless / Knative, autoscaling patterns
- [ ] GitOps (Argo CD / Flux) as a delivery model
- [ ] Cloud native security: the 4 Cs, supply chain, admission control

---

## Session log

Newest last. One line per working session — what moved.

- **2026-08-25** — Kickoff. Confirmed environment (Rancher Desktop k3s already running, 382d
  uptime). Chose Python/FastAPI and the "explain, then he writes the YAML" working mode.
  Wrote this roadmap. M0 done; starting M1.
- **2026-08-25** — First objects applied. `k8s/00-namespaces.yaml` creates the `kubeplayground`
  and `playground` namespaces. Learned along the way: dry-run creates nothing (it's
  `terraform plan`); `metadata.namespace` on a cluster-scoped object is silently dropped rather
  than rejected — diff submitted-vs-stored with `--dry-run=server -o yaml` to catch that class of
  bug; the API server adds `kubernetes.io/metadata.name` via mutating admission. Next: a bare Pod.
- **2026-08-26** — **M1 complete.** Hand-wrote and applied Pod, Deployment, Service and ConfigMap
  in `playground`. Saw self-healing (deleted a Pod, ReplicaSet replaced it), a rolling update
  across two ReplicaSets with `pod-template-hash`, `rollout undo`, Service discovery via cluster
  DNS from a throwaway curl Pod, and the ConfigMap volume-vs-env update asymmetry.
  Recurring theme worth remembering: **Kubernetes accepts invalid intent silently** — a
  cluster-scoped object with `metadata.namespace`, and an `env` entry with no `valueFrom`, both
  applied cleanly and did nothing. Diff submitted-vs-stored when something "works" but doesn't.
  Next: M2, the FastAPI backend.
- **2026-08-27** — **M2 written, M3 and M4 complete.** FastAPI backend (`backend/main.py`,
  Claude-written, reviewed by Jovan), containerised non-root, and now running *inside* the
  cluster as a Pod: `/api/health` reports `"mode":"in-cluster"`, meaning it authenticated with
  a ServiceAccount token rather than a kubeconfig. RBAC written to least privilege — six grants,
  no `secrets`, no `create`/`delete`, and `deployments/scale` granted separately from
  `deployments` so the scale button works without the app being able to redeploy anything.
  Verified by deliberately deleting the scale rule and watching a 403.
  Reachable end-to-end at `http://localhost/api/...` via Traefik.
  Recurring lesson this session: **editing a manifest is not applying it** — twice a "fixed" file
  hadn't reached the cluster. Reflex to build: edit → dry-run → apply → verify.
  Next: M5, the frontend.
