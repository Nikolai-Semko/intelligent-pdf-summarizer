import logging
import os
from azure.storage.blob import BlobServiceClient
import azure.functions as func
import azure.durable_functions as df
from azure.identity import DefaultAzureCredential
from azure.ai.formrecognizer import DocumentAnalysisClient
import json
import time
from datetime import datetime

# Initialize the Durable Functions app
app = df.DFApp(http_auth_level=func.AuthLevel.ANONYMOUS)

# Initialize blob service client
blob_service_client = BlobServiceClient.from_connection_string(os.environ.get("BLOB_STORAGE_ENDPOINT"))

@app.blob_trigger(arg_name="myblob", path="input", connection="BLOB_STORAGE_ENDPOINT")
@app.durable_client_input(client_name="client")
async def blob_trigger(myblob: func.InputStream, client):
    """
    Blob trigger function that starts the durable orchestration when a PDF is uploaded
    """
    logging.info(f"Python blob trigger function processed blob "
                f"Name: {myblob.name} "
                f"Blob Size: {myblob.length} bytes")

    # Extract blob name from the full path
    blob_name = myblob.name.split("/")[1]
    
    # Start the durable orchestration
    instance_id = await client.start_new("process_document", client_input=blob_name)
    logging.info(f"Started orchestration with ID = {instance_id}")

@app.orchestration_trigger(context_name="context")
def process_document(context: df.DurableOrchestrationContext):
    """
    Orchestrator function that coordinates the PDF processing workflow
    """
    blob_name = context.get_input()
    logging.info(f"Processing document: {blob_name}")

    # Configure retry options for resilience
    first_retry_interval_in_milliseconds = 5000  # 5 seconds
    max_number_of_attempts = 3
    retry_options = df.RetryOptions(first_retry_interval_in_milliseconds, max_number_of_attempts)

    try:
        # Step 1: Download PDF from Blob Storage and extract text using Document Intelligence
        extracted_text = yield context.call_activity_with_retry("analyze_pdf", retry_options, blob_name)
        logging.info(f"Text extraction completed for {blob_name}")
        
        # Step 2: Send extracted text to Azure OpenAI for summarization
        summary_result = yield context.call_activity_with_retry("summarize_text", retry_options, extracted_text)
        logging.info(f"Text summarization completed for {blob_name}")
        
        # Step 3: Save the summary to a new file and upload to output container
        output_file = yield context.call_activity_with_retry("write_doc", retry_options, {
            "blob_name": blob_name, 
            "summary": summary_result
        })
        
        logging.info(f"Successfully processed {blob_name}, output saved as {output_file}")
        return output_file
        
    except Exception as e:
        logging.error(f"Error processing document {blob_name}: {str(e)}")
        return f"Error: {str(e)}"

@app.activity_trigger(input_name='blob_name')
def analyze_pdf(blob_name: str):
    """
    Activity function that extracts text from PDF using Azure Document Intelligence
    """
    logging.info(f"Starting text extraction for {blob_name}")
    
    try:
        # Download the blob from storage
        container_client = blob_service_client.get_container_client("input")
        blob_client = container_client.get_blob_client(blob_name)
        blob_data = blob_client.download_blob().read()
        
        # Initialize Document Intelligence client
        endpoint = os.environ["COGNITIVE_SERVICES_ENDPOINT"]
        credential = DefaultAzureCredential()
        document_analysis_client = DocumentAnalysisClient(endpoint, credential)
        
        # Analyze the document using prebuilt-layout model
        poller = document_analysis_client.begin_analyze_document(
            "prebuilt-layout", 
            document=blob_data, 
            locale="en-US"
        )
        result = poller.result()
        
        # Extract text from all pages
        extracted_text = ""
        for page in result.pages:
            for line in page.lines:
                extracted_text += line.content + "\n"
        
        logging.info(f"Successfully extracted {len(extracted_text)} characters from {blob_name}")
        return extracted_text
        
    except Exception as e:
        logging.error(f"Error analyzing PDF {blob_name}: {str(e)}")
        raise

@app.activity_trigger(input_name='text_content')
def summarize_text(text_content: str):
    """
    Activity function that generates a summary using direct Azure OpenAI API calls
    """
    import requests
    import json
    
    logging.info("Starting text summarization with direct API call")
    
    try:
        # Получить настройки из environment variables
        azure_openai_endpoint = os.environ.get("AZURE_OPENAI_ENDPOINT")
        azure_openai_key = os.environ.get("AZURE_OPENAI_KEY") 
        deployment_name = os.environ.get("CHAT_MODEL_DEPLOYMENT_NAME", "chat")
        
        if not azure_openai_endpoint or not azure_openai_key:
            raise Exception("Azure OpenAI settings not found in environment variables")
        
        # Убедиться что endpoint заканчивается на /
        if not azure_openai_endpoint.endswith('/'):
            azure_openai_endpoint += '/'
        
        # Ограничить длину текста для экономии токенов
        max_length = 4000
        if len(text_content) > max_length:
            text_content = text_content[:max_length] + "..."
            
        logging.info(f"Processing text of length: {len(text_content)}")
        logging.info(f"Using endpoint: {azure_openai_endpoint}")
        logging.info(f"Using deployment: {deployment_name}")
        
        # Построить URL для API
        api_url = f"{azure_openai_endpoint}openai/deployments/{deployment_name}/chat/completions?api-version=2024-02-15-preview"
        
        headers = {
            "Content-Type": "application/json",
            "api-key": azure_openai_key
        }
        
        data = {
            "messages": [
                {
                    "role": "system",
                    "content": "You are a helpful assistant that provides concise and informative summaries of documents."
                },
                {
                    "role": "user",
                    "content": f"Please provide a concise summary of the following text, highlighting the key points and main ideas:\n\n{text_content}"
                }
            ],
            "max_tokens": 500,
            "temperature": 0.7
        }
        
        logging.info(f"Making API request to: {api_url}")
        
        response = requests.post(
            api_url,
            headers=headers,
            json=data,
            timeout=60
        )
        
        logging.info(f"API response status: {response.status_code}")
        
        if response.status_code != 200:
            logging.error(f"API Error: {response.status_code} - {response.text}")
            raise Exception(f"OpenAI API error: {response.status_code} - {response.text}")
        
        result = response.json()
        logging.info("API response received successfully")
        
        if 'choices' not in result or len(result['choices']) == 0:
            raise Exception("No choices in OpenAI response")
        
        summary = result['choices'][0]['message']['content']
        
        logging.info(f"Successfully generated summary: {len(summary)} characters")
        
        return {
            "content": summary,
            "usage": result.get('usage', {}),
            "model": result.get('model', 'unknown')
        }
        
    except Exception as e:
        logging.error(f"Error in summarize_text: {str(e)}")
        # В случае ошибки возвращаем базовое резюме
        return {
            "content": f"Summary generation failed: {str(e)}. Original text length: {len(text_content)} characters.",
            "error": str(e)
        }

@app.activity_trigger(input_name='input_data')
def write_doc(input_data: dict):
    """
    Activity function that saves the summary to blob storage
    """
    blob_name = input_data['blob_name']
    summary_data = input_data['summary']
    
    logging.info(f"Saving summary for {blob_name}")
    
    try:
        # Create output filename with timestamp
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        base_name = blob_name.rsplit('.', 1)[0]  # Remove file extension
        output_filename = f"{base_name}_summary_{timestamp}.txt"
        
        # Get the summary content
        summary_content = summary_data.get('content', 'No summary available')
        
        # Upload to output container
        container_client = blob_service_client.get_container_client("output")
        container_client.upload_blob(
            name=output_filename, 
            data=summary_content, 
            overwrite=True
        )
        
        logging.info(f"Successfully saved summary to {output_filename}")
        return output_filename
        
    except Exception as e:
        logging.error(f"Error writing document {blob_name}: {str(e)}")
        raise

# Health check endpoint for monitoring
@app.function_name("health")
@app.route(route="health", methods=["GET"])
def health_check(req: func.HttpRequest) -> func.HttpResponse:
    """
    Simple health check endpoint
    """
    try:
        health_status = {
            "status": "healthy",
            "timestamp": datetime.utcnow().isoformat(),
            "version": "1.0.0"
        }
        
        return func.HttpResponse(
            json.dumps(health_status),
            status_code=200,
            mimetype="application/json"
        )
    except Exception as e:
        error_response = {
            "status": "unhealthy",
            "error": str(e),
            "timestamp": datetime.utcnow().isoformat()
        }
        
        return func.HttpResponse(
            json.dumps(error_response),
            status_code=503,
            mimetype="application/json"
        )

# Optional: Manual trigger endpoint for testing
@app.function_name("manual_trigger")
@app.route(route="process/{blob_name}", methods=["POST"])
@app.durable_client_input(client_name="client")
async def manual_trigger(req: func.HttpRequest, client) -> func.HttpResponse:
    """
    Manual trigger endpoint for testing without uploading files
    """
    blob_name = req.route_params.get('blob_name')
    
    if not blob_name:
        return func.HttpResponse(
            "Please provide a blob name in the URL",
            status_code=400
        )
    
    try:
        # Start the orchestration
        instance_id = await client.start_new("process_document", client_input=blob_name)
        
        response_data = {
            "instanceId": instance_id,
            "statusQueryGetUri": f"{req.url.replace(req.path_info, '')}/api/orchestrators/process_document/{instance_id}",
            "message": f"Started processing {blob_name}"
        }
        
        return func.HttpResponse(
            json.dumps(response_data),
            status_code=202,
            mimetype="application/json"
        )
        
    except Exception as e:
        return func.HttpResponse(
            f"Error starting orchestration: {str(e)}",
            status_code=500
        )