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
    name    = optional(string, "default")
    vm_size = optional(string, "Standard_D2s_v5")

    # Only used when auto_scaling_enabled = false. When auto_scaling_enabled is
    # true this value is ignored (see main.tf): the azurerm provider seeds the
    # initial node count from min_count instead and treats node_count as
    # computed afterwards, so continuing to pass a fixed value here would make
    # every apply after the autoscaler first resizes the pool fail with
    # "cannot change node_count when auto_scaling_enabled is set to true".
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
    Network policy engine enforcing pod-to-pod traffic rules. One of azure or
    calico, or null to run the cluster with no policy enforcement at all.
    Defaults to azure, which requires network_plugin = "azure".

    "cilium" is intentionally not accepted: the azurerm provider also requires
    network_data_plane = "cilium" plus either network_plugin_mode = "overlay" or
    a pod_subnet_id whenever network_policy = "cilium", and this module exposes
    none of those. Passing "cilium" through would validate here and then fail
    against the real Azure API on every apply.
  EOT
  type        = string
  default     = "azure"

  validation {
    condition     = var.network_policy == null ? true : contains(["azure", "calico"], var.network_policy)
    error_message = "network_policy must be one of azure, calico or null. cilium is not supported by this module (see the variable description)."
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

variable "oidc_issuer_enabled" {
  description = <<-EOT
    Whether to enable the cluster's OIDC issuer (needed for Microsoft Entra
    Workload ID). Defaults to false, the behaviour of azurerm 4.x, so upgrading
    the provider does not change existing clusters. Once enabled it cannot be
    disabled again without recreating the cluster: azurerm 5.x plans a replace
    for true -> false, azurerm 4.x sends an in-place update that AKS rejects.
  EOT
  type        = bool
  default     = false
}

variable "workload_identity_enabled" {
  description = <<-EOT
    Whether to enable Microsoft Entra Workload ID, so pods can authenticate as a
    user-assigned managed identity through a federated credential. Requires
    oidc_issuer_enabled = true. Defaults to false; can be switched either way
    in place.
  EOT
  type        = bool
  default     = false
}

variable "federated_identities" {
  description = <<-EOT
    Federated identity credentials to create against the cluster's OIDC issuer,
    keyed by credential name. Each entry trusts the Kubernetes service account
    namespace/service_account to act as the user-assigned identity identity_id.
    audience defaults to the Entra ID token exchange audience. Requires
    workload_identity_enabled = true.
  EOT
  type = map(object({
    identity_id     = string
    namespace       = string
    service_account = string
    audience        = optional(list(string), ["api://AzureADTokenExchange"])
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.federated_identities : can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{2,119}$", k))
    ])
    error_message = "Each federated_identities key is used as the credential name: 3-120 characters, letters, digits, hyphens and underscores, starting with a letter or digit."
  }

  validation {
    condition = alltrue([
      for v in values(var.federated_identities) : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.ManagedIdentity/userAssignedIdentities/[^/]+$", v.identity_id))
    ])
    error_message = "Each federated_identities identity_id must be a user-assigned identity resource ID (/subscriptions/.../resourceGroups/.../providers/Microsoft.ManagedIdentity/userAssignedIdentities/...)."
  }

  validation {
    condition = alltrue([
      for v in values(var.federated_identities) : v.namespace != "" && v.service_account != ""
    ])
    error_message = "Each federated_identities entry needs a non-empty namespace and service_account."
  }

  # The provider caps audience at one item (MaxItems = 1).
  validation {
    condition = alltrue([
      for v in values(var.federated_identities) : length(v.audience) == 1
    ])
    error_message = "Each federated_identities audience must contain exactly one value."
  }
}

variable "node_provisioning_mode" {
  description = "Node provisioning mode. Manual (the default) keeps node pools as declared; Auto enables node auto-provisioning."
  type        = string
  default     = "Manual"

  validation {
    condition     = contains(["Manual", "Auto"], var.node_provisioning_mode)
    error_message = "node_provisioning_mode must be either Manual or Auto."
  }
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
