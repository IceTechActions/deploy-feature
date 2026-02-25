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

| Input | Required | Description |
|-------|----------|-------------|
| `feature_name` | Yes | Feature environment name, e.g. `feature-1234`. Used as a prefix for all resource names. |
| `resource_group` | Yes | Azure resource group to deploy into |
| `registry_server` | Yes | Container registry login server, e.g. `niscontainers.azurecr.io` |
| `nordic_image_tag` | Yes | Tag of the Nordic container image to deploy |
| `worker_image_tag` | Yes | Tag of the Worker container image to deploy |
| `pr_id` | Yes | Pull request number — sets the App Configuration label to `Feature-{pr_id}` |
| `waf_policy_id` | Yes | Full resource ID of the WAF policy to associate with the custom domain |
| `dns_zone_resource_group` | Yes | Resource group containing the `nisportal.com` DNS zone (used for Front Door custom domain validation) |

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
    pr_id: 1234
    waf_policy_id: /subscriptions/.../providers/Microsoft.Network/frontDoorWebApplicationFirewallPolicies/myWafPolicy
    dns_zone_resource_group: my-dns-rg

- name: Create DNS CNAME
  uses: IceTechActions/create-dns-cname@v1
  with:
    feature_name: feature-1234
    fd_hostname: ${{ steps.deploy.outputs.fd_hostname }}
    dns_zone_resource_group: my-dns-rg
```
