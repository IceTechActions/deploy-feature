// ============================================================
// Feature Environment Deployment - Azure Container Apps
// ============================================================
// Deploys a per-feature environment with:
//   - Nordic WebAPI container (internal ingress)
//   - Worker container (internal ingress)
//   - HttpRouteConfig for path-based routing (/* → Nordic, /worker/* → Worker)
//   - Per-feature Hangfire storage account
//   - Application Insights
//   - Front Door endpoint, origin, custom domain, route, WAF
//
// Prerequisites (deploy once via modules/container-apps-environment.bicep
// and modules/frontdoor-shared.bicep):
//   - Shared Container Apps Environment with VNet + Log Analytics
//   - Shared Front Door Premium profile + WAF policies
//
// DNS CNAME must be created separately via modules/frontdoor-dns.bicep
// in the DNS zone's resource group (cross-RG deployment).
// ============================================================

@description('The name of the feature environment (e.g., feature-1234). Must be lowercase alphanumeric and hyphens.')
param name string

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Name of the shared Container Apps Environment.')
param containerAppsEnvironmentName string = 'feature-environments'

@description('The Azure Container Registry server URL (e.g., niscontainers.azurecr.io).')
param registryServer string

@description('The full image name for the Nordic container (e.g., niscontainers.azurecr.io/nordic).')
param nordicContainerImageName string

@description('The Nordic container image tag (e.g., 25.10.0-feature-1234).')
param nordicContainerImageTag string

@description('The full image name for the Worker container (e.g., niscontainers.azurecr.io/worker).')
param workerContainerImageName string

@description('The Worker container image tag (e.g., 25.10.0-feature-1234).')
param workerContainerImageTag string

@description('The name of the user-assigned managed identity for pulling container images.')
param userManagedIdentityName string

@description('The resource group where the user-assigned managed identity resides.')
param userManagedIdentityResourceGroup string

@description('The App Configuration label to use.')
param appConfigLabel string

@description('The name of the App Configuration resource.')
param appConfigName string

@description('Flag to indicate if Elastic 8 is used.')
param useElastic8 bool

@description('The Elasticsearch 8 endpoint URL.')
param elastic8Endpoint string

@description('Flag to enable GraphQL Playground and Swagger UI.')
param enablePlayground bool

@description('Flag to enable unsecure GraphQL endpoints (only meaningful when playground is enabled).')
param enableUnsecurePlayground bool

@description('Flag to enable Super Administrator Mode.')
param superAdministratorMode bool

@description('Flag to include exception details in error responses.')
param includeExceptionDetails bool

@description('Flag indicating if the environment has a custom JWT secret configured in Key Vault.')
param hasCustomJwtSecret bool = false

@description('Name of the shared Azure Front Door profile.')
param frontDoorName string = 'fd-nisportal'

@description('Resource ID of the WAF policy to associate with this feature environment.')
param wafPolicyId string

@description('Resource group containing the nisportal.com DNS zone.')
param dnsZoneResourceGroup string

@description('Name of the Azure DNS zone resource (e.g. "cust.nisportal.com"). Used both to reference the DNS zone and to construct feature hostnames.')
param dnsZoneName string = 'cust.nisportal.com'

// Derived container image references
var nordicContainerImage = '${nordicContainerImageName}:${nordicContainerImageTag}'
var workerContainerImage = '${workerContainerImageName}:${workerContainerImageTag}'

// Per-feature hangfire storage (mirrors appservice-sidecar pattern)
var hangfireStorageAccountName = '${toLower(replace(name, '-', ''))}storage'
var hangfireFileShareName = 'appservicestorage'
// Unique mount name per feature so multiple features can share one Container Apps Environment
var hangfireStorageMountName = '${name}-hangfire'

var appInsightsName = '${name}-application-insights'

// ── Existing resource references ─────────────────────────────────────────────

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-07-01' existing = {
  name: 'nis-developers-logAnalytics'
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: userManagedIdentityName
  scope: resourceGroup(userManagedIdentityResourceGroup)
}

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2025-01-01' existing = {
  name: containerAppsEnvironmentName
}

resource frontDoor 'Microsoft.Cdn/profiles@2025-06-01' existing = {
  name: frontDoorName
}

// Reference existing DNS zone for Front Door custom domain validation
resource dnsZone 'Microsoft.Network/dnsZones@2018-05-01' existing = {
  name: dnsZoneName
  scope: resourceGroup(dnsZoneResourceGroup)
}

// ── Per-feature resources ─────────────────────────────────────────────────────

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

// Per-feature storage account for Hangfire persistence
resource hangfireStorageAccount 'Microsoft.Storage/storageAccounts@2025-06-01' = {
  name: hangfireStorageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
  }
}

resource hangfireFileService 'Microsoft.Storage/storageAccounts/fileServices@2025-06-01' = {
  parent: hangfireStorageAccount
  name: 'default'
}

resource hangfireFileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2025-06-01' = {
  parent: hangfireFileService
  name: hangfireFileShareName
  properties: {
    accessTier: 'Hot'
  }
}

// Register the per-feature hangfire storage in the shared environment
resource hangfireStorageMount 'Microsoft.App/managedEnvironments/storages@2025-01-01' = {
  parent: containerAppsEnvironment
  name: hangfireStorageMountName
  properties: {
    azureFile: {
      accountName: hangfireStorageAccount.name
      #disable-next-line use-secure-value-for-secure-inputs
      accountKey: hangfireStorageAccount.listKeys().keys[0].value
      shareName: hangfireFileShareName
      accessMode: 'ReadWrite'
    }
  }
}

// ── Environment variables ─────────────────────────────────────────────────────

var sharedEnvironmentVariables = [
  { name: 'AppConfig__Label', value: appConfigLabel }
  { name: 'AppConfig__ManagedIdentityId', value: managedIdentity.properties.clientId }
  { name: 'AppConfig__Name', value: appConfigName }
  { name: 'AppConfig__UseManaged', value: 'true' }
  { name: 'AZURE_CLIENT_ID', value: managedIdentity.properties.clientId }
  { name: 'APPINSIGHTS_INSTRUMENTATIONKEY', value: appInsights.properties.InstrumentationKey }
  { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
  { name: 'Elastic__Uris__0', value: useElastic8 ? elastic8Endpoint : '' }
  { name: 'Elastic__Uris__1', value: useElastic8 ? elastic8Endpoint : '' }
  { name: 'Elastic__Uris__2', value: useElastic8 ? elastic8Endpoint : '' }
  { name: 'GraphQL__EnablePlayground', value: enablePlayground ? 'true' : 'false' }
  { name: 'GraphQL__EnableUnsecureEndpoint', value: enableUnsecurePlayground ? 'true' : 'false' }
  { name: 'GraphQL__EnableIntrospection', value: enablePlayground ? 'true' : 'false' }
  { name: 'Swagger__Enabled', value: enablePlayground ? 'true' : 'false' }
  { name: 'GraphQL__IncludeExceptionDetails', value: includeExceptionDetails ? 'true' : 'false' }
  { name: 'SuperAdministratorMode', value: superAdministratorMode ? 'true' : 'false' }
]

var jwtEnvironmentVariables = hasCustomJwtSecret
  ? [
      { name: 'Security__Jwt__Issuer', value: 'http://nisportal.com' }
      { name: 'Security__Jwt__Audience', value: 'Any' }
      { name: 'Security__Jwt__Expires', value: '60' }
    ]
  : []

var nordicEnvironmentVariables = concat(sharedEnvironmentVariables, jwtEnvironmentVariables, [
  { name: 'ASPNETCORE_HTTP_PORTS', value: '8080' }
])

var workerEnvironmentVariables = concat(sharedEnvironmentVariables, jwtEnvironmentVariables, [
  { name: 'ASPNETCORE_HTTP_PORTS', value: '8080' }
])

// ── Container Apps ────────────────────────────────────────────────────────────

// Nordic WebAPI - internal ingress, accessed via HttpRouteConfig
resource nordicApp 'Microsoft.App/containerApps@2025-01-01' = {
  name: '${name}-nordic'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: false
        targetPort: 8080
        transport: 'http'
      }
      registries: [
        {
          server: registryServer
          identity: managedIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'nordic'
          image: nordicContainerImage
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
          env: nordicEnvironmentVariables
          volumeMounts: [
            {
              volumeName: 'aci-storage'
              mountPath: '/aci/storage'
            }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 8080
              }
              initialDelaySeconds: 30
              periodSeconds: 10
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health'
                port: 8080
              }
              initialDelaySeconds: 5
              periodSeconds: 5
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
      volumes: [
        {
          name: 'aci-storage'
          storageName: 'nisacistorage'
          storageType: 'AzureFile'
        }
      ]
    }
  }
}

// Background Worker - internal ingress, accessed via HttpRouteConfig
resource workerApp 'Microsoft.App/containerApps@2025-01-01' = {
  name: '${name}-worker'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: false
        targetPort: 8080
        transport: 'http'
      }
      registries: [
        {
          server: registryServer
          identity: managedIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'worker'
          image: workerContainerImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: workerEnvironmentVariables
          volumeMounts: [
            {
              volumeName: 'aci-storage'
              mountPath: '/aci/storage'
            }
            {
              volumeName: 'hangfire-storage'
              mountPath: '/aci/storage/hangfire'
            }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 8080
              }
              initialDelaySeconds: 30
              periodSeconds: 10
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health'
                port: 8080
              }
              initialDelaySeconds: 5
              periodSeconds: 5
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
      volumes: [
        {
          name: 'aci-storage'
          storageName: 'nisacistorage'
          storageType: 'AzureFile'
        }
        {
          name: 'hangfire-storage'
          storageName: hangfireStorageMountName
          storageType: 'AzureFile'
        }
      ]
    }
  }
  dependsOn: [
    hangfireStorageMount
  ]
}

// Path-based routing via native Container Apps HttpRouteConfig
// Replaces the Traefik gateway container — routes at the environment level with $0 extra cost
// Rule order matters: more specific prefixes must come before less specific ones
resource httpRouteConfig 'Microsoft.App/managedEnvironments/httpRouteConfigs@2025-07-01' = {
  parent: containerAppsEnvironment
  name: '${name}-routing'
  properties: {
    rules: [
      {
        description: 'Worker routes - /worker/* prefix stripped before forwarding'
        routes: [
          {
            match: {
              prefix: '/worker'
            }
            action: {
              prefixRewrite: '/'
            }
          }
        ]
        targets: [
          {
            containerApp: workerApp.name
          }
        ]
      }
      {
        description: 'Nordic catch-all - /, /api/*, /graphql, /hangfire, /swagger, /health'
        routes: [
          {
            match: {
              prefix: '/'
            }
          }
        ]
        targets: [
          {
            containerApp: nordicApp.name
          }
        ]
      }
    ]
  }
}

// ── Front Door per-feature resources ─────────────────────────────────────────

// Dedicated endpoint for this feature environment
resource fdEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2025-06-01' = {
  parent: frontDoor
  name: name
  location: 'global'
  properties: {
    enabledState: 'Enabled'
  }
}

// Origin group with health probe targeting Nordic /health (via HttpRouteConfig catch-all)
resource fdOriginGroup 'Microsoft.Cdn/profiles/originGroups@2025-06-01' = {
  parent: frontDoor
  name: '${name}-origins'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/health'
      probeRequestType: 'HEAD'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 30
    }
    sessionAffinityState: 'Disabled'
  }
}

// Origin pointing to the HttpRouteConfig FQDN
resource fdOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2025-06-01' = {
  parent: fdOriginGroup
  name: 'routing'
  properties: {
    hostName: httpRouteConfig.properties.fqdn
    httpPort: 80
    httpsPort: 443
    originHostHeader: httpRouteConfig.properties.fqdn
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
  }
}

// Custom domain: feature-1234.cust.nisportal.com
// azureDnsZone enables automatic CNAME validation and managed certificate provisioning
resource fdCustomDomain 'Microsoft.Cdn/profiles/customDomains@2025-06-01' = {
  parent: frontDoor
  name: replace('${name}-${dnsZoneName}', '.', '-')
  properties: {
    hostName: '${name}.${dnsZoneName}'
    tlsSettings: {
      certificateType: 'ManagedCertificate'
      minimumTlsVersion: 'TLS12'
    }
    azureDnsZone: {
      id: dnsZone.id
    }
  }
}

// Route: custom domain → origin group, HTTPS only with redirect
resource fdRoute 'Microsoft.Cdn/profiles/afdEndpoints/routes@2025-06-01' = {
  parent: fdEndpoint
  name: 'default'
  properties: {
    customDomains: [
      { id: fdCustomDomain.id }
    ]
    originGroup: {
      id: fdOriginGroup.id
    }
    supportedProtocols: ['Https']
    httpsRedirect: 'Enabled'
    forwardingProtocol: 'HttpsOnly'
    patternsToMatch: ['/*']
    linkToDefaultDomain: 'Enabled'
    enabledState: 'Enabled'
  }
  dependsOn: [fdOrigin] // ensure origin is provisioned before route references the origin group
}

// WAF policy association for this feature environment's domain
resource fdSecurityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2025-06-01' = {
  parent: frontDoor
  name: '${name}-waf'
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: wafPolicyId
      }
      associations: [
        {
          domains: [
            { id: fdCustomDomain.id }
          ]
          patternsToMatch: ['/*']
        }
      ]
    }
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

// Primary URL via Front Door with custom domain
output featureUrl string = 'https://${name}.${dnsZoneName}'

// Front Door default URL (usable before DNS CNAME is created)
output frontDoorUrl string = 'https://${fdEndpoint.properties.hostName}'

// HttpRouteConfig FQDN - pass to modules/frontdoor-dns.bicep when creating CNAME record
output routeConfigFqdn string = httpRouteConfig.properties.fqdn

// Container App names (for reference and teardown)
output nordicAppName string = nordicApp.name
output workerAppName string = workerApp.name

// Internal URLs (for debugging)
output nordicInternalUrl string = 'http://${nordicApp.name}:8080'
output workerInternalUrl string = 'http://${workerApp.name}:8080'
