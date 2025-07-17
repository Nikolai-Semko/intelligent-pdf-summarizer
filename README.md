# Intelligent PDF Summarizer - Lab 2

**CST8917 - Serverless Applications Lab 2**  
*Build an Intelligent PDF Summarizer using Azure Durable Functions*

> **Lab Assignment:** Build an Intelligent PDF Summarizer using Azure Durable Functions and Cognitive Services, closely modeled after the Azure-Samples implementation.

## 🎥 **Demo Video**

**🔗 [Watch the 5-minute Demo on YouTube](https://www.youtube.com/watch?v=WH1ePpapRg8)**


[![Azure Functions](https://img.shields.io/badge/Azure-Functions-blue?logo=microsoft-azure)](https://azure.microsoft.com/en-us/services/functions/)
[![Python](https://img.shields.io/badge/Python-3.9+-blue?logo=python)](https://www.python.org/)
[![Azure OpenAI](https://img.shields.io/badge/Azure-OpenAI-green?logo=openai)](https://azure.microsoft.com/en-us/products/cognitive-services/openai-service/)

## 📋 Lab 2 Requirements Fulfillment

This project fulfills all Lab 2 requirements:

✅ **Develop solution using Azure Durable Functions** - Complete serverless workflow implemented  
✅ **Reuse Azure-Samples patterns** - Architecture closely follows Microsoft's best practices  
✅ **GitHub repository with clear README** - Comprehensive documentation provided  
✅ **5-minute demo video** - Complete walkthrough with code explanation  
✅ **Video link in README** - Demo video embedded above  

## 📋 Project Overview

This project demonstrates an intelligent PDF summarization system built using **Azure Durable Functions**, **Azure Document Intelligence**, and **Azure OpenAI Services**. The application automatically processes PDF documents uploaded to Azure Blob Storage, extracts text content, generates AI-powered summaries, and saves the results for easy access.

**Based on:** [Azure-Samples/Intelligent-PDF-Summarizer](https://github.com/Azure-Samples/Intelligent-PDF-Summarizer) with custom improvements for production reliability.

### 🎯 Key Features

- **Automatic PDF Processing**: Triggered when PDFs are uploaded to Blob Storage
- **Durable Workflow Orchestration**: Ensures reliable processing with retry logic
- **Text Extraction**: Uses Azure Document Intelligence (Form Recognizer) for accurate text extraction
- **AI-Powered Summarization**: Leverages Azure OpenAI GPT-4o-mini for intelligent content summarization
- **Scalable Architecture**: Built on Azure serverless technologies for automatic scaling
- **Error Handling**: Comprehensive error handling with retry mechanisms

## 🏗️ Architecture

The solution follows a serverless architecture pattern using Azure Durable Functions to orchestrate the workflow:

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Blob Storage  │    │ Durable Function │    │  Azure OpenAI   │
│   (Input PDFs)  │────┤   Orchestrator   │────┤   (GPT-4o-mini) │
└─────────────────┘    │                  │    └─────────────────┘
                       │  ┌─────────────┐ │
                       │  │ Blob Trigger│ │    ┌─────────────────┐
                       │  │ Function    │ │    │ Document Intel. │
                       │  └─────────────┘ │────┤ (Text Extract.) │
                       │                  │    └─────────────────┘
                       │  ┌─────────────┐ │
                       │  │   Output    │ │    ┌─────────────────┐
                       │  │ Generation  │ │────┤  Blob Storage   │
                       │  └─────────────┘ │    │ (Output Files)  │
                       └──────────────────┘    └─────────────────┘
```

## 🛠️ Technology Stack

- **Azure Durable Functions** - Workflow orchestration
- **Azure Blob Storage** - File storage (input/output)
- **Azure Document Intelligence** - PDF text extraction
- **Azure OpenAI Service** - GPT-4o-mini for summarization
- **Python 3.9+** - Runtime environment
- **Azure Functions Core Tools** - Local development

## 📁 Project Structure

```
intelligent-pdf-summarizer/
├── function_app.py              # Main application with all functions
├── requirements.txt             # Python dependencies
├── host.json                   # Function app configuration
├── local.settings.json         # Local development settings
├── local.settings.template.json # Template for settings
├── deploy.sh                   # Deployment automation script
├── main.bicep                  # Infrastructure as Code (Bicep)
├── main.parameters.json        # Bicep parameters
└── README.md                   # This file
```

## 🚀 Key Functions

### 1. Blob Trigger Function
- **Trigger**: New PDF uploaded to `input` container
- **Action**: Starts the durable orchestration workflow
- **Input**: PDF file from Blob Storage

### 2. Orchestrator Function (`process_document`)
- **Purpose**: Coordinates the entire workflow
- **Steps**:
  1. Extract text from PDF using Document Intelligence
  2. Generate summary using Azure OpenAI
  3. Save summary to output container
- **Features**: Retry logic, error handling, state management

### 3. Text Extraction Activity (`analyze_pdf`)
- **Service**: Azure Document Intelligence (Form Recognizer)
- **Input**: PDF binary data
- **Output**: Extracted text content
- **Features**: Handles multi-page documents, preserves formatting

### 4. Summarization Activity (`summarize_text`)
- **Service**: Azure OpenAI GPT-4o-mini
- **Method**: Direct HTTP API calls (bypasses Azure Functions OpenAI Extension)
- **Input**: Extracted text content
- **Output**: AI-generated summary
- **Features**: Token optimization, error handling, configurable prompts

### 5. Output Generation Activity (`write_doc`)
- **Purpose**: Save summary to Blob Storage
- **Output**: Timestamped summary files in `output` container
- **Format**: `{original_name}_summary_{timestamp}.txt`

## ⚙️ Configuration

### Required Environment Variables

```json
{
  "AZURE_OPENAI_ENDPOINT": "https://your-openai-resource.openai.azure.com/",
  "AZURE_OPENAI_KEY": "your-openai-api-key",
  "CHAT_MODEL_DEPLOYMENT_NAME": "chat",
  "COGNITIVE_SERVICES_ENDPOINT": "https://your-doc-intel-resource.cognitiveservices.azure.com/",
  "BLOB_STORAGE_ENDPOINT": "your-storage-connection-string"
}
```

### Azure Resources Required

1. **Function App** (Python 3.9+, Consumption Plan)
2. **Storage Account** with containers: `input`, `output`
3. **Document Intelligence Service** (S0 tier)
4. **Azure OpenAI Service** with `gpt-4o-mini` deployment

## 🔧 Deployment

### Option 1: Automated Deployment
```bash
./deploy.sh
```

### Option 2: Manual Deployment
```bash
# Deploy infrastructure
az deployment group create --resource-group rg-pdf-summarizer --template-file main.bicep

# Deploy function code
func azure functionapp publish your-function-app-name --python
```

## 🧪 Testing

### Upload a PDF for Processing
```bash
az storage blob upload \
  --account-name your-storage-account \
  --container-name input \
  --name test.pdf \
  --file path/to/your/file.pdf \
  --auth-mode login
```

### Monitor Processing
```bash
az webapp log tail --name your-function-app --resource-group your-rg
```

### Check Results
```bash
az storage blob list \
  --account-name your-storage-account \
  --container-name output \
  --auth-mode login
```

## 🔧 Key Implementation Details

### Solved Issues

1. **Azure OpenAI Integration**: 
   - **Problem**: Azure Functions OpenAI Extension had deployment detection issues
   - **Solution**: Implemented direct HTTP API calls to Azure OpenAI
   - **Benefit**: More reliable, better error handling, easier debugging

2. **Endpoint Configuration**:
   - **Problem**: Mixed Cognitive Services and OpenAI endpoints
   - **Solution**: Properly configured separate endpoints for each service
   - **Result**: Clean separation of concerns

3. **Error Handling**:
   - **Implementation**: Comprehensive try-catch blocks with detailed logging
   - **Features**: Graceful degradation, meaningful error messages

### Custom Improvements Over Azure-Samples

- **Direct OpenAI API Integration**: Bypassed Azure Functions OpenAI Extension for better reliability
- **Enhanced Error Handling**: Comprehensive logging and graceful error recovery
- **Production-Ready Configuration**: Proper endpoint separation and environment variable management
- **Improved Monitoring**: Detailed logging at each workflow step
- **Token Optimization**: Smart text truncation to optimize API costs

### Performance Optimizations

- **Text Limiting**: Truncate input to 4000 characters to optimize token usage
- **Timeout Configuration**: 60-second timeout for OpenAI API calls
- **Retry Logic**: Built-in Durable Functions retry mechanisms

## 📊 Monitoring & Logging

The application provides comprehensive logging at each step:

```
[Information] Processing document: filename.pdf
[Information] Processing text of length: 3318
[Information] Using endpoint: https://your-resource.openai.azure.com/
[Information] API response status: 200
[Information] Successfully generated summary: 245 characters
[Information] Successfully processed filename.pdf, output saved as filename_summary_20250712_123456.txt
```


## 🔒 Security Features

- **Managed Identity**: Uses Azure Managed Identity for service authentication
- **Key Vault Integration**: Secure storage of API keys and connection strings
- **Network Security**: Private endpoints for enhanced security
- **Access Control**: Role-based access control (RBAC) for all resources

## 📈 Scalability

- **Automatic Scaling**: Function App scales based on demand
- **Consumption Plan**: Pay-per-execution model
- **Durable Functions**: Handle high-throughput scenarios efficiently
- **Storage Partitioning**: Efficient file organization for large volumes
