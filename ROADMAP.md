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

### ◐ M1 — kubectl fluency + core objects by hand
*Goal: never touch the app code until you can build and break these from memory.*
- [x] Contexts and namespaces: `config get-contexts`, `config current-context`, `get ns`
- [x] Create the `playground` + `kubeplayground` namespaces **from a YAML file**, not `kubectl create ns`
- [x] Validation habits: `--dry-run=client` vs `--dry-run=server` vs `kubectl diff`
- [x] Cluster-scoped vs namespaced objects (`kubectl api-resources --namespaced=false`)
- [x] Admission control: the server can modify what you submit (`kubernetes.io/metadata.name`)
- [ ] Write a bare **Pod** manifest; `get`, `describe`, `logs`, `exec`, `delete` it
- [ ] Write a **Deployment**; observe Deployment → ReplicaSet → Pod ownership
- [ ] Scale it, delete a Pod by hand, watch the ReplicaSet resurrect it
- [ ] Write a **Service** (ClusterIP); reach it via `port-forward` and via DNS from another Pod
- [ ] Write a **ConfigMap**; mount it as env vars and as a volume
- [ ] Understand `kubectl apply` vs `create` (declarative vs imperative)

### ☐ M2 — Backend API, running locally
*Still outside the cluster — talks to it using your kubeconfig.*
- [ ] Python venv + `fastapi`, `uvicorn`, `kubernetes`
- [ ] `GET /api/namespaces`, `/api/pods`, `/api/deployments`, `/api/nodes`
- [ ] `POST /api/deployments/{ns}/{name}/scale`
- [ ] Understand `load_kube_config()` vs `load_incluster_config()` — the seam that matters in M3

### ☐ M3 — Containerise and run it *in* the cluster
- [ ] Dockerfile (non-root user, slim base, no secrets baked in)
- [ ] Get the image into k3s (Rancher Desktop shares the docker daemon — no registry needed)
- [ ] **ServiceAccount** `kubeplayground-sa`
- [ ] **ClusterRole** + **ClusterRoleBinding** — least privilege, exactly the verbs needed
- [ ] **Deployment** for the API, using `load_incluster_config()`
- [ ] Prove RBAC works by *removing* a verb and watching it 403

### ☐ M4 — Expose it
- [ ] **Service** (ClusterIP) in front of the Deployment
- [ ] **Ingress** via Traefik; reach it from the Windows browser
- [ ] Understand the path: browser → Ingress → Service → Endpoints → Pod

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
