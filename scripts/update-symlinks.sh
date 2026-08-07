#!/bin/bash
# Script para atualizar symlinks após git pull
# Uso: ./update-symlinks.sh <build-path> <static-root>

set -e

BUILD_PATH="$1"
STATIC_ROOT="$2"

if [ -z "$BUILD_PATH" ] || [ -z "$STATIC_ROOT" ]; then
    echo "Uso: $0 <build-path> <static-root>"
    exit 1
fi

# Expande caminhos
BUILD_PATH=$(cd "$BUILD_PATH" && pwd)
STATIC_ROOT=$(cd "$(dirname "$STATIC_ROOT")" && pwd)/$(basename "$STATIC_ROOT")

echo "🔄 Atualizando symlinks..."
echo "Build: $BUILD_PATH"
echo "Static: $STATIC_ROOT"

# Remove symlinks antigos
sudo rm -rf "$STATIC_ROOT"/*

# Cria novos symlinks
sudo cp -rs "$BUILD_PATH"/* "$STATIC_ROOT/" 2>/dev/null || {
    for item in "$BUILD_PATH"/*; do
        [ -e "$item" ] && sudo ln -sf "$item" "$STATIC_ROOT/$(basename "$item")"
    done
}

# Permissões
sudo chown -R www-data:www-data "$STATIC_ROOT"
sudo chmod 755 "$STATIC_ROOT"

# Recarrega nginx
sudo nginx -t && sudo systemctl reload nginx

echo "✅ Symlinks atualizados!"