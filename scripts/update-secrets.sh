#!/bin/bash

# Script para atualizar secrets no AWS Secrets Manager usando um arquivo JSON
# Requisitos: aws-cli configurado, jq instalado
# Uso: ./update-secrets.sh <secret-name> <arquivo.json> [--region <regiao>] [--profile <profile>]

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variáveis
SECRET_NAME=""
JSON_FILE=""
AWS_REGION=""
AWS_PROFILE=""
DRY_RUN=false
MERGE_MODE=false

# Função de ajuda
show_help() {
    echo "Uso: $0 <secret-name> <arquivo.json> [opções]"
    echo ""
    echo "Atualiza secrets no AWS Secrets Manager usando um arquivo JSON."
    echo ""
    echo "Argumentos obrigatórios:"
    echo "  <secret-name>      Nome ou ARN do secret no Secrets Manager"
    echo "  <arquivo.json>     Arquivo JSON com as variáveis de ambiente"
    echo ""
    echo "Opções:"
    echo "  --region <regiao>  Região AWS (padrão: usa configuração do CLI)"
    echo "  --profile <profile> Perfil AWS a ser usado"
    echo "  --merge            Mescla com valores existentes (não substitui tudo)"
    echo "  --dry-run          Mostra o que seria atualizado sem executar"
    echo "  -h, --help         Mostra esta ajuda"
    echo ""
    echo "Formato do arquivo JSON:"
    echo '  {'
    echo '    "VARIAVEL1": "valor1",'
    echo '    "VARIAVEL2": "valor2"'
    echo '  }'
    echo ""
    echo "Exemplos:"
    echo "  $0 meu-app/producao secrets.json"
    echo "  $0 meu-app/producao secrets.json --region us-east-1"
    echo "  $0 meu-app/producao secrets.json --profile meu-perfil --merge"
    echo "  $0 meu-app/producao secrets.json --dry-run"
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

# Função para validar arquivo JSON
validate_json_file() {
    local file=$1
    
    if [ ! -f "$file" ]; then
        echo -e "${RED}❌ Arquivo não encontrado: $file${NC}"
        exit 1
    fi
    
    if ! jq empty "$file" 2>/dev/null; then
        echo -e "${RED}❌ Arquivo JSON inválido: $file${NC}"
        exit 1
    fi
    
    # Verifica se é um objeto (não array)
    local json_type=$(jq -r 'type' "$file")
    if [ "$json_type" != "object" ]; then
        echo -e "${RED}❌ O arquivo JSON deve conter um objeto, não um $json_type${NC}"
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

# Função para obter secrets atuais
get_current_secrets() {
    local secret_name=$1
    local aws_cmd=$(build_aws_cmd)
    
    $aws_cmd secretsmanager get-secret-value \
        --secret-id "$secret_name" \
        --query 'SecretString' \
        --output text 2>/dev/null || echo "{}"
}

# Função para atualizar secrets
update_secrets() {
    local secret_name=$1
    local new_secrets=$2
    local aws_cmd=$(build_aws_cmd)
    
    if [ "$MERGE_MODE" = true ]; then
        echo -e "${BLUE}🔀 Modo merge: mesclando com valores existentes...${NC}"
        local current_secrets=$(get_current_secrets "$secret_name")
        
        # Mescla: valores novos sobrescrevem os existentes
        new_secrets=$(echo "$current_secrets" "$new_secrets" | jq -s '.[0] * .[1]')
    fi
    
    # Conta quantas variáveis serão atualizadas
    local var_count=$(echo "$new_secrets" | jq 'keys | length')
    
    echo -e "${BLUE}📝 Variáveis a serem atualizadas: $var_count${NC}"
    echo ""
    
    # Mostra as variáveis (sem mostrar valores sensíveis)
    echo "Variáveis:"
    echo "$new_secrets" | jq -r 'keys[]' | while read key; do
        local value=$(echo "$new_secrets" | jq -r --arg k "$key" '.[$k]')
        local masked_value
        if [ ${#value} -gt 4 ]; then
            masked_value="${value:0:2}***${value: -2}"
        else
            masked_value="****"
        fi
        echo "  - $key = $masked_value"
    done
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}🔍 DRY RUN: Nenhuma alteração foi feita${NC}"
        echo ""
        echo "JSON que seria enviado:"
        echo "$new_secrets" | jq .
        return 0
    fi
    
    # Atualiza o secret
    echo -e "${BLUE}🔄 Atualizando secret '$secret_name'...${NC}"
    
    if $aws_cmd secretsmanager put-secret-value \
        --secret-id "$secret_name" \
        --secret-string "$new_secrets" \
        --output text &>/dev/null; then
        echo -e "${GREEN}✓ Secret atualizado com sucesso!${NC}"
    else
        echo -e "${RED}❌ Falha ao atualizar secret${NC}"
        exit 1
    fi
}

# Função para criar novo secret
create_secret() {
    local secret_name=$1
    local secrets=$2
    local aws_cmd=$(build_aws_cmd)
    
    echo -e "${BLUE}🆕 Criando novo secret '$secret_name'...${NC}"
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}🔍 DRY RUN: Secret seria criado${NC}"
        return 0
    fi
    
    if $aws_cmd secretsmanager create-secret \
        --name "$secret_name" \
        --secret-string "$secrets" \
        --output text &>/dev/null; then
        echo -e "${GREEN}✓ Secret criado com sucesso!${NC}"
    else
        echo -e "${RED}❌ Falha ao criar secret${NC}"
        exit 1
    fi
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
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --profile)
            AWS_PROFILE="$2"
            shift 2
            ;;
        --merge)
            MERGE_MODE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
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
            elif [ -z "$JSON_FILE" ]; then
                JSON_FILE="$1"
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
if [ -z "$SECRET_NAME" ] || [ -z "$JSON_FILE" ]; then
    echo -e "${RED}❌ Argumentos obrigatórios não fornecidos${NC}"
    echo ""
    show_help
    exit 1
fi

echo "🔐 Atualização de Secrets no AWS Secrets Manager"
echo "================================================="
echo ""

# Verifica dependências
check_dependencies

# Valida arquivo JSON
validate_json_file "$JSON_FILE"

# Lê o arquivo JSON
NEW_SECRETS=$(cat "$JSON_FILE")

echo "Secret: $SECRET_NAME"
echo "Arquivo: $JSON_FILE"
[ -n "$AWS_REGION" ] && echo "Região: $AWS_REGION"
[ -n "$AWS_PROFILE" ] && echo "Perfil: $AWS_PROFILE"
[ "$MERGE_MODE" = true ] && echo "Modo: Merge (mescla com existentes)"
[ "$DRY_RUN" = true ] && echo -e "${YELLOW}Modo: DRY RUN${NC}"
echo ""

# Verifica se o secret existe
if check_secret_exists "$SECRET_NAME"; then
    echo -e "${GREEN}✓ Secret encontrado${NC}"
    update_secrets "$SECRET_NAME" "$NEW_SECRETS"
else
    echo -e "${YELLOW}⚠️  Secret não encontrado. Criando novo...${NC}"
    read -p "Deseja criar o secret '$SECRET_NAME'? (s/n): " create_confirm
    if [[ $create_confirm =~ ^[Ss]$ ]]; then
        create_secret "$SECRET_NAME" "$NEW_SECRETS"
    else
        echo "Operação cancelada."
        exit 0
    fi
fi

echo ""
echo -e "${GREEN}✅ Operação concluída!${NC}"
