#!/bin/bash

# Simple deployment script for Intelligent PDF Summarizer
# This script creates the basic Azure resources needed for the application

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🤖 Intelligent PDF Summarizer - Deployment Script${NC}"
echo "======================================================"

# Check if required tools are installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}❌ Azure CLI is not installed. Please install it first.${NC}"
    exit 1
fi

if ! command -v azd &> /dev/null; then
    echo -e "${YELLOW}⚠️  Azure Developer CLI not found. You can install it from https://aka.ms/azd${NC}"
    echo -e "${BLUE}💡 Continuing with Azure CLI deployment...${NC}"
fi

# Get deployment parameters
echo -e "${YELLOW}📝 Please provide the following information:${NC}"

read -p "Resource Group Name (default: rg-pdf-summarizer): " RESOURCE_GROUP
RESOURCE_GROUP=${RESOURCE_GROUP:-rg-pdf-summarizer}

read -p "Azure Region (default: eastus): " LOCATION
LOCATION=${LOCATION:-eastus}

read -p "Environment Name (default: dev): " ENVIRONMENT
ENVIRONMENT=${ENVIRONMENT:-dev}

# Generate unique names
RANDOM_SUFFIX=$(openssl rand -hex 3)
STORAGE_NAME="stpdf${RANDOM_SUFFIX}"
FUNCTION_NAME="func-pdf-${RANDOM_SUFFIX}"
OPENAI_NAME="openai-pdf-${RANDOM_SUFFIX}"
DOCINT_NAME="docint-pdf-${RANDOM_SUFFIX}"

echo -e "${BLUE}📋 Deployment Configuration:${NC}"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Location: $LOCATION"
echo "  Environment: $ENVIRONMENT"
echo "  Storage Account: $STORAGE_NAME"
echo "  Function App: $FUNCTION_NAME"
echo "  OpenAI Service: $OPENAI_NAME"
echo "  Document Intelligence: $DOCINT_NAME"
echo ""

read -p "Continue with deployment? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Deployment cancelled.${NC}"
    exit 1
fi

# Login to Azure
echo -e "${BLUE}🔐 Checking Azure login...${NC}"
if ! az account show &>/dev/null; then
    echo "Please login to Azure:"
    az login
fi

# Create Resource Group
echo -e "${BLUE}📦 Creating resource group...${NC}"
az group create --name $RESOURCE_GROUP --location $LOCATION --output none
echo -e "${GREEN}✅ Resource group created${NC}"

# Create Storage Account
echo -e "${BLUE}💾 Creating storage account...${NC}"
az storage account create \
    --name $STORAGE_NAME \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --sku Standard_LRS \
    --kind StorageV2 \
    --output none

# Create storage containers
STORAGE_KEY=$(az storage account keys list --resource-group $RESOURCE_GROUP --account-name $STORAGE_NAME --query '[0].value' -o tsv)
az storage container create --name input --account-name $STORAGE_NAME --account-key $STORAGE_KEY --output none
az storage container create --name output --account-name $STORAGE_NAME --account-key $STORAGE_KEY --output none
echo -e "${GREEN}✅ Storage account and containers created${NC}"

# Create Document Intelligence Service
echo -e "${BLUE}📄 Creating Document Intelligence service...${NC}"
az cognitiveservices account create \
    --name $DOCINT_NAME \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --kind FormRecognizer \
    --sku S0 \
    --output none
echo -e "${GREEN}✅ Document Intelligence service created${NC}"

# Create OpenAI Service
echo -e "${BLUE}🧠 Creating OpenAI service...${NC}"
az cognitiveservices account create \
    --name $OPENAI_NAME \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --kind OpenAI \
    --sku S0 \
    --output none

# Deploy OpenAI model
echo -e "${BLUE}🚀 Deploying OpenAI model...${NC}"
az cognitiveservices account deployment create \
    --name $OPENAI_NAME \
    --resource-group $RESOURCE_GROUP \
    --deployment-name chat \
    --model-name gpt-35-turbo \
    --model-version "0613" \
    --model-format OpenAI \
    --sku-capacity 10 \
    --sku-name "Standard" \
    --output none
echo -e "${GREEN}✅ OpenAI service and model deployed${NC}"

# Create Function App
echo -e "${BLUE}⚡ Creating Function App...${NC}"

# Create App Service Plan
az functionapp plan create \
    --resource-group $RESOURCE_GROUP \
    --name "plan-$FUNCTION_NAME" \
    --location $LOCATION \
    --number-of-workers 1 \
    --sku EP1 \
    --is-linux \
    --output none

# Create Function App
STORAGE_CONNECTION=$(az storage account show-connection-string --name $STORAGE_NAME --resource-group $RESOURCE_GROUP --query connectionString -o tsv)

az functionapp create \
    --resource-group $RESOURCE_GROUP \
    --plan "plan-$FUNCTION_NAME" \
    --name $FUNCTION_NAME \
    --storage-account $STORAGE_NAME \
    --runtime python \
    --runtime-version 3.11 \
    --functions-version 4 \
    --output none

# Configure Function App settings
echo -e "${BLUE}⚙️  Configuring Function App...${NC}"

DOCINT_ENDPOINT=$(az cognitiveservices account show --name $DOCINT_NAME --resource-group $RESOURCE_GROUP --query properties.endpoint -o tsv)
OPENAI_ENDPOINT=$(az cognitiveservices account show --name $OPENAI_NAME --resource-group $RESOURCE_GROUP --query properties.endpoint -o tsv)
OPENAI_KEY=$(az cognitiveservices account keys list --name $OPENAI_NAME --resource-group $RESOURCE_GROUP --query key1 -o tsv)

az functionapp config appsettings set \
    --name $FUNCTION_NAME \
    --resource-group $RESOURCE_GROUP \
    --settings \
        "BLOB_STORAGE_ENDPOINT=$STORAGE_CONNECTION" \
        "COGNITIVE_SERVICES_ENDPOINT=$DOCINT_ENDPOINT" \
        "AZURE_OPENAI_ENDPOINT=$OPENAI_ENDPOINT" \
        "AZURE_OPENAI_KEY=$OPENAI_KEY" \
        "CHAT_MODEL_DEPLOYMENT_NAME=chat" \
    --output none

echo -e "${GREEN}✅ Function App created and configured${NC}"

# Deploy function code
echo -e "${BLUE}📤 Deploying function code...${NC}"
if command -v func &> /dev/null; then
    func azure functionapp publish $FUNCTION_NAME --python
    echo -e "${GREEN}✅ Function code deployed${NC}"
else
    echo -e "${YELLOW}⚠️  Azure Functions Core Tools not found. Please deploy code manually:${NC}"
    echo "   func azure functionapp publish $FUNCTION_NAME --python"
fi

# Create local.settings.json for development
echo -e "${BLUE}📝 Creating local.settings.json...${NC}"
cat > local.settings.json << EOF
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "$STORAGE_CONNECTION",
    "AzureWebJobsFeatureFlags": "EnableWorkerIndexing",
    "FUNCTIONS_WORKER_RUNTIME": "python",
    "BLOB_STORAGE_ENDPOINT": "$STORAGE_CONNECTION",
    "COGNITIVE_SERVICES_ENDPOINT": "$DOCINT_ENDPOINT",
    "AZURE_OPENAI_ENDPOINT": "$OPENAI_ENDPOINT",
    "AZURE_OPENAI_KEY": "$OPENAI_KEY",
    "CHAT_MODEL_DEPLOYMENT_NAME": "chat"
  }
}
EOF

# Summary
echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
echo ""
echo -e "${BLUE}📋 Resource Summary:${NC}"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Function App: https://$FUNCTION_NAME.azurewebsites.net"
echo "  Storage Account: $STORAGE_NAME"
echo "  OpenAI Service: $OPENAI_NAME"
echo "  Document Intelligence: $DOCINT_NAME"
echo ""
echo -e "${BLUE}🚀 Next Steps:${NC}"
echo "1. Upload PDF files to the 'input' container"
echo "2. Check the 'output' container for summaries"
echo "3. Monitor logs: az functionapp log tail --name $FUNCTION_NAME --resource-group $RESOURCE_GROUP"
echo ""
echo -e "${BLUE}🔧 Local Development:${NC}"
echo "1. Run: pip install -r requirements.txt"
echo "2. Run: func start"
echo ""
echo -e "${GREEN}Happy coding! 🚀${NC}"
