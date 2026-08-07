#!/bin/bash

# Script para atualizar variáveis environment (literais) na Task Definition do ECS
# Uso: ./scripts/update-ecs-env.sh --family <family> --cluster <cluster> --service <service> --file <arquivo> [--region <region>] [--wait]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAMILY=""
CLUSTER=""
SERVICE=""
ENV_FILE=""
REGION="us-east-1"
WAIT=true
PROFILE="stg"

usage() {
    echo "Uso: $0 --family <family> --cluster <cluster> --service <service> --file <arquivo> [--region <region>] [--wait] [--profile <profile>] [--help]"
    echo ""
    echo "Parâmetros:"
    echo "  --family    Nome da família da Task Definition (obrigatório)"
    echo "  --cluster   Nome do cluster ECS (obrigatório)"
    echo "  --service   Nome do serviço ECS (obrigatório)"
    echo "  --file      Caminho do arquivo JSON com environment (valores literais) (obrigatório)"
    echo "  --region    Região AWS (padrão: us-east-1)"
    echo "  --wait      Aguardar estabilização do serviço após atualização"
    echo "  --profile   Perfil AWS (padrão: stg)"
    echo "  --help      Exibe esta mensagem de ajuda"
    echo ""
    echo "Formato do arquivo JSON:"
    echo "  {\"VAR_NAME\": \"valor_literal\", \"OUTRA\": \"123\"}"
    echo "  ou"
    echo "  [{\"name\": \"VAR_NAME\", \"value\": \"valor_literal\"}]"
    echo ""
    echo "Exemplo:"
    echo "  $0 --family my-app --cluster my-cluster --service my-service --file env.json --region us-east-1 --wait"
    exit 1
}

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

    if [ -z "$FAMILY" ] || [ -z "$CLUSTER" ] || [ -z "$SERVICE" ] || [ -z "$ENV_FILE" ]; then
        echo -e "${RED}❌ Parâmetros obrigatórios faltando!${NC}"
        usage
    fi

    if [ ! -f "$ENV_FILE" ]; then
        echo -e "${RED}❌ Arquivo não encontrado: $ENV_FILE${NC}"
        exit 1
    fi

    if [[ ! "$ENV_FILE" == *.json ]]; then
        echo -e "${RED}❌ Arquivo deve ser JSON (.json): $ENV_FILE${NC}"
        exit 1
    fi
}

# Monta array ECS [{"name","value"},...] a partir do JSON de entrada (jq garante escaping correto)
build_environment_json_from_file() {
    local file=$1

    if ! command -v jq &> /dev/null; then
        echo -e "${RED}❌ jq não está instalado. Instale com: sudo apt-get install jq${NC}"
        exit 1
    fi

    jq -c '
      if type == "object" then
        [to_entries[] | {name: .key, value: (.value | tostring)}]
      elif type == "array" then
        [.[] | select(.name != null) | {name: .name, value: (.value | tostring)}]
      else
        []
      end
    ' "$file"
}

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

# Substitui TODAS as environment existentes pelas novas (não mescla)
update_task_definition_environment() {
    local task_def_file=$1
    local new_env_json=$2
    local temp_file=$(mktemp)

    jq --argjson new_env "$new_env_json" \
       '.containerDefinitions[0].environment = $new_env' \
       "$task_def_file" > "$temp_file"

    echo "$temp_file"
}

main() {
    parse_args "$@"

    echo "🔧 Atualizando environment da Task Definition"
    echo "=================================================="
    echo "Family: $FAMILY"
    echo "Cluster: $CLUSTER"
    echo "Service: $SERVICE"
    echo "File: $ENV_FILE"
    echo "Region: $REGION"
    echo "Profile: $PROFILE"
    echo "=================================================="
    echo ""

    echo -e "${YELLOW}📄 Lendo environment do arquivo JSON...${NC}"

    local env_json
    env_json=$(build_environment_json_from_file "$ENV_FILE")

    local env_count
    env_count=$(jq 'length' <<< "$env_json")

    if [ "$env_count" -eq 0 ]; then
        echo -e "${RED}❌ Nenhuma variável de environment encontrada no arquivo!${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ ${env_count} variável(is) de environment encontrada(s)${NC}"
    echo -e "${YELLOW}⚠️  Valores literais ficam visíveis na Task Definition (API/Console). Use secrets para dados sensíveis.${NC}"
    echo ""

    local task_def_arn=$(get_active_task_definition "$CLUSTER" "$SERVICE" "$REGION")
    local task_def_file=$(get_task_definition "$task_def_arn" "$REGION")

    echo -e "${YELLOW}🔄 Substituindo environment na Task Definition...${NC}"
    echo -e "${YELLOW}⚠️  ATENÇÃO: Todas as variáveis environment existentes serão substituídas pelas do arquivo!${NC}"
    local updated_task_def=$(update_task_definition_environment "$task_def_file" "$env_json")

    local new_container_defs=$(jq -c '.containerDefinitions' "$updated_task_def")

    local network_mode=$(jq -r '.networkMode' "$task_def_file")
    local execution_role_arn=$(jq -r '.executionRoleArn' "$task_def_file")

    local requires_compatibilities_array=($(jq -r '.requiresCompatibilities[]' "$task_def_file"))

    local cpu=$(jq -r '.cpu // empty' "$task_def_file")
    local memory=$(jq -r '.memory // empty' "$task_def_file")

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

    echo -e "${YELLOW}📝 Registrando nova revisão da Task Definition...${NC}"

    local register_cmd="aws ecs register-task-definition \
        --family \"$FAMILY\" \
        --container-definitions '$new_container_defs' \
        --network-mode \"$network_mode\" \
        --execution-role-arn \"$execution_role_arn\" \
        --requires-compatibilities"

    for compat in "${requires_compatibilities_array[@]}"; do
        register_cmd="$register_cmd \"$compat\""
    done

    if [ -n "$cpu" ] && [ "$cpu" != "null" ] && [ "$cpu" != "" ]; then
        register_cmd="$register_cmd --cpu \"$cpu\""
    fi

    if [ -n "$memory" ] && [ "$memory" != "null" ] && [ "$memory" != "" ]; then
        register_cmd="$register_cmd --memory \"$memory\""
    fi

    register_cmd="$register_cmd --region \"$REGION\" --profile $PROFILE --query 'taskDefinition.taskDefinitionArn' --output text"

    local new_task_def_arn=$(eval "$register_cmd")

    if [ -z "$new_task_def_arn" ] || [ "$new_task_def_arn" = "None" ]; then
        echo -e "${RED}❌ Falha ao registrar nova revisão da Task Definition${NC}"
        echo -e "${RED}   Verifique os logs acima para mais detalhes${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Nova revisão criada: $new_task_def_arn${NC}"
    echo ""

    rm -f "$task_def_file" "$updated_task_def"

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

main "$@"
