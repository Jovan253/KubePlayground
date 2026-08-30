# KubePlayground — project context

Context for anyone (human or AI) picking this repo up. **`ROADMAP.md` is the source of truth for
what's done and what's next** — read it before assuming where things stand.

---

## Who this is for

Jovan Hadzic — Cloud/DevOps engineer, ~2 years experience as of August 2026, first job after
university.

- **Strong on:** CI/CD pipelines, Terraform, Azure. Reads and writes IaC daily.
- **New to:** Kubernetes. Has watched course material but had done essentially **no hands-on
  practical work** before starting this project in August 2026.
- **Goal:** pass the **KCNA** (Kubernetes and Cloud Native Associate) exam.

Assume familiarity with declarative config, YAML, cloud IAM concepts and container basics. Do
**not** assume familiarity with Kubernetes objects, kubectl muscle memory, or cluster internals.

## Working mode — important

Jovan chose **"you explain, I write the YAML"** at kickoff:

- Explain the concept, name the file to create, describe what it must contain *conceptually* —
  which fields, why each exists, what breaks without it. Then **stop and wait**.
- **He writes the Kubernetes manifests himself.** Review and correct afterwards.
- Application code (Python/FastAPI backend, frontend JS) *may* be written for him — that's
  plumbing, not the thing he's trying to learn.

**Why:** his words were *"I want you to help me with Kubernetes but not do all of it."* The point
is building Kubernetes muscle memory for the exam; handing over finished manifests defeats it.

**How to apply:** don't pre-emptively create `.yaml` files. Reviewing, debugging his errors, and
quizzing him are all in scope and welcome. If he asks outright for a manifest, give it — but flag
what he should understand about it.

## What the project is

An interactive web app that visualises a live Kubernetes cluster — Pods, Deployments, Services,
Nodes — and lets you scale and inspect workloads from the browser. It serves as both a **learning
vehicle** for KCNA and an **interactive portfolio piece**.

**The design trick:** the app is deployed *into* the cluster it observes. That's deliberate — the
app's requirements *are* the curriculum. It can't list Pods without a ServiceAccount and RBAC,
can't be reached without a Service and Ingress, can't survive without probes and resource limits.
Building it forces a pass through exactly the objects KCNA tests. See the table in `ROADMAP.md`.

## Stack

Decided at kickoff, 2026-08-25:

- **Backend:** Python 3.12 + FastAPI + the official `kubernetes` client. Chosen for minimal
  boilerplate and readability over Go's idiomatic-but-steeper `client-go` — the aim is to learn
  Kubernetes, not to learn Go at the same time.
- **Frontend:** plain HTML/CSS/JS first; React only if it earns its place.
- **Packaging:** raw manifests first, Helm chart later.

## Environment

**Changed on 2026-08-30 — the machine no longer matches the original setup.** Rancher Desktop and
WSL2 are gone; there is no k3s. Do not trust older notes in `ROADMAP.md`'s session log about the
local cluster.

Windows 11. Local cluster is **Docker Desktop's built-in Kubernetes** (context `docker-desktop`),
single node `desktop-control-plane`, **Kubernetes v1.36.1**.

Docker Desktop now provisions that cluster with **kind** under the hood (`kindest/node:v1.36.1`),
not the old kubeadm-on-the-host setup — so the container runtime is **containerd 2.3.1**, not
docker. Docker itself is on the containerd image store, and Docker Desktop runs a registry mirror
(`desktop-containerd-registry-mirror`) plus `desktop-cloud-provider-kind` for LoadBalancer
Services.

On PATH: `kubectl` and `docker` (both via Docker Desktop), Node.js, Python **3.11**.
**Not installed:** `helm`, `go`, `aws`, `terraform`, `gh` — the last three are needed for M9.
WSL2 *is* present after all (distros: `Ubuntu`, stopped; `docker-desktop`, running) — enabling
Kubernetes installed it.

Docker Desktop specifics that affect manifests — these differ from k3s and bit us already:

- **No ingress controller ships with it.** k3s bundled Traefik; Docker Desktop bundles nothing.
  **Installed 2026-08-30:** ingress-nginx `controller-v1.15.1`, cloud provider variant, which
  creates the `nginx` IngressClass. `k8s/14-ingress.yaml` must therefore say
  `ingressClassName: nginx`, not `traefik`.

  Reinstall command if the cluster is ever reset:
  ```powershell
  kubectl --context docker-desktop apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/cloud/deploy.yaml
  ```
- **LoadBalancer Services work and map to localhost.** The controller Service gets an external IP
  on the Docker network (e.g. `172.18.0.5`) which is NOT reachable from Windows, but Docker Desktop
  forwards `localhost:80` to it — so `http://localhost/` is still the entry point, exactly as it
  was under Traefik. A bare `http://localhost/` with no matching Ingress rule returns a 404 from
  nginx's default backend, which is a *healthy* answer, not a failure.
- StorageClasses are `standard` (**the default**) and `hostpath`. Both use the
  `rancher.io/local-path` provisioner — the same one k3s used.
- **Images:** unverified whether a locally-built tag is visible to the cluster. The old Docker
  Desktop shared one dockerd with Kubernetes, which is what made `imagePullPolicy: IfNotPresent`
  work with no registry (see M3). The kind-based cluster has its own containerd, with a registry
  mirror bridging the two. TEST THIS before assuming M3's note still holds.

## ⚠️ Context safety rule

The employer's `SHAREDSERVICES-01-AKS` context is **not on this machine any more**, so the original
hazard is currently absent. The habit stays anyway — it costs nothing and the context will come
back the moment that kubeconfig is restored, or once EKS is added alongside local.

| context | what it is |
|---|---|
| `docker-desktop` | the local sandbox — safe, this is the playground |
| *(future)* EKS | the AWS deployment target — real infrastructure, real money |

Every mutating command (`apply`, `delete`, `scale`, `edit`) passes `--context docker-desktop`
explicitly, or the active context is verified first:

```powershell
kubectl config current-context
```


## Layout

```
KubePlayground/
├─ CLAUDE.md      this file — background, working mode, safety rules
├─ ROADMAP.md     milestones, progress, session log, KCNA coverage tracker
└─ k8s/           Kubernetes manifests, numbered in dependency order
```
