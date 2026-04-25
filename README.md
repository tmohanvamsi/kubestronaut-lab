# kubestronaut-lab

A local-first, $0-cost lab covering every domain for the full **Kubestronaut** stack:
CKA · CKAD · CKS · KCNA · KCSA

Runs entirely on your laptop via **kind** (4-node cluster). Cloud-agnostic by design —
swap kind for EKS/GKE when you're ready to go multi-cloud.

---

## Architecture

```text
┌─────────────────────────────────────────────────────┐
│  kind cluster: kubestronaut (local Docker)          │
│                                                     │
│  ┌──────────────────┐  ┌──────────┐  ┌──────────┐  │
│  │  control-plane   │  │ worker-1 │  │ worker-2 │  │
│  │  (ingress-ready) │  │ workload:│  │ workload:│  │
│  │                  │  │   apps   │  │   apps   │  │
│  └──────────────────┘  └──────────┘  └──────────┘  │
│                          ┌──────────┐               │
│                          │ worker-3 │               │
│                          │ workload:│               │
│                          │ platform │               │
│                          └──────────┘               │
└─────────────────────────────────────────────────────┘

Platform tools (via Helm):
  ArgoCD       → GitOps continuous delivery
  Kyverno      → Policy engine (PSS, OPA-style)
  kube-prometheus-stack → Metrics + Grafana
  Loki         → Log aggregation
  Istio        → Service mesh (optional)
```

---

## Prerequisites

| Tool | Install |
|------|---------|
| Docker Desktop | [docs.docker.com/desktop/mac](https://docs.docker.com/desktop/mac/) |
| kind | `brew install kind` |
| kubectl | `brew install kubectl` |
| helm | `brew install helm` |
| terraform | `brew install terraform` |
| ansible | `brew install ansible` |
| argocd CLI | `brew install argocd` |
| istioctl | `brew install istioctl` |

Or run everything at once:

```bash
make ansible-tools
```

---

## Quick start (5 minutes to a running cluster)

```bash
# 1. Create 4-node kind cluster
make cluster-create

# 2. Install everything: ArgoCD + Kyverno + Prometheus/Grafana + Loki
make full-stack

# 3. Open dashboards
make argocd-ui       # http://localhost:8080  (admin / make argocd-password)
make monitoring-ui   # http://localhost:3000  (admin / prom-operator)
```

---

## Repository layout

```text
kubestronaut-lab/
├── Makefile                        ← all commands live here
├── kind/
│   └── cluster.yaml                ← 1 control-plane + 3 workers
├── terraform/
│   └── local/                      ← Kubernetes provider (namespaces, RBAC, quotas)
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── ansible/
│   ├── inventory/hosts.ini         ← local + remote inventory
│   └── playbooks/
│       ├── setup-tools.yml         ← install full toolchain (macOS + Ubuntu)
│       └── setup-cluster.yml       ← bootstrap cluster (ArgoCD, Kyverno, monitoring)
├── manifests/
│   ├── argocd/                     ← ArgoCD install + App-of-Apps pattern
│   ├── kyverno/policies/           ← require-labels, disallow-privileged, resource-limits
│   ├── rbac/                       ← developer Role, cluster-readonly ClusterRole
│   ├── network-policies/           ← default-deny, same-namespace allow, monitoring allow
│   └── pod-security/               ← restricted PSS namespace label
├── monitoring/
│   ├── prometheus/values.yaml      ← kube-prometheus-stack Helm values
│   └── loki/values.yaml            ← Loki-stack Helm values
└── labs/
    ├── cka/README.md               ← CKA practice (etcd backup, RBAC, scheduling...)
    ├── ckad/README.md              ← CKAD practice (probes, jobs, ingress...)
    ├── cks/README.md               ← CKS practice (PSS, network policy, supply chain...)
    ├── kcna/README.md              ← KCNA concepts + hands-on exploration
    └── kcsa/README.md              ← KCSA security domains + kube-bench
```

---

## Cert domain coverage

| File / tool | CKA | CKAD | CKS | KCNA | KCSA |
| --- | :---: | :---: | :---: | :---: | :---: |
| `kind/cluster.yaml` — multi-node | ✓ | | | ✓ | |
| `terraform/local/` — namespaces, RBAC, quotas | ✓ | ✓ | ✓ | | ✓ |
| `manifests/argocd/` — GitOps | | ✓ | | ✓ | |
| `manifests/kyverno/` — policy engine | | | ✓ | | ✓ |
| `manifests/rbac/` — roles, bindings | ✓ | | ✓ | | ✓ |
| `manifests/network-policies/` — zero-trust | ✓ | | ✓ | | ✓ |
| `manifests/pod-security/` — PSS restricted | | | ✓ | | ✓ |
| `monitoring/prometheus/` — metrics | ✓ | ✓ | ✓ | ✓ | ✓ |
| `monitoring/loki/` — logs | ✓ | ✓ | ✓ | ✓ | |
| `labs/cka/` — etcd, scheduling, storage | ✓ | | | | |
| `labs/ckad/` — sidecar, probes, jobs | | ✓ | | | |
| `labs/cks/` — hardening, supply chain | | | ✓ | | |
| `labs/kcna/` — core concepts | | | | ✓ | |
| `labs/kcsa/` — 4Cs, threat model, kube-bench | | | | | ✓ |

---

## Terraform workflow (local Kubernetes provider)

```bash
make terraform-init     # terraform init
make terraform-apply    # creates namespaces, RBAC, quotas, LimitRanges via TF
make terraform-destroy  # tear it all down (prompts for confirmation)
```

Terraform here uses the **hashicorp/kubernetes** provider — no cloud credentials needed.
It's great CKA/CKS practice for managing cluster state declaratively.

---

## Ansible workflow

```bash
# Install tools on your Mac (or point inventory at remote VMs)
make ansible-tools

# Bootstrap an already-running cluster
make ansible-cluster
```

To target remote VMs: edit [ansible/inventory/hosts.ini](ansible/inventory/hosts.ini) under `[remote]`.

---

## Going multi-cloud (Phase 2)

When you're ready to move off kind:

| Cloud | Path |
| ----- | ---- |
| AWS (EKS) | Add `terraform/aws/` with EKS module, update inventory |
| GCP (GKE) | Add `terraform/gcp/` with GKE module, update inventory |
| Bare VM | Ansible `setup-tools.yml` handles Ubuntu, then point kubeconfig |

The manifests, Helm values, and Ansible playbooks are all cloud-agnostic — only the
Terraform provider block changes.

---

## Common commands reference

```bash
make help              # full command listing
make cluster-create    # spin up kind cluster
make cluster-destroy   # tear down (asks for confirmation)
make cluster-status    # nodes + system pods
make full-stack        # cluster + ArgoCD + Kyverno + monitoring
make argocd-password   # initial admin password
make argocd-ui         # port-forward → http://localhost:8080
make monitoring-ui     # port-forward → http://localhost:3000
make kyverno-policies  # apply all policies from manifests/kyverno/policies/
make terraform-apply   # manage cluster resources via Terraform
make ansible-tools     # install full toolchain
make lab-cka           # open CKA practice guide
make lab-cks           # open CKS practice guide
make clean             # delete cluster + terraform state
```
