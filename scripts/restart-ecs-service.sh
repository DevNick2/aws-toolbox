#!/bin/bash

# Script para reiniciar um serviço ECS
# Uso: ./scripts/restart-ecs-service.sh <cluster> <service> [region]

set -e

CLUSTER="$1"
SERVICE="$2"
FAMILY="$3"
REGION="$4"
PROFILE="$5"

echo "🔄 Reiniciando serviço ECS..."
echo "Cluster: $CLUSTER"
echo "Service: $SERVICE"
echo "Family: $FAMILY"
echo "Region: $REGION"
echo "Profile: $PROFILE"

# Forçar novo deployment
aws ecs update-service \
  --cluster "$CLUSTER" \
  --service "$SERVICE" \
  --task-definition "$FAMILY" \
  --force-new-deployment \
  --region "$REGION" \
  --query 'service.{ServiceName:serviceName,Status:status,DesiredCount:desiredCount,RunningCount:runningCount}' \
  --output table \
  --profile "$PROFILE"

echo ""
echo "✅ Novo deployment iniciado!"
echo "⏳ Aguardando estabilização do serviço..."

# Aguardar estabilização
aws ecs wait services-stable \
  --cluster "$CLUSTER" \
  --services "$SERVICE" \
  --region "$REGION" \
  --profile "$PROFILE"

echo "✅ Serviço reiniciado com sucesso!"