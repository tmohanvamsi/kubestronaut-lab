# CKA Labs — Certified Kubernetes Administrator

Exam weight breakdown (use to prioritise practice time):

| Domain | Weight |
|--------|--------|
| Cluster Architecture, Installation & Configuration | 25% |
| Workloads & Scheduling | 15% |
| Services & Networking | 20% |
| Storage | 10% |
| Troubleshooting | 30% |

---

## Lab 1 — Cluster Architecture

```bash
# Inspect control-plane components
kubectl get pods -n kube-system
kubectl describe pod -n kube-system kube-apiserver-kubestronaut-control-plane

# View etcd health
kubectl -n kube-system exec etcd-kubestronaut-control-plane -- \
  etcdctl --cacert=/etc/kubernetes/pki/etcd/ca.crt \
          --cert=/etc/kubernetes/pki/etcd/server.crt \
          --key=/etc/kubernetes/pki/etcd/server.key \
          endpoint health

# Backup etcd (exam staple)
kubectl -n kube-system exec etcd-kubestronaut-control-plane -- \
  etcdctl snapshot save /tmp/etcd-backup.db \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

## Lab 2 — Workloads & Scheduling

```bash
# Create a deployment, scale it, roll it back
kubectl create deployment nginx --image=nginx:1.25 --replicas=3 -n apps
kubectl rollout status deployment/nginx -n apps
kubectl set image deployment/nginx nginx=nginx:1.26 -n apps
kubectl rollout undo deployment/nginx -n apps

# Node affinity — schedule on worker nodes labelled workload=apps
kubectl label node kubestronaut-worker workload=apps
# Then apply manifests/workloads/node-affinity-demo.yaml
```

## Lab 3 — Services & Networking

```bash
# Expose a deployment and test connectivity
kubectl expose deployment nginx --port=80 --type=ClusterIP -n apps
kubectl run test-pod --image=busybox --rm -it --restart=Never -- wget -qO- nginx

# Apply and test NetworkPolicy
kubectl apply -f manifests/network-policies/deny-all-ingress.yaml
kubectl apply -f manifests/network-policies/allow-same-namespace.yaml

# Verify: pod in apps can still reach other pods in apps
kubectl run client --image=busybox --rm -it --restart=Never -n apps -- \
  wget -qO- http://nginx
```

## Lab 4 — Storage

```bash
# Create a PVC and mount it
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
  namespace: apps
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 100Mi
EOF

# Attach to a pod
kubectl run pvc-pod --image=busybox --restart=Never -n apps \
  --overrides='{"spec":{"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"test-pvc"}}],"containers":[{"name":"pvc-pod","image":"busybox","command":["sh","-c","echo hello > /data/test.txt && cat /data/test.txt"],"volumeMounts":[{"name":"data","mountPath":"/data"}]}]}}' \
  -- sh
```

## Lab 5 — Troubleshooting

```bash
# Simulate a broken pod and debug it
kubectl run broken --image=nginx:nonexistent -n apps
kubectl describe pod broken -n apps   # check Events
kubectl logs broken -n apps --previous

# Check node issues
kubectl describe node kubestronaut-worker
kubectl top node   # requires metrics-server

# Install metrics-server in kind
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system \
  --type=json -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

## Key kubectl shortcuts for the exam

```bash
export do="--dry-run=client -o yaml"
export now="--force --grace-period 0"

kubectl run nginx --image=nginx $do > pod.yaml
kubectl delete pod nginx $now
kubectl explain pod.spec.containers.securityContext
kubectl api-resources --namespaced=true
```
