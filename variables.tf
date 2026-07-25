variable "name" {
  description = "Name of the managed Kubernetes cluster."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group in which to create the cluster."
  type        = string
}

variable "location" {
  description = "Azure region in which to create the cluster."
  type        = string
}

variable "dns_prefix" {
  description = "DNS prefix used when creating the managed cluster's API server FQDN."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the control plane and node pool. Null uses the region default."
  type        = string
  default     = null
}

variable "sku_tier" {
  description = "SLA tier of the cluster control plane. One of Free, Standard or Premium."
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be one of Free, Standard or Premium."
  }
}

variable "default_node_pool" {
  description = "Configuration of the default (system) node pool."
  type = object({
    name                 = optional(string, "default")
    vm_size              = optional(string, "Standard_D2s_v5")
    node_count           = optional(number, 2)
    auto_scaling_enabled = optional(bool, false)
    min_count            = optional(number, null)
    max_count            = optional(number, null)
    vnet_subnet_id       = optional(string, null)

    # Encryption at host encrypts the node's temporary disk and the OS/data disk
    # caches on the VM host itself. Requires the EncryptionAtHost feature to be
    # registered on the subscription, so it is opt-in.
    host_encryption_enabled = optional(bool, false)
  })
  default = {}

  validation {
    condition = (
      !var.default_node_pool.auto_scaling_enabled ||
      (var.default_node_pool.min_count != null && var.default_node_pool.max_count != null)
    )
    error_message = "default_node_pool.min_count and max_count are required when auto_scaling_enabled is true."
  }

  validation {
    condition = (
      var.default_node_pool.min_count == null ||
      var.default_node_pool.max_count == null ||
      var.default_node_pool.min_count <= var.default_node_pool.max_count
    )
    error_message = "default_node_pool.min_count must be less than or equal to max_count."
  }
}

variable "network_plugin" {
  description = "Network plugin used by the cluster. One of azure, kubenet or none."
  type        = string
  default     = "azure"

  validation {
    condition     = contains(["azure", "kubenet", "none"], var.network_plugin)
    error_message = "network_plugin must be one of azure, kubenet or none."
  }
}

variable "network_policy" {
  description = <<-EOT
    Network policy engine enforcing pod-to-pod traffic rules. One of azure, calico
    or cilium, or null to run the cluster with no policy enforcement at all.
    Defaults to azure, which requires network_plugin = "azure".
  EOT
  type        = string
  default     = "azure"

  validation {
    condition     = var.network_policy == null ? true : contains(["azure", "calico", "cilium"], var.network_policy)
    error_message = "network_policy must be one of azure, calico, cilium or null."
  }
}

variable "api_server_authorized_ip_ranges" {
  description = <<-EOT
    CIDR ranges permitted to reach the public Kubernetes API server endpoint.
    Null (the default) leaves the API server reachable from any address, which is
    the AKS default but is not a safe posture for anything beyond a sandbox. Set
    this to your egress ranges.
  EOT
  type        = list(string)
  default     = null

  validation {
    condition = var.api_server_authorized_ip_ranges == null || !contains(
      coalesce(var.api_server_authorized_ip_ranges, []), "0.0.0.0/0"
    )
    error_message = "api_server_authorized_ip_ranges must not contain 0.0.0.0/0. Leave the variable null if you genuinely intend an unrestricted API server."
  }

  validation {
    condition = alltrue([
      for cidr in coalesce(var.api_server_authorized_ip_ranges, []) : can(cidrnetmask(cidr))
    ])
    error_message = "Every entry in api_server_authorized_ip_ranges must be a valid IPv4 CIDR block."
  }
}

variable "azure_active_directory_role_based_access_control" {
  description = <<-EOT
    AKS-managed Microsoft Entra ID integration. Null (the default) leaves the
    cluster on local Kubernetes accounts only. Setting this also disables the
    local admin account unless local_account_disabled says otherwise.
  EOT
  type = object({
    tenant_id              = optional(string, null)
    admin_group_object_ids = optional(list(string), null)
    azure_rbac_enabled     = optional(bool, true)
  })
  default = null
}

variable "local_account_disabled" {
  description = <<-EOT
    Whether to disable the cluster's local (certificate-based) admin account.
    Null (the default) resolves to true when azure_active_directory_role_based_access_control
    is configured and false otherwise, because AKS only permits disabling local
    accounts on Entra ID integrated clusters.
  EOT
  type        = bool
  default     = null
}

variable "disk_encryption_set_id" {
  description = <<-EOT
    ID of a Disk Encryption Set used to encrypt the node OS and data disks with a
    customer-managed key. Null (the default) keeps Azure platform-managed keys,
    which still encrypt the disks at rest.
  EOT
  type        = string
  default     = null
}

variable "tags" {
  description = "Map of tags applied to the cluster."
  type        = map(string)
  default     = {}
}
