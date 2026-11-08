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

## Workload identity

Off by default. To let pods authenticate as a user-assigned managed identity,
turn on the OIDC issuer and workload identity and list the service accounts to
trust:

```hcl
oidc_issuer_enabled       = true
workload_identity_enabled = true

federated_identities = {
  # Key = credential name: 3-120 characters, letters, digits, - and _.
  app-backend = {
    identity_id     = azurerm_user_assigned_identity.backend.id
    namespace       = "apps"
    service_account = "backend"
    # audience defaults to ["api://AzureADTokenExchange"]
  }
}
```

Each entry creates an `azurerm_federated_identity_credential` with issuer
`oidc_issuer_url` and subject `system:serviceaccount:<namespace>:<service_account>`.
The service account still needs the `azure.workload.identity/client-id`
annotation, and the pods the `azure.workload.identity/use: "true"` label.
Entra ID allows at most 20 federated credentials per identity.

`workload_identity_enabled = true` without `oidc_issuer_enabled = true`, and
`federated_identities` without `workload_identity_enabled = true`, are rejected
at plan time.

What changing these does to an existing cluster, per the azurerm source
(`kubernetes_cluster` resource, v4.65.0 and v5.13.0):

| Change | azurerm 4.x | azurerm 5.x |
|--------|-------------|-------------|
| `oidc_issuer_enabled` false -> true | in-place update | in-place update |
| `oidc_issuer_enabled` true -> false | in-place update that AKS rejects | cluster is replaced (`ForceNewIfChange`) |
| `workload_identity_enabled` either way | in-place update | in-place update |

So enabling the issuer is a one-way step. Recommended for new clusters:
`oidc_issuer_enabled = true` and `workload_identity_enabled = true`.

## Requirements

| Name      | Version           |
|-----------|-------------------|
| terraform | >= 1.5            |
| azurerm   | >= 4.65.0, < 6.0  |

The lower bound is `4.65.0` because that release added
`user_assigned_identity_id` to `azurerm_federated_identity_credential` (renamed
from `parent_id`, which 5.0 removes), so it is the first version where the same
configuration works on 4.x and 5.x. `node_provisioning_profile`, which azurerm
5.0 makes required, has been there since 4.57.0. (The module
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
| `workload_identity_enabled`                       | Enable Microsoft Entra Workload ID. Requires `oidc_issuer_enabled = true`. In-place either way. | `bool`         | `false`   |    no    |
| `federated_identities`                            | Federated credentials keyed by name: `identity_id`, `namespace`, `service_account`, optional `audience`. Requires `workload_identity_enabled`. | `map(object)`  | `{}`      |    no    |
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
| `oidc_issuer_url`       | OIDC issuer URL, or null when the issuer is disabled.   |
| `federated_identity_credential_ids` | Federated credential IDs, keyed like `federated_identities`. |

## License

[MIT](LICENSE)
