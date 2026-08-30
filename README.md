# KubePlayground

A web app that visualises a live Kubernetes cluster — and is **deployed into the cluster it
observes**.

That constraint is the whole design. The app can't list a Pod without a ServiceAccount and an
RBAC grant. It can't be reached without a Service and an Ingress. It can't survive a node without
probes and resource limits. Every feature drags a Kubernetes object in with it.

It is **not** trying to be Lens or k9s. Those hide the mechanics; this exposes them:

- **Every action shows the `kubectl` it's equivalent to.** A transcript bar logs each mutation as
  the command that would have done the same thing, alongside the standing reads the poll loop
  re-runs.
- **Every object can be read as live YAML, twice over** — as a spec, and as the API server
  actually stored it — with a panel listing exactly what the server added and why.
- **The app marks its own Pod** in the ownership tree. It's running inside the picture it's
  drawing.

<!-- TODO: replace with a screenshot or a short GIF of the tree + transcript + YAML pane.
     This is the single highest-value thing in the README — most readers will never run it. -->
<!-- ![KubePlayground](docs/screenshot.png) -->

---

## Why it exists

I'm a Cloud/DevOps engineer — CI/CD, Terraform and Azure day to day — who had read about
Kubernetes but done essentially no hands-on work with it. Rather than follow tutorials, I built
the thing that would force me to learn it, then used the app's own requirements as the syllabus.

Every manifest in `k8s/` was hand-written, applied, deliberately broken, and fixed. The mistakes
are recorded in [`ROADMAP.md`](ROADMAP.md) alongside what they taught — including several where
Kubernetes accepted invalid intent silently and failed somewhere else entirely.

---

## Architecture

```
                    browser
                       │  http://localhost/
                       ▼
        ┌──────────────────────────────┐
        │ Ingress  (ingress-nginx)     │   class: nginx
        └──────────────┬───────────────┘
                       ▼
        ┌──────────────────────────────┐
        │ Service (ClusterIP)          │   port 80 → targetPort 8000
        └──────────────┬───────────────┘
                       ▼
        ┌───────────────────────────────────────────┐
        │ Deployment: kubeplayground-api            │
        │   FastAPI + the official kubernetes client│
        │   ServiceAccount: kubeplayground-sa       │──┐
        │   probes · resource limits · downward API │  │
        └───────────────────────────────────────────┘  │  least-privilege RBAC
                                                        │  (see below)
                       ┌────────────────────────────────┘
                       ▼
        ┌──────────────────────────────┐
        │ Kubernetes API server        │
        └──────────────┬───────────────┘
                       ▼
        ┌───────────────────────────────────────────┐
        │ namespace: playground                     │
        │   sample workloads to view and scale      │
        └───────────────────────────────────────────┘
```

**Backend:** Python 3.12, FastAPI, the official `kubernetes` client.
**Frontend:** plain HTML/CSS/JS, no build step, no external assets — the Pod serves it with no
internet access, so nothing can silently fail to load.

---

## Design decisions worth reading

### Least privilege, at subresource granularity

The scale button works. The app still cannot redeploy anything.

```yaml
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch"]      # read only

- apiGroups: ["apps"]
  resources: ["deployments/scale"]     # a SEPARATE RBAC target
  verbs: ["patch"]
```

`PATCH /deployments/{name}` and `PATCH /deployments/{name}/scale` are different endpoints, so RBAC
treats them as different resources. The first lets you rewrite `spec.template` — a new image, a
`hostPath` mount, `privileged: true` — which in practice is **arbitrary code execution on every
node**. The second lets you change one integer.

If someone found a request-forgery bug in this dashboard, the worst they could do is set a replica
count. No Secrets, no `exec`, no `create`, no `delete` — enforced by the API server, not by
application code. Verified by deleting the verb and watching the 403.

### Resource limits set from measurement, not from a blog post

Read out of the container's own cgroup rather than estimated:

| | idle | under load (~3 req/s) |
|---|---|---|
| CPU | 6m | **142m** |
| memory | 81 MiB | 86–90 MiB peak |

The finding that changed the numbers: at a `500m` CPU limit, **while averaging 142m — 28% of the
allowance — the container was still throttled in 11 of 147 scheduling windows.**

CFS quota is enforced per 100ms period, not as an average. `500m` means 50ms of CPU per 100ms
window, and this workload is bursty — a request lands, serialises a few hundred objects in one
tight burst, then idles. A burst wanting more than 50ms in a single window is stopped dead.

This is the classic production misdiagnosis: p99 latency spikes with no CPU pressure visible
anywhere, because dashboards average over 30–60s and the damage happens in 100ms slices.
`nr_throttled` is the only place it shows.

**CPU limits degrade you silently; memory limits kill you loudly.** Hence: honest CPU requests
with generous limits, and memory limits treated as non-negotiable.

### The app finds itself without touching the API

A container can't know its own Pod name — the image is identical across replicas and the name is
assigned at creation. The **downward API** injects it as an environment variable, so the "you are
here" marker costs **no RBAC at all**: it's the cluster describing the Pod to itself.

---

## Running it locally

Requires a local cluster (developed against Docker Desktop's Kubernetes, v1.36) and an ingress
controller.

```powershell
# ingress-nginx — Docker Desktop ships no ingress controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/cloud/deploy.yaml

# build the image (frontend and backend; build context is the repo root)
docker build -f backend/Dockerfile -t kubeplayground-api:0.7.0 .

# apply everything — 00-namespaces.yaml must land first, and does
kubectl apply -f k8s/

kubectl -n kubeplayground rollout status deployment/kubeplayground-api
```

Then open <http://localhost/>.

> **Note on image tags.** There's no registry in the local setup, so `imagePullPolicy: IfNotPresent`
> is used with a locally built tag. The node caches what it pulls, so **rebuilding an existing tag
> serves stale layers with no error anywhere.** Bump the tag on every build.

The backend runs outside the cluster too, against your kubeconfig — the only thing that changes is
`load_config()`, which detects the ServiceAccount token that only exists inside a Pod. Out of
cluster it refuses to start unless the active context matches `KUBE_CONTEXT` (default
`docker-desktop`), so a stray API call can't land on a cluster you didn't mean:

```powershell
cd backend
$env:KUBE_CONTEXT = "your-context"
uvicorn main:app --port 8000
```

---

## Layout

```
KubePlayground/
├─ backend/       FastAPI app + Dockerfile
├─ frontend/      single-page UI, no build step
├─ k8s/           manifests, numbered roughly in dependency order
├─ CLAUDE.md      environment, working mode, safety rules
└─ ROADMAP.md     milestones, findings, and a session-by-session log
```

## Status

Working locally end to end: RBAC, Ingress, probes, measured resource limits, the kubectl
transcript, the YAML viewer, and pod detail with events and logs.

Planned next — tracked in [`ROADMAP.md`](ROADMAP.md):

- **M9** — deploy to **EKS** via **GitHub Actions**, authenticating with **OIDC federation** and
  no long-lived AWS keys. Terraform'd to be raised and destroyed on demand rather than idling.
- **M10** — a catalogue of predefined workloads the site can create safely: fixed server-side
  templates, a namespaced Role, a ResourceQuota, and a CronJob that resets the namespace.
- Observability, and packaging as a Helm chart.

This is an active learning project as much as a portfolio piece, and the roadmap is written to be
honest about what's done and what isn't.
