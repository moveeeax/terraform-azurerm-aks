# terraform-azurerm-aks

Terraform module that manages an [Azure](https://azure.microsoft.com/)
Kubernetes Service (AKS) cluster. It provisions a cluster with a system node
pool, a system-assigned managed identity and the Azure CNI network plugin, and
exposes the API server FQDN and a sensitive kubeconfig output.

## Usage

```hcl
module "aks" {
  source = "github.com/moveeeax/terraform-azurerm-aks?ref=v1.0.0"

  name                = "prod-aks"
  resource_group_name = "prod-rg"
  location            = "eastus"
  dns_prefix          = "prodaks"

  default_node_pool = {
    name                 = "system"
    vm_size              = "Standard_D4s_v5"
    auto_scaling_enabled = true
    min_count            = 2
    max_count            = 5
  }

  # Restrict who can reach the public API server endpoint.
  api_server_authorized_ip_ranges = ["198.51.100.0/24"]

  # Authenticate through Entra ID; this also disables the local admin account.
  azure_active_directory_role_based_access_control = {
    admin_group_object_ids = ["00000000-0000-0000-0000-000000000000"]
  }

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

A runnable example lives in [`examples/basic`](examples/basic).

## Security defaults

| Control | Module behaviour |
|---------|------------------|
| Network policy | `network_policy` defaults to `azure`, so pod-to-pod traffic is subject to `NetworkPolicy` objects instead of being unrestricted. Set it to `null` to opt out. |
| API server exposure | `api_server_authorized_ip_ranges` is `null` by default (AKS's own behaviour: reachable from anywhere). Supplying ranges emits an `api_server_access_profile`; `0.0.0.0/0` is rejected outright. |
| Cluster authentication | Setting `azure_active_directory_role_based_access_control` turns on AKS-managed Entra ID with Azure RBAC and, by default, disables the local certificate-based admin account. `local_account_disabled` overrides that derivation and is refused when there is no Entra ID integration to fall back on. |
| Disk encryption | Node disks are encrypted at rest with platform-managed keys by default. `disk_encryption_set_id` switches to a customer-managed key; `default_node_pool.host_encryption_enabled` additionally encrypts the temp disk and host caches (needs the `EncryptionAtHost` subscription feature). |
| Kubernetes version | `kubernetes_version` defaults to `null`, which tracks the region's AKS default rather than pinning a version that will silently fall out of support. Pin it explicitly once you have an upgrade process. |

## Requirements

| Name      | Version           |
|-----------|-------------------|
| terraform | >= 1.5            |
| azurerm   | >= 4.57.0, < 6.0  |

The lower bound is `4.57.0` because that release added the
`node_provisioning_profile` block, which azurerm 5.0 makes required. (The module
also uses the 4.x argument names `auto_scaling_enabled` and
`host_encryption_enabled`, which do not exist in 3.x.) CI validates and tests the
module against both the declared minimum and the latest 5.x release. azurerm 6.x
is excluded until it has been tested.

azurerm 5.0 changed the provider default of `oidc_issuer_enabled` to `true`. The
module sets it explicitly (`oidc_issuer_enabled`, default `false`), so moving an
existing cluster from azurerm 4.x to 5.x does not change it.

Running `terraform test` additionally requires Terraform / OpenTofu >= 1.7 for
`mock_provider`. That is a test-only requirement and does not apply to consumers
of the module.

## Inputs

| Name                                              | Description                                                                                     | Type           | Default   | Required |
|---------------------------------------------------|-------------------------------------------------------------------------------------------------|----------------|-----------|:--------:|
| `name`                                            | Name of the managed Kubernetes cluster.                                                         | `string`       | n/a       |   yes    |
| `resource_group_name`                             | Name of the resource group in which to create the cluster.                                      | `string`       | n/a       |   yes    |
| `location`                                        | Azure region in which to create the cluster.                                                    | `string`       | n/a       |   yes    |
| `dns_prefix`                                      | DNS prefix used for the cluster's API server FQDN.                                              | `string`       | n/a       |   yes    |
| `kubernetes_version`                              | Kubernetes version. Null uses the region default.                                               | `string`       | `null`    |    no    |
| `sku_tier`                                        | SLA tier of the control plane. One of `Free`, `Standard` or `Premium`.                          | `string`       | `"Free"`  |    no    |
| `default_node_pool`                               | Configuration of the default (system) node pool. See below.                                     | `object`       | `{}`      |    no    |
| `network_plugin`                                  | Network plugin. One of `azure`, `kubenet` or `none`.                                            | `string`       | `"azure"` |    no    |
| `network_policy`                                  | Policy engine enforcing pod-to-pod rules. One of `azure`, `calico`, or `null` to disable. `cilium` is not supported (see variable description). | `string`       | `"azure"` |    no    |
| `api_server_authorized_ip_ranges`                 | CIDRs allowed to reach the public API server. `null` means unrestricted. `0.0.0.0/0` is rejected. | `list(string)` | `null`    |    no    |
| `azure_active_directory_role_based_access_control` | AKS-managed Entra ID integration (`tenant_id`, `admin_group_object_ids`, `azure_rbac_enabled`).  | `object`       | `null`    |    no    |
| `local_account_disabled`                          | Disable the local admin account. `null` derives it from the Entra ID setting above.              | `bool`         | `null`    |    no    |
| `oidc_issuer_enabled`                             | Enable the OIDC issuer (Entra Workload ID). Cannot be turned off again without recreating the cluster. | `bool`         | `false`   |    no    |
| `node_provisioning_mode`                          | `node_provisioning_profile.mode`: `Manual` or `Auto` (node auto-provisioning).                  | `string`       | `"Manual"` |    no    |
| `disk_encryption_set_id`                          | Disk Encryption Set for customer-managed key encryption of node disks.                          | `string`       | `null`    |    no    |
| `tags`                                            | Map of tags applied to the cluster.                                                             | `map(string)`  | `{}`      |    no    |

### `default_node_pool`

| Key                       | Type           | Default              | Description                                                       |
|---------------------------|----------------|----------------------|-------------------------------------------------------------------|
| `name`                    | `string`       | `"default"`          | Node pool name.                                                   |
| `vm_size`                 | `string`       | `"Standard_D2s_v5"`  | VM SKU for the nodes.                                             |
| `node_count`              | `number`       | `2`                  | Initial node count. Only applied when `auto_scaling_enabled = false`; ignored (left for the provider to manage from `min_count`) once autoscaling is on. |
| `auto_scaling_enabled`    | `bool`         | `false`              | Enable the cluster autoscaler. Requires `min_count` and `max_count`. |
| `min_count`               | `number`       | `null`               | Autoscaler lower bound.                                           |
| `max_count`               | `number`       | `null`               | Autoscaler upper bound.                                           |
| `vnet_subnet_id`          | `string`       | `null`               | Subnet to place nodes in.                                         |
| `host_encryption_enabled` | `bool`         | `false`              | Encryption at host for temp disk and OS/data disk caches.         |

## Tests

```sh
terraform test   # or: tofu test
```

The suite in [`tests/`](tests) runs against a mocked azurerm provider, so it
needs no Azure credentials and no network access.

## Outputs

| Name                    | Description                                             |
|-------------------------|---------------------------------------------------------|
| `id`                    | ID of the managed Kubernetes cluster.                   |
| `name`                  | Name of the managed Kubernetes cluster.                 |
| `fqdn`                  | FQDN of the cluster's Kubernetes API server.            |
| `kube_config_raw`       | Raw kubeconfig for the cluster (sensitive).             |
| `identity_principal_id` | Principal ID of the cluster's managed identity.         |

## License

[MIT](LICENSE)
