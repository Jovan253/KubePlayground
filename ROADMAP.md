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
        │ Ingress               │   NOTE: k3s shipped Traefik; Docker
        └───────────┬───────────┘   Desktop ships no controller at all
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
- **Cluster:** local Docker Desktop Kubernetes (`docker-desktop`); EKS in M9
- **Packaging:** raw manifests first → Helm chart later

---

## ⚠️ Safety rule

The employer's `SHAREDSERVICES-01-AKS` context is **no longer on this machine** (see the
environment note below), so the original hazard is currently absent. The habit stays: it costs
nothing, and a second context returns the moment EKS lands in M9.

| context | what it is |
|---|---|
| `docker-desktop` | the local sandbox — safe |
| *(M9)* EKS | the AWS target — real infrastructure, real money |

Every mutating command (`apply`, `delete`, `scale`, `edit`) gets an explicit
`--context docker-desktop`. Check with `kubectl config current-context` before anything else.

---

## ⚠️ Environment changed — 2026-08-30

The machine no longer matches M0. **Rancher Desktop, WSL2 and k3s are gone**, along with the local
Python venv and the `SHAREDSERVICES-01-AKS` context. `kubectl` and `docker` now come from
**Docker Desktop**, whose built-in Kubernetes had never been enabled.

Consequences to keep in mind when reading older entries below:

- The local cluster is empty. Everything in `k8s/` has to be re-applied in dependency order.
- **Docker Desktop ships no ingress controller.** k3s bundled Traefik, so `k8s/14-ingress.yaml`
  (`ingressClassName: traefik`) currently routes nowhere. Either install ingress-nginx and change
  the class, or fall back to `kubectl port-forward` until EKS.
- `helm`, `aws`, `terraform` and `gh` are not installed. The last three are needed for M9.
- The backend context guard now defaults to `docker-desktop`, not `rancher-desktop`.

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

### ☑ M4b — Two more sites behind the same Ingress
*Jovan's idea, 2026-08-31: two extra namespaces each serving a real web page, routed to from the
same controller. Demonstrates what an Ingress controller is actually FOR — host/path-based virtual
hosting, many sites behind one entry point — which the single-app setup never shows.*

Note that `playground/my-deployment` is already a second website: nginx serving the `index.html`
from the `hello-config` ConfigMap. It is unreachable from a browser only because no Ingress rule
points at it.

- [x] Two namespaces (`site-a`, `site-b`), each with a Deployment + Service + a
      ConfigMap-served page. Cheap: `nginx:alpine` with the HTML mounted from a ConfigMap, exactly
      like `k8s/02-deployment.yaml` and `k8s/04-configmap.yaml` already do.
- [x] **One Ingress per namespace.** An Ingress can only name a Service in its OWN namespace —
      the cross-namespace reference rule already learned in M3. This is where that constraint
      stops being trivia and shapes the design.
- [x] Host-based routing chosen. Why the choice matters:
      - **Host-based** — `site-a.localhost`, `site-b.localhost`. Browsers resolve `*.localhost`
        to 127.0.0.1 with no hosts-file edit, and it needs no path rewriting. Cleanest.
      - **Path-based** — `/site-a`, `/site-b`. Looks simpler but nginx forwards the full path, so
        the backend gets `/site-a/index.html` and 404s. Needs
        `nginx.ingress.kubernetes.io/rewrite-target`, which is a genuinely instructive gotcha and
        the reason path-based routing has a reputation.
- [x] The existing Ingress has NO `host:` and `path: /` with `pathType: Prefix`, so it currently
      matches everything. Adding siblings forces that to be disambiguated — which is the real
      lesson about how a controller picks a rule.
- [x] Payoff for the UI: three apps in three namespaces makes the namespace filter and the
      ownership tree demonstrate something, instead of showing one app next to kube-system noise.
      Pairs well with M5c.

**Verified 2026-08-31.** All three reachable simultaneously through one controller:

    kubeplayground   nginx   *                  <- catch-all, no host
    site-a           nginx   site-a.localhost
    site-b           nginx   site-b.localhost

Precedence confirmed: a specific `host:` rule beats the host-less catch-all, so KubePlayground
still answers plain `http://localhost/`.

Only defect on review: both Ingresses were missing `apiVersion: networking.k8s.io/v1`. Everything
else — namespace-per-Ingress, the ConfigMap volume mount, matching selectors, `pathType` — was
right first time. Worth noting the failure mode: a missing `apiVersion` is one of the few things
Kubernetes rejects outright rather than accepting silently.

### ◐ M5 — The frontend
- [x] Static HTML/JS served by FastAPI (`frontend/index.html`, mounted at `/`, last route)
- [x] Live-updating grid of Pods with phase/status colouring; 3s poll with pause
- [x] Scale buttons on Deployments; watch Pods appear and vanish live
- [x] Namespace filter; error banner surfaces RBAC 403s verbatim
- [x] Image now carries frontend + backend; build context is the repo root
- [x] **Visualise the ownership chain** (Jovan's idea) — Deployment › ReplicaSet › Pod as a
      nested tree, superseded ReplicaSets shown greyed at zero so rollout history is visible.
      Needed a new `/api/replicasets` endpoint (two hops: Pod → RS → Deployment) and a new
      `replicasets` RBAC grant.
- [x] Click a Pod → detail drawer with facts, Events and Logs. Needed an events endpoint;
      Events are separate objects in the core group, filtered with a FIELD selector because
      they carry no useful labels. Added an `events` RBAC grant.
- [ ] **Flat/tree view toggle.** Verdict after using it: the flat grid scanned better, the tree
      explains better. Neither wins outright — keep both and let the viewer switch. ~15 lines.
- [ ] Polling → `watch` + WebSocket (the `watch` RBAC verb is already granted)

### ◐ M5b — Make it a playground, not a dashboard
*Chosen 2026-08-30. The complaint was fair: you could look, and you could scale. Nothing else.
Both additions are READ-ONLY, which is the point — they need no new RBAC and stay safe to expose
publicly on EKS.*
- [x] **Show the kubectl for every action.** A transcript bar echoes each action as the command
      that would have done the same thing, plus a standing list of the six reads the 3s poll
      re-runs. The project is about muscle memory; a UI that hides the commands works against it.
      Watching six commands repeat every three seconds is also the argument for `watch`.
- [x] **Show the YAML.** Click any Deployment, ReplicaSet, Pod, Node or Service → the live
      manifest, rendered twice: *as written* (what a human would have typed) and *as stored*
      (what etcd actually holds). A panel lists what was stripped between the two — `status`,
      `managedFields`, `uid`, `resourceVersion`, `ownerReferences`, the kubelet-injected
      ServiceAccount token volume — so the removal is itself the lesson.
      **This is the exam-facing feature:** it makes "spec is your intent, status is
      system-written reality" something you can see rather than a slogan you repeat.
- [x] Generalised `/api/pods/{ns}/{name}/events` into `/api/events?kind=&name=&namespace=`.
      Field selectors match `involvedObject.kind` AND `.name`, comma-separated, because a name is
      only unique within a kind — this repo has a Deployment *and* a Service both called
      `kubeplayground-api`.
- [ ] Verify end to end against a live cluster — **not done yet, there is no cluster** (see above)

### ☑ M4c — Reachability links, and `playground` retired
*2026-08-31.*

- [x] **`playground` namespace deleted**, along with `k8s/01-pod.yaml` … `04-configmap.yaml` and
      its block in `00-namespaces.yaml`. Those were the M1 hand-written learning objects; they
      served their purpose and `site-a`/`site-b` are better demo material. Still in git history if
      ever wanted back. (M1's notes below refer to them by name — the files are gone, the lessons
      stand.)
- [x] **`/api/ingresses`** + a link chip on every Deployment the cluster can actually route to.
      Needed a new RBAC grant: Ingresses are in the `networking.k8s.io` group, neither core nor
      apps, so `get list watch` on `ingresses` was added to `11-rbac.yaml`. Read-only — the app
      still cannot change routing.
- [x] The link resolution is **Ingress → Service → Deployment**, and the middle hop is different
      in kind from the rest of the tree: Pod → ReplicaSet → Deployment is recorded as data in
      `ownerReferences`, but a Service finds its Pods by **label selector**, so nothing stores
      that relationship. The UI has to match `service.spec.selector` against the Deployment's own
      selector to infer it. Worth understanding: selectors are a query, not a link.
- [x] Correctly shows **no** link for `coredns` and `local-path-provisioner` — nothing routes to
      them.

**Bonus lesson, accidentally.** `12-api-deployment.yaml` was bumped to `0.8.0` before the image
was built, so the new ReplicaSet sat in `ImagePullBackOff` for 22 hours — and the site stayed up
the entire time. The rollout never completed, so the old ReplicaSet was never scaled down. That
is the rolling-update safety net doing exactly its job, and a much better demonstration of it
than a deliberate test would have been. Once the image existed, deleting the stuck Pod was faster
than waiting out the exponential backoff.

### ☐ M5c — Readability pass
*Noted 2026-08-30 after looking at the running UI in a browser for the first time. Jovan's read
was "it feels quite dense"; the screenshots suggest the problem is not density — spacing and type
are fine — but **priority**. The page shows the wrong things first.*

Observed on a default load (all namespaces, 5 deployments, 17 pods):

- [ ] **The app's own Deployment is the third card, below the fold.** Default view is
      all-namespaces in API order, so `ingress-nginx-controller` and `coredns` lead. The
      "you are here" banner literally promises a highlighted Pod "below" that isn't on screen.
      Fix: sort `kubeplayground` and `playground` first, or default to hiding system namespaces
      with a toggle. The banner and the thing it points at must be visible together.
- [ ] **Superseded ReplicaSets dominate the card.** `kubeplayground-api` shows five, each with
      its own "no pods — scaled to zero" line — roughly 200px of near-empty rows. Collapse to a
      single expandable "4 superseded revisions" summary; the history is worth keeping, five
      expanded rows of it is not.
- [ ] **Image digests eat a full line.** `registry.k8s.io/ingress-nginx/controller:v1.15.1@sha256:594ceea76b01c...`
      Truncate the digest, keep the tag, full value on hover or in the YAML pane.
- [ ] **Scale buttons appear on kube-system workloads.** You can scale `coredns` and the ingress
      controller from this UI. A genuine footgun rather than clutter — and it must not exist in a
      public deployment. Restrict the control to namespaces the app is meant to manage.
- [x] Fixed on sight: the collapsed transcript bar rendered `$ kubectl  kubectl describe ...` —
      the label and the command both said "kubectl".

Confirmed working when viewed: the ownership tree, "you are here" / "this app" markers, the YAML
pane with syntax highlighting and the spec ↔ spec+status toggle, the stripped-fields panel, the
kubectl transcript with standing reads separated from timestamped actions.

### ◐ M6 — Make it production-shaped
- [x] **Liveness / readiness / startup probes** on `kubeplayground-api`, all three `httpGet` at
      `/api/health` on the named port `http`. Mistakes made and understood along the way, each of
      which applied cleanly and broke something else:
      - `exec` takes a COMMAND, not a URL path. `/api/health` is not a file on disk.
      - a probe talks straight to the Pod IP — it never goes through the Service, so the port is
        `containerPort` (8000), never the Service's `port` (80).
      - `containerPort` **binds nothing**; it is documentation. Setting it to 80 did not move the
        listener, but it did repoint the named port `http`, so every probe hit a closed port and
        the container CrashLoopBackOff'd while the app itself was fine.
      - with a `startupProbe` present, liveness and readiness do not run until it succeeds, which
        makes `initialDelaySeconds` on them redundant. That is the whole reason startup probes
        exist: a generous boot budget AND fast failure detection afterwards, instead of trading
        one for the other via a large `initialDelaySeconds`.
- [x] **Resource requests & limits — set from measurement, not guesswork.** Read out of the
      container's own cgroup (`/sys/fs/cgroup/memory.current`, `cpu.stat`) rather than estimated:

      | | idle | under load (~3 req/s) |
      |---|---|---|
      | CPU | 6m | **142m** |
      | memory | 81 MiB | 86–90 MiB peak |

      QoS class is `Burstable` — `Guaranteed` needs requests == limits for **both** cpu and memory
      on **every** container; matching only CPU buys nothing.

      **The finding worth keeping.** At a `500m` CPU limit while averaging **142m — 28% of the
      allowance — the container was still throttled in 11 of 147 scheduling windows (7.5%)**,
      losing 0.26s to forced idling in 16 seconds.

      Why: CFS quota is enforced per **100ms period**, not as an average. `500m` means 50ms of CPU
      per 100ms window. This app is bursty — a request lands, serialises a few hundred objects in
      one tight burst, then idles — and a burst that wants more than 50ms inside one window is
      stopped dead until the next.

      This is the classic production misdiagnosis: p99 latency spikes with no CPU pressure visible
      anywhere, because dashboards average over 30–60s and the damage happens in 100ms slices.
      `nr_throttled` is the only place it shows.

      **The asymmetry to remember: CPU limits degrade you silently, memory limits kill you
      loudly.** Hence the defensible position — set a CPU *request* and consider omitting the CPU
      *limit* entirely for latency-sensitive services, while memory limits stay mandatory because
      the failure mode there is an OOMKill, not a stall.
- [ ] Break each probe on purpose — readiness (drops out of the EndpointSlice, Pod keeps running)
      vs liveness (container is killed and restarted). Break them SEPARATELY; they are currently
      identical, so they would otherwise always fail together.
- [ ] Trigger an OOMKill deliberately and see exit code 137
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
- [ ] Package as a **Helm chart** (M9's deploy job then uses `helm upgrade --install`)
- [ ] README with architecture diagram and screenshots — the portfolio artefact

### ☐ M9 — Ship it to AWS with GitHub Actions
*Added 2026-08-30. Deliberately AWS + GitHub rather than Azure + GitLab: those are already
day-job skills, and the gap is the thing worth closing.*

**Cost decision.** EKS costs **$0.10/hr for the control plane alone (~$73/month) whether or not
anything runs on it**, plus nodes, load balancer and NAT. So the environment is built to be
**raised and destroyed on demand**, with `destroy` as a workflow you can trigger. "The pipeline
stands the whole environment up from nothing" is a better story than a cluster idling at $100/mo.

**How the Terraform gets written.** Incrementally, one AWS concept at a time. Jovan writes
Terraform daily but has not used AWS — the unfamiliar part is the resources, not the language, so
each step below lands separately with an explanation of what it creates and why AWS needs it.

- [x] **Step 1 — Identity.** GitHub OIDC provider + an IAM role Actions can assume. No long-lived
      access keys in repo secrets, ever. The single most interview-relevant detail here.

      **Gotcha that cost a debugging round — GitHub issues IMMUTABLE subject claims.** The trust
      policy was written the way every tutorial shows it:

          repo:Jovan253/KubePlayground:ref:refs/heads/main

      and the token actually said:

          repo:Jovan253@54801590/KubePlayground@1346312309:ref:refs/heads/main

      Every name carries its numeric ID. `StringEquals` is exact, so it never matched, and the
      error — "Not authorized to perform sts:AssumeRoleWithWebIdentity" — says nothing about why.

      This is a security feature, not a bug. Names are mutable: delete a repo or rename an
      account, someone else claims the name, and a policy matching plain names would trust THEIR
      workflows. Numeric IDs are never reused. So the fix is to match the immutable form, never
      to disable it.

      **The technique worth keeping:** don't guess at claim mismatches. A workflow step can
      request its own OIDC token and print selected claims — see
      `.github/workflows/aws-oidc-check.yml`. Print `sub` and nothing sensitive; the token itself
      is a bearer credential and must never reach a log.

      Ruled out first, in order: provider exists with the right audience, trust policy contents,
      canonical repo casing (`StringEquals` is case-sensitive and a git remote preserves whatever
      you typed, not GitHub's canonical name), default branch, and IAM propagation timing.
- [ ] **Step 2 — Registry.** ECR repository + lifecycle policy. The first point at which the image
      needs a real registry: `imagePullPolicy: IfNotPresent` with a locally-built tag stops
      working the moment the node is not your own laptop.
- [ ] **Step 3 — Network.** VPC, subnets, routing. Why EKS wants multiple AZs; why a NAT gateway
      costs real money, and how keeping nodes in public subnets avoids it.
- [ ] **Step 4 — Cluster.** EKS control plane + a small managed node group. What AWS runs for you,
      and what is still yours to run.
- [ ] **Step 5 — Access.** EKS access entries — how an AWS IAM identity becomes a Kubernetes RBAC
      subject. **The concept to actually understand:** authentication is AWS's job, authorisation
      is still Kubernetes RBAC. Two systems, joined at exactly one seam.
- [ ] **Workflows — Jovan writes these.** `terraform plan` on PR and `apply` on merge; build and
      push to ECR; deploy; smoke-test `/api/health`; a manually-triggered `destroy`.
- [ ] Concepts to be able to explain afterwards: OIDC federation vs static keys, why an image tag
      must be treated as immutable, and what does and does not change about RBAC on a managed
      cluster.

---

### ☐ M10 — A safe workload catalogue (the "playground" half)
*Added 2026-08-30. Answers "can the site create Deployments once it's on AWS?" — yes, but never
as a raw `create Deployment` endpoint.*

**Why not the obvious version.** `create` on deployments means the caller chooses the image, and
choosing the image is **arbitrary code execution in the cluster** — the same reasoning that made
`patch deployments` unacceptable in M3. Publicly reachable endpoints that accept workloads get
found by scanners quickly, and the usual payload is a crypto miner. On EKS that is a real bill,
and a pod that can reach IMDS may be able to borrow the node's instance credentials.

**The design instead:** the client sends a *choice*, never a spec. The server builds the manifest
from a fixed template.

- [ ] A **catalogue** of predefined workloads, rendered server-side: plain nginx, a sleeper, and
      the deliberately broken ones — bad image tag (`ImagePullBackOff`), oversized resource
      request (`Pending`/unschedulable), a tight memory limit (`OOMKilled`), a broken selector
      (empty EndpointSlice). These double as the "break it and diagnose it" scenarios.
- [ ] A namespaced **Role** granting `create`/`delete` in `playground` ONLY — not a ClusterRole.
- [ ] **ResourceQuota** + **LimitRange** on `playground`, so a runaway cannot eat the cluster or
      trigger the node autoscaler.
- [ ] A **CronJob** that wipes `playground` on a timer, so the public demo resets itself.
- [ ] Only then: the `create` verb and the POST endpoint.

**Order matters.** Ship the safeguards before the capability, not after — "add create now, secure
it later" is how a demo becomes an incident. Build this *after* M9: the pipeline is what makes
this a DevOps portfolio piece; the catalogue is a feature to add once there is somewhere to
deploy it.

Four objects the project hasn't touched yet — ResourceQuota, LimitRange, CronJob, and a
namespaced Role — so it holds to the original rule that every feature drags curriculum with it.

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
- **2026-08-27** — **M5 mostly done.** Frontend written (Claude), image rebuilt as `0.2.0`
  carrying both halves, rolled out. `http://localhost/` now shows live Deployments, Pods and
  Nodes with working scale buttons — which exercise the `deployments/scale` grant end to end.
  Tag bumped rather than rebuilt in place: same tag = identical Pod template = no new hash =
  no rollout, and `IfNotPresent` would keep serving cached bits. Treat tags as immutable.
  Left open: the ownership-chain visualisation (see M5), Pod detail/logs, and WebSocket.
  Next: M6, making it production-shaped — probes, limits, HPA, NetworkPolicy.
- **2026-08-30** — **Environment rebuild + M5b.** Found the machine no longer matches `CLAUDE.md`:
  Rancher Desktop, WSL2, k3s, the venv and the AKS context are all gone, and Docker Desktop's
  Kubernetes had never been enabled. `CLAUDE.md` and the context guard in `main.py` corrected to
  `docker-desktop`; the Traefik assumption in `k8s/14-ingress.yaml` is now wrong and unresolved.
  Also found the roadmap trailing the code — the Pod detail drawer was built but still logged as
  todo. Agreed two new directions: **M9**, ship to AWS via GitHub Actions using OIDC and no static
  keys; and **M5b**, make the app a playground rather than a viewer. Built M5b's two features — a
  kubectl transcript of every action, and a live-manifest viewer showing *as written* against
  *as stored*. Both read-only, so no RBAC change, and safe to expose publicly later.
  **Not yet verified against a live cluster** — there isn't one until Docker Desktop's Kubernetes
  is enabled. Next: enable it, re-apply `k8s/` in dependency order, test M5b, then M6.
