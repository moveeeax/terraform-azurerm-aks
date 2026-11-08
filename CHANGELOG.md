# Changelog

All notable changes to this module are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.2.0] - 2026-11-08

### Added

- `workload_identity_enabled` (default `false`) for Microsoft Entra Workload
  ID. A precondition requires `oidc_issuer_enabled = true`.
- `federated_identities` (default `{}`): creates one
  `azurerm_federated_identity_credential` per entry, trusting
  `system:serviceaccount:<namespace>:<service_account>` from the cluster's
  OIDC issuer for a user-assigned identity. Requires
  `workload_identity_enabled = true`. Validates the credential name, the
  identity ID format, non-empty namespace and service account, and a single
  audience.
- Outputs `oidc_issuer_url` and `federated_identity_credential_ids`.

### Changed

- Minimum azurerm raised from 4.57.0 to 4.65.0, the first release with
  `user_assigned_identity_id` on `azurerm_federated_identity_credential`.
  The CI minimum-provider job now pins 4.65.0.
- Docs: what toggling `oidc_issuer_enabled` and `workload_identity_enabled`
  does on azurerm 4.x and 5.x.

## [1.1.0] - 2026-11-05

### Added

- `node_provisioning_mode` (`node_provisioning_profile`, required by azurerm
  5.0) and an explicit `oidc_issuer_enabled` (default `false`).

### Changed

- Allow azurerm 5.x (`>= 4.57.0, < 6.0`).
- CI: bump actions, pin OpenTofu 1.13.8, add tflint and minimum-provider
  jobs, restrict the workflow token to `contents: read`, add Dependabot.

### Fixed

- Reject `network_policy = "cilium"`, which always failed against Azure.
- Do not pass `node_count` when autoscaling is enabled.

## [1.0.0]

Initial release (`v0.1.0` points at the same commit).

[Unreleased]: https://github.com/moveeeax/terraform-azurerm-aks/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/moveeeax/terraform-azurerm-aks/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/moveeeax/terraform-azurerm-aks/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/moveeeax/terraform-azurerm-aks/releases/tag/v1.0.0
