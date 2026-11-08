output "id" {
  description = "ID of the managed Kubernetes cluster."
  value       = azurerm_kubernetes_cluster.this.id
}

output "name" {
  description = "Name of the managed Kubernetes cluster."
  value       = azurerm_kubernetes_cluster.this.name
}

output "fqdn" {
  description = "FQDN of the cluster's Kubernetes API server."
  value       = azurerm_kubernetes_cluster.this.fqdn
}

output "kube_config_raw" {
  description = "Raw kubeconfig for the cluster, suitable for use with kubectl."
  value       = azurerm_kubernetes_cluster.this.kube_config_raw
  sensitive   = true
}

output "identity_principal_id" {
  description = "Principal ID of the cluster's system-assigned managed identity."
  value       = azurerm_kubernetes_cluster.this.identity[0].principal_id
}

output "oidc_issuer_url" {
  description = "URL of the cluster's OIDC issuer, or null when oidc_issuer_enabled is false."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "federated_identity_credential_ids" {
  description = "IDs of the federated identity credentials, keyed like federated_identities."
  value       = { for k, v in azurerm_federated_identity_credential.this : k => v.id }
}
