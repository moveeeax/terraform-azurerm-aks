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

  # azurerm 5.0 flipped the provider default to true. Set it explicitly so the
  # result does not depend on which provider major resolves.
  oidc_issuer_enabled = var.oidc_issuer_enabled

  # Turns on the AKS workload identity webhook, which projects a federated
  # service account token into pods. Changing it is an in-place update in both
  # directions; the cluster-level requirement on the OIDC issuer is enforced by
  # a precondition below.
  workload_identity_enabled = var.workload_identity_enabled

  # Required from azurerm 5.0 (available since 4.57.0). "Manual" is the AKS
  # default and keeps node pools under the module's control; "Auto" turns on
  # node auto-provisioning (Karpenter).
  node_provisioning_profile {
    mode = var.node_provisioning_mode
  }

  default_node_pool {
    name    = var.default_node_pool.name
    vm_size = var.default_node_pool.vm_size

    # node_count is only meaningful when autoscaling is off. When it's on, leave
    # it unset so the provider seeds the pool from min_count and treats the
    # field as computed from then on, instead of fighting the autoscaler on
    # every subsequent apply (see the variable description for node_count).
    node_count              = var.default_node_pool.auto_scaling_enabled ? null : var.default_node_pool.node_count
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

    # The provider only checks this on create, and only after Azure has been
    # called; an update that enables workload identity on a cluster without an
    # issuer goes straight to the API. Fail at plan time instead.
    precondition {
      condition     = !var.workload_identity_enabled || var.oidc_issuer_enabled
      error_message = "workload_identity_enabled = true requires oidc_issuer_enabled = true."
    }

    # A federated credential trusts tokens from the cluster's OIDC issuer, and
    # pods only receive such tokens when the workload identity webhook is on.
    precondition {
      condition     = length(var.federated_identities) == 0 || var.workload_identity_enabled
      error_message = "federated_identities requires workload_identity_enabled = true (which in turn requires oidc_issuer_enabled = true)."
    }
  }
}

# Trust between a Kubernetes service account and a user-assigned managed
# identity. A pod running as system:serviceaccount:<namespace>:<service_account>
# with the azure.workload.identity/use label can then exchange its projected
# token for an Entra ID token of that identity.
resource "azurerm_federated_identity_credential" "this" {
  for_each = var.federated_identities

  name                      = each.key
  user_assigned_identity_id = each.value.identity_id
  audience                  = each.value.audience
  issuer                    = azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject                   = "system:serviceaccount:${each.value.namespace}:${each.value.service_account}"
}
