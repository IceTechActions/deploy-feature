// ============================================================
// Per-Feature Environment Parameters
// ============================================================
// Used by main.bicep to deploy a feature environment.
//
// In CI/CD, most values are overridden via --parameters on the CLI:
//   az deployment group create \
//     --resource-group $RESOURCE_GROUP \
//     --template-file main.bicep \
//     --parameters parameters/feature-environment.bicepparam \
//     --parameters name="feature-1234" \
//                  nordicContainerImageTag="25.10.0-feature-1234" \
//                  workerContainerImageTag="25.10.0-feature-1234"
// ============================================================

using '../main.bicep'

// ── Feature identity (overridden per deployment) ──────────────────────────────
param name = 'feature-0000'

// ── Container Registry ────────────────────────────────────────────────────────
param registryServer = 'niscontainers.azurecr.io'

param nordicContainerImageName = 'niscontainers.azurecr.io/nordic'
param nordicContainerImageTag = 'latest'

param workerContainerImageName = 'niscontainers.azurecr.io/worker'
param workerContainerImageTag = 'latest'

// ── Identity ──────────────────────────────────────────────────────────────────
param userManagedIdentityName = 'GHAction'
param userManagedIdentityResourceGroup = 'nc-internal-testops'

// ── App Configuration ─────────────────────────────────────────────────────────
param appConfigLabel = 'Feature-0000'
param appConfigName = 'nis-developers-aac'

// ── Elasticsearch ─────────────────────────────────────────────────────────────
param useElastic8 = true
param elastic8Endpoint = 'https://nis-virt-esdata-0.nisportal.com:9200'

// ── Feature flags ─────────────────────────────────────────────────────────────
param enablePlayground = true
param enableUnsecurePlayground = true
param superAdministratorMode = true
param includeExceptionDetails = true
param hasCustomJwtSecret = false

// ── Front Door ────────────────────────────────────────────────────────────────
param frontDoorName = 'fd-nisportal'
param wafPolicyId = ''
param dnsZoneResourceGroup = ''
param customDomainBase = 'cust.nisportal.com'
param dnsZoneName = 'cust.nisportal.com'
