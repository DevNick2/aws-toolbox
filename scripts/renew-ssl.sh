#!/bin/bash

# Script para renovar certificados SSL automaticamente
# Este script deve ser executado via cron (recomendado: diariamente)

set -e

DOMAIN="meu.site"

echo "🔄 Verificando renovação de certificado SSL para $DOMAIN..."

# Renova o certificado se necessário (certbot só renova se estiver próximo do vencimento)
sudo certbot renew --quiet --nginx

# Testa e recarrega nginx se a renovação foi bem-sucedida
if [ $? -eq 0 ]; then
    echo "✅ Certificado verificado/renovado com sucesso"
    sudo nginx -t && sudo systemctl reload nginx
    echo "✅ Nginx recarregado"
else
    echo "⚠️  Nenhuma renovação necessária ou erro na renovação"
    exit 1
fi

