terraform {
  required_version = ">= 1.5"

  required_providers {
    # The module uses the azurerm 4.x argument names (auto_scaling_enabled,
    # host_encryption_enabled), which do not exist in 3.x.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0, < 5.0"
    }
  }
}
