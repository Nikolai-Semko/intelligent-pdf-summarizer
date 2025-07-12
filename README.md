# 🤖 Intelligent PDF Summarizer

A serverless solution that automatically summarizes PDF documents using Azure Durable Functions, Azure Document Intelligence, and Azure OpenAI.

## 🎥 Demo Video

[![Watch Demo](https://img.shields.io/badge/Watch%20Demo-FF0000?style=for-the-badge&logo=youtube&logoColor=white)](https://youtu.be/WH1ePpapRg8)


## 🏗️ Architecture

The solution uses the following Azure services:

1. **Azure Blob Storage** - Stores input PDFs and output summaries
2. **Azure Durable Functions** - Orchestrates the processing workflow
3. **Azure Document Intelligence** - Extracts text from PDFs
4. **Azure OpenAI** - Generates intelligent summaries

### Workflow

```
PDF Upload → Blob Trigger → Extract Text → Generate Summary → Save Result
```

## 📋 Prerequisites

- Azure subscription with access to:
  - Azure Functions
  - Azure Storage
  - Azure Document Intelligence (Form Recognizer)
  - Azure OpenAI Service
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Azure Developer CLI](https://aka.ms/azd)
- [Python 3.9+](https://www.python.org/downloads/)
- [Azure Functions Core Tools](https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local)

## 🚀 Quick Start

### 1. Clone and Setup

```bash
git clone https://github.com/yourusername/intelligent-pdf-summarizer.git
cd intelligent-pdf-summarizer
```

### 2. Deploy to Azure

```bash
# Initialize and deploy with Azure Developer CLI
azd init
azd up
```

**OR** use the deployment script:

```bash
# For Windows (PowerShell)
./deploy.ps1

# For Linux/Mac
chmod +x deploy.sh
./deploy.sh
```

### 3. Configure Local Development (Optional)

```bash
# Install dependencies
pip install -r requirements.txt

# Copy settings template
cp local.settings.template.json local.settings.json

# Edit local.settings.json with your Azure service endpoints and keys

# Start local development
func start
```

## 📖 Usage

### Upload PDFs

1. Navigate to your storage account in the Azure Portal
2. Open the **input** container
3. Upload PDF files
4. Check the **output** container for summaries

### Monitor Processing

- View function logs in Azure Portal
- Check Application Insights for detailed telemetry
- Use the health endpoint: `https://your-function-app.azurewebsites.net/api/health`

## ⚙️ Configuration

The application uses these environment variables:

| Variable | Description |
|----------|-------------|
| `BLOB_STORAGE_ENDPOINT` | Azure Storage connection string |
| `COGNITIVE_SERVICES_ENDPOINT` | Document Intelligence endpoint |
| `AZURE_OPENAI_ENDPOINT` | Azure OpenAI service endpoint |
| `AZURE_OPENAI_KEY` | Azure OpenAI API key |
| `CHAT_MODEL_DEPLOYMENT_NAME` | OpenAI model deployment name |

## 🧪 Testing

### Manual Testing

Test the function manually:

```bash
# Test with existing blob
curl -X POST "https://your-function-app.azurewebsites.net/api/process/your-document.pdf"
```

### Health Check

```bash
curl "https://your-function-app.azurewebsites.net/api/health"
```

## 📁 Project Structure

**Core Files (Required):**
```
├── function_app.py                 # Main application logic
├── host.json                       # Function host configuration  
├── requirements.txt                # Python dependencies
├── azure.yaml                     # Azure Developer CLI configuration
├── main.parameters.json           # Deployment parameters
└── README.md                      # Documentation
```

**Helper Files (Optional):**
```
├── deploy.sh                      # Simple deployment script
├── local.settings.template.json   # Local development template
├── .gitignore                     # Git ignore rules
└── infra/                         # Infrastructure as Code (Bicep templates)
```

**Minimum required:** Just the core files are enough to run the application!

## 🔧 Troubleshooting

### Common Issues

**Function not starting:**
- Check that all environment variables are set correctly
- Verify Azure service endpoints are accessible
- Check function app logs for specific errors

**PDF processing fails:**
- Ensure the PDF is less than 50MB
- Verify Document Intelligence service is deployed
- Check that the PDF is not password-protected

**No summary generated:**
- Verify Azure OpenAI service is deployed and accessible
- Check that the model deployment name is correct
- Ensure sufficient quota is available

### Debug Commands

```bash
# View function logs
az functionapp log tail --name YOUR_FUNCTION_APP --resource-group YOUR_RESOURCE_GROUP

# Check storage containers
az storage container list --account-name YOUR_STORAGE_ACCOUNT

# Test connectivity
curl -I https://YOUR_FUNCTION_APP.azurewebsites.net/api/health
```

## 📊 Performance

- **Processing Time**: 30-60 seconds per document
- **File Size Limit**: 50MB per PDF
- **Supported Formats**: PDF documents
- **Concurrency**: Scales automatically with demand

## 🔒 Security

- All secrets stored in Azure Key Vault
- HTTPS-only communication
- Managed identities for service authentication
- Private endpoints available for enhanced security

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📞 Support

For issues and questions:
- Check the troubleshooting section above
- Review Azure service documentation
- Open an issue in this repository

---

**Built with ❤️ using Azure Services**