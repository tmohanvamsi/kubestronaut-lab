terraform {
  required_version = ">= 1.6"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
  }
}

# ── Providers ─────────────────────────────────────────────────────────────────

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}

provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = var.kube_context
  }
}

# ── Namespaces ─────────────────────────────────────────────────────────────────

resource "kubernetes_namespace" "namespaces" {
  for_each = toset(var.namespaces)

  metadata {
    name = each.value
    labels = {
      "managed-by" = "terraform"
      "env"        = var.environment
    }
  }
}

# ── RBAC: developer role ───────────────────────────────────────────────────────

resource "kubernetes_role" "developer" {
  for_each = toset(["apps", "staging"])

  metadata {
    name      = "developer"
    namespace = each.value
    labels = {
      "managed-by" = "terraform"
    }
  }

  depends_on = [kubernetes_namespace.namespaces]

  rule {
    api_groups = ["", "apps", "batch"]
    resources  = ["pods", "pods/log", "deployments", "replicasets", "jobs", "cronjobs", "configmaps", "services"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_role_binding" "developer" {
  for_each = toset(["apps", "staging"])

  metadata {
    name      = "developer-binding"
    namespace = each.value
  }

  depends_on = [kubernetes_role.developer]

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = "developer"
  }

  subject {
    kind      = "Group"
    name      = "developers"
    api_group = "rbac.authorization.k8s.io"
  }
}

# ── RBAC: read-only ClusterRole ────────────────────────────────────────────────

resource "kubernetes_cluster_role" "readonly" {
  metadata {
    name = "cluster-readonly"
    labels = {
      "managed-by" = "terraform"
    }
  }

  rule {
    api_groups = ["", "apps", "batch", "extensions"]
    resources  = ["*"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "readonly" {
  metadata {
    name = "cluster-readonly-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.readonly.metadata[0].name
  }

  subject {
    kind      = "Group"
    name      = "viewers"
    api_group = "rbac.authorization.k8s.io"
  }
}

# ── Resource quotas ────────────────────────────────────────────────────────────

resource "kubernetes_resource_quota" "apps" {
  metadata {
    name      = "apps-quota"
    namespace = "apps"
  }

  depends_on = [kubernetes_namespace.namespaces]

  spec {
    hard = {
      "requests.cpu"    = "4"
      "requests.memory" = "4Gi"
      "limits.cpu"      = "8"
      "limits.memory"   = "8Gi"
      "pods"            = "20"
    }
  }
}

# ── LimitRange ─────────────────────────────────────────────────────────────────

resource "kubernetes_limit_range" "apps" {
  metadata {
    name      = "apps-limits"
    namespace = "apps"
  }

  depends_on = [kubernetes_namespace.namespaces]

  spec {
    limit {
      type = "Container"
      default = {
        cpu    = "200m"
        memory = "256Mi"
      }
      default_request = {
        cpu    = "100m"
        memory = "128Mi"
      }
    }
  }
}

# ── ConfigMap: lab metadata ────────────────────────────────────────────────────

resource "kubernetes_config_map" "lab_info" {
  metadata {
    name      = "lab-info"
    namespace = "default"
    labels = {
      "managed-by" = "terraform"
    }
  }

  data = {
    lab_name    = "kubestronaut-lab"
    environment = var.environment
    created_by  = "terraform"
    purpose     = "CKA, CKAD, CKS, KCNA, KCSA practice"
  }
}
