# KCNA Labs — Kubernetes and Cloud Native Associate

Foundational, multiple-choice exam. No hands-on tasks, but this lab
gives you practical exposure to every concept tested.

| Domain | Weight |
|--------|--------|
| Kubernetes Fundamentals | 46% |
| Container Orchestration | 22% |
| Cloud Native Architecture | 16% |
| Cloud Native Observability | 8% |
| Cloud Native Application Delivery | 8% |

---

## Concept: Kubernetes Core Objects

```bash
# Every object has: apiVersion, kind, metadata, spec, status

# Pods — smallest deployable unit
kubectl explain pod.spec
kubectl explain pod.spec.containers

# ReplicaSet — ensures N copies
kubectl explain replicaset.spec.replicas

# Deployment — ReplicaSet + rolling updates
kubectl create deployment demo --image=nginx --replicas=2 -n apps
kubectl rollout history deployment/demo -n apps

# StatefulSet — ordered, stable identity (databases)
kubectl explain statefulset.spec.serviceName

# DaemonSet — one pod per node (log agents, monitoring)
kubectl get daemonset -n kube-system

# Service types
kubectl explain service.spec.type
# ClusterIP  → internal only
# NodePort   → accessible on every node IP
# LoadBalancer → cloud LB (emulated in kind via NodePort)
```

## Concept: Container Orchestration

```bash
# Scheduler: assigns pods to nodes
kubectl get events -n apps --sort-by='.lastTimestamp'

# Kubelet: runs containers on each node
docker exec kubestronaut-worker cat /var/lib/kubelet/config.yaml

# Kube-proxy: manages iptables/IPVS rules for Services
kubectl get pods -n kube-system -l k8s-app=kube-proxy

# Container runtime (containerd)
docker exec kubestronaut-control-plane crictl ps
```

## Concept: Cloud Native Architecture (12-factor)

Key principles to know for KCNA:
1. **Codebase** — one repo, many deploys
2. **Dependencies** — declared and isolated (requirements.txt, go.mod)
3. **Config** — in environment (ConfigMaps/Secrets, not hardcoded)
4. **Backing services** — treat as attached resources (DB = env var URL)
5. **Stateless processes** — state in backing services, not in-process
6. **Port binding** — export service via port (containers do this naturally)
7. **Concurrency** — scale via process model (replicas)
8. **Disposability** — fast startup, graceful shutdown
9. **Dev/prod parity** — same images across environments
10. **Logs** — treat as event streams (stdout → Loki → Grafana)

## Concept: Observability

```bash
# The three pillars: Metrics, Logs, Traces

# Metrics (Prometheus)
make monitoring-ui   # → Grafana http://localhost:3000

# Logs (Loki → Grafana)
# In Grafana: Explore → select Loki → query {namespace="apps"}

# Traces (OpenTelemetry → Tempo)
# Instrument apps with otel SDK; traces appear in Grafana Explore → Tempo

# Useful kubectl for observability
kubectl top pods -n apps          # requires metrics-server
kubectl top nodes
kubectl logs -f deployment/nginx -n apps
kubectl logs -f deployment/nginx -n apps --all-containers
```

## Concept: GitOps / Application Delivery

```bash
# ArgoCD = pull-based GitOps controller
# Git repo is the source of truth; ArgoCD syncs cluster state to match

make argocd-ui   # http://localhost:8080

# Key ArgoCD concepts:
# Application   — maps a Git path to a cluster namespace
# Project       — groups Applications with access controls
# Sync Policy   — manual vs automated (auto-heal, auto-prune)
# App of Apps   — one Application that deploys other Applications

# See manifests/argocd/app-of-apps.yaml for the pattern
```
