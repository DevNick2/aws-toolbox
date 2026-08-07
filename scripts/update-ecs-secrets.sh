#!/bin/bash

# Script para atualizar secrets de Task Definition do ECS
# Uso: ./scripts/update-ecs-secrets.sh --family <family> --cluster <cluster> --service <service> --file <arquivo> [--region <region>] [--wait]

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Variáveis globais
FAMILY=""
CLUSTER=""
SERVICE=""
ENV_FILE=""
REGION="us-east-1"
WAIT=true
PROFILE="stg"

# Função para exibir uso
usage() {
    echo "Uso: $0 --family <family> --cluster <cluster> --service <service> --file <arquivo> [--region <region>] [--wait] [--profile <profile>] [--help]"
    echo ""
    echo "Parâmetros:"
    echo "  --family    Nome da família da Task Definition (obrigatório)"
    echo "  --cluster   Nome do cluster ECS (obrigatório)"
    echo "  --service   Nome do serviço ECS (obrigatório)"
    echo "  --file      Caminho do arquivo JSON com secrets (obrigatório)"
    echo "  --region    Região AWS (padrão: us-east-1)"
    echo "  --wait      Aguardar estabilização do serviço após atualização"
    echo "  --profile   Perfil AWS (padrão: stg)"
    echo "  --help      Exibe esta mensagem de ajuda"
    echo ""
    echo "Formato do arquivo JSON:"
    echo "  {\"VAR_NAME\": \"arn:aws:secretsmanager:region:account:secret:name:key::\"}"
    echo "  ou"
    echo "  [{\"name\": \"VAR_NAME\", \"valueFrom\": \"arn:aws:secretsmanager:...\"}]"
    echo ""
    echo "Exemplo:"
    echo "  $0 --family my-app --cluster my-cluster --service my-service --file secrets.json --region us-east-1 --wait"
    exit 1
}

# Função para parsear argumentos
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --family)
                FAMILY="$2"
                shift 2
                ;;
            --cluster)
                CLUSTER="$2"
                shift 2
                ;;
            --service)
                SERVICE="$2"
                shift 2
                ;;
            --file)
                ENV_FILE="$2"
                shift 2
                ;;
            --region)
                REGION="$2"
                shift 2
                ;;
            --wait)
                WAIT=true
                shift
                ;;
            --profile)
                PROFILE="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                echo -e "${RED}❌ Opção desconhecida: $1${NC}"
                usage
                ;;
        esac
    done

    # Validação de parâmetros obrigatórios
    if [ -z "$FAMILY" ] || [ -z "$CLUSTER" ] || [ -z "$SERVICE" ] || [ -z "$ENV_FILE" ]; then
        echo -e "${RED}❌ Parâmetros obrigatórios faltando!${NC}"
        usage
    fi

    # Validar se arquivo existe
    if [ ! -f "$ENV_FILE" ]; then
        echo -e "${RED}❌ Arquivo não encontrado: $ENV_FILE${NC}"
        exit 1
    fi
    
    # Validar se arquivo é JSON
    if [[ ! "$ENV_FILE" == *.json ]]; then
        echo -e "${RED}❌ Arquivo deve ser JSON (.json): $ENV_FILE${NC}"
        exit 1
    fi
}

# Função para parsear arquivo JSON com secrets
parse_json_file() {
    local file=$1
    
    # Verifica se jq está instalado
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}❌ jq não está instalado. Instale com: sudo apt-get install jq${NC}"
        exit 1
    fi
    
    # Extrai secrets do JSON
    # Espera formato: {"VAR1": "arn:aws:secretsmanager:...", "VAR2": "arn:..."}
    # ou [{"name": "VAR1", "valueFrom": "arn:..."}]
    jq -r 'if type == "object" then to_entries[] | "\(.key)=\(.value)" elif type == "array" then .[] | "\(.name)=\(.valueFrom)" else empty end' "$file"
}

# Função para converter secrets para formato JSON do AWS ECS
# Formato ECS secrets: {"name": "VAR_NAME", "valueFrom": "arn:aws:secretsmanager:..."}
convert_to_ecs_format() {
    local secrets=("$@")
    local json_array="["
    local first=true
    
    for secret in "${secrets[@]}"; do
        if [ -n "$secret" ]; then
            IFS='=' read -r key value_from <<< "$secret"
            # Remove aspas do valor se existirem
            value_from=$(echo "$value_from" | sed 's/^"//;s/"$//')
            
            # Valida se é um ARN válido do Secrets Manager
            if [[ ! "$value_from" =~ ^arn:aws:secretsmanager: ]]; then
                echo -e "${RED}❌ ARN inválido para $key: $value_from${NC}"
                echo -e "${RED}   Formato esperado: arn:aws:secretsmanager:region:account:secret:name:key::${NC}"
                exit 1
            fi
            
            if [ "$first" = true ]; then
                first=false
            else
                json_array+=","
            fi
            
            json_array+="{\"name\":\"$key\",\"valueFrom\":\"$value_from\"}"
        fi
    done
    
    json_array+="]"
    echo "$json_array"
}

# Função para buscar Task Definition ativa do serviço
get_active_task_definition() {
    local cluster=$1
    local service=$2
    local region=$3
    
    echo -e "${YELLOW}📋 Buscando Task Definition ativa do serviço: $service${NC}" >&2
    
    local task_def_arn=$(aws ecs describe-services \
        --cluster "$cluster" \
        --services "$service" \
        --region "$region" \
        --profile $PROFILE \
        --query 'services[0].taskDefinition' \
        --output text)
    
    if [ -z "$task_def_arn" ] || [ "$task_def_arn" = "None" ]; then
        echo -e "${RED}❌ Task Definition ativa não encontrada para o serviço: $service${NC}" >&2
        exit 1
    fi
    
    echo -e "${GREEN}✓ Task Definition ativa encontrada: $task_def_arn${NC}" >&2
    echo "$task_def_arn"
}

# Função para obter Task Definition completa
get_task_definition() {
    local task_def_arn=$1
    local region=$2
    local temp_file=$(mktemp)
    
    aws ecs describe-task-definition \
        --task-definition "$task_def_arn" \
        --region "$region" \
        --query 'taskDefinition' \
        --profile $PROFILE \
        > "$temp_file"
    
    echo "$temp_file"
}

# Função para atualizar secrets na Task Definition
# Substitui TODAS as secrets existentes pelas novas (não mescla)
update_task_definition_secrets() {
    local task_def_file=$1
    local new_secrets_json=$2
    local temp_file=$(mktemp)
    
    # Usa jq para substituir completamente os secrets
    # Remove todos os secrets existentes e define apenas os novos
    jq --argjson new_secrets "$new_secrets_json" \
       '.containerDefinitions[0].secrets = $new_secrets' \
       "$task_def_file" > "$temp_file"
    
    echo "$temp_file"
}

# Função principal
main() {
    parse_args "$@"
    
    echo "🔧 Atualizando secrets da Task Definition"
    echo "=================================================="
    echo "Family: $FAMILY"
    echo "Cluster: $CLUSTER"
    echo "Service: $SERVICE"
    echo "File: $ENV_FILE"
    echo "Region: $REGION"
    echo "Profile: $PROFILE"
    echo "=================================================="
    echo ""
    
    # Parseia secrets do arquivo JSON
    echo -e "${YELLOW}📄 Lendo secrets do arquivo JSON...${NC}"
    
    local secrets=($(parse_json_file "$ENV_FILE"))
    
    if [ ${#secrets[@]} -eq 0 ]; then
        echo -e "${RED}❌ Nenhum secret encontrado no arquivo!${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ ${#secrets[@]} secret(s) encontrado(s)${NC}"
    echo ""
    
    # Converte para formato JSON do ECS (secrets)
    local secrets_json=$(convert_to_ecs_format "${secrets[@]}")
    
    # Busca Task Definition ativa do serviço
    local task_def_arn=$(get_active_task_definition "$CLUSTER" "$SERVICE" "$REGION")
    local task_def_file=$(get_task_definition "$task_def_arn" "$REGION")
    
    # Atualiza secrets (substitui todas)
    echo -e "${YELLOW}🔄 Substituindo secrets na Task Definition...${NC}"
    echo -e "${YELLOW}⚠️  ATENÇÃO: Todas as secrets existentes serão substituídas pelas do arquivo!${NC}"
    local updated_task_def=$(update_task_definition_secrets "$task_def_file" "$secrets_json")
    
    # Extrai container definitions atualizados (compacto, sem quebras de linha)
    local new_container_defs=$(jq -c '.containerDefinitions' "$updated_task_def")
    
    # Extrai campos necessários da Task Definition original
    local network_mode=$(jq -r '.networkMode' "$task_def_file")
    local execution_role_arn=$(jq -r '.executionRoleArn' "$task_def_file")
    
    # Extrai requires-compatibilities como array para passar como múltiplos argumentos
    local requires_compatibilities_array=($(jq -r '.requiresCompatibilities[]' "$task_def_file"))
    
    # Extrai cpu e memory (podem ser null ou não existir)
    local cpu=$(jq -r '.cpu // empty' "$task_def_file")
    local memory=$(jq -r '.memory // empty' "$task_def_file")
    
    # Valida campos obrigatórios
    if [ -z "$network_mode" ] || [ "$network_mode" = "null" ]; then
        echo -e "${RED}❌ networkMode não encontrado na Task Definition${NC}"
        exit 1
    fi
    
    if [ -z "$execution_role_arn" ] || [ "$execution_role_arn" = "null" ]; then
        echo -e "${RED}❌ executionRoleArn não encontrado na Task Definition${NC}"
        exit 1
    fi
    
    if [ ${#requires_compatibilities_array[@]} -eq 0 ]; then
        echo -e "${RED}❌ requiresCompatibilities não encontrado na Task Definition${NC}"
        exit 1
    fi
    
    # Registra nova revisão da Task Definition usando parâmetros individuais
    echo -e "${YELLOW}📝 Registrando nova revisão da Task Definition...${NC}"
    
    # Monta comando base
    local register_cmd="aws ecs register-task-definition \
        --family \"$FAMILY\" \
        --container-definitions '$new_container_defs' \
        --network-mode \"$network_mode\" \
        --execution-role-arn \"$execution_role_arn\" \
        --requires-compatibilities"
    
    # Adiciona cada compatibilidade como argumento separado
    for compat in "${requires_compatibilities_array[@]}"; do
        register_cmd="$register_cmd \"$compat\""
    done
    
    # Adiciona cpu e memory se existirem
    if [ -n "$cpu" ] && [ "$cpu" != "null" ] && [ "$cpu" != "" ]; then
        register_cmd="$register_cmd --cpu \"$cpu\""
    fi
    
    if [ -n "$memory" ] && [ "$memory" != "null" ] && [ "$memory" != "" ]; then
        register_cmd="$register_cmd --memory \"$memory\""
    fi
    
    # Adiciona região e profile
    register_cmd="$register_cmd --region \"$REGION\" --profile $PROFILE --query 'taskDefinition.taskDefinitionArn' --output text"
    
    # Executa comando e captura resultado
    local new_task_def_arn=$(eval "$register_cmd")
    
    # Verifica se o comando foi bem-sucedido
    if [ -z "$new_task_def_arn" ] || [ "$new_task_def_arn" = "None" ]; then
        echo -e "${RED}❌ Falha ao registrar nova revisão da Task Definition${NC}"
        echo -e "${RED}   Verifique os logs acima para mais detalhes${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Nova revisão criada: $new_task_def_arn${NC}"
    echo ""
    
    # Limpa arquivos temporários
    rm -f "$task_def_file" "$updated_task_def"
    
    # Atualiza serviço ECS
    echo -e "${YELLOW}🚀 Atualizando serviço ECS...${NC}"
    aws ecs update-service \
        --cluster "$CLUSTER" \
        --service "$SERVICE" \
        --task-definition "$new_task_def_arn" \
        --region "$REGION" \
        --query 'service.{ServiceName:serviceName,Status:status,TaskDefinition:taskDefinition,DesiredCount:desiredCount,RunningCount:runningCount}' \
        --output table \
        --profile $PROFILE
    
    echo ""
    echo -e "${GREEN}✅ Serviço atualizado com sucesso!${NC}"
    
    # Aguarda estabilização se solicitado
    if [ "$WAIT" = true ]; then
        echo ""
        echo -e "${YELLOW}⏳ Aguardando estabilização do serviço...${NC}"
        aws ecs wait services-stable \
            --cluster "$CLUSTER" \
            --services "$SERVICE" \
            --region "$REGION" \
            --profile $PROFILE
        echo -e "${GREEN}✅ Serviço estabilizado!${NC}"
    else
        echo ""
        echo -e "${YELLOW}💡 Dica: Use --wait para aguardar estabilização automática${NC}"
    fi
}

# Executa função principal
main "$@"

