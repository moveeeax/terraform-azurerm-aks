terraform {
  required_version = ">= 1.5"

  required_providers {
    # Lower bound: azurerm_federated_identity_credential gained
    # user_assigned_identity_id in 4.65.0 (renamed from parent_id, which 5.0
    # removes), so 4.65.0 is the first release where one configuration works
    # on both majors. node_provisioning_profile, which azurerm 5.0 makes
    # required, has been there since 4.57.0. The 4.x argument names
    # (auto_scaling_enabled, host_encryption_enabled) rule out 3.x anyway.
    # Upper bound: tested against 5.x; 6.0 has not been vetted.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.65.0, < 6.0"
    }
  }
}
