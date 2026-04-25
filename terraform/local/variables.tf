variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Kubernetes context to use"
  type        = string
  default     = "kind-kubestronaut"
}

variable "environment" {
  description = "Environment label applied to all resources"
  type        = string
  default     = "lab"
}

variable "namespaces" {
  description = "Namespaces to create and manage"
  type        = list(string)
  default = [
    "apps",
    "staging",
    "monitoring",
    "argocd",
    "kyverno",
    "istio-system",
    "cert-manager",
  ]
}
