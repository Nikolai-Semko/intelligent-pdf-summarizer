# Fixed deployment script that avoids VM quota issues
# This uses Consumption plan (serverless) instead of Premium plan

param(
    [string]$ResourceGroup = "rg-pdf-lab2",
    [string]$Location = "eastus"
)

Write-Host "🔧 Fixed PDF Summarizer Deployment" -ForegroundColor Blue
Write-Host "Using Consumption plan to avoid VM quota issues"
Write-Host "==============================================="

# Generate unique names
$randomSuffix = Get-Random -Maximum 9999
$storageAccount = "stpdflab$randomSuffix"
$functionApp = "func-pdf-lab-$randomSuffix"
$openAIService = "openai-pdf-lab-$randomSuffix" 
$docIntelService = "docint-pdf-lab-$randomSuffix"

Write-Host "📋 Configuration:" -ForegroundColor Yellow
Write-Host "  Resource Group: $ResourceGroup"
Write-Host "  Location: $Location"
Write-Host "  Function App: $functionApp (Consumption Plan)"
Write-Host ""

try {
    # Create Resource Group
    Write-Host "📦 Creating resource group..." -ForegroundColor Blue
    az group create --name $ResourceGroup --location $Location --output none
    Write-Host "✅ Resource group created" -ForegroundColor Green

    # Create Storage Account (required for Functions)
    Write-Host "💾 Creating storage account..." -ForegroundColor Blue
    az storage account create `
        --name $storageAccount `
        --resource-group $ResourceGroup `
        --location $Location `
        --sku Standard_LRS `
        --output none

    # Create containers
    $storageKey = az storage account keys list --resource-group $ResourceGroup --account-name $storageAccount --query '[0].value' -o tsv
    az storage container create --name input --account-name $storageAccount --account-key $storageKey --output none
    az storage container create --name output --account-name $storageAccount --account-key $storageKey --output none
    Write-Host "✅ Storage account created" -ForegroundColor Green

    # Create Document Intelligence
    Write-Host "📄 Creating Document Intelligence..." -ForegroundColor Blue
    az cognitiveservices account create `
        --name $docIntelService `
        --resource-group $ResourceGroup `
        --location $Location `
        --kind FormRecognizer `
        --sku S0 `
        --output none
    Write-Host "✅ Document Intelligence created" -ForegroundColor Green

    # Create OpenAI Service with updated model
    Write-Host "🧠 Creating OpenAI service..." -ForegroundColor Blue
    az cognitiveservices account create `
        --name $openAIService `
        --resource-group $ResourceGroup `
        --location $Location `
        --kind OpenAI `
        --sku S0 `
        --output none

    # Deploy UPDATED OpenAI model
    Write-Host "🚀 Deploying updated OpenAI model..." -ForegroundColor Blue
    try {
        az cognitiveservices account deployment create `
            --name $openAIService `
            --resource-group $ResourceGroup `
            --deployment-name chat `
            --model-name gpt-4o-mini `
            --model-version "2024-07-18" `
            --model-format OpenAI `
            --sku-capacity 10 `
            --sku-name "Standard" `
            --output none
        Write-Host "✅ OpenAI model deployed (gpt-4o-mini)" -ForegroundColor Green
    } catch {
        Write-Host "⚠️  Trying fallback model..." -ForegroundColor Yellow
        az cognitiveservices account deployment create `
            --name $openAIService `
            --resource-group $ResourceGroup `
            --deployment-name chat `
            --model-name gpt-35-turbo `
            --model-version "1106" `
            --model-format OpenAI `
            --sku-capacity 10 `
            --sku-name "Standard" `
            --output none
        Write-Host "✅ OpenAI model deployed (fallback)" -ForegroundColor Green
    }

    # Create Function App with CONSUMPTION plan (no VMs!)
    Write-Host "⚡ Creating Function App (Consumption plan)..." -ForegroundColor Blue
    az functionapp create `
        --resource-group $ResourceGroup `
        --consumption-plan-location $Location `
        --name $functionApp `
        --storage-account $storageAccount `
        --runtime python `
        --runtime-version 3.11 `
        --functions-version 4 `
        --os-type linux `
        --output none

    # Configure app settings
    Write-Host "⚙️  Configuring Function App..." -ForegroundColor Blue
    $storageConnection = az storage account show-connection-string --name $storageAccount --resource-group $ResourceGroup --query connectionString -o tsv
    $docIntelEndpoint = az cognitiveservices account show --name $docIntelService --resource-group $ResourceGroup --query properties.endpoint -o tsv
    $openAIEndpoint = az cognitiveservices account show --name $openAIService --resource-group $ResourceGroup --query properties.endpoint -o tsv
    $openAIKey = az cognitiveservices account keys list --name $openAIService --resource-group $ResourceGroup --query key1 -o tsv

    az functionapp config appsettings set `
        --name $functionApp `
        --resource-group $ResourceGroup `
        --settings `
            "BLOB_STORAGE_ENDPOINT=$storageConnection" `
            "COGNITIVE_SERVICES_ENDPOINT=$docIntelEndpoint" `
            "AZURE_OPENAI_ENDPOINT=$openAIEndpoint" `
            "AZURE_OPENAI_KEY=$openAIKey" `
            "CHAT_MODEL_DEPLOYMENT_NAME=chat" `
        --output none

    Write-Host "✅ Function App configured" -ForegroundColor Green

    # Deploy function code
    Write-Host "📤 Deploying function code..." -ForegroundColor Blue
    if (Get-Command func -ErrorAction SilentlyContinue) {
        func azure functionapp publish $functionApp --python
        Write-Host "✅ Code deployed successfully" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Deploy code manually: func azure functionapp publish $functionApp --python" -ForegroundColor Yellow
    }

    # Create local settings
    $localSettings = @{
        IsEncrypted = $false
        Values = @{
            AzureWebJobsStorage = $storageConnection
            AzureWebJobsFeatureFlags = "EnableWorkerIndexing" 
            FUNCTIONS_WORKER_RUNTIME = "python"
            BLOB_STORAGE_ENDPOINT = $storageConnection
            COGNITIVE_SERVICES_ENDPOINT = $docIntelEndpoint
            AZURE_OPENAI_ENDPOINT = $openAIEndpoint
            AZURE_OPENAI_KEY = $openAIKey
            CHAT_MODEL_DEPLOYMENT_NAME = "chat"
        }
    }
    
    $localSettings | ConvertTo-Json -Depth 3 | Out-File -FilePath "local.settings.json" -Encoding UTF8

    # Success!
    Write-Host ""
    Write-Host "🎉 SUCCESS! No VM quota issues!" -ForegroundColor Green
    Write-Host "=================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "📋 Your Resources:" -ForegroundColor Blue
    Write-Host "  Function App: https://$functionApp.azurewebsites.net"
    Write-Host "  Health Check: https://$functionApp.azurewebsites.net/api/health"
    Write-Host "  Resource Group: $ResourceGroup"
    Write-Host ""
    Write-Host "🧪 Test Your App:" -ForegroundColor Blue
    Write-Host "1. Go to Azure Portal → Storage Account '$storageAccount'"
    Write-Host "2. Upload a PDF to 'input' container"
    Write-Host "3. Check 'output' container for summary"
    Write-Host ""
    Write-Host "🔧 Local Development:" -ForegroundColor Blue
    Write-Host "  pip install -r requirements.txt"
    Write-Host "  func start"
    Write-Host ""
    Write-Host "All done! 🚀" -ForegroundColor Green

} catch {
    Write-Host "❌ Error: $($_.Exception.Message)" -ForegroundColor Red
}