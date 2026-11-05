terraform {
  required_version = ">= 1.5"

  required_providers {
    # Lower bound: node_provisioning_profile, which azurerm 5.0 makes
    # required, was added in 4.57.0. The 4.x argument names
    # (auto_scaling_enabled, host_encryption_enabled) rule out 3.x anyway.
    # Upper bound: tested against 5.x; 6.0 has not been vetted.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.57.0, < 6.0"
    }
  }
}
