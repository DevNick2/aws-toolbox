#!/bin/bash

# Script interativo para criar certificado SSL usando certbot
# Requisitos: certbot, nginx instalado e configurado
# Sistema: Ubuntu

set -e

NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Variáveis globais que serão preenchidas interativamente
DOMAIN=""
EMAIL=""
CONFIG_TYPE=""  # "front" ou "api"
STATIC_ROOT=""
BUILD_PATH=""
NEEDS_REVERSE_PROXY=false
PROXY_URL=""
PROXY_PORT=""
PROXY_PATH=""
PROXY_HEADERS=""

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Função para validar formato de email
validate_email() {
    local email=$1
    if [[ $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Função para validar formato de domínio
validate_domain() {
    local domain=$1
    if [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Função para validar URL do proxy reverso
validate_proxy_url() {
    local url=$1
    if [[ $url =~ ^https?://[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*(\.[a-zA-Z]{2,})?(:[0-9]{1,5})?$ ]] || [[ $url =~ ^http://localhost(:[0-9]{1,5})?$ ]] || [[ $url =~ ^http://127\.0\.0\.1(:[0-9]{1,5})?$ ]]; then
        return 0
    else
        return 1
    fi
}

# Função para solicitar domínio
prompt_domain() {
    while true; do
        read -p "Digite o domínio (ex: exemplo.com): " DOMAIN
        if [ -z "$DOMAIN" ]; then
            echo -e "${RED}❌ Domínio não pode estar vazio.${NC}"
            continue
        fi
        if validate_domain "$DOMAIN"; then
            echo -e "${GREEN}✓ Domínio válido: $DOMAIN${NC}"
            break
        else
            echo -e "${RED}❌ Formato de domínio inválido. Tente novamente.${NC}"
        fi
    done
}

# Função para solicitar email
prompt_email() {
    while true; do
        read -p "Digite o email para o certificado SSL: " EMAIL
        if [ -z "$EMAIL" ]; then
            echo -e "${RED}❌ Email não pode estar vazio.${NC}"
            continue
        fi
        if validate_email "$EMAIL"; then
            echo -e "${GREEN}✓ Email válido: $EMAIL${NC}"
            break
        else
            echo -e "${RED}❌ Formato de email inválido. Tente novamente.${NC}"
        fi
    done
}

# Função para solicitar tipo de configuração
prompt_config_type() {
    while true; do
        echo ""
        echo "Selecione o tipo de configuração:"
        echo "  1) Front estático (servir arquivos HTML/CSS/JS)"
        echo "  2) API (proxy reverso para backend)"
        read -p "Escolha (1 ou 2): " choice
        
        case $choice in
            1)
                CONFIG_TYPE="front"
                echo -e "${GREEN}✓ Tipo selecionado: Front estático${NC}"
                break
                ;;
            2)
                CONFIG_TYPE="api"
                echo -e "${GREEN}✓ Tipo selecionado: API${NC}"
                break
                ;;
            *)
                echo -e "${RED}❌ Opção inválida. Escolha 1 ou 2.${NC}"
                ;;
        esac
    done
}

# Função para solicitar configuração de proxy reverso
prompt_reverse_proxy() {
    echo ""
    echo "Configuração de Proxy Reverso:"
    
    # URL do backend
    while true; do
        read -p "URL do backend (ex: http://localhost:3000 ou http://127.0.0.1:8080): " PROXY_URL
        if [ -z "$PROXY_URL" ]; then
            echo -e "${RED}❌ URL não pode estar vazia.${NC}"
            continue
        fi
        if validate_proxy_url "$PROXY_URL"; then
            echo -e "${GREEN}✓ URL válida: $PROXY_URL${NC}"
            break
        else
            echo -e "${RED}❌ Formato de URL inválido. Use http://hostname:porta ou http://localhost:porta${NC}"
        fi
    done
    
    # Caminho da API (opcional, padrão é /)
    read -p "Caminho da API (ex: /api ou / para tudo) [padrão: /]: " PROXY_PATH
    PROXY_PATH=${PROXY_PATH:-/}
    if [ "$PROXY_PATH" != "/" ] && [[ ! "$PROXY_PATH" =~ ^/ ]]; then
        PROXY_PATH="/$PROXY_PATH"
    fi
    
    # Headers customizados (opcional)
    echo ""
    read -p "Headers customizados (ex: Host \$host; X-Real-IP \$remote_addr;) [opcional]: " PROXY_HEADERS
    if [ -n "$PROXY_HEADERS" ]; then
        echo -e "${GREEN}✓ Headers configurados${NC}"
    fi
}

# Função para solicitar caminho dos arquivos estáticos
prompt_static_root() {
    local default_path="/var/www/$DOMAIN"
    read -p "Caminho do diretório estático [padrão: $default_path]: " STATIC_ROOT
    STATIC_ROOT=${STATIC_ROOT:-$default_path}
    echo -e "${GREEN}✓ Diretório estático: $STATIC_ROOT${NC}"
}

# Função para solicitar caminho do diretório de build
prompt_build_path() {
    while true; do
        read -p "Caminho do diretório de build (ex: ./dist, ./build): " BUILD_PATH
        if [ -z "$BUILD_PATH" ]; then
            echo -e "${RED}❌ Caminho do build não pode estar vazio.${NC}"
            continue
        fi
        # Expande ~ e caminhos relativos
        BUILD_PATH=$(eval echo "$BUILD_PATH")
        if [ ! -d "$BUILD_PATH" ]; then
            echo -e "${RED}❌ Diretório não encontrado: $BUILD_PATH${NC}"
            continue
        fi
        if [ -z "$(ls -A "$BUILD_PATH" 2>/dev/null)" ]; then
            echo -e "${YELLOW}⚠️  Diretório está vazio: $BUILD_PATH${NC}"
            read -p "Continuar mesmo assim? (s/n): " empty_choice
            if [[ ! $empty_choice =~ ^[Ss]$ ]]; then
                continue
            fi
        fi
        echo -e "${GREEN}✓ Diretório de build válido: $BUILD_PATH${NC}"
        break
    done
}

# Função para corrigir permissões do BUILD_PATH e caminho até ele
fix_build_path_permissions() {
    local build_path=$1
    if [ -z "$build_path" ] || [ ! -d "$build_path" ]; then
        return 1
    fi
    
    echo "🔐 Corrigindo permissões do diretório de build..."
    
    # Converte para caminho absoluto
    local build_path_abs=$(cd "$build_path" && pwd)
    
    # Garante permissão de execução (x) em todos os diretórios do caminho até o BUILD_PATH
    # Isso é necessário para que o nginx possa atravessar os diretórios até chegar aos arquivos
    local current_path="/"
    local path_parts=$(echo "$build_path_abs" | sed 's|^/||' | tr '/' ' ')
    
    for part in $path_parts; do
        current_path="${current_path}${part}/"
        if [ -d "$current_path" ]; then
            # Garante que o diretório tenha pelo menos 755 (rwxr-xr-x)
            sudo chmod 755 "$current_path" 2>/dev/null || true
        fi
    done
    
    # Garante permissões adequadas nos arquivos e diretórios do BUILD_PATH
    # Arquivos: 644 (rw-r--r--) - leitura para todos (incluindo www-data)
    # Diretórios: 755 (rwxr-xr-x) - execução para todos (necessário para navegar)
    sudo find "$build_path_abs" -type f -exec chmod 644 {} \; 2>/dev/null || true
    sudo find "$build_path_abs" -type d -exec chmod 755 {} \; 2>/dev/null || true
    
    echo -e "${GREEN}✓ Permissões corrigidas${NC}"
}

# Função para gerar configuração nginx temporária (para validação do certbot)
generate_temp_nginx_config() {
    local domain=$1
    sudo tee "$NGINX_SITES_AVAILABLE/$domain" > /dev/null <<EOF
server {
    listen 80;
    server_name $domain;

    location / {
        return 301 https://\$host\$request_uri;
    }

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
}
EOF
}

# Função para gerar configuração nginx completa
generate_nginx_config() {
    local domain=$1
    local config_type=$2
    local static_root=$3
    local needs_proxy=$4
    local proxy_url=$5
    local proxy_path=$6
    local proxy_headers=$7
    local output_file=$8
    
    # Cria arquivo temporário para construir a configuração
    local temp_file=$(mktemp)
    
    {
        cat <<EOF
# Redirecionamento HTTP para HTTPS
server {
    listen 80;
    server_name $domain;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

# Configuração HTTPS
server {
    listen 443 ssl http2;
    server_name $domain;

    # Certificados SSL
    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;

    # Configurações SSL recomendadas
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;

    # OCSP Stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_trusted_certificate /etc/letsencrypt/live/$domain/chain.pem;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;

    # Headers de segurança
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Logs
    access_log /var/log/nginx/$domain-access.log;
    error_log /var/log/nginx/$domain-error.log;

    # Tamanho máximo de upload
    client_max_body_size 10M;

EOF
        
        # Adiciona configuração baseada no tipo
        if [ "$config_type" = "api" ]; then
            # Configuração para API com proxy reverso
            cat <<EOF
    # Proxy reverso para API
    location $proxy_path {
        proxy_pass $proxy_url;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
EOF
            if [ -n "$proxy_headers" ]; then
                echo "        $proxy_headers"
            fi
            echo "    }"
            
        elif [ "$config_type" = "front" ]; then
            # Configuração para front estático
            cat <<EOF
    # Raiz dos arquivos estáticos
    root $static_root;
    index index.html index.htm;

    # Cache para arquivos estáticos (imagens, CSS, JS, fonts)
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
EOF
            
            # Se precisa de proxy reverso parcial (para API do front)
            if [ "$needs_proxy" = true ]; then
                cat <<EOF

    # Proxy reverso para API (parcial)
    location $proxy_path {
        proxy_pass $proxy_url;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
EOF
                if [ -n "$proxy_headers" ]; then
                    echo "        $proxy_headers"
                fi
                echo "    }"
            fi
            
            # Servir arquivos estáticos (SPA support)
            cat <<EOF

    # Servir arquivos estáticos (SPA support)
    location / {
        try_files \$uri \$uri/ /index.html;
    }
EOF
        fi
        
        # Adiciona gzip compression
        cat <<EOF

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/xml+rss application/json application/javascript;
}
EOF
    } > "$temp_file"
    
    # Copia o arquivo temporário para o destino
    sudo cp "$temp_file" "$output_file"
    rm "$temp_file"
}

# Função para obter certificado SSL com tratamento de erros
# Esta função é segura para usar em instâncias com múltiplas aplicações usando certbot
obtain_ssl_certificate() {
    local domain=$1
    local email=$2
    
    # Verifica se já existe um certificado válido para este domínio
    echo "🔍 Verificando se já existe certificado válido para $domain..."
    if sudo certbot certificates 2>/dev/null | grep -q "Certificate Name: $domain"; then
        local cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"
        if [ -f "$cert_path" ]; then
            # Verifica se o certificado é válido (não expirado)
            local expiry_date=$(sudo openssl x509 -enddate -noout -in "$cert_path" 2>/dev/null | cut -d= -f2)
            if [ -n "$expiry_date" ]; then
                local expiry_timestamp=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry_date" +%s 2>/dev/null || echo "0")
                local current_timestamp=$(date +%s)
                if [ "$expiry_timestamp" -gt "$current_timestamp" ]; then
                    echo -e "${GREEN}✓ Certificado válido já existe para $domain${NC}"
                    echo "   Reutilizando certificado existente..."
                    return 0
                else
                    echo "⚠️  Certificado existente está expirado. Criando novo..."
                fi
            fi
        fi
    fi
    
    echo "🧹 Limpando apenas tentativas pendentes para $domain..."
    # Limpa apenas autorizações pendentes deste domínio específico (não deleta certificados válidos)
    # Remove apenas arquivos de autorização pendente que podem causar erro "No such authorization"
    sudo find /var/lib/letsencrypt -name "*$domain*" -type f -delete 2>/dev/null || true
    
    # Limpa diretórios de autorizações pendentes apenas para este domínio
    # CUIDADO: Não remove certificados válidos, apenas tentativas pendentes
    if [ -d "/var/lib/letsencrypt/archive/$domain" ]; then
        # Verifica se há certificado válido antes de limpar
        if [ ! -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]; then
            echo "   Removendo tentativas pendentes de $domain..."
            sudo rm -rf /var/lib/letsencrypt/archive/"$domain" 2>/dev/null || true
            sudo rm -rf /var/lib/letsencrypt/live/"$domain" 2>/dev/null || true
            sudo rm -rf /var/lib/letsencrypt/renewal/"$domain".conf 2>/dev/null || true
        fi
    fi
    
    echo "🔒 Tentando obter certificado SSL com modo nginx..."
    # Tenta primeiro com modo nginx (preferencial quando nginx está rodando)
    if sudo certbot certonly --nginx \
        --non-interactive \
        --agree-tos \
        --email "$email" \
        -d "$domain" 2>&1; then
        echo -e "${GREEN}✓ Certificado obtido com sucesso usando modo nginx${NC}"
        return 0
    fi
    
    echo "⚠️  Modo nginx falhou. Tentando modo standalone..."
    echo "🛑 Parando nginx temporariamente para liberar porta 80..."
    echo "   (Isso não afeta outras aplicações que já têm certificados válidos)"
    
    # Para o nginx temporariamente
    sudo systemctl stop nginx || true
    
    # Aguarda um pouco para garantir que a porta foi liberada
    sleep 2
    
    # Verifica se a porta 80 está livre
    if sudo lsof -i :80 >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Porta 80 ainda está em uso. Aguardando mais um pouco...${NC}"
        sleep 3
    fi
    
    # Tenta com modo standalone
    if sudo certbot certonly --standalone \
        --non-interactive \
        --agree-tos \
        --email "$email" \
        -d "$domain" \
        --preferred-challenges http 2>&1; then
        echo -e "${GREEN}✓ Certificado obtido com sucesso usando modo standalone${NC}"
        echo "🔄 Reiniciando nginx..."
        sudo systemctl start nginx || true
        # Aguarda nginx iniciar antes de continuar
        sleep 2
        return 0
    else
        echo -e "${RED}❌ Falha ao obter certificado SSL${NC}"
        echo "🔄 Reiniciando nginx..."
        sudo systemctl start nginx || true
        sleep 2
        return 1
    fi
}

# ============================================
# INÍCIO DO SCRIPT
# ============================================

echo "🔐 Configurando SSL com Certbot"
echo "================================"
echo ""

# Coleta informações interativamente
prompt_domain
prompt_email
prompt_config_type

# Configurações específicas baseadas no tipo
if [ "$CONFIG_TYPE" = "front" ]; then
    prompt_static_root
    prompt_build_path
    
    # Pergunta se precisa de proxy reverso para API
    while true; do
        read -p "Precisa de proxy reverso para API? (s/n) [padrão: n]: " needs_proxy_choice
        needs_proxy_choice=${needs_proxy_choice:-n}
        case $needs_proxy_choice in
            [Ss]*)
                NEEDS_REVERSE_PROXY=true
                prompt_reverse_proxy
                break
                ;;
            [Nn]*)
                NEEDS_REVERSE_PROXY=false
                break
                ;;
            *)
                echo -e "${RED}❌ Digite 's' para sim ou 'n' para não.${NC}"
                ;;
        esac
    done
elif [ "$CONFIG_TYPE" = "api" ]; then
    # API sempre precisa de proxy reverso
    NEEDS_REVERSE_PROXY=true
    prompt_reverse_proxy
fi

echo ""
echo "================================"
echo "Resumo da configuração:"
echo "  Domínio: $DOMAIN"
echo "  Email: $EMAIL"
echo "  Tipo: $CONFIG_TYPE"
if [ "$CONFIG_TYPE" = "front" ]; then
    echo "  Diretório estático: $STATIC_ROOT"
    echo "  Diretório de build: $BUILD_PATH"
fi
if [ "$NEEDS_REVERSE_PROXY" = true ]; then
    echo "  Proxy reverso: $PROXY_URL"
    echo "  Caminho: $PROXY_PATH"
fi
echo "================================"
echo ""

read -p "Continuar com a configuração? (s/n): " confirm
if [[ ! $confirm =~ ^[Ss]$ ]]; then
    echo "Operação cancelada."
    exit 0
fi

# Verifica se o certbot está instalado
if ! command -v certbot &> /dev/null; then
    echo "❌ Certbot não está instalado. Instalando..."
    sudo apt-get update
    sudo apt-get install -y certbot python3-certbot-nginx
fi

# Verifica se o nginx está instalado
if ! command -v nginx &> /dev/null; then
    echo "❌ Nginx não está instalado. Por favor, instale o nginx primeiro."
    exit 1
fi

# Cria o diretório de sites-available se não existir
if [ ! -d "$NGINX_SITES_AVAILABLE" ]; then
    echo "❌ Diretório $NGINX_SITES_AVAILABLE não existe."
    exit 1
fi

# Cria o diretório para arquivos estáticos e symlinks do build se necessário
if [ "$CONFIG_TYPE" = "front" ]; then
    # Converte caminhos para absolutos (com verificação de segurança)
    if [ -d "$BUILD_PATH" ]; then
        BUILD_PATH_ABS=$(cd "$BUILD_PATH" && pwd)
    else
        BUILD_PATH_ABS="$BUILD_PATH"
    fi
    STATIC_ROOT_ABS=$(cd "$(dirname "$STATIC_ROOT")" && pwd)/$(basename "$STATIC_ROOT")
    
    # Garante permissões adequadas no diretório pai do STATIC_ROOT
    STATIC_ROOT_PARENT=$(dirname "$STATIC_ROOT_ABS")
    if [ -d "$STATIC_ROOT_PARENT" ]; then
        sudo chmod 755 "$STATIC_ROOT_PARENT" 2>/dev/null || true
    fi
    
    if [ ! -d "$STATIC_ROOT" ]; then
        echo "📁 Criando diretório para arquivos estáticos: $STATIC_ROOT"
        sudo mkdir -p "$STATIC_ROOT"
        sudo chmod 755 "$STATIC_ROOT"
        sudo chown -R www-data:www-data "$STATIC_ROOT"
    else
        # Garante permissões adequadas mesmo se o diretório já existir
        sudo chmod 755 "$STATIC_ROOT"
    fi
    
    # Cria symlinks do conteúdo do build para o STATIC_ROOT
    echo "🔗 Criando symlinks do build para o diretório estático..."
    if [ -d "$BUILD_PATH" ] && [ -n "$(ls -A "$BUILD_PATH" 2>/dev/null)" ]; then
        # Corrige permissões do BUILD_PATH ANTES de criar os symlinks
        # Isso garante que o nginx possa ler os arquivos originais através dos symlinks
        fix_build_path_permissions "$BUILD_PATH_ABS"
        
        # Usa cp -rs para criar symlinks recursivos (GNU coreutils)
        # Se cp não suportar -rs, usa método alternativo com find + ln -s
        if cp --help 2>/dev/null | grep -q "\-s"; then
            sudo cp -rs "$BUILD_PATH_ABS"/* "$STATIC_ROOT_ABS/" 2>/dev/null || {
                # Método alternativo: criar symlinks manualmente
                echo "   Usando método alternativo para criar symlinks..."
                for item in "$BUILD_PATH_ABS"/*; do
                    if [ -e "$item" ]; then
                        item_name=$(basename "$item")
                        sudo ln -sf "$item" "$STATIC_ROOT_ABS/$item_name"
                    fi
                done
            }
        else
            # Método alternativo para sistemas sem cp -rs
            echo "   Usando método alternativo para criar symlinks..."
            for item in "$BUILD_PATH_ABS"/*; do
                if [ -e "$item" ]; then
                    item_name=$(basename "$item")
                    sudo ln -sf "$item" "$STATIC_ROOT_ABS/$item_name"
                fi
            done
        fi
        
        # Garante permissões adequadas no STATIC_ROOT (para os symlinks)
        sudo chmod 755 "$STATIC_ROOT_ABS"
        sudo chown -R www-data:www-data "$STATIC_ROOT_ABS"
        echo -e "${GREEN}✓ Symlinks criados com sucesso${NC}"
    else
        echo -e "${YELLOW}⚠️  Diretório de build vazio ou não encontrado. Symlinks não foram criados.${NC}"
        echo -e "${YELLOW}   Você pode criar os symlinks manualmente depois.${NC}"
    fi
fi

# Cria o virtual host temporário para validação do certbot
echo "📝 Criando configuração temporária do nginx para validação..."
generate_temp_nginx_config "$DOMAIN"

# Cria link simbólico se não existir
if [ ! -L "$NGINX_SITES_ENABLED/$DOMAIN" ]; then
    sudo ln -s "$NGINX_SITES_AVAILABLE/$DOMAIN" "$NGINX_SITES_ENABLED/$DOMAIN"
fi

# Testa configuração do nginx
echo "🧪 Testando configuração do nginx..."
if ! sudo nginx -t; then
    echo "❌ Erro na configuração do nginx. Corrija antes de continuar."
    exit 1
fi

# Reinicia nginx
echo "🔄 Reiniciando nginx..."
sudo systemctl reload nginx

# Gera o certificado SSL usando certbot
# A função obtain_ssl_certificate é segura para usar com múltiplas aplicações
echo "🔒 Gerando certificado SSL com certbot..."
if ! obtain_ssl_certificate "$DOMAIN" "$EMAIL"; then
    echo -e "${RED}❌ Não foi possível obter o certificado SSL. Verifique os logs acima.${NC}"
    echo ""
    echo "💡 Dicas para resolver o problema:"
    echo "   1. Verifique se o DNS aponta corretamente para este servidor"
    echo "   2. Verifique se a porta 80 está acessível externamente"
    echo "   3. Verifique os logs: sudo tail -f /var/log/letsencrypt/letsencrypt.log"
    echo "   4. Se houver rate limit do Let's Encrypt, aguarde algumas horas"
    exit 1
fi

# Atualiza o virtual host com configuração completa SSL
echo "📝 Atualizando configuração do nginx com SSL..."
generate_nginx_config "$DOMAIN" "$CONFIG_TYPE" "$STATIC_ROOT" "$NEEDS_REVERSE_PROXY" "$PROXY_URL" "$PROXY_PATH" "$PROXY_HEADERS" "$NGINX_SITES_AVAILABLE/$DOMAIN"

# Testa configuração do nginx novamente
echo "🧪 Testando nova configuração do nginx..."
if ! sudo nginx -t; then
    echo "❌ Erro na configuração do nginx."
    exit 1
fi

# Reinicia nginx
echo "🔄 Reiniciando nginx com nova configuração..."
sudo systemctl reload nginx

echo ""
echo "✅ SSL configurado com sucesso para $DOMAIN!"
echo ""
echo "📋 Próximos passos:"
echo "   1. Verifique se o DNS aponta para este servidor"
if [ "$CONFIG_TYPE" = "front" ]; then
    echo "   2. Symlinks dos arquivos estáticos criados de $BUILD_PATH para $STATIC_ROOT"
    echo "   3. Certifique-se de que o arquivo index.html existe em $STATIC_ROOT"
fi
if [ "$CONFIG_TYPE" = "api" ] || [ "$NEEDS_REVERSE_PROXY" = true ]; then
    echo "   2. Certifique-se de que o backend está rodando em: $PROXY_URL"
fi
echo "   4. Acesse https://$DOMAIN para testar"
echo "   5. O certificado será renovado automaticamente via cron"
echo ""

if [ "$CONFIG_TYPE" = "front" ]; then
    echo "📁 Para atualizar os symlinks após novo build:"
    echo "   sudo rm -rf $STATIC_ROOT/*"
    echo "   sudo cp -rs $BUILD_PATH/* $STATIC_ROOT/ || sudo find $BUILD_PATH -mindepth 1 -maxdepth 1 -exec ln -sf {} $STATIC_ROOT/ \\;"
    echo "   sudo chown -R www-data:www-data $STATIC_ROOT"
    echo ""
fi

echo "🔍 Para verificar o certificado:"
echo "   sudo certbot certificates"
echo ""
echo "🔄 Para renovar manualmente:"
echo "   sudo certbot renew"
