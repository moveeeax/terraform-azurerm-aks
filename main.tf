locals {
  # Local (certificate-based) admin accounts bypass Entra ID and Kubernetes RBAC
  # entirely. AKS only allows them to be disabled on a cluster with managed
  # Entra ID integration, so default to disabling them exactly when that
  # integration is configured.
  local_account_disabled = (
    var.local_account_disabled != null
    ? var.local_account_disabled
    : var.azure_active_directory_role_based_access_control != null
  )
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  dns_prefix          = var.dns_prefix
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier

  local_account_disabled = local.local_account_disabled
  disk_encryption_set_id = var.disk_encryption_set_id

  default_node_pool {
    name                    = var.default_node_pool.name
    vm_size                 = var.default_node_pool.vm_size
    node_count              = var.default_node_pool.node_count
    auto_scaling_enabled    = var.default_node_pool.auto_scaling_enabled
    min_count               = var.default_node_pool.auto_scaling_enabled ? var.default_node_pool.min_count : null
    max_count               = var.default_node_pool.auto_scaling_enabled ? var.default_node_pool.max_count : null
    vnet_subnet_id          = var.default_node_pool.vnet_subnet_id
    host_encryption_enabled = var.default_node_pool.host_encryption_enabled
  }

  identity {
    type = "SystemAssigned"
  }

  dynamic "azure_active_directory_role_based_access_control" {
    for_each = var.azure_active_directory_role_based_access_control == null ? [] : [var.azure_active_directory_role_based_access_control]

    content {
      tenant_id              = azure_active_directory_role_based_access_control.value.tenant_id
      admin_group_object_ids = azure_active_directory_role_based_access_control.value.admin_group_object_ids
      azure_rbac_enabled     = azure_active_directory_role_based_access_control.value.azure_rbac_enabled
    }
  }

  dynamic "api_server_access_profile" {
    for_each = var.api_server_authorized_ip_ranges == null ? [] : [var.api_server_authorized_ip_ranges]

    content {
      authorized_ip_ranges = api_server_access_profile.value
    }
  }

  network_profile {
    network_plugin = var.network_plugin
    network_policy = var.network_policy
  }

  tags = var.tags

  lifecycle {
    # Cross-variable checks. `variable` validation blocks cannot reference other
    # variables on the minimum Terraform version this module supports (1.5).
    precondition {
      condition     = var.network_policy == null || var.network_plugin != "none"
      error_message = "network_policy cannot be set when network_plugin is \"none\". Set network_policy = null and bring your own CNI policy engine."
    }

    precondition {
      condition     = var.network_policy != "azure" || var.network_plugin == "azure"
      error_message = "network_policy = \"azure\" requires network_plugin = \"azure\". Use \"calico\" with the kubenet plugin."
    }

    precondition {
      condition     = !local.local_account_disabled || var.azure_active_directory_role_based_access_control != null
      error_message = "local_account_disabled = true requires azure_active_directory_role_based_access_control to be configured, otherwise nobody could authenticate to the cluster."
    }
  }
}
