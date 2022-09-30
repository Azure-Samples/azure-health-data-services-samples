@minLength(2)
@maxLength(6)
@description('Prefex for your resources. It must be 2-6 characters and only be letters.')
param resourcePrefix string = 'fhirdl'

@description('Location for your resources.')
param resourceLocation string = resourceGroup().location

var resourceTags = {
  'AHDS-Sample': 'Databricks-Delta-Lake'
}

var uniqueNameString = uniqueString(guid(resourceGroup().id), resourceLocation)
var name = '${resourcePrefix}${uniqueNameString}'
var databricksWorkspaceName = '${name}-dbws'
var managedResourceGroupName = 'databricks-rg-${databricksWorkspaceName}-${uniqueString(databricksWorkspaceName, resourceGroup().id)}'
var managedIdentityName = '${name}-identity'
var ahdsWorkspaceName = '${name}0ahds'
var fhirName = 'databricks-delta-test'
var fhirUrl = 'https://${ahdsWorkspaceName}-${fhirName}.fhir.azurehealthcareapis.com'
var datalakeName = '${name}0lake'

@description('Creates Databricks managed resource group.')
resource managedResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  scope: subscription()
  name: managedResourceGroupName
}

@description('Creates the managed identity needed for deployment screpts')
module managed_identity 'managedIdentity.bicep' = {
  name: 'ManagedIdentity'
  params: {
    managedIdentityName: managedIdentityName
    location: resourceLocation
  }
}

module databricks_template 'databricks.bicep'= {
  name: 'databricks-workspace-${databricksWorkspaceName}'
  params: {
    workspaceName: databricksWorkspaceName
    location: resourceLocation
    tier: 'premium'
    tags: resourceTags
    managedResourceGroupId: managedResourceGroup.id
    identity: managed_identity.outputs.identityId
    storageName: datalakeName
  }

  dependsOn: [ datalake_template ]
}

@description('Deploys Azure Health Data Services and FHIR Service')
module fhir_template 'fhir.bicep'= {
  name: 'ahds-with-fhir-${ahdsWorkspaceName}'
  params: {
    workspaceName: ahdsWorkspaceName
    fhirServiceName: fhirName
    tenantId: subscription().tenantId
    location: resourceLocation
    tags: resourceTags
  }
}

@description('Deploys Azure Health Data Services and FHIR Service')
module synthea_data 'loadSynthea.bicep'= {
  name: 'load-synthea-${ahdsWorkspaceName}'
  params: {
    fhirUrl: fhirUrl
    location: resourceLocation
    identity: managed_identity.outputs.identityId
  }
  dependsOn: [fhir_template]
}

@description('Deploys an Azure Data Lake Gen 2 for data pipeline')
module datalake_template 'datalake.bicep'= {
  name: 'datalake-${datalakeName}'
  params: {
    name: datalakeName
    location: resourceLocation
    tags: resourceTags
  }
}

@description('Deploys FHIR to Analytics function.')
module analytics_sync_app_template 'analytics_sync_app.bicep'= {
  name: 'fhirtoanalyticsfunction-${name}'
  params: {
    name: name
    location: resourceLocation
    fhirServiceUrl: fhirUrl
    storageAccountName: datalakeName
    tags: resourceTags
  }

  dependsOn: [databricks_template, datalake_template]
}

@description('Setup identity connection between FHIR and the function app')
module functionFhirIdentity './roleAssignment.bicep'= {
  name: 'fhirIdentity-function'
  params: {
    resourceId: fhir_template.outputs.fhirId
    roleId: '5a1fc7df-4bf1-4951-a576-89034ee01acd'
    principalId: analytics_sync_app_template.outputs.functionAppPrincipalId
  }
}

@description('Setup identity connection between FHIR and the function app')
module deploymentScriptFhirIdentity './roleAssignment.bicep'= {
  name: 'fhirIdentity-deployment'
  params: {
    resourceId: fhir_template.outputs.fhirId
    roleId: '5a1fc7df-4bf1-4951-a576-89034ee01acd'
    principalId: managed_identity.outputs.identityPrincipalId
  }
}

@description('Setup identity connection between FHIR and the function app')
module functionStorageIdentity './roleAssignment.bicep'= {
  name: 'storageIdentity-function'
  params: {
    resourceId: datalake_template.outputs.storage_account_id
    roleId: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    principalId: analytics_sync_app_template.outputs.functionAppPrincipalId
  }
}


