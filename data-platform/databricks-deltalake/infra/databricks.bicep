@description('Name of the Databricks workspace')
param workspaceName string

@description('Location for Azure Databricks workspack')
param location string

@allowed([
//  'standard'
  'premium'
])
@description('Tier for the Azure Databricks Service. Premium is required for Delta Live Tables.')
param tier string

@description('Resource tag for databricks')
param tags object = {}

@description('ID of the resource group for Databricks managed resources.')
param managedResourceGroupId string

param force_update string = utcNow()
param identity string
param adb_pat_lifetime string = '3600'
param adb_secret_scope_name string = 'sample-secrets'
param adb_cluster_name string = 'test-cluster-01'
param adb_spark_version string = '7.3.x-scala2.12'
param adb_node_type string = 'Standard_D3_v2'
param adb_num_worker string = '3'
param adb_auto_terminate_min string = '30'

@secure()
param storageName string
param storageContainerName string = 'fhir'

resource databricks 'Microsoft.Databricks/workspaces@2022-04-01-preview' = {
  name: workspaceName
  location: location
  tags: tags
  sku: {
    name: tier
  }
  properties: {
    managedResourceGroupId: managedResourceGroupId
    publicNetworkAccess: 'Enabled'
  }
}

resource testDatabricks 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'testDatabricks'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identity}': {}
    }
  }
  properties: {
    azCliVersion: '2.26.0'
    timeout: 'PT5M'
    cleanupPreference: 'OnExpiration'
    retentionInterval: 'PT1H'
    environmentVariables: [
      {
        name: 'ADB_WORKSPACE_URL'
        value: databricks.properties.workspaceUrl
      }
      {
        name: 'ADB_WORKSPACE_ID'
        value: databricks.id
      }
      {
        name: 'SECRET_SCOPE_NAME'
        value: adb_secret_scope_name
      }
      {
        name: 'STORAGE_ACCOUNT_NAME'
        value: storageName
      }
      {
        name: 'RESOURCE_GROUP_NAME'
        value: resourceGroup().name
      }
      {
        name: 'STORAGE_CONTAINER_NAME'
        value: storageContainerName
      }
      {
        name: 'PIPELINE_TEMPLATE'
        value: loadTextContent('scripts/pipeline.json')
      }
    ]
    scriptContent: loadTextContent('scripts/setup-databricks.sh')
  }
}

output databricksWorkspaceId string = databricks.id
output databricksWorkspaceUrl string = databricks.properties.workspaceUrl
