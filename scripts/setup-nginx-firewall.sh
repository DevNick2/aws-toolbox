#!/bin/bash

# Script para instalar nginx e sincronizar firewall com AWS Security Groups
# Requisitos: AWS CLI configurado com credenciais e permissões adequadas

set -e

echo "🚀 Iniciando instalação e configuração do nginx e firewall..."

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Função para imprimir mensagens coloridas
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "ℹ️  $1"
}

# Verifica se está rodando como root
if [ "$EUID" -ne 0 ]; then 
    print_error "Por favor, execute como root ou com sudo"
    exit 1
fi

# ============================================================================
# 1. INSTALAÇÃO DO NGINX
# ============================================================================
print_info "Instalando nginx..."

if command -v nginx &> /dev/null; then
    print_warning "Nginx já está instalado"
    nginx -v
else
    apt-get update
    apt-get install -y nginx
    print_success "Nginx instalado com sucesso"
    nginx -v
fi

# Inicia e habilita nginx
systemctl enable nginx
systemctl start nginx
print_success "Nginx iniciado e habilitado"

# ============================================================================
# 2. CONFIGURAÇÃO DO FIREWALL (UFW)
# ============================================================================
print_info "Configurando firewall (UFW)..."

# Instala UFW se não estiver instalado
if ! command -v ufw &> /dev/null; then
    print_info "Instalando UFW..."
    apt-get install -y ufw
fi

# Verifica se AWS CLI está instalado
if ! command -v aws &> /dev/null; then
    print_warning "AWS CLI não está instalado. Instalando..."
    apt-get update
    apt-get install -y awscli
    print_success "AWS CLI instalado"
fi

# Verifica se jq está instalado (útil para processar JSON)
if ! command -v jq &> /dev/null; then
    print_info "Instalando jq para processar JSON..."
    apt-get update
    apt-get install -y jq
fi

# Verifica se AWS CLI está configurado
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS CLI não está configurado ou não tem permissões"
    print_info "Configure com: aws configure"
    exit 1
fi

# Obtém o ID da instância EC2 atual
print_info "Obtendo informações da instância EC2..."
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "")

if [ -z "$INSTANCE_ID" ]; then
    print_warning "Não foi possível obter o Instance ID automaticamente"
    print_info "Você está executando em uma instância EC2?"
    if [ -t 0 ]; then
        # Modo interativo
        read -p "Digite o Instance ID manualmente (ou pressione Enter para pular sincronização AWS): " INSTANCE_ID
    else
        # Modo não-interativo (ex: via cron ou script automatizado)
        print_info "Modo não-interativo detectado. Pulando sincronização AWS."
        INSTANCE_ID=""
    fi
fi

# Função para sincronizar regras do Security Group com UFW
sync_security_groups() {
    if [ -z "$INSTANCE_ID" ]; then
        print_warning "Pulando sincronização com AWS Security Groups"
        return
    fi

    print_info "Sincronizando regras dos Security Groups da AWS..."

    # Obtém os Security Groups da instância
    SECURITY_GROUPS=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].SecurityGroups[*].GroupId' \
        --output text 2>/dev/null || echo "")

    if [ -z "$SECURITY_GROUPS" ]; then
        print_warning "Não foi possível obter os Security Groups da instância"
        return
    fi

    print_info "Security Groups encontrados: $SECURITY_GROUPS"

    # Obtém todas as regras de entrada dos Security Groups
    INGRESS_RULES=$(aws ec2 describe-security-groups \
        --group-ids $SECURITY_GROUPS \
        --query 'SecurityGroups[*].IpPermissions[*]' \
        --output json 2>/dev/null || echo "[]")

    if [ "$INGRESS_RULES" = "[]" ] || [ -z "$INGRESS_RULES" ]; then
        print_warning "Nenhuma regra de entrada encontrada nos Security Groups"
        return
    fi

    print_info "Aplicando regras dos Security Groups no UFW..."

    # Arquivo temporário para armazenar regras aplicadas
    TEMP_RULES_FILE=$(mktemp)
    trap "rm -f $TEMP_RULES_FILE" EXIT
    
    # Itera sobre cada Security Group
    for sg_id in $SECURITY_GROUPS; do
        print_info "Processando Security Group: $sg_id"
        
        # Obtém regras de entrada do Security Group e processa com jq
        aws ec2 describe-security-groups \
            --group-ids "$sg_id" \
            --query 'SecurityGroups[0].IpPermissions' \
            --output json 2>/dev/null | \
        jq -r '.[] | 
            select(.IpProtocol == "tcp" or .IpProtocol == "udp") |
            .IpProtocol as $proto |
            .FromPort as $from |
            .ToPort as $to |
            (if $from == $to then "\($from)" else "\($from):\($to)" end) as $port |
            .IpRanges[]? |
            "\($proto)|\($port)|\(.CidrIp)|\(.Description // "AWS SG")"' 2>/dev/null | \
        while IFS='|' read -r proto port cidr description; do
            if [ -z "$proto" ] || [ -z "$port" ]; then
                continue
            fi
            
            # Cria chave única para evitar duplicatas
            rule_key="${proto}:${port}:${cidr}"
            if grep -q "^${rule_key}$" "$TEMP_RULES_FILE" 2>/dev/null; then
                continue
            fi
            echo "$rule_key" >> "$TEMP_RULES_FILE"
            
            # Limpa descrição para uso no comando
            clean_desc=$(echo "$description" | tr -d '"' | sed "s/'/\\\'/g" || echo "AWS SG")
            
            # Aplica regra no UFW
            if [ "$cidr" = "0.0.0.0/0" ]; then
                ufw_command="ufw allow ${port}/${proto} comment \"${clean_desc}\""
            else
                ufw_command="ufw allow from ${cidr} to any port ${port} proto ${proto} comment \"${clean_desc}\""
            fi
            
            print_info "Aplicando: $ufw_command"
            eval "$ufw_command" || print_warning "Falha ao aplicar regra: $ufw_command"
        done
    done

    rm -f "$TEMP_RULES_FILE"
    print_success "Regras dos Security Groups sincronizadas"
}

# Garante que as portas essenciais estão abertas
ensure_essential_ports() {
    print_info "Garantindo que as portas essenciais estão abertas..."

    # Porta 22 (SSH) - sempre permitir
    ufw allow 22/tcp comment "SSH - Essential" || true
    print_success "Porta 22 (SSH) liberada"

    # Porta 80 (HTTP)
    ufw allow 80/tcp comment "HTTP - Essential" || true
    print_success "Porta 80 (HTTP) liberada"

    # Porta 443 (HTTPS)
    ufw allow 443/tcp comment "HTTPS - Essential" || true
    print_success "Porta 443 (HTTPS) liberada"
}

# Sincroniza regras dos Security Groups
sync_security_groups

# Garante portas essenciais
ensure_essential_ports

# Configura UFW para permitir tráfego de saída por padrão
ufw default allow outgoing || true

# Configura UFW para negar tráfego de entrada por padrão (mas as regras acima permitem o necessário)
ufw default deny incoming || true

# Habilita UFW (modo não-interativo)
print_info "Habilitando UFW..."
echo "y" | ufw enable || true

# Recarrega UFW para aplicar todas as regras
ufw reload || true

print_success "Firewall configurado e ativado"

# ============================================================================
# 3. VERIFICAÇÃO FINAL
# ============================================================================
print_info "Verificando status do firewall..."
ufw status verbose

print_info "Verificando status do nginx..."
systemctl status nginx --no-pager -l | head -n 10

# ============================================================================
# RESUMO
# ============================================================================
echo ""
print_success "Configuração concluída!"
echo ""
echo "📋 Resumo:"
echo "   ✅ Nginx instalado e rodando"
echo "   ✅ Firewall (UFW) configurado e ativado"
echo "   ✅ Portas 22, 80 e 443 liberadas"
if [ ! -z "$INSTANCE_ID" ]; then
    echo "   ✅ Regras sincronizadas com AWS Security Groups"
fi
echo ""
echo "🔍 Comandos úteis:"
echo "   - Ver status do firewall: sudo ufw status verbose"
echo "   - Ver regras do firewall: sudo ufw status numbered"
echo "   - Verificar nginx: sudo systemctl status nginx"
echo "   - Testar nginx: curl http://localhost"
echo ""
echo "⚠️  Importante:"
echo "   - Certifique-se de que o SSH está acessível antes de fechar a sessão atual"
echo "   - As regras do firewall foram aplicadas baseadas nos Security Groups da AWS"
echo "   - Você pode adicionar regras manualmente com: sudo ufw allow <porta>/<protocolo>"

