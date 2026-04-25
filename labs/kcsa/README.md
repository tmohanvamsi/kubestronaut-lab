# KCSA Labs — Kubernetes and Cloud Native Security Associate

Foundational security exam. Multiple-choice, no hands-on tasks.
The lab gives you practical exposure to each domain.

| Domain | Weight |
|--------|--------|
| Overview of Cloud Native Security | 14% |
| Kubernetes Cluster Component Security | 22% |
| Kubernetes Security Fundamentals | 22% |
| Kubernetes Threat Model | 16% |
| Platform Security | 16% |
| Compliance and Security Frameworks | 10% |

---

## Domain 1 — 4Cs of Cloud Native Security

```
Cloud → Cluster → Container → Code
```

Each layer depends on the one below it being secure.

```bash
# Cloud layer: IAM, VPC, network ACLs (out of scope for kind)

# Cluster layer: RBAC, NetworkPolicy, PSS
kubectl get clusterrolebindings | grep cluster-admin

# Container layer: no root, read-only FS, dropped caps
kubectl apply -f manifests/pod-security/restricted-namespace.yaml

# Code layer: no secrets in env, dependency scanning
# trivy image myapp:latest
```

## Domain 2 — Cluster Component Security

```bash
# kube-apiserver flags to know
docker exec kubestronaut-control-plane \
  cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep -E "authorization-mode|audit|anonymous"

# Key flags:
# --authorization-mode=Node,RBAC         (not AlwaysAllow)
# --audit-log-path=/var/log/audit.log
# --anonymous-auth=false
# --insecure-port=0                       (disable HTTP)
# --tls-cert-file / --tls-private-key-file

# etcd encryption at rest
docker exec kubestronaut-control-plane \
  cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep encryption

# kubelet security
docker exec kubestronaut-worker \
  cat /var/lib/kubelet/config.yaml | grep -E "anonymous|authorization"
```

## Domain 3 — Kubernetes Security Fundamentals

```bash
# RBAC: principle of least privilege
kubectl apply -f manifests/rbac/developer-role.yaml
kubectl apply -f manifests/rbac/readonly-clusterrole.yaml

# Verify with auth can-i
kubectl auth can-i create pods --as=system:serviceaccount:apps:default -n apps
kubectl auth can-i create pods --as=system:serviceaccount:apps:viewer  -n apps

# Secrets: know these limitations for the exam
# - stored base64 (not encrypted) in etcd by default
# - use EncryptionConfiguration to enable AES encryption at rest
# - use external stores (Vault, AWS Secrets Manager) for production

kubectl get secret -n apps -o yaml | grep -v "^  annotations"

# Pod Security Admission (PSA)
# Labels: enforce, warn, audit × baseline, restricted, privileged
kubectl get ns apps --show-labels
```

## Domain 4 — Threat Model

Key attack vectors for the exam:

| Threat | Mitigation |
|--------|-----------|
| Compromised container | PSS restricted, no-root, read-only FS, dropped caps |
| API server exposure | RBAC, NetworkPolicy to API server, audit logs |
| Secret exfiltration | Encryption at rest, vault, RBAC on secrets |
| Lateral movement | NetworkPolicy default-deny, namespace isolation |
| Supply chain | Image scanning (trivy), image digest pinning, Kyverno |
| Privileged container | PSS Baseline enforcement, Kyverno disallow-privileged |

```bash
# Test lateral movement prevention
kubectl apply -f manifests/network-policies/deny-all-ingress.yaml
kubectl run attacker -n default --image=busybox --rm -it --restart=Never -- \
  wget --timeout=3 http://nginx.apps.svc.cluster.local
# Should timeout — cross-namespace blocked
```

## Domain 5 — Platform Security

```bash
# Kyverno policy engine (admission controller)
kubectl apply -f manifests/kyverno/policies/

# Check which policies are enforced vs audited
kubectl get clusterpolicies -o custom-columns="NAME:.metadata.name,ACTION:.spec.validationFailureAction"

# Image pull policies
# Always    → prevents using cached/compromised images
# IfNotPresent → default (acceptable for immutable tags/digests)
# Never     → only use pre-loaded images (air-gapped)

# Service Account token mounting
# By default every pod gets a SA token mounted at /var/run/secrets/kubernetes.io/serviceaccount/
# Disable when the pod doesn't need API access:
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: no-sa-token
  namespace: apps
spec:
  automountServiceAccountToken: false
  containers:
  - name: app
    image: nginx
EOF
```

## Domain 6 — Compliance Frameworks

Key frameworks to know (conceptual, no hands-on):

- **CIS Kubernetes Benchmark** — hardening checklist; run with `kube-bench`
- **NIST SP 800-190** — container security guide
- **PCI-DSS** — card data; requires network segmentation, audit logs
- **SOC 2** — access controls, monitoring, incident response
- **GDPR** — data residency, encryption, breach notification

```bash
# kube-bench (CIS benchmark scanner)
docker run --pid=host --net=host --rm \
  -v /etc:/etc:ro \
  -v /var/lib:/var/lib:ro \
  aquasec/kube-bench:latest \
  --benchmark cis-1.8
```
