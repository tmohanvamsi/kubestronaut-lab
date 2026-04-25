output "namespaces_created" {
  description = "Namespaces managed by Terraform"
  value       = keys(kubernetes_namespace.namespaces)
}

output "developer_roles" {
  description = "Namespaces where developer Role exists"
  value       = keys(kubernetes_role.developer)
}

output "cluster_readonly_role" {
  description = "Name of the cluster-wide read-only ClusterRole"
  value       = kubernetes_cluster_role.readonly.metadata[0].name
}

output "lab_info" {
  description = "Lab metadata ConfigMap data"
  value       = kubernetes_config_map.lab_info.data
}
