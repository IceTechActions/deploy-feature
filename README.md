# deploy-feature

Deploys a per-feature Azure environment consisting of:

- **Two Container Apps** — Nordic WebAPI (`{name}-nordic`) and background Worker (`{name}-worker`), both with internal ingress
- **HttpRouteConfig** — path-based routing at the Container Apps Environment level; routes `/worker/*` to the Worker and `/*` to Nordic
- **Per-feature Hangfire storage** — a dedicated Storage Account and file share, mounted into the Worker container at `/aci/storage/hangfire`
- **Application Insights** — per-feature `{name}-application-insights`
- **Front Door endpoint, origin group, origin, custom domain, route, WAF association** — exposes the environment at `https://{name}.cust.nisportal.com`

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
| `waf_policy_id` | Yes | — | Full resource ID of the WAF policy to associate with the custom domain |
| `dns_zone_resource_group` | Yes | — | Resource group containing the `cust.nisportal.com` DNS zone |
| `user_managed_identity_name` | Yes | — | Name of the user-assigned managed identity used for ACR pull access on the Container Apps |
| `user_managed_identity_resource_group` | Yes | — | Resource group where the user-assigned managed identity resides |
| `app_config_name` | Yes | — | Name of the Azure App Configuration resource |
| `use_elastic8` | No | `true` | Whether to enable Elastic 8 (`true`/`false`) |
| `elastic8_endpoint` | No | `''` | Elastic 8 endpoint URL (leave empty to disable) |
| `has_custom_jwt_secret` | No | `false` | Whether a custom JWT secret is configured in Key Vault for this environment |
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

### Front Door propagation polling

After the Bicep deployment completes, the action runs a **"Wait for Front Door configuration to propagate"** step. This step polls the AFD endpoint and route `deploymentStatus` every 30 seconds until both reach `Succeeded`, ensuring the environment is actually reachable before the job moves on.

- **Timeout:** 10 minutes (600 s). If propagation has not completed by then, the step emits a `::warning::` annotation and exits — the site may not be immediately accessible, but the deployment itself succeeded.
- **Why this matters:** Front Door changes can take several minutes to distribute to all points of presence. Without this wait, DNS and routing may not be active yet when downstream steps (e.g. smoke tests) run.
- **Skipping:** There is no skip option. If you need to bypass the wait, set `front_door_name` to an endpoint name that resolves immediately, or accept the warning and add a manual delay in your workflow instead.
