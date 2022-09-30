@description('Name prefix for all resources.')
@minLength(3)
@maxLength(24)
param name string

@description('Location to deploy resources.')
param location string

@description('The FHIR Service endpoint to export data from.')
param fhirServiceUrl string

@description('Name of the Azure Datalake Storage Gen 2 Storage Account')
param storageAccountName string

param tags object = {}

@allowed([
  'R4'
])
param fhirVersion string = 'R4'

@description('Start timestamp of the data range you want to export.')
param dataStart string = '1970-01-01 00:00:00 +00:00'

@description('End timestamp of the data range you want to export. Will continuous export all data if not specified.')
param dataEnd string = ''

@description('The name of the container to store job and data.')
param containerName string = 'fhir'

@description('The fhir-to-synapse pipeline package url.')
param packageUrl string = 'https://fhiranalyticspipeline.blob.core.windows.net/builds/Microsoft.Health.Fhir.Synapse.FunctionApp.zip'

resource functionStorageAccount 'Microsoft.Storage/storageAccounts@2021-09-01' existing = {
  name: storageAccountName
}

var hostingPlanName = '${name}-host'
resource functionHostingPlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: hostingPlanName
  location: location
  tags: tags
  sku: {
    tier: 'ElasticPremium'
    name: 'EP3'
  }
  properties: {
    elasticScaleEnabled: true
  }
}

var functionAppName = '${name}-fa'
resource functionApp 'Microsoft.Web/sites@2022-03-01' = {
  name: functionAppName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  kind: 'functionapp'
  properties: {
    serverFarmId: functionHostingPlan.id
    siteConfig: {
      use32BitWorkerProcess: false
    }
  }
}

@description('FHIR to Datalake function all settings')
resource functionAppSettings 'Microsoft.Web/sites/config@2020-12-01' = {
  name: 'appsettings'
  parent: functionApp
  properties: {
    AzureWebJobsStorage: 'DefaultEndpointsProtocol=https;AccountName=${functionStorageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(functionStorageAccount.id, '2019-06-01').keys[0].value}'
    WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: 'DefaultEndpointsProtocol=https;AccountName=${functionStorageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(functionStorageAccount.id, '2019-06-01').keys[0].value}'
    WEBSITE_CONTENTSHARE: toLower(functionAppName)
    FUNCTIONS_EXTENSION_VERSION: '~2'
    FUNCTIONS_WORKER_RUNTIME: 'dotnet-isolated'
    APPINSIGHTS_INSTRUMENTATIONKEY: appInsights.properties.InstrumentationKey
    APPLICATIONINSIGHTS_CONNECTION_STRING: 'InstrumentationKey=${appInsights.properties.InstrumentationKey}'
    job__containerName: containerName
    job__startTime: dataStart
    job__endTime: dataEnd
    filter__filterScope: 'System'
    filter__groupId: ''
    filter__requiredTypes: ''
    filter__typeFilters: ''
    schema__enableCustomizedSchema: 'false'
    dataLakeStore__storageUrl: 'https://${functionStorageAccount.name}.blob.${environment().suffixes.storage}'
    fhirServer__serverUrl: fhirServiceUrl
    fhirServer__version: fhirVersion
    fhirServer__authentication: 'ManagedIdentity'
  }
}


@description('Deploy the FHIR to Analytics function app code to the function app')
resource fhirToAnalyticsMsDeploy 'Microsoft.Web/sites/Extensions@2022-03-01' = {
  parent: functionApp
  name: 'MSDeploy'
  properties: {
    packageUri: packageUrl
  }

  dependsOn: [ functionAppSettings ]
}

var appInsightsName = '${name}-ai'

@description('Monitoring for Function App')
resource appInsights 'Microsoft.Insights/components@2020-02-02-preview' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
  tags: union(tags, {
      'hidden-link:${resourceId('Microsoft.Web/sites', appInsightsName)}': 'Resource'
    })
}

output functionAppName string = functionAppName
output functionAppPrincipalId string = functionApp.identity.principalId
output hostName string = functionApp.properties.defaultHostName
