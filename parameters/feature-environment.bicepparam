// ============================================================
// Per-Feature Environment Parameters
// ============================================================
// Used by main.bicep to deploy a feature environment.
//
// Parameters marked "override via action input" have placeholder values here.
// The deploy-feature action always passes the real values at deploy time via
// --parameters on the CLI, sourced from GitHub repository variables.
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
// Override via action inputs user_managed_identity_name /
// user_managed_identity_resource_group (GitHub vars: AZURE_FEATURE_MANAGED_IDENTITY,
// MANAGED_IDENTITY_RESOURCE_GROUP).
param userManagedIdentityName = ''
param userManagedIdentityResourceGroup = ''

// ── App Configuration ─────────────────────────────────────────────────────────
// appConfigLabel is set at deploy time to "Feature-{pr_id}" (derived from the
// feature environment name). Override via --parameters appConfigLabel="Feature-{pr_id}".
param appConfigLabel = 'Feature-0000'
// Override via action input app_config_name (GitHub var: AZURE_APP_CONFIG_NAME).
param appConfigName = ''

// ── Elasticsearch ─────────────────────────────────────────────────────────────
// Override via action inputs use_elastic8 / elastic8_endpoint
// (GitHub var: ELASTIC8_ENDPOINT).
param useElastic8 = true
param elastic8Endpoint = ''

// ── Feature flags (correct defaults for all feature environments) ─────────────
param enablePlayground = true
param enableUnsecurePlayground = true
param superAdministratorMode = true
param includeExceptionDetails = true
// Override via action input has_custom_jwt_secret when a JWT secret exists.
param hasCustomJwtSecret = false

// ── Front Door ────────────────────────────────────────────────────────────────
param frontDoorName = 'fd-nisportal'
param wafPolicyId = ''
param dnsZoneResourceGroup = ''
param dnsZoneName = 'cust.nisportal.com'
