terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.57.0, < 6.0"
    }
  }
}

provider "azurerm" {
  features {}
}

module "aks" {
  source = "../.."

  name                = "example-aks"
  resource_group_name = "example-rg"
  location            = "eastus"
  dns_prefix          = "exampleaks"

  default_node_pool = {
    name       = "system"
    vm_size    = "Standard_D2s_v5"
    node_count = 2
  }

  # Documentation range (RFC 5737) standing in for your own egress addresses.
  api_server_authorized_ip_ranges = ["198.51.100.0/24"]

  tags = {
    Environment = "sandbox"
    ManagedBy   = "terraform"
  }
}

output "aks_fqdn" {
  value = module.aks.fqdn
}
