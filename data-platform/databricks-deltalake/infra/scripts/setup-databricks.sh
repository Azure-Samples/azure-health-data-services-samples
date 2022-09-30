#/bin/bash -e

## Install databricks CLI and refresh environment
pip install databricks-cli
eval "$(exec /usr/bin/env -i "${SHELL}" -l -c "export")"

## Setup auth
echo "Geting access tokens for accessing resources..."

databricksResourceToken=$(az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --output json | jq -r .accessToken)
azureManagementToken=$(az account get-access-token --resource https://management.core.windows.net/ --output json | jq -r .accessToken)

token_response=$(
    curl -sS -X POST \
        -H "Authorization: Bearer $databricksResourceToken" \
        -H "Content-Type: application/json" \
        -H "X-Databricks-Azure-SP-Management-Token:$azureManagementToken" \
        -H "X-Databricks-Azure-Workspace-Resource-Id:$ADB_WORKSPACE_ID" \
        --data '{"lifetime_seconds": 180, "comment": "Deployment Token"}' \
        "https://${ADB_WORKSPACE_URL}/api/2.0/token/create"
)

export DATABRICKS_TOKEN=`echo $token_response | jq -r '.token_value'`
export DATABRICKS_HOST="https://${ADB_WORKSPACE_URL}"

## Setup secret scope
EXISTING_SCOPE_COUNT=$(databricks secrets list-scopes | grep -c $SECRET_SCOPE_NAME)
if [ "$EXISTING_SCOPE_COUNT" -eq "0" ]; then
    databricks secrets create-scope --scope $SECRET_SCOPE_NAME
    printf "\nSecret scope $SECRET_SCOPE_NAME created."
else
    printf "\nSecret scope $SECRET_SCOPE_NAME already exists."
fi

## Setup secrets
databricks secrets put --scope $SECRET_SCOPE_NAME --key "adls-storage-account-name" --string-value "$STORAGE_ACCOUNT_NAME" >> $AZ_SCRIPTS_OUTPUT_PATH
printf "\n Secret adls-storage-account-name created"
databricks secrets put --scope $SECRET_SCOPE_NAME --key "adls-storage-container-name" --string-value "$STORAGE_CONTAINER_NAME" >> $AZ_SCRIPTS_OUTPUT_PATH
printf "\n Secret adls-storage-container-name created"

STORAGE_ACCOUNT_KEY=$(az storage account keys list --resource-group "$RESOURCE_GROUP_NAME" --account-name "$STORAGE_ACCOUNT_NAME" --query "[0].value" --output tsv)
databricks secrets put --scope $SECRET_SCOPE_NAME --key "adls-access-account-key" --string-value "$STORAGE_ACCOUNT_KEY" >> $AZ_SCRIPTS_OUTPUT_PATH
printf "\n Secret adls-access-client-id created"

printf "\nStaging notebooks..."
mkdir -p notebooks && cd notebooks
curl -L \
    -O "https://mikaeldevcdn.blob.core.windows.net/public/FHIR-To-Databricks-Delta.py"
cd -

printf "\nUploading notebooks..."
for notebook in notebooks/*.py; do
    filename=$(basename $notebook)
    databricks workspace import --language "PYTHON" --format "SOURCE" --overwrite $notebook "/Shared/${filename}" >> $AZ_SCRIPTS_OUTPUT_PATH
    printf "\n Uploaded notebook $notebook"
done


printf "\Setting up pipeline..."

EXISTING_PIPELINE_COUNT=$(databricks pipelines list | grep -c "Databricks Delta Lake Sample")
if [ "$EXISTING_PIPELINE_COUNT" -eq "0" ]; then
    echo $PIPELINE_TEMPLATE > pipeline.json
    databricks pipelines create --settings pipeline.json
else
    PIPELINE_ID=$(databricks pipelines list | jq -r '.[] | select( .name | contains("Databricks Delta Lake Sample")) | .pipeline_id')
    echo $PIPELINE_TEMPLATE | jq --arg pipeline_id $PIPELINE_ID '{id: $pipeline_id} + .' > pipeline.json
    databricks pipelines edit --settings pipeline.json
fi