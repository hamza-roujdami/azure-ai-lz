using '../foundry-connection.bicep'

// Example parameter file — duplicate and customize per business/project
param accountName = '<FOUNDRY_ACCOUNT>'
param projectName = '<FOUNDRY_PROJECT>'
param targetUrl = 'https://<APIM_NAME>.azure-api.net/<API_PATH>'
param apiKey = '' // pass at runtime: -p apiKey='<key>' (never commit secrets)
