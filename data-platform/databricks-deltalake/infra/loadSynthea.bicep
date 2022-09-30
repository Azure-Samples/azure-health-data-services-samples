param fhirUrl string
param location string
param identity string

resource loadSyntheaData 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'loadSyntheaData'
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
    timeout: 'PT15M'
    cleanupPreference: 'OnExpiration'
    retentionInterval: 'PT1H'
    environmentVariables: [
      {
        name: 'FHIR_URL'
        value: fhirUrl
      }
    ]
    scriptContent: loadTextContent('scripts/load-synthea-data.sh')
  }
}
