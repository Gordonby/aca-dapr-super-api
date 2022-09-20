param location string = resourceGroup().location

module myenv 'br/public:app/dapr-containerapps-environment:1.0.1' = {
  name: 'state'
  params: {
    location: location
    nameseed: 'superApi'
    applicationEntityName: 'statestore'
    daprComponentType: 'state.azure.cosmosdb'
    daprComponentScopes: [
      'back'
    ]
    daprComponentName: 'cosmosdb'
  }
}

module front 'br/public:app/dapr-containerapp:1.0.1' = {
  name: 'front'
  params: {
    location: location
    containerAppName: 'front'
    containerAppEnvName: myenv.outputs.containerAppEnvironmentName
    containerImage: 'ghcr.io/gbaeke/super:1.0.5'
    targetPort: 8080
    externalIngress: true
    createUserManagedId: false
    minReplicas: 0
    maxReplicas: 5
  }
}

module back 'br/public:app/dapr-containerapp:1.0.1' = {
  name: 'back'
  params: {
    location: location
    containerAppName: 'back'
    containerAppEnvName: myenv.outputs.containerAppEnvironmentName
    containerImage: 'ghcr.io/gbaeke/super:1.0.5'
    targetPort: 8080
    enableIngress: true
    externalIngress: false
    createUserManagedId: false
    minReplicas: 1
    maxReplicas: 5
  }
}
