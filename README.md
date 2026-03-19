# deploy-feature

Deploys a per-feature Azure environment consisting of:

- **Two Container Apps** — Nordic WebAPI (`{name}-nordic`) and background Worker (`{name}-worker`), both with internal ingress
- **HttpRouteConfig** — path-based routing at the Container Apps Environment level; routes `/worker/*` to the Worker and `/*` to Nordic
- **Per-feature Hangfire storage** — a dedicated Storage Account and file share, mounted into the Worker container at `/aci/storage/hangfire`
- **Application Insights** — per-feature `{name}-application-insights`
- **Front Door endpoint, origin group, origin, custom domain, and route** — exposes the environment at `https://{name}.cust.nisportal.com`

After the Bicep deployment the action calls the shared [`IceTechActions/front-door-waf-domain`](https://github.com/IceTechActions/front-door-waf-domain) action to associate the new custom domain with the shared WAF security policy. This avoids the Azure AFD restriction that only one security policy may exist per WAF policy per Front Door profile.

The action bundles `main.bicep` and `parameters/feature-environment.bicepparam` — the calling repo does not need any Bicep files.

## Prerequisites

- Active Azure CLI session with permissions to deploy to the target resource group and modify the shared Front Door profile
- Shared infrastructure already deployed: Container Apps Environment (`feature-environments`), shared Front Door profile (`fd-nisportal`), Log Analytics workspace, and user-assigned managed identity
- `nisacistorage` storage mount already registered in the Container Apps Environment

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `feature_name` | Yes | — | Feature environment name, e.g. `feature-1234`. Used as a prefix for all resource names. |
| `resource_group` | Yes | — | Azure resource group to deploy into |
| `registry_server` | Yes | — | Container registry login server, e.g. `niscontainers.azurecr.io` |
| `nordic_image_tag` | Yes | — | Tag of the Nordic container image to deploy |
| `worker_image_tag` | Yes | — | Tag of the Worker container image to deploy |
| `waf_policy_id` | Yes | — | Full resource ID of the WAF policy. Passed to the shared `front-door-waf-domain` action to add the custom domain to the shared security policy. |
| `dns_zone_resource_group` | Yes | — | Resource group containing the `cust.nisportal.com` DNS zone |
| `user_managed_identity_name` | Yes | — | Name of the user-assigned managed identity used for ACR pull access on the Container Apps |
| `user_managed_identity_resource_group` | Yes | — | Resource group where the user-assigned managed identity resides |
| `app_config_name` | Yes | — | Name of the Azure App Configuration resource |
| `use_elastic8` | No | `true` | Whether to enable Elastic 8 (`true`/`false`) |
| `elastic8_endpoint` | No | `''` | Elastic 8 endpoint URL (leave empty to disable) |
| `dns_zone_name` | No | `cust.nisportal.com` | DNS zone name used to construct the AFD custom domain resource name |
| `keyvault_name` | Yes | — | Key Vault name where feature secrets are stored |
| `sql_server` | Yes | — | SQL server hostname for the feature database connection string |
| `sql_user_name` | Yes | — | Feature SQL login name |
| `sql_user_password` | Yes | — | SQL login password (sensitive) |
| `jwt_secret` | No | `''` | JWT secret value (sensitive). When provided, the secret is written to Key Vault and `hasCustomJwtSecret` is set to `true` for the Bicep deployment. Omit (or leave empty) when no custom JWT secret is needed. |
| `is_pr_check` | No | `false` | Skip secret-setting when `'true'` (PR check redeployment) |
| `container_apps_environment_name` | No | `feature-environments` | Name of the shared Container Apps Environment |
| `front_door_name` | No | `fd-nisportal` | Name of the shared Azure Front Door profile |

## Outputs

| Output | Description |
|--------|-------------|
| `feature_url` | Full HTTPS URL of the deployed environment, e.g. `https://feature-1234.cust.nisportal.com` |
| `fd_hostname` | Front Door endpoint hostname without `https://` — pass to `IceTechActions/create-dns-cname` |

## Usage

```yaml
- name: Azure Login (OIDC)
  uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

- name: Deploy feature environment
  id: deploy
  uses: IceTechActions/deploy-feature@v1
  with:
    feature_name: feature-1234
    resource_group: my-resource-group
    registry_server: niscontainers.azurecr.io
    nordic_image_tag: 25.10.0-feature-1234
    worker_image_tag: 25.10.0-feature-1234
    waf_policy_id: /subscriptions/.../providers/Microsoft.Network/frontDoorWebApplicationFirewallPolicies/myWafPolicy
    dns_zone_resource_group: my-dns-rg
    user_managed_identity_name: my-acr-pull-identity
    user_managed_identity_resource_group: my-identity-rg
    app_config_name: my-app-config

- name: Create DNS CNAME
  uses: IceTechActions/create-dns-cname@v1
  with:
    feature_name: feature-1234
    fd_hostname: ${{ steps.deploy.outputs.fd_hostname }}
    dns_zone_resource_group: my-dns-rg
```

## Behaviour

### WAF domain association

After the Bicep deployment, the action calls [`IceTechActions/front-door-waf-domain`](https://github.com/IceTechActions/front-door-waf-domain) to add the new custom domain to the shared WAF security policy (identified by `waf_policy_id`). Azure AFD allows only **one** security policy per WAF policy per Front Door profile; the shared action manages that single security policy and safely adds individual domain associations, making concurrent environment deployments safe.

### Front Door propagation polling

This action **does not** wait for the Front Door custom domain certificate to be ready. After the Bicep deployment (and WAF association) completes, the workflow continues immediately.

If you need to wait for HTTPS/TLS to be live, add a separate step in your workflow that polls the AFD custom domain resource every 30 seconds until both `domainValidationState == Approved` and `provisioningState == Succeeded`, confirming that the managed certificate has been issued.

The custom domain resource name is derived from the feature name and DNS zone: `${feature_name}-${dns_zone_name}` with dots replaced by hyphens (e.g. `feature-1234-cust-nisportal-com`), matching the Bicep `replace()` call in `main.bicep`.

- **Recommended timeout:** 30 minutes (1800 s). Fresh deployments typically complete in 5–15 minutes as Azure provisions the managed certificate. Redeployments of existing environments typically exit at the first poll iteration (0 s elapsed) since the cert is already `Approved`/`Succeeded`.
- **Why this matters:** The `domainValidationState` and `provisioningState` fields on the custom domain resource are the correct signal for HTTPS readiness. The previously used `deploymentStatus` on the endpoint and route resources reflects internal AFD PoP sync, which can remain `NotStarted` indefinitely even when the site is fully reachable.
- **Skipping:** If you choose not to implement this polling step, be aware that the endpoint may not have HTTPS ready immediately after deployment; add a manual delay or accept potential transient HTTPS failures.
