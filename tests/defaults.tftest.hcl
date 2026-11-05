# Runs offline against a mocked azurerm provider: no credentials, no network.
#
# `mock_provider` requires Terraform >= 1.7 / OpenTofu >= 1.7. That is a
# test-only requirement — the module itself still supports >= 1.5, so do not
# raise required_version in versions.tf for it.

mock_provider "azurerm" {}

variables {
  name                = "test-aks"
  resource_group_name = "test-rg"
  location            = "eastus"
  dns_prefix          = "testaks"
}

run "defaults_are_safe" {
  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].network_policy == "azure"
    error_message = "A network policy engine must be enabled by default, otherwise all pod-to-pod traffic is permitted."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].network_plugin == "azure"
    error_message = "Default network plugin should be azure."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.identity[0].type == "SystemAssigned"
    error_message = "Cluster should use a system-assigned managed identity, not a service principal."
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.this.api_server_access_profile) == 0
    error_message = "No API server access profile should be emitted when no authorized ranges are supplied."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.local_account_disabled == false
    error_message = "Without Entra ID integration the local account must stay enabled, otherwise nobody can reach the cluster."
  }
}

run "authorized_ip_ranges_are_applied" {
  variables {
    api_server_authorized_ip_ranges = ["198.51.100.0/24", "203.0.113.7/32"]
  }

  assert {
    condition = join(",", sort(tolist(
      azurerm_kubernetes_cluster.this.api_server_access_profile[0].authorized_ip_ranges
    ))) == "198.51.100.0/24,203.0.113.7/32"
    error_message = "Authorized IP ranges should be passed through to the API server access profile."
  }
}

run "rejects_world_open_api_server" {
  command = plan

  variables {
    api_server_authorized_ip_ranges = ["0.0.0.0/0"]
  }

  expect_failures = [var.api_server_authorized_ip_ranges]
}

run "rejects_malformed_cidr" {
  command = plan

  variables {
    api_server_authorized_ip_ranges = ["198.51.100.1"]
  }

  expect_failures = [var.api_server_authorized_ip_ranges]
}

run "entra_id_integration_disables_local_accounts" {
  variables {
    azure_active_directory_role_based_access_control = {
      admin_group_object_ids = ["00000000-0000-0000-0000-000000000000"]
    }
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.local_account_disabled == true
    error_message = "Configuring Entra ID integration should disable the local admin account by default."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.azure_active_directory_role_based_access_control[0].azure_rbac_enabled == true
    error_message = "Azure RBAC for Kubernetes authorization should default to enabled."
  }
}

run "local_account_disabled_can_be_overridden" {
  variables {
    azure_active_directory_role_based_access_control = {
      admin_group_object_ids = ["00000000-0000-0000-0000-000000000000"]
    }
    local_account_disabled = false
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.local_account_disabled == false
    error_message = "An explicit local_account_disabled value must win over the derived default."
  }
}

run "rejects_disabling_local_accounts_without_entra_id" {
  command = plan

  variables {
    local_account_disabled = true
  }

  expect_failures = [azurerm_kubernetes_cluster.this]
}

run "rejects_azure_policy_with_kubenet" {
  command = plan

  variables {
    network_plugin = "kubenet"
  }

  expect_failures = [azurerm_kubernetes_cluster.this]
}

run "calico_policy_with_kubenet_is_accepted" {
  variables {
    network_plugin = "kubenet"
    network_policy = "calico"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].network_policy == "calico"
    error_message = "calico should be accepted alongside the kubenet plugin."
  }
}

run "rejects_invalid_network_policy" {
  command = plan

  variables {
    network_policy = "NotAPolicy"
  }

  expect_failures = [var.network_policy]
}

run "rejects_cilium_network_policy" {
  command = plan

  variables {
    network_policy = "cilium"
  }

  # cilium needs network_data_plane / network_plugin_mode / pod_subnet_id,
  # none of which this module exposes, so it is rejected rather than left to
  # fail against the real Azure API on every apply.
  expect_failures = [var.network_policy]
}

run "rejects_invalid_sku_tier" {
  command = plan

  variables {
    sku_tier = "Enterprise"
  }

  expect_failures = [var.sku_tier]
}

run "rejects_autoscaling_without_bounds" {
  command = plan

  variables {
    default_node_pool = {
      auto_scaling_enabled = true
    }
  }

  expect_failures = [var.default_node_pool]
}

run "rejects_min_count_above_max_count" {
  command = plan

  variables {
    default_node_pool = {
      auto_scaling_enabled = true
      min_count            = 5
      max_count            = 2
    }
  }

  expect_failures = [var.default_node_pool]
}

run "autoscaling_leaves_node_count_for_the_provider_to_manage" {
  variables {
    default_node_pool = {
      node_count           = 9
      auto_scaling_enabled = true
      min_count            = 2
      max_count            = 5
    }
  }

  # The mock provider fills unset Optional+Computed int attributes with its own
  # placeholder rather than preserving a literal null, so we can't assert
  # `== null` here. What we *can* assert is that our configured node_count (9)
  # was not forced through to the resource: "node_count_resize_still_works..."
  # below proves the mock provider echoes an explicitly-set value back
  # unchanged, so seeing anything other than 9 here proves the module omitted
  # node_count from the resource config once autoscaling is on.
  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].node_count != 9
    error_message = "node_count must not be forced through once autoscaling is enabled, otherwise the next apply after the autoscaler resizes the pool fails against the real provider."
  }
}

run "node_count_resize_still_works_without_autoscaling" {
  variables {
    default_node_pool = {
      node_count = 3
    }
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].node_count == 3
    error_message = "node_count must still be applied when autoscaling is off, otherwise resizing a static pool through this module stops working."
  }
}

run "encryption_knobs_are_wired_through" {
  variables {
    disk_encryption_set_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Compute/diskEncryptionSets/test-des"
    default_node_pool = {
      host_encryption_enabled = true
    }
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].host_encryption_enabled == true
    error_message = "host_encryption_enabled should reach the default node pool."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.disk_encryption_set_id != null
    error_message = "disk_encryption_set_id should reach the cluster."
  }
}

run "provider_major_independent_defaults" {
  assert {
    condition     = azurerm_kubernetes_cluster.this.oidc_issuer_enabled == false
    error_message = "oidc_issuer_enabled must be set explicitly so azurerm 4.x and 5.x produce the same cluster."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.node_provisioning_profile[0].mode == "Manual"
    error_message = "node_provisioning_profile must default to Manual mode."
  }
}

run "rejects_unknown_node_provisioning_mode" {
  command = plan

  variables {
    node_provisioning_mode = "Karpenter"
  }

  expect_failures = [var.node_provisioning_mode]
}
