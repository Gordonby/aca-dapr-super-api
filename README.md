# Azure Container Apps -  Super API

⚠️ **IMPORTANT:** this is for an older version of Container Apps; although some commands might still work, expect issues

In the video, I did not show all steps:
- configuring pre-requisites
- provisioning a Container App Environment

I will use ACA for Azure Container Apps.

## Pre-requisites

Make sure you use a recent version of the **Azure CLI** and that you are able to login with **az login**.

Install the ACA extension:

```
az extension add \
  --source https://workerappscliextension.blob.core.windows.net/azure-cli-extension/containerapp-0.2.0-py2.py3-none-any.whl
```

Register the `Microsoft.Web` namespace:

```
az provider register --namespace Microsoft.Web
```

## Provision ACA Environment

Set some variables:

```
RESOURCE_GROUP="rg-aca"
LOCATION="northeurope"
LOG_ANALYTICS_WORKSPACE="la-aca"
CONTAINERAPPS_ENVIRONMENT="myenv"
```

Create the resource group:

```
az group create --name $RESOURCE_GROUP --location "$LOCATION"
```

Create the Log Analytics workspace:

```
az monitor log-analytics workspace create \
  --resource-group $RESOURCE_GROUP \
  --workspace-name $LOG_ANALYTICS_WORKSPACE
```

Retrieve the workspace ID and secret:

```
LOG_ANALYTICS_WORKSPACE_CLIENT_ID=`az monitor log-analytics workspace show --query customerId -g $RESOURCE_GROUP -n $LOG_ANALYTICS_WORKSPACE -o tsv | tr -d '[:space:]'`

LOG_ANALYTICS_WORKSPACE_CLIENT_SECRET=`az monitor log-analytics workspace get-shared-keys --query primarySharedKey -g $RESOURCE_GROUP -n $LOG_ANALYTICS_WORKSPACE -o tsv | tr -d '[:space:]'`
```

Create the ACA environment:

```
az containerapp env create \
  --name $CONTAINERAPPS_ENVIRONMENT \
  --resource-group $RESOURCE_GROUP \
  --logs-workspace-id $LOG_ANALYTICS_WORKSPACE_CLIENT_ID \
  --logs-workspace-key $LOG_ANALYTICS_WORKSPACE_CLIENT_SECRET \
  --location "$LOCATION"
```

You should now have an ACA environment called `myenv` linked to a log analytics workspace called `la-aca` in location `northeurope`.

## Create a Cosmos DB collection

Create the Cosmos DB instance:

```
uniqueId=$RANDOM
az cosmosdb create \
  --name dapr-cosmosdb-$uniqueId \
  --resource-group rg-aca \
  --locations regionName='northeurope' \
  --default-consistency-level Strong
```

Create the database:

```
az cosmosdb sql database create \
  -a dapr-cosmosdb-$uniqueId \
  -g rg-aca \
  -n dapr-db
```

Create the collection:

```
az cosmosdb sql container create \
  -a dapr-cosmosdb-$uniqueId \
  -g rg-aca \
  -d dapr-db \
  -n statestore \
  -p '/partitionKey' \
  --throughput 400
```

## Create front container app

Run the following command:

```
az containerapp create --name front --resource-group rg-aca \
--environment myenv --image ghcr.io/gbaeke/super:1.0.5 \
--min-replicas 0 --max-replicas 5 --enable-dapr \
--dapr-app-id front --target-port 8080 --ingress external
```

Currently, --max-replicas cannot be more than 10.

## Create back container app

Run the following command:

```
az containerapp create --name back --resource-group rg-aca \
--environment myenv --image ghcr.io/gbaeke/super:1.0.5 \
--min-replicas 1 --max-replicas 5 --enable-dapr \
--dapr-app-port 8080 --dapr-app-id back \
--dapr-components ./cosmos-component.yaml \
--target-port 8080 --ingress internal \
--secrets cosmoskey='YOUR COSMOS KEY' \
-v STATESTORE=cosmos
```

cosmos-component.yaml should be:

```
- name: cosmosdb
  type: state.azure.cosmosdb
  version: v1
  metadata:
    - name: url
      value: "https://dapr-cosmosdb-21357.documents.azure.com:443/"
    - name: masterkey
      secretRef: cosmoskey
    - name: database
      value: dapr-db
    - name: collection
      value: statestore
```

## Curl command

The following curl command will hit the /call endpoint of the front container app. In turn, the front container app will call the /savestate endpoint of the back container app and save the state to the Cosmos DB collection.

```bash
curl -X POST \
  -d '{"appId": "back", "method": "savestate", "httpMethod": "POST", "payload": "{\"key\":\"yoohoo10\",\"data\":\"123\"}"}' \
  https://URL_TO_YOUR_FRONT_CONTAINER_APP/call
```
When Dapr tries to save "123" as the value, it will Base64 encode it. That does not happen when the value contains valid JSON.

To send valid JSON, try the horrible command below 😉:

```bash
curl -X POST \
    -d '{"appId": "back", "method": "savestate", "httpMethod": "POST", "payload": "{\"key\":\"yoohoo10\",\"data\": \"{\\\"name\\\": \\\"geert\\\"}\"  }"}'  http://URL_TO_YOUR_FRONT_CONTAINER_APP/call
```

In Cosmos DB, the value will be shown as below:

```json
{
    "id": "back||yoohoo10",
    "value": {
        "name": "geert"
    },
    "isBinary": false,
    "partitionKey": "back||yoohoo10",
    ....
}
```
