# Azure Resources Setup Script for PDF Summarizer
# Run this script in PowerShell after logging into Azure CLI

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName = "rg-pdf-summarizer",
    
    [Parameter(Mandatory=$true)]
    [string]$Location = "eastus",
    
    [Parameter(Mandatory=$false)]
    [string]$UniquePrefix = "pdfsumm$(Get-Random -Maximum 9999)"
)

Write-Host "Starting Azure resources setup..." -ForegroundColor Green
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Cyan
Write-Host "Location: $Location" -ForegroundColor Cyan
Write-Host "Unique Prefix: $UniquePrefix" -ForegroundColor Cyan

# Variables
$storageAccountName = "${UniquePrefix}storage".ToLower() -replace '[^a-z0-9]', ''
$functionAppName = "${UniquePrefix}-func-app"
$appServicePlanName = "${UniquePrefix}-asp"
$appInsightsName = "${UniquePrefix}-insights"
$formRecognizerName = "${UniquePrefix}-formrecognizer"
$openAiName = "${UniquePrefix}-openai"

# Ensure the name is valid (3-24 characters)
if ($storageAccountName.Length -gt 24) {
    $storageAccountName = $storageAccountName.Substring(0, 24)
}

try {
    # 1. Create Resource Group
    Write-Host "`n1. Creating Resource Group..." -ForegroundColor Yellow
    az group create --name $ResourceGroupName --location $Location --output none
    Write-Host "   ✓ Resource Group created" -ForegroundColor Green

    # 2. Create Storage Account
    Write-Host "`n2. Creating Storage Account..." -ForegroundColor Yellow
    az storage account create `
        --name $storageAccountName `
        --resource-group $ResourceGroupName `
        --location $Location `
        --sku Standard_LRS `
        --kind StorageV2 `
        --output none
    Write-Host "   ✓ Storage Account created: $storageAccountName" -ForegroundColor Green

    # Get Storage Connection String
    $storageConnectionString = az storage account show-connection-string `
        --name $storageAccountName `
        --resource-group $ResourceGroupName `
        --query connectionString `
        --output tsv

    # 3. Create Blob Containers
    Write-Host "`n3. Creating Blob Containers..." -ForegroundColor Yellow
    az storage container create `
        --name "input" `
        --connection-string $storageConnectionString `
        --output none
    Write-Host "   ✓ Container 'input' created" -ForegroundColor Green
    
    az storage container create `
        --name "output" `
        --connection-string $storageConnectionString `
        --output none
    Write-Host "   ✓ Container 'output' created" -ForegroundColor Green

    # 4. Create Application Insights
    Write-Host "`n4. Creating Application Insights..." -ForegroundColor Yellow
    az monitor app-insights component create `
        --app $appInsightsName `
        --resource-group $ResourceGroupName `
        --location $Location `
        --output none
    Write-Host "   ✓ Application Insights created" -ForegroundColor Green

    # 5. Create Form Recognizer (Document Intelligence)
    Write-Host "`n5. Creating Form Recognizer..." -ForegroundColor Yellow
    az cognitiveservices account create `
        --name $formRecognizerName `
        --resource-group $ResourceGroupName `
        --kind FormRecognizer `
        --sku S0 `
        --location $Location `
        --yes `
        --output none
    Write-Host "   ✓ Form Recognizer created" -ForegroundColor Green

    # Get Form Recognizer endpoint
    $formRecognizerEndpoint = az cognitiveservices account show `
        --name $formRecognizerName `
        --resource-group $ResourceGroupName `
        --query properties.endpoint `
        --output tsv

    # 6. Create Azure OpenAI (if available in the region)
    Write-Host "`n6. Creating Azure OpenAI..." -ForegroundColor Yellow
    $openAiCreated = $false
    try {
        az cognitiveservices account create `
            --name $openAiName `
            --resource-group $ResourceGroupName `
            --kind OpenAI `
            --sku S0 `
            --location $Location `
            --yes `
            --output none 2>$null
        
        Write-Host "   ✓ Azure OpenAI created" -ForegroundColor Green
        $openAiCreated = $true
        
        # Deploy a model (gpt-35-turbo)
        Write-Host "   Deploying GPT-3.5 Turbo model..." -ForegroundColor Yellow
        az cognitiveservices account deployment create `
            --name $openAiName `
            --resource-group $ResourceGroupName `
            --deployment-name "gpt-35-turbo" `
            --model-name "gpt-35-turbo" `
            --model-version "0301" `
            --model-format OpenAI `
            --scale-type "Standard" `
            --output none 2>$null
        Write-Host "   ✓ Model deployed" -ForegroundColor Green
    }
    catch {
        Write-Host "   ⚠ Azure OpenAI not available in $Location or you don't have access" -ForegroundColor Red
        Write-Host "   You'll need to create it manually in a supported region" -ForegroundColor Yellow
    }

    # Get OpenAI endpoint and key (if created)
    if ($openAiCreated) {
        $openAiEndpoint = az cognitiveservices account show `
            --name $openAiName `
            --resource-group $ResourceGroupName `
            --query properties.endpoint `
            --output tsv

        $openAiKey = az cognitiveservices account keys list `
            --name $openAiName `
            --resource-group $ResourceGroupName `
            --query key1 `
            --output tsv
    }

    # 7. Create App Service Plan
    Write-Host "`n7. Creating App Service Plan..." -ForegroundColor Yellow
    az appservice plan create `
        --name $appServicePlanName `
        --resource-group $ResourceGroupName `
        --location $Location `
        --sku Y1 `
        --is-linux `
        --output none
    Write-Host "   ✓ App Service Plan created" -ForegroundColor Green

    # 8. Create Function App
    Write-Host "`n8. Creating Function App..." -ForegroundColor Yellow
    az functionapp create `
        --name $functionAppName `
        --resource-group $ResourceGroupName `
        --plan $appServicePlanName `
        --runtime python `
        --runtime-version 3.9 `
        --storage-account $storageAccountName `
        --app-insights $appInsightsName `
        --output none
    Write-Host "   ✓ Function App created" -ForegroundColor Green

    # 9. Configure Function App Settings
    Write-Host "`n9. Configuring Function App settings..." -ForegroundColor Yellow
    
    # Base settings
    $settings = @(
        "BLOB_STORAGE_ENDPOINT=$storageConnectionString",
        "COGNITIVE_SERVICES_ENDPOINT=$formRecognizerEndpoint",
        "AzureWebJobsFeatureFlags=EnableWorkerIndexing"
    )
    
    # Add OpenAI settings if available
    if ($openAiCreated) {
        $settings += @(
            "AZURE_OPENAI_ENDPOINT=$openAiEndpoint",
            "AZURE_OPENAI_KEY=$openAiKey",
            "CHAT_MODEL_DEPLOYMENT_NAME=gpt-35-turbo"
        )
    }
    
    az functionapp config appsettings set `
        --name $functionAppName `
        --resource-group $ResourceGroupName `
        --settings $settings `
        --output none
    Write-Host "   ✓ Function App configured" -ForegroundColor Green

    # Output summary
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "✓ Azure Resources Created Successfully!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "`nResource Summary:" -ForegroundColor Yellow
    Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor White
    Write-Host "  Storage Account: $storageAccountName" -ForegroundColor White
    Write-Host "  Function App: $functionAppName" -ForegroundColor White
    Write-Host "  Form Recognizer: $formRecognizerName" -ForegroundColor White
    if ($openAiCreated) {
        Write-Host "  Azure OpenAI: $openAiName" -ForegroundColor White
    }
    
    # Create local.settings.json
    Write-Host "`nCreating local.settings.json file..." -ForegroundColor Yellow
    $localSettings = @{
        IsEncrypted = $false
        Values = @{
            AzureWebJobsStorage = $storageConnectionString
            AzureWebJobsFeatureFlags = "EnableWorkerIndexing"
            FUNCTIONS_WORKER_RUNTIME = "python"
            BLOB_STORAGE_ENDPOINT = $storageConnectionString
            COGNITIVE_SERVICES_ENDPOINT = $formRecognizerEndpoint
        }
    }
    
    if ($openAiCreated) {
        $localSettings.Values.AZURE_OPENAI_ENDPOINT = $openAiEndpoint
        $localSettings.Values.AZURE_OPENAI_KEY = $openAiKey
        $localSettings.Values.CHAT_MODEL_DEPLOYMENT_NAME = "gpt-35-turbo"
    }
    
    $localSettings | ConvertTo-Json -Depth 3 | Out-File -FilePath "local.settings.json" -Encoding UTF8
    Write-Host "✓ local.settings.json created" -ForegroundColor Green
    
    Write-Host "`nNext Steps:" -ForegroundColor Yellow
    Write-Host "1. If Azure OpenAI wasn't created, create it manually in a supported region" -ForegroundColor White
    Write-Host "2. Deploy your function code using: func azure functionapp publish $functionAppName" -ForegroundColor White
    Write-Host "3. Or use VS Code Azure Functions extension for deployment" -ForegroundColor White
}
catch {
    Write-Host "`nError occurred: $_" -ForegroundColor Red
    Write-Host "Please check your Azure CLI login and permissions" -ForegroundColor Yellow
}
