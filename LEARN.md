# Kubestronaut Lab — Step-by-Step Learning Guide

Work through this file **top to bottom**. Every section has:
- **What it is** — the concept
- **The file** — what we wrote and why each line exists
- **Run this** — the exact command to execute
- **What to observe** — what to look for in the output
- **The exam connection** — which cert domain this covers

---

## Step 0 — Check your prerequisites

```bash
# Run each line and confirm you get a version back
docker --version          # Docker Desktop must be running
kind version              # should say v0.23.x
kubectl version --client  # should say v1.29+
helm version --short      # should say v3.x
terraform version         # should say v1.6+
ansible --version         # should say 2.x
```

**If anything is missing:**
```bash
make ansible-tools   # installs everything via Homebrew
```

---

## Step 1 — The kind cluster

### What is kind?

kind = **K**ubernetes **IN** **D**ocker. It runs entire Kubernetes nodes as Docker
containers on your laptop. No VM, no cloud account needed.

### Read the cluster file first

Open [kind/cluster.yaml](kind/cluster.yaml). Here's what every section does:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: kubestronaut        # ← cluster name, also used in kubeconfig context
```

```yaml
nodes:
  - role: control-plane   # ← this node runs: API server, etcd, Scheduler,
                          #   Controller Manager, CoreDNS
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"   # ← lets nginx ingress bind here
    extraPortMappings:
      - containerPort: 8080   # ← port INSIDE the cluster node (Docker container)
        hostPort: 8080        # ← port on YOUR Mac — http://localhost:8080
```

```yaml
  - role: worker    # worker-1 → we label it: role=worker-apps
  - role: worker    # worker-2 → we label it: role=worker-observability
```

```yaml
networking:
  podSubnet: "10.244.0.0/16"      # ← IPs assigned to Pods
  serviceSubnet: "10.96.0.0/16"   # ← IPs assigned to Services (ClusterIP)
```

### Run it

```bash
make cluster-create
```

This runs `kind create cluster --config kind/cluster.yaml` then labels the workers.
Takes ~2 minutes.

### What to observe

```bash
kubectl get nodes -o wide --show-labels
```

Expected output:
```
NAME                         STATUS   ROLES           LABELS
kubestronaut-control-plane   Ready    control-plane   ingress-ready=true,role=control-plane,...
kubestronaut-worker          Ready    <none>          role=worker-apps,...
kubestronaut-worker2         Ready    <none>          role=worker-observability,...
```

Now explore what's running inside:
```bash
# The cluster runs as Docker containers — each node is a container
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"

# System components that kubeadm started for you
kubectl get pods -n kube-system

# Your kubeconfig was automatically updated — see the new context
kubectl config get-contexts
kubectl config current-context   # → kind-kubestronaut
```

**Exam connection — CKA (25% Cluster Architecture):** The exam asks you to understand
what runs on a control-plane node vs a worker. You just built one from scratch.

---

## Step 2 — Ansible: install tools and understand the playbook

### What is Ansible?

Ansible runs tasks on machines (local or remote) declared in YAML. It's idempotent —
running it twice gives the same result as running it once.

### Read the inventory first

Open [ansible/inventory/hosts.ini](ansible/inventory/hosts.ini):

```ini
[local]
localhost ansible_connection=local   # ← runs tasks on YOUR machine, no SSH
```

The `[remote]` section is where you'd add cloud VMs when going multi-cloud.

### Read setup-tools.yml

Open [ansible/playbooks/setup-tools.yml](ansible/playbooks/setup-tools.yml).

Key ideas to notice:
- `hosts: local` → targets the `[local]` group in inventory
- `when: ansible_os_family == "Darwin"` → runs only on macOS
- `community.general.homebrew` → Ansible module that calls `brew install`
- Each `name:` block is a **task** — Ansible reports changed/ok/failed per task
- `args: creates: /usr/local/bin/kubectl` → skip if binary already exists (idempotency)

### Run it

```bash
make ansible-tools
# or directly:
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/setup-tools.yml
```

Watch the output — each line is a task. Green = ok, yellow = changed, red = failed.

### What to observe

```bash
# After it finishes, verify every tool installed
kubectl version --client --short
helm version --short
argocd version --client --short 2>/dev/null
istioctl version --remote=false 2>/dev/null
```

**Exam connection — DevOps/MLOps:** Ansible is how you configure remote VMs before
they join a Kubernetes cluster. The same playbook works on your Mac today and on
an AWS EC2 instance tomorrow — you only change the inventory.

---

## Step 3 — Terraform: manage cluster resources as code

### What is Terraform doing here?

Normally Terraform provisions cloud infrastructure (VMs, VPCs). Here we use the
**hashicorp/kubernetes provider** to create Kubernetes objects *inside* the running
cluster — without touching any cloud.

This lets you practice: "declare state in code → apply → observe → change → apply again."

### Read the files

**[terraform/local/variables.tf](terraform/local/variables.tf)**
```hcl
variable "kube_context" {
  default = "kind-kubestronaut"   # ← points at the kind cluster in your kubeconfig
}
variable "namespaces" {
  default = ["apps", "staging", "monitoring", "argocd", ...]
}
```

**[terraform/local/main.tf](terraform/local/main.tf)** — key blocks:

```hcl
provider "kubernetes" {
  config_path    = var.kubeconfig_path   # ~/.kube/config
  config_context = var.kube_context      # kind-kubestronaut
}

resource "kubernetes_namespace" "namespaces" {
  for_each = toset(var.namespaces)   # ← creates ONE namespace per item in the list
  metadata { name = each.value }
}

resource "kubernetes_role" "developer" {
  # Role scoped to a namespace — can do most things EXCEPT delete secrets
}

resource "kubernetes_cluster_role" "readonly" {
  # ClusterRole — cluster-wide read access — great for CI pipelines / auditors
}

resource "kubernetes_resource_quota" "apps" {
  # Limits total CPU/memory/pods in the 'apps' namespace
}

resource "kubernetes_limit_range" "apps" {
  # Default CPU/memory for containers that don't set their own requests/limits
}
```

### Run it

```bash
cd /Users/tmohanvamsi/Documents/Code/kubestronaut-lab
make terraform-init    # downloads the kubernetes + helm providers (~30 seconds)
make terraform-apply   # creates namespaces, roles, quotas
```

### What to observe

```bash
# Namespaces Terraform created
kubectl get namespaces

# The developer Role in the apps namespace
kubectl describe role developer -n apps

# The cluster-wide read-only role
kubectl describe clusterrole cluster-readonly

# ResourceQuota limiting the apps namespace
kubectl describe resourcequota apps-quota -n apps

# LimitRange giving default CPU/mem to containers
kubectl describe limitrange apps-limits -n apps

# Test: try to delete a pod as a 'viewer' (should be denied)
kubectl auth can-i delete pods --as=system:serviceaccount:apps:default -n apps
```

Now make a change — edit `terraform/local/variables.tf`, add `"dev"` to the namespaces list:
```bash
# Edit the file, then:
make terraform-apply
kubectl get ns   # 'dev' appears
```

Remove it and apply again — `dev` is gone. This is **IaC lifecycle management**.

**Exam connection — CKA (15% Workloads & Scheduling) + CKS (15% Cluster Hardening):**
RBAC, ResourceQuotas, and LimitRanges are exam staples. Terraform shows you the
declarative model; `kubectl describe` shows you the live state.

---

## Step 4 — ArgoCD: GitOps continuous delivery

### What is ArgoCD?

ArgoCD watches a Git repository and continuously syncs the cluster to match it.
You never `kubectl apply` in production — you push to Git, ArgoCD does the rest.

### Install it

```bash
make argocd-install
```

This applies the official ArgoCD manifest to the `argocd` namespace and waits for
the server deployment to become available.

### What to observe

```bash
# All ArgoCD components
kubectl get pods -n argocd

# The main pieces:
# argocd-server          → the API + UI
# argocd-application-controller → watches cluster state
# argocd-repo-server     → clones Git repos
# argocd-dex-server      → SSO/auth
# argocd-redis           → caching
```

### Open the UI

```bash
make argocd-password    # prints the initial admin password
make argocd-ui          # port-forwards to http://localhost:8080
```

Go to http://localhost:8080 → login: `admin` / (password from above)

### Deploy an app through ArgoCD (the GitOps way)

```bash
# Log in via CLI
argocd login localhost:8080 --username admin --password $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d) --insecure

# Create an app that points at the nginx helm chart
argocd app create nginx-demo \
  --repo https://charts.bitnami.com/bitnami \
  --helm-chart nginx \
  --revision 15.0.0 \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace apps \
  --sync-policy automated

# Watch it sync
argocd app get nginx-demo
argocd app list
```

Look in the ArgoCD UI — you'll see the app tree: Deployment → ReplicaSet → Pods.

### Read the App-of-Apps manifest

Open [manifests/argocd/app-of-apps.yaml](manifests/argocd/app-of-apps.yaml).
This pattern lets ONE ArgoCD Application deploy ALL other Applications.
It's how real organisations manage hundreds of services.

**Exam connection — CKAD (20% Application Deployment) + KCNA (8% Application Delivery):**
Understanding GitOps pull model vs push model (`kubectl apply`) is tested in CKAD and KCNA.

---

## Step 5 — Kyverno: policy engine

### What is Kyverno?

Kyverno is an **admission controller** — it intercepts every create/update request
to the Kubernetes API server before it's stored in etcd, and can:
- **Validate** (reject or warn if rules violated)
- **Mutate** (auto-patch resources — e.g., add a label)
- **Generate** (create related resources automatically)

### Install it

```bash
make kyverno-install
```

### Apply the policies

```bash
make kyverno-policies
```

### Read the policies one by one

**[manifests/kyverno/policies/disallow-privileged.yaml](manifests/kyverno/policies/disallow-privileged.yaml)**
```yaml
validationFailureAction: Enforce   # ← BLOCKS the request (vs Audit which only logs)
spec:
  containers:
    securityContext:
      privileged: "false"          # ← pattern match — must be false
```

**[manifests/kyverno/policies/require-resource-limits.yaml](manifests/kyverno/policies/require-resource-limits.yaml)**
```yaml
validationFailureAction: Audit     # ← LOGS a violation but allows it through
spec:
  containers:
    resources:
      limits:
        cpu: "?*"                  # ← ?* means "any non-empty value"
        memory: "?*"
```

### Test the policies

```bash
# This should be REJECTED (privileged=true, policy is Enforce)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: bad-pod
  namespace: default
spec:
  containers:
  - name: bad
    image: busybox
    securityContext:
      privileged: true
EOF
# Expected: "admission webhook ... denied the request"

# Check audit violations (Audit mode policies)
kubectl get policyreport -A
kubectl get clusterpolicyreport -o yaml | grep -A5 "status:"
```

**Exam connection — CKS (20% Minimize Microservice Vulnerabilities) + KCSA (16% Platform Security):**
Admission controllers are a core CKS topic. Kyverno is the modern OPA/Gatekeeper alternative.

---

## Step 6 — Monitoring: Prometheus + Grafana + Loki

### What we're installing

| Tool | What it does |
| ---- | ------------ |
| Prometheus | Scrapes metrics from every pod/node every 15s, stores as time-series |
| Grafana | Dashboards that query Prometheus + Loki |
| Loki | Log aggregation — receives logs from Promtail |
| Promtail | DaemonSet that tails container logs and ships to Loki |

### Install it

```bash
make monitoring-install   # takes 3-5 minutes — pulling images
```

### What to observe

```bash
# All pods should be Running
kubectl get pods -n monitoring

# Key workloads:
# kube-prometheus-stack-grafana                → Grafana UI
# kube-prometheus-stack-prometheus-0           → Prometheus server
# kube-prometheus-stack-operator-*             → manages Prometheus config
# kube-prometheus-stack-kube-state-metrics-*   → K8s object metrics
# kube-prometheus-stack-prometheus-node-exporter-* → node metrics (DaemonSet)
# loki-0                                       → Loki log store
# loki-promtail-*                              → log collector (DaemonSet)
```

### Read the Prometheus values

Open [monitoring/prometheus/values.yaml](monitoring/prometheus/values.yaml):

```yaml
prometheus:
  prometheusSpec:
    retention: 7d                        # ← keep metrics for 7 days
    serviceMonitorSelectorNilUsesHelmValues: false  # ← scrape ALL ServiceMonitors
    storageSpec:                         # ← PVC for persistent metrics storage
      ...

grafana:
  adminPassword: prom-operator           # ← change this in production!
  service:
    type: NodePort
    nodePort: 30300                      # ← maps to localhost:3000 via kind port mapping
  dashboards:
    default:
      kubernetes-cluster:
        gnetId: 7249                     # ← auto-imports this dashboard from grafana.com
```

### Open the dashboards

```bash
make monitoring-ui    # port-forwards Grafana → http://localhost:3000
# Login: admin / prom-operator
```

In Grafana:
1. Click **Dashboards** → you'll see pre-loaded K8s dashboards
2. Click **Kubernetes / Compute Resources / Cluster** — see CPU/memory per node
3. Click **Explore** → switch to **Loki** → query: `{namespace="argocd"}` → see live logs

### Query Prometheus directly

```bash
# Port-forward Prometheus
kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090 &
# Open http://localhost:9090
```

Try these PromQL queries in the Prometheus UI:
```promql
# CPU usage per node
rate(node_cpu_seconds_total{mode="idle"}[5m])

# Memory used per pod in argocd namespace
container_memory_working_set_bytes{namespace="argocd"}

# Number of pods per node
count by (node) (kube_pod_info)
```

**Exam connection — CKS (20% Monitoring, Logging, Runtime Security) + KCNA (8% Observability):**
Understanding the three pillars (metrics/logs/traces) and how to query them is tested.

---

## Step 7 — Network Policies: zero-trust networking

### What is a NetworkPolicy?

By default Kubernetes allows ALL pod-to-pod traffic. NetworkPolicy lets you whitelist
exactly which traffic is allowed — every other flow is dropped.

### Apply the policies

```bash
kubectl apply -f manifests/network-policies/deny-all-ingress.yaml
kubectl apply -f manifests/network-policies/allow-same-namespace.yaml
kubectl apply -f manifests/network-policies/allow-monitoring-scrape.yaml
```

### Read each one

**[manifests/network-policies/deny-all-ingress.yaml](manifests/network-policies/deny-all-ingress.yaml)**
```yaml
podSelector: {}      # matches ALL pods in the namespace
policyTypes: [Ingress]
# No ingress rules → blocks ALL inbound traffic
```

**[manifests/network-policies/allow-same-namespace.yaml](manifests/network-policies/allow-same-namespace.yaml)**
```yaml
ingress:
  - from:
    - podSelector: {}   # from: any pod... with no namespaceSelector = same namespace only
```

### Test them

```bash
# Create two pods to test with
kubectl run server --image=nginx -n apps
kubectl run client --image=busybox -n apps -- sleep 3600
kubectl run attacker --image=busybox -n default -- sleep 3600

# Wait for them to start
kubectl get pods -n apps
kubectl get pods -n default

# Get the server's cluster IP
SERVER_IP=$(kubectl get pod server -n apps -o jsonpath='{.status.podIP}')

# Test 1: client in SAME namespace → should WORK
kubectl exec client -n apps -- wget -qO- --timeout=3 $SERVER_IP

# Test 2: attacker in DEFAULT namespace → should TIMEOUT (blocked)
kubectl exec attacker -n default -- wget -qO- --timeout=3 $SERVER_IP
```

**Exam connection — CKA (20% Services & Networking) + CKS (10% Cluster Setup):**
NetworkPolicy is one of the most-tested CKA topics. Know default-deny + selective-allow cold.

---

## Step 8 — Pod Security Standards

### What is PSS?

Pod Security Standards replace the old PodSecurityPolicy. You label a namespace
and Kubernetes enforces one of three profiles on every pod in it:
- `privileged` — anything goes (system namespaces)
- `baseline` — blocks the most dangerous settings
- `restricted` — maximum hardening (no root, no caps, read-only FS)

### Apply it

```bash
kubectl apply -f manifests/pod-security/restricted-namespace.yaml
```

### Read the file

Open [manifests/pod-security/restricted-namespace.yaml](manifests/pod-security/restricted-namespace.yaml):

```yaml
metadata:
  name: apps
  labels:
    pod-security.kubernetes.io/enforce: restricted   # ← rejects non-compliant pods
    pod-security.kubernetes.io/warn: restricted      # ← warns but allows (useful while migrating)
    pod-security.kubernetes.io/audit: restricted     # ← logs to audit log
```

### Test it

```bash
# This pod runs as root → REJECTED by restricted PSS
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: root-pod
  namespace: apps
spec:
  containers:
  - name: c
    image: nginx    # nginx runs as root by default
EOF

# This pod is fully compliant → ACCEPTED
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
  namespace: apps
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: busybox
    command: ["sleep", "3600"]
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
      readOnlyRootFilesystem: true
EOF
```

**Exam connection — CKS (20% Minimize Microservice Vulnerabilities) + KCSA (22% K8s Security Fundamentals).**

---

## Step 9 — RBAC: who can do what

### Already created by Terraform (Step 3). Now let's really test it.

```bash
# Create a ServiceAccount to test with
kubectl create serviceaccount dev-user -n apps

# Bind the 'developer' Role to it
kubectl create rolebinding dev-user-binding \
  --role=developer \
  --serviceaccount=apps:dev-user \
  -n apps

# Test: what CAN dev-user do?
kubectl auth can-i list pods        --as=system:serviceaccount:apps:dev-user -n apps   # yes
kubectl auth can-i create deployments --as=system:serviceaccount:apps:dev-user -n apps # yes
kubectl auth can-i delete secrets   --as=system:serviceaccount:apps:dev-user -n apps   # no
kubectl auth can-i list nodes       --as=system:serviceaccount:apps:dev-user           # no (cluster-scoped)

# Test the cluster-readonly ClusterRole
kubectl create serviceaccount auditor -n default
kubectl create clusterrolebinding auditor-binding \
  --clusterrole=cluster-readonly \
  --serviceaccount=default:auditor

kubectl auth can-i list pods   --as=system:serviceaccount:default:auditor -A    # yes
kubectl auth can-i delete pods --as=system:serviceaccount:default:auditor -A    # no
```

**Exam connection — CKA + CKS:** `kubectl auth can-i` is the fastest way to verify RBAC
on the exam. Know it cold.

---

## Step 10 — Run the full stack in one shot

Now that you understand each piece, tear it down and build it all from scratch:

```bash
make clean            # deletes cluster + terraform state (confirm with 'yes')
make cluster-create   # fresh 4-node cluster
make full-stack       # ArgoCD + Kyverno + Prometheus/Grafana/Loki
make terraform-apply  # namespaces, RBAC, quotas
```

Then validate everything:

```bash
make cluster-status
kubectl get pods -A | grep -v Running   # should be empty after a few minutes

make argocd-password
make argocd-ui          # http://localhost:8080

make monitoring-ui      # http://localhost:3000
```

---

## What's next

| You want to practice | Do this |
| -------------------- | ------- |
| CKA: etcd backup | [labs/cka/README.md](labs/cka/README.md) → Lab 1 |
| CKA: troubleshooting | [labs/cka/README.md](labs/cka/README.md) → Lab 5 |
| CKAD: probes, jobs, ingress | [labs/ckad/README.md](labs/ckad/README.md) |
| CKS: full hardening run | [labs/cks/README.md](labs/cks/README.md) |
| KCNA: concepts + exploration | [labs/kcna/README.md](labs/kcna/README.md) |
| KCSA: kube-bench, threat model | [labs/kcsa/README.md](labs/kcsa/README.md) |
| Add Istio service mesh | `make istio-install` → [labs/cks/README.md](labs/cks/README.md) |
| Add Flux (alternative GitOps) | Coming in Phase 2 |
| Move to cloud (EKS/GKE) | Update `ansible/inventory/hosts.ini` + add `terraform/aws/` |
