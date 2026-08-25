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

Windows 11. Local cluster is **Rancher Desktop** running single-node **k3s v1.33.3+k3s1** in WSL2
(node `synldnlt8sglgs3`, docker runtime). No kind/minikube — not needed.

On PATH: `kubectl` v1.36, `helm`, `docker` (all via Rancher Desktop), Node.js, Python 3.12.
**`go` is not installed.**

k3s specifics that affect manifests: **Traefik** is the built-in ingress controller (don't install
nginx-ingress) and **local-path** is the default StorageClass.

## ⚠️ Two contexts — safety rule

| context | what it is |
|---|---|
| `rancher-desktop` | the local k3s sandbox — safe, this is the playground |
| `SHAREDSERVICES-01-AKS` | **the employer's real AKS cluster**, default ns `nexusproposal-uat` |

`rancher-desktop` is normally active, but **never assume it**. Every mutating command
(`apply`, `delete`, `scale`, `edit`) must pass `--context rancher-desktop` explicitly, or the
active context must be verified first:

```powershell
kubectl config current-context
```

An `apply` or `delete` that lands on the AKS context would hit production-adjacent infrastructure.

## Layout

```
KubePlayground/
├─ CLAUDE.md      this file — background, working mode, safety rules
├─ ROADMAP.md     milestones, progress, session log, KCNA coverage tracker
└─ k8s/           Kubernetes manifests, numbered in dependency order
```
