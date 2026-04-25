# CKS Labs — Certified Kubernetes Security Specialist

> Prerequisite: valid CKA certification.

| Domain | Weight |
|--------|--------|
| Cluster Setup | 10% |
| Cluster Hardening | 15% |
| System Hardening | 15% |
| Minimize Microservice Vulnerabilities | 20% |
| Supply Chain Security | 20% |
| Monitoring, Logging, Runtime Security | 20% |

---

## Lab 1 — Cluster Hardening: RBAC

```bash
# Inspect current cluster-admin bindings (who has full access?)
kubectl get clusterrolebindings -o json | \
  jq '.items[] | select(.roleRef.name=="cluster-admin") | .metadata.name'

# Apply our read-only ClusterRole
kubectl apply -f manifests/rbac/readonly-clusterrole.yaml

# Test: create a ServiceAccount and bind it to readonly
kubectl create serviceaccount viewer -n apps
kubectl create clusterrolebinding viewer-binding \
  --clusterrole=cluster-readonly \
  --serviceaccount=apps:viewer

# Impersonate and verify access
kubectl auth can-i list pods --as=system:serviceaccount:apps:viewer
kubectl auth can-i delete pods --as=system:serviceaccount:apps:viewer  # should be no
```

## Lab 2 — Pod Security Standards

```bash
# Apply restricted PSS to apps namespace
kubectl apply -f manifests/pod-security/restricted-namespace.yaml

# This pod should fail (privileged + root)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: bad-pod
  namespace: apps
spec:
  containers:
  - name: bad
    image: nginx
    securityContext:
      privileged: true
      runAsUser: 0
EOF

# This pod should pass (restricted compliant)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: good-pod
  namespace: apps
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: nginx
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
      readOnlyRootFilesystem: true
    volumeMounts:
    - name: tmp
      mountPath: /tmp
  volumes:
  - name: tmp
    emptyDir: {}
EOF
```

## Lab 3 — Network Policies (Zero-Trust)

```bash
# Apply default-deny then allow selectively
kubectl apply -f manifests/network-policies/deny-all-ingress.yaml
kubectl apply -f manifests/network-policies/allow-same-namespace.yaml
kubectl apply -f manifests/network-policies/allow-monitoring-scrape.yaml

# Test connectivity
kubectl run attacker --image=busybox --rm -it --restart=Never -- \
  wget --timeout=3 http://nginx.apps  # should fail from default namespace

kubectl run client --image=busybox --rm -it --restart=Never -n apps -- \
  wget --timeout=3 http://nginx      # should succeed (same namespace)
```

## Lab 4 — Kyverno Policies

```bash
# All policies are pre-loaded by make kyverno-install + make kyverno-policies

# Check policy reports
kubectl get policyreport -A
kubectl get clusterpolicyreport

# Test disallow-privileged (set to Enforce)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: priv-test
  namespace: default
spec:
  containers:
  - name: c
    image: busybox
    securityContext:
      privileged: true
EOF
# Should be REJECTED by Kyverno

# Audit report for require-resource-limits
kubectl get policyreport -n apps -o yaml | grep -A5 "policy: require-resource-limits"
```

## Lab 5 — Image Security and Supply Chain

```bash
# Scan an image with trivy (install: brew install trivy)
trivy image nginx:latest

# Set imagePullPolicy to Always (prevents cached image attacks)
kubectl patch deployment nginx -n apps \
  --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"Always"}]'

# OCI image with digest pinning (exam tip: use digest not tag)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pinned-image
  namespace: apps
spec:
  containers:
  - name: app
    image: nginx@sha256:4c0fdaa8b6341bfdeca5f18f7837462c80cff90527ee35ef185571e1c327beac
EOF
```

## Lab 6 — Audit Logging

```bash
# kind clusters don't expose audit logs by default.
# For exam practice, know where they live on a real cluster:
#   /etc/kubernetes/audit-policy.yaml  (policy)
#   /var/log/kubernetes/audit.log      (log output)

# A minimal audit policy
cat <<EOF
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: None
    resources:
    - group: ""
      resources: ["events"]
  - level: Metadata
    resources:
    - group: ""
      resources: ["secrets", "configmaps"]
  - level: RequestResponse
    resources:
    - group: ""
      resources: ["pods"]
  - level: Metadata
    userGroups: ["system:authenticated"]
EOF
```
