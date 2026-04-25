CLUSTER_NAME   := kubestronaut
KUBECONFIG     := $(HOME)/.kube/config
KUBECTL        := kubectl
HELM           := helm
ARGOCD_NS      := argocd
KYVERNO_NS     := kyverno
MONITORING_NS  := monitoring
ISTIO_NS       := istio-system

.PHONY: help cluster-create cluster-destroy cluster-status tools-install \
        argocd-install argocd-password argocd-ui \
        kyverno-install kyverno-policies \
        monitoring-install monitoring-ui \
        istio-install istio-ui \
        terraform-init terraform-apply terraform-destroy \
        ansible-tools ansible-cluster \
        lab-cka lab-ckad lab-cks lab-kcna lab-kcsa \
        full-stack clean

help:
	@echo ""
	@echo "  Kubestronaut Lab — command reference"
	@echo "  ====================================="
	@echo ""
	@echo "  CLUSTER"
	@echo "    make cluster-create     Create kind cluster (4 nodes)"
	@echo "    make cluster-destroy    Delete kind cluster"
	@echo "    make cluster-status     Show node and pod status"
	@echo ""
	@echo "  TOOLS (via Ansible)"
	@echo "    make ansible-tools      Install kubectl, helm, kind, argocd, kyverno, istioctl"
	@echo "    make ansible-cluster    Bootstrap cluster with all platform tools"
	@echo ""
	@echo "  PLATFORM"
	@echo "    make argocd-install     Install ArgoCD"
	@echo "    make argocd-password    Get initial admin password"
	@echo "    make argocd-ui          Port-forward ArgoCD UI to :8080"
	@echo "    make kyverno-install    Install Kyverno policy engine"
	@echo "    make kyverno-policies   Apply all policies from manifests/kyverno/policies/"
	@echo "    make monitoring-install Install kube-prometheus-stack + Loki"
	@echo "    make monitoring-ui      Port-forward Grafana to :3000"
	@echo "    make istio-install      Install Istio (minimal profile)"
	@echo ""
	@echo "  TERRAFORM (local K8s provider)"
	@echo "    make terraform-init     terraform init"
	@echo "    make terraform-apply    terraform apply (local only)"
	@echo "    make terraform-destroy  terraform destroy (local only)"
	@echo ""
	@echo "  LABS"
	@echo "    make lab-cka            Print CKA lab hints"
	@echo "    make lab-ckad           Print CKAD lab hints"
	@echo "    make lab-cks            Print CKS lab hints"
	@echo "    make lab-kcna           Print KCNA lab hints"
	@echo "    make lab-kcsa           Print KCSA lab hints"
	@echo ""
	@echo "  SHORTCUTS"
	@echo "    make full-stack         cluster-create + all platform tools"
	@echo "    make clean              Remove cluster + terraform state"
	@echo ""

# ─── CLUSTER ─────────────────────────────────────────────────────────────────

cluster-create:
	kind create cluster --config kind/cluster.yaml --name $(CLUSTER_NAME)
	@echo "Labelling nodes..."
	$(KUBECTL) label node kubestronaut-worker  role=worker-apps          --overwrite
	$(KUBECTL) label node kubestronaut-worker2 role=worker-observability --overwrite
	$(KUBECTL) cluster-info --context kind-$(CLUSTER_NAME)
	$(KUBECTL) get nodes -o wide --show-labels

cluster-destroy:
	@echo "WARNING: This will delete the '$(CLUSTER_NAME)' cluster."
	@read -p "Type 'yes' to confirm: " confirm && [ "$$confirm" = "yes" ] || (echo "Aborted." && exit 1)
	kind delete cluster --name $(CLUSTER_NAME)

cluster-status:
	@echo "=== Nodes ==="
	$(KUBECTL) get nodes -o wide
	@echo ""
	@echo "=== System Pods ==="
	$(KUBECTL) get pods -A --field-selector=metadata.namespace==kube-system

# ─── ANSIBLE ─────────────────────────────────────────────────────────────────

ansible-tools:
	ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/setup-tools.yml

ansible-cluster:
	ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/setup-cluster.yml

# ─── ARGOCD ──────────────────────────────────────────────────────────────────

argocd-install:
	$(KUBECTL) create namespace $(ARGOCD_NS) --dry-run=client -o yaml | $(KUBECTL) apply -f -
	$(KUBECTL) apply -n $(ARGOCD_NS) -f manifests/argocd/install.yaml
	@echo "Waiting for ArgoCD to be ready..."
	$(KUBECTL) wait --for=condition=available --timeout=120s deployment/argocd-server -n $(ARGOCD_NS)

argocd-password:
	@$(KUBECTL) -n $(ARGOCD_NS) get secret argocd-initial-admin-secret \
		-o jsonpath="{.data.password}" | base64 -d && echo ""

argocd-ui:
	@echo "ArgoCD UI → http://localhost:8080  (admin / run 'make argocd-password')"
	$(KUBECTL) port-forward svc/argocd-server -n $(ARGOCD_NS) 8080:443

# ─── KYVERNO ─────────────────────────────────────────────────────────────────

kyverno-install:
	$(HELM) repo add kyverno https://kyverno.github.io/kyverno/ 2>/dev/null || true
	$(HELM) repo update
	$(HELM) upgrade --install kyverno kyverno/kyverno \
		--namespace $(KYVERNO_NS) --create-namespace \
		--set replicaCount=1 \
		--wait

kyverno-policies:
	$(KUBECTL) apply -f manifests/kyverno/policies/

# ─── MONITORING ──────────────────────────────────────────────────────────────

monitoring-install:
	$(HELM) repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
	$(HELM) repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
	$(HELM) repo update
	$(KUBECTL) create namespace $(MONITORING_NS) --dry-run=client -o yaml | $(KUBECTL) apply -f -
	$(HELM) upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
		--namespace $(MONITORING_NS) \
		--values monitoring/prometheus/values.yaml \
		--wait --timeout 5m
	$(HELM) upgrade --install loki grafana/loki-stack \
		--namespace $(MONITORING_NS) \
		--values monitoring/loki/values.yaml \
		--wait

monitoring-ui:
	@echo "Grafana → http://localhost:3000  (admin/prom-operator)"
	$(KUBECTL) port-forward svc/kube-prometheus-stack-grafana -n $(MONITORING_NS) 3000:80

# ─── ISTIO ───────────────────────────────────────────────────────────────────

istio-install:
	@which istioctl || (echo "istioctl not found — run 'make ansible-tools' first" && exit 1)
	istioctl install --set profile=minimal -y
	$(KUBECTL) label namespace default istio-injection=enabled --overwrite

# ─── TERRAFORM ───────────────────────────────────────────────────────────────

terraform-init:
	cd terraform/local && terraform init

terraform-apply:
	cd terraform/local && terraform apply -auto-approve

terraform-destroy:
	@echo "WARNING: This will destroy all Terraform-managed resources."
	@read -p "Type 'yes' to confirm: " confirm && [ "$$confirm" = "yes" ] || (echo "Aborted." && exit 1)
	cd terraform/local && terraform destroy -auto-approve

# ─── LABS ────────────────────────────────────────────────────────────────────

lab-cka:
	@cat labs/cka/README.md

lab-ckad:
	@cat labs/ckad/README.md

lab-cks:
	@cat labs/cks/README.md

lab-kcna:
	@cat labs/kcna/README.md

lab-kcsa:
	@cat labs/kcsa/README.md

# ─── SHORTCUTS ───────────────────────────────────────────────────────────────

full-stack: cluster-create argocd-install kyverno-install monitoring-install
	@echo ""
	@echo "Full stack ready."
	@echo "  ArgoCD:     make argocd-ui"
	@echo "  Grafana:    make monitoring-ui"
	@echo "  Kyverno:    make kyverno-policies"

clean:
	@echo "This will delete the cluster and all local Terraform state."
	@read -p "Type 'yes' to confirm: " confirm && [ "$$confirm" = "yes" ] || (echo "Aborted." && exit 1)
	kind delete cluster --name $(CLUSTER_NAME) 2>/dev/null || true
	rm -rf terraform/local/.terraform terraform/local/terraform.tfstate*
