# Runs offline against a mocked azurerm provider: no credentials, no network.
# `mock_provider` requires Terraform >= 1.7 / OpenTofu >= 1.7 (test-only).

mock_provider "azurerm" {}

variables {
  name                = "test-aks"
  resource_group_name = "test-rg"
  location            = "eastus"
  dns_prefix          = "testaks"
}

# Upgrade guard: existing callers must get the same cluster and no new
# resources.
run "workload_identity_off_by_default" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.this.workload_identity_enabled == false
    error_message = "workload_identity_enabled must default to false."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.oidc_issuer_enabled == false
    error_message = "oidc_issuer_enabled must still default to false."
  }

  assert {
    condition     = length(azurerm_federated_identity_credential.this) == 0
    error_message = "No federated identity credentials should be planned by default."
  }
}

run "workload_identity_with_federated_identity" {
  command = plan

  variables {
    oidc_issuer_enabled       = true
    workload_identity_enabled = true
    federated_identities = {
      app-backend = {
        identity_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/backend"
        namespace       = "apps"
        service_account = "backend"
      }
    }
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.workload_identity_enabled == true
    error_message = "workload_identity_enabled should reach the cluster."
  }

  assert {
    condition     = azurerm_federated_identity_credential.this["app-backend"].subject == "system:serviceaccount:apps:backend"
    error_message = "subject must be built from namespace and service_account."
  }

  assert {
    condition     = azurerm_federated_identity_credential.this["app-backend"].audience == tolist(["api://AzureADTokenExchange"])
    error_message = "audience must default to api://AzureADTokenExchange."
  }

  assert {
    condition     = azurerm_federated_identity_credential.this["app-backend"].name == "app-backend"
    error_message = "The map key must be used as the credential name."
  }

  assert {
    condition     = azurerm_federated_identity_credential.this["app-backend"].user_assigned_identity_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/backend"
    error_message = "identity_id must be passed as user_assigned_identity_id."
  }
}

run "rejects_workload_identity_without_oidc_issuer" {
  command = plan

  variables {
    workload_identity_enabled = true
  }

  expect_failures = [azurerm_kubernetes_cluster.this]
}

run "rejects_federated_identities_without_workload_identity" {
  command = plan

  variables {
    oidc_issuer_enabled = true
    federated_identities = {
      app-backend = {
        identity_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/backend"
        namespace       = "apps"
        service_account = "backend"
      }
    }
  }

  expect_failures = [azurerm_kubernetes_cluster.this]
}

run "rejects_invalid_credential_name" {
  command = plan

  variables {
    oidc_issuer_enabled       = true
    workload_identity_enabled = true
    federated_identities = {
      "-bad" = {
        identity_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/backend"
        namespace       = "apps"
        service_account = "backend"
      }
    }
  }

  expect_failures = [var.federated_identities]
}

run "rejects_non_identity_id" {
  command = plan

  variables {
    oidc_issuer_enabled       = true
    workload_identity_enabled = true
    federated_identities = {
      app-backend = {
        identity_id     = "00000000-0000-0000-0000-000000000000"
        namespace       = "apps"
        service_account = "backend"
      }
    }
  }

  expect_failures = [var.federated_identities]
}

run "rejects_empty_service_account" {
  command = plan

  variables {
    oidc_issuer_enabled       = true
    workload_identity_enabled = true
    federated_identities = {
      app-backend = {
        identity_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/backend"
        namespace       = "apps"
        service_account = ""
      }
    }
  }

  expect_failures = [var.federated_identities]
}

run "rejects_multiple_audiences" {
  command = plan

  variables {
    oidc_issuer_enabled       = true
    workload_identity_enabled = true
    federated_identities = {
      app-backend = {
        identity_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/backend"
        namespace       = "apps"
        service_account = "backend"
        audience        = ["api://AzureADTokenExchange", "api://other"]
      }
    }
  }

  expect_failures = [var.federated_identities]
}
