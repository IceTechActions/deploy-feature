// ============================================================
// Per-Feature Environment Parameters
// ============================================================
// Used by main.bicep to deploy a feature environment.
//
// The following parameters have NO defaults here and MUST be supplied
// as inputs to the deploy-feature action (which passes them via --parameters):
//
//   userManagedIdentityName        (action input: user_managed_identity_name)
//   userManagedIdentityResourceGroup (action input: user_managed_identity_resource_group)
//   appConfigName                  (action input: app_config_name)
//   useElastic8                    (action input: use_elastic8)
//   elastic8Endpoint               (action input: elastic8_endpoint)
//   hasCustomJwtSecret             (action input: has_custom_jwt_secret)
//   containerAppsEnvironmentName   (action input: container_apps_environment_name)
//
// The following are overridden per deployment via --parameters on the CLI:
//   name, registryServer, nordicContainerImageName/Tag, workerContainerImageName/Tag,
//   appConfigLabel, wafPolicyId, dnsZoneResourceGroup
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

// ── App Configuration ─────────────────────────────────────────────────────────
param appConfigLabel = 'Feature-0000'

// ── Feature flags (correct defaults for all feature environments) ─────────────
param enablePlayground = true
param enableUnsecurePlayground = true
param superAdministratorMode = true
param includeExceptionDetails = true

// ── Front Door ────────────────────────────────────────────────────────────────
param frontDoorName = 'fd-nisportal'
param wafPolicyId = ''
param dnsZoneResourceGroup = ''
param dnsZoneName = 'cust.nisportal.com'
