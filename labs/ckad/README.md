# CKAD Labs — Certified Kubernetes Application Developer

| Domain | Weight |
|--------|--------|
| Application Design and Build | 20% |
| Application Deployment | 20% |
| Application Observability and Maintenance | 15% |
| Application Environment, Configuration, Security | 25% |
| Services and Networking | 20% |

---

## Lab 1 — Application Design and Build

```bash
# Multi-container pod (sidecar pattern)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: sidecar-demo
  namespace: apps
spec:
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - name: shared-logs
      mountPath: /var/log/nginx
  - name: log-shipper
    image: busybox
    command: ["sh", "-c", "tail -f /logs/access.log"]
    volumeMounts:
    - name: shared-logs
      mountPath: /logs
  volumes:
  - name: shared-logs
    emptyDir: {}
EOF

# Init container pattern
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: init-demo
  namespace: apps
spec:
  initContainers:
  - name: init-db
    image: busybox
    command: ["sh", "-c", "until nc -z postgres 5432; do sleep 2; done"]
  containers:
  - name: app
    image: nginx
EOF
```

## Lab 2 — ConfigMaps and Secrets

```bash
# ConfigMap from literal
kubectl create configmap app-config \
  --from-literal=APP_ENV=staging \
  --from-literal=LOG_LEVEL=info \
  -n apps

# Secret from literal (base64 encoded automatically)
kubectl create secret generic db-creds \
  --from-literal=username=admin \
  --from-literal=password=s3cr3t \
  -n apps

# Mount both as env vars
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: config-demo
  namespace: apps
spec:
  containers:
  - name: app
    image: nginx
    envFrom:
    - configMapRef:
        name: app-config
    - secretRef:
        name: db-creds
EOF
```

## Lab 3 — Probes and Observability

```bash
# Liveness + readiness probes
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: probe-demo
  namespace: apps
spec:
  containers:
  - name: app
    image: nginx
    livenessProbe:
      httpGet:
        path: /
        port: 80
      initialDelaySeconds: 10
      periodSeconds: 5
    readinessProbe:
      httpGet:
        path: /
        port: 80
      initialDelaySeconds: 5
      periodSeconds: 3
    startupProbe:
      httpGet:
        path: /
        port: 80
      failureThreshold: 30
      periodSeconds: 10
EOF

# Check Grafana dashboards (make monitoring-ui) for pod metrics
```

## Lab 4 — Jobs and CronJobs

```bash
# One-shot Job
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: pi
  namespace: apps
spec:
  completions: 3
  parallelism: 2
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: pi
        image: perl
        command: ["perl", "-Mbignum=bpi", "-wle", "print bpi(2000)"]
EOF

# CronJob (every minute for testing)
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: hello
  namespace: apps
spec:
  schedule: "*/1 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: hello
            image: busybox
            command: ["echo", "hello from cronjob"]
EOF
```

## Lab 5 — Ingress

```bash
# Install ingress-nginx for kind
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s

# Create an Ingress
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: demo-ingress
  namespace: apps
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: demo.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx
            port:
              number: 80
EOF

# Test (add 127.0.0.1 demo.local to /etc/hosts)
curl -H "Host: demo.local" http://localhost
```
