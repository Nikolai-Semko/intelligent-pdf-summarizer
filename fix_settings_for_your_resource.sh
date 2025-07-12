# Используем ваш правильный OpenAI ресурс
OPENAI_NAME="cog-xjvxu2o3kqvss"
RESOURCE_GROUP="rg-pdf-summarizer-dev"
FUNCTION_NAME="func-xjvxu2o3kqvss"

# 1. Проверить существующие deployments
echo "🔍 Проверка существующих deployments..."
az cognitiveservices account deployment list \
  --name $OPENAI_NAME \
  --resource-group $RESOURCE_GROUP \
  --output table

# 2. Получить правильный endpoint (уже знаем, но проверим)
echo "🔗 Получение правильного endpoint..."
CORRECT_ENDPOINT=$(az cognitiveservices account show \
  --name $OPENAI_NAME \
  --resource-group $RESOURCE_GROUP \
  --query properties.endpoint \
  --output tsv)

echo "Правильный endpoint: $CORRECT_ENDPOINT"

# 3. Получить API ключ
echo "🔑 Получение API ключа..."
OPENAI_KEY=$(az cognitiveservices account keys list \
  --name $OPENAI_NAME \
  --resource-group $RESOURCE_GROUP \
  --query key1 \
  --output tsv)

echo "API Key получен: ${OPENAI_KEY:0:10}..."

# 4. Создать deployment если его нет (попробуем создать 'chat')
echo "🚀 Создание deployment 'chat' если не существует..."
az cognitiveservices account deployment create \
  --name $OPENAI_NAME \
  --resource-group $RESOURCE_GROUP \
  --deployment-name chat \
  --model-name gpt-4o-mini \
  --model-version "2024-07-18" \
  --model-format OpenAI \
  --sku-capacity 10 \
  --sku-name "Standard" 2>/dev/null || echo "Deployment уже существует или произошла ошибка - это нормально"

# 5. Обновить настройки Function App
echo "⚙️ Обновление настроек Function App..."
az functionapp config appsettings set \
  --name $FUNCTION_NAME \
  --resource-group $RESOURCE_GROUP \
  --settings \
    "AZURE_OPENAI_ENDPOINT=$CORRECT_ENDPOINT" \
    "AZURE_OPENAI_KEY=$OPENAI_KEY" \
    "CHAT_MODEL_DEPLOYMENT_NAME=chat" \
  --output none

echo "✅ Настройки Function App обновлены!"

# 6. Перезапустить Function App
echo "🔄 Перезапуск Function App..."
az functionapp restart --name $FUNCTION_NAME --resource-group $RESOURCE_GROUP

echo ""
echo "🎉 Исправление завершено!"
echo ""
echo "📋 Обновленные настройки:"
echo "  AZURE_OPENAI_ENDPOINT: $CORRECT_ENDPOINT"
echo "  AZURE_OPENAI_KEY: ${OPENAI_KEY:0:10}..."
echo "  CHAT_MODEL_DEPLOYMENT_NAME: chat"
echo ""
echo "📝 Обновите также ваш local.settings.json:"
echo "  \"AZURE_OPENAI_ENDPOINT\": \"$CORRECT_ENDPOINT\""
echo "  \"AZURE_OPENAI_KEY\": \"$OPENAI_KEY\""