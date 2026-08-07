#!/bin/bash

# Script para buscar secrets do AWS Secrets Manager e salvar em formato JSON
# Requisitos: aws-cli configurado, jq instalado
# Uso: ./get-secrets.sh <secret-name> [--output <arquivo.json>] [--region <regiao>] [--profile <profile>]

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variáveis
SECRET_NAME=""
OUTPUT_FILE=""
AWS_REGION=""
AWS_PROFILE=""
SHOW_VALUES=false
ENV_FORMAT=false
QUIET=false

# Função de ajuda
show_help() {
    echo "Uso: $0 <secret-name> [opções]"
    echo ""
    echo "Busca secrets do AWS Secrets Manager e exibe/salva em formato JSON."
    echo ""
    echo "Argumentos obrigatórios:"
    echo "  <secret-name>        Nome ou ARN do secret no Secrets Manager"
    echo ""
    echo "Opções:"
    echo "  -o, --output <file>  Salva o resultado no arquivo especificado"
    echo "  --region <regiao>    Região AWS (padrão: usa configuração do CLI)"
    echo "  --profile <profile>  Perfil AWS a ser usado"
    echo "  --show-values        Mostra os valores completos (padrão: mascara valores)"
    echo "  --env                Formato .env ao invés de JSON (VARIAVEL=valor)"
    echo "  -q, --quiet          Não exibe mensagens de status"
    echo "  -h, --help           Mostra esta ajuda"
    echo ""
    echo "Exemplos:"
    echo "  $0 meu-app/producao"
    echo "  $0 meu-app/producao -o secrets.json"
    echo "  $0 meu-app/producao --region us-east-1 --show-values"
    echo "  $0 meu-app/producao --env -o .env"
    echo "  $0 meu-app/producao --profile meu-perfil -q -o secrets.json"
}

# Função para log condicional
log() {
    if [ "$QUIET" = false ]; then
        echo -e "$1"
    fi
}

# Função para verificar dependências
check_dependencies() {
    local missing=()
    
    if ! command -v aws &> /dev/null; then
        missing+=("aws-cli")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}❌ Dependências não encontradas: ${missing[*]}${NC}"
        echo "Instale com:"
        echo "  sudo apt-get install -y jq"
        echo "  # Para aws-cli, veja: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi
}

# Função para construir comando AWS
build_aws_cmd() {
    local cmd="aws"
    
    if [ -n "$AWS_PROFILE" ]; then
        cmd="$cmd --profile $AWS_PROFILE"
    fi
    
    if [ -n "$AWS_REGION" ]; then
        cmd="$cmd --region $AWS_REGION"
    fi
    
    echo "$cmd"
}

# Função para verificar se o secret existe
check_secret_exists() {
    local secret_name=$1
    local aws_cmd=$(build_aws_cmd)
    
    if $aws_cmd secretsmanager describe-secret --secret-id "$secret_name" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Função para obter metadados do secret
get_secret_metadata() {
    local secret_name=$1
    local aws_cmd=$(build_aws_cmd)
    
    $aws_cmd secretsmanager describe-secret --secret-id "$secret_name" 2>/dev/null
}

# Função para obter secrets
get_secrets() {
    local secret_name=$1
    local aws_cmd=$(build_aws_cmd)
    
    local secret_value=$($aws_cmd secretsmanager get-secret-value \
        --secret-id "$secret_name" \
        --query 'SecretString' \
        --output text 2>/dev/null)
    
    if [ -z "$secret_value" ] || [ "$secret_value" = "null" ]; then
        echo -e "${RED}❌ Secret está vazio ou não é uma string${NC}"
        exit 1
    fi
    
    # Valida se é JSON válido
    if ! echo "$secret_value" | jq empty 2>/dev/null; then
        echo -e "${RED}❌ Secret não está em formato JSON válido${NC}"
        exit 1
    fi
    
    echo "$secret_value"
}

# Função para mascarar valores
mask_value() {
    local value=$1
    local length=${#value}
    
    if [ $length -eq 0 ]; then
        echo "(vazio)"
    elif [ $length -le 4 ]; then
        echo "****"
    else
        echo "${value:0:2}***${value: -2}"
    fi
}

# Função para exibir secrets mascarados
display_masked_secrets() {
    local secrets=$1
    
    echo "$secrets" | jq -r 'to_entries | .[] | "\(.key)=\(.value)"' | while IFS='=' read -r key value; do
        local masked=$(mask_value "$value")
        echo "  $key = $masked"
    done
}

# Função para converter JSON para formato .env
json_to_env() {
    local secrets=$1
    
    echo "$secrets" | jq -r 'to_entries | .[] | "\(.key)=\(.value)"'
}

# Função para formatar JSON com indentação
format_json() {
    local secrets=$1
    
    echo "$secrets" | jq --sort-keys .
}

# ============================================
# INÍCIO DO SCRIPT
# ============================================

# Processa argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --profile)
            AWS_PROFILE="$2"
            shift 2
            ;;
        --show-values)
            SHOW_VALUES=true
            shift
            ;;
        --env)
            ENV_FORMAT=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -*)
            echo -e "${RED}❌ Opção desconhecida: $1${NC}"
            show_help
            exit 1
            ;;
        *)
            if [ -z "$SECRET_NAME" ]; then
                SECRET_NAME="$1"
            else
                echo -e "${RED}❌ Argumento inesperado: $1${NC}"
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

# Valida argumentos obrigatórios
if [ -z "$SECRET_NAME" ]; then
    echo -e "${RED}❌ Nome do secret não fornecido${NC}"
    echo ""
    show_help
    exit 1
fi

log "🔐 Busca de Secrets no AWS Secrets Manager"
log "==========================================="
log ""

# Verifica dependências
check_dependencies

log "Secret: $SECRET_NAME"
[ -n "$AWS_REGION" ] && log "Região: $AWS_REGION"
[ -n "$AWS_PROFILE" ] && log "Perfil: $AWS_PROFILE"
[ -n "$OUTPUT_FILE" ] && log "Saída: $OUTPUT_FILE"
log ""

# Verifica se o secret existe
if ! check_secret_exists "$SECRET_NAME"; then
    echo -e "${RED}❌ Secret não encontrado: $SECRET_NAME${NC}"
    exit 1
fi

log -e "${GREEN}✓ Secret encontrado${NC}"

# Obtém metadados
if [ "$QUIET" = false ]; then
    METADATA=$(get_secret_metadata "$SECRET_NAME")
    LAST_CHANGED=$(echo "$METADATA" | jq -r '.LastChangedDate // "N/A"')
    CREATED=$(echo "$METADATA" | jq -r '.CreatedDate // "N/A"')
    
    log ""
    log "📋 Metadados:"
    log "   Criado em: $CREATED"
    log "   Última alteração: $LAST_CHANGED"
fi

# Obtém os secrets
log ""
log -e "${BLUE}🔄 Buscando secrets...${NC}"

SECRETS=$(get_secrets "$SECRET_NAME")

# Conta variáveis
VAR_COUNT=$(echo "$SECRETS" | jq 'keys | length')
log -e "${GREEN}✓ $VAR_COUNT variáveis encontradas${NC}"
log ""

# Prepara saída
if [ "$ENV_FORMAT" = true ]; then
    OUTPUT=$(json_to_env "$SECRETS")
else
    OUTPUT=$(format_json "$SECRETS")
fi

# Exibe na tela
if [ "$QUIET" = false ]; then
    if [ "$SHOW_VALUES" = true ]; then
        log "📄 Conteúdo:"
        echo "$OUTPUT"
    else
        log "📄 Variáveis (valores mascarados):"
        display_masked_secrets "$SECRETS"
        log ""
        log -e "${YELLOW}💡 Use --show-values para ver os valores completos${NC}"
    fi
fi

# Salva em arquivo se especificado
if [ -n "$OUTPUT_FILE" ]; then
    log ""
    
    # Verifica se o arquivo já existe
    if [ -f "$OUTPUT_FILE" ]; then
        if [ "$QUIET" = false ]; then
            read -p "⚠️  Arquivo '$OUTPUT_FILE' já existe. Sobrescrever? (s/n): " overwrite
            if [[ ! $overwrite =~ ^[Ss]$ ]]; then
                echo "Operação cancelada."
                exit 0
            fi
        fi
    fi
    
    echo "$OUTPUT" > "$OUTPUT_FILE"
    log -e "${GREEN}✓ Secrets salvos em: $OUTPUT_FILE${NC}"
    
    # Ajusta permissões do arquivo para apenas o usuário
    chmod 600 "$OUTPUT_FILE"
    log -e "${BLUE}🔒 Permissões do arquivo ajustadas (600)${NC}"
fi

log ""
log -e "${GREEN}✅ Operação concluída!${NC}"

# Se estiver em modo quiet e não tiver arquivo de saída, imprime o resultado
if [ "$QUIET" = true ] && [ -z "$OUTPUT_FILE" ]; then
    echo "$OUTPUT"
fi
