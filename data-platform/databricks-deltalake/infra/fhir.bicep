param workspaceName string
param fhirServiceName string
param tenantId string
param location string
param tags object = {}

var loginURL = environment().authentication.loginEndpoint
var authority = '${loginURL}${tenantId}'
var audience = 'https://${workspaceName}-${fhirServiceName}.fhir.azurehealthcareapis.com'

resource healthWorkspace 'Microsoft.HealthcareApis/workspaces@2021-06-01-preview' = {
  name: workspaceName
  location: location
  tags: tags
}

resource fhir 'Microsoft.HealthcareApis/workspaces/fhirservices@2021-06-01-preview' = {
  name: '${workspaceName}/${fhirServiceName}'
  location: location
  kind: 'fhir-R4'

  identity: {
    type: 'SystemAssigned'
  }

  properties: {
    authenticationConfiguration: {
      authority: authority
      audience: audience
      smartProxyEnabled: false
    }
  }

  tags: tags

  dependsOn: [
    healthWorkspace
  ]
}

output fhirId string = fhir.id
output fhirServiceUrl string = 'https://${workspaceName}-${fhirServiceName}.fhir.azurehealthcareapis.com'
