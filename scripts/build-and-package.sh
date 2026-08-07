#!/bin/bash

# Script para fazer build de front-end e empacotar em ZIP
# Requisitos: npm ou yarn instalado, zip instalado
# Uso: ./build-and-package.sh [opções]

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variáveis
PROJECT_DIR="."
BUILD_DIR="dist"
OUTPUT_ZIP=""
PACKAGE_MANAGER=""
SKIP_BUILD=false
CLEAN_BUILD=true
KEEP_BUILD_DIR=false

# Função de ajuda
show_help() {
    echo "Uso: $0 [opções]"
    echo ""
    echo "Executa o build de um front-end e empacota em um arquivo ZIP."
    echo ""
    echo "Opções:"
    echo "  -d, --dir <diretorio>     Diretório do projeto (padrão: diretório atual)"
    echo "  -b, --build-dir <dir>     Diretório de build (padrão: dist)"
    echo "  -o, --output <arquivo>    Nome do arquivo ZIP de saída"
    echo "  -m, --manager <npm|yarn>  Força uso de npm ou yarn (padrão: auto-detecta)"
    echo "  --skip-build              Pula o build e apenas empacota o diretório existente"
    echo "  --no-clean                Não limpa o diretório de build antes de construir"
    echo "  --keep-build-dir           Mantém o diretório de build após criar o ZIP"
    echo "  -h, --help                Mostra esta ajuda"
    echo ""
    echo "Exemplos:"
    echo "  $0"
    echo "  $0 -d ./meu-projeto -o build.zip"
    echo "  $0 --build-dir build --output app-production.zip"
    echo "  $0 -m yarn --skip-build"
    echo "  $0 --no-clean --keep-build-dir"
}

# Função para verificar dependências
check_dependencies() {
    local missing=()
    
    if ! command -v zip &> /dev/null; then
        missing+=("zip")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}❌ Dependências não encontradas: ${missing[*]}${NC}"
        echo "Instale com:"
        echo "  sudo apt-get install -y zip"
        exit 1
    fi
}

# Função para detectar gerenciador de pacotes
detect_package_manager() {
    if [ -n "$PACKAGE_MANAGER" ]; then
        if [ "$PACKAGE_MANAGER" != "npm" ] && [ "$PACKAGE_MANAGER" != "yarn" ]; then
            echo -e "${RED}❌ Gerenciador inválido: $PACKAGE_MANAGER (use npm ou yarn)${NC}"
            exit 1
        fi
        return 0
    fi
    
    # Verifica se existe yarn.lock
    if [ -f "$PROJECT_DIR/yarn.lock" ]; then
        PACKAGE_MANAGER="yarn"
        return 0
    fi
    
    # Verifica se existe package-lock.json
    if [ -f "$PROJECT_DIR/package-lock.json" ]; then
        PACKAGE_MANAGER="npm"
        return 0
    fi
    
    # Tenta detectar pelo comando disponível
    if command -v yarn &> /dev/null; then
        PACKAGE_MANAGER="yarn"
    elif command -v npm &> /dev/null; then
        PACKAGE_MANAGER="npm"
    else
        echo -e "${RED}❌ Nenhum gerenciador de pacotes encontrado (npm ou yarn)${NC}"
        exit 1
    fi
}

# Função para verificar se o gerenciador está instalado
check_package_manager() {
    if [ "$PACKAGE_MANAGER" = "yarn" ]; then
        if ! command -v yarn &> /dev/null; then
            echo -e "${RED}❌ Yarn não está instalado${NC}"
            echo "Instale com: npm install -g yarn"
            exit 1
        fi
    elif [ "$PACKAGE_MANAGER" = "npm" ]; then
        if ! command -v npm &> /dev/null; then
            echo -e "${RED}❌ NPM não está instalado${NC}"
            exit 1
        fi
    fi
}

# Função para executar build
run_build() {
    local project_dir=$1
    local build_dir=$2
    
    echo -e "${BLUE}📦 Executando build com $PACKAGE_MANAGER...${NC}"
    
    cd "$project_dir"
    
    # Limpa build anterior se necessário
    if [ "$CLEAN_BUILD" = true ] && [ -d "$build_dir" ]; then
        echo -e "${YELLOW}🧹 Limpando build anterior...${NC}"
        rm -rf "$build_dir"
    fi
    
    # Executa o build
    if [ "$PACKAGE_MANAGER" = "yarn" ]; then
        yarn build
    else
        npm run build
    fi
    
    # Verifica se o build foi criado
    if [ ! -d "$build_dir" ]; then
        echo -e "${RED}❌ Diretório de build não foi criado: $build_dir${NC}"
        echo "Verifique se o script de build está configurado corretamente no package.json"
        exit 1
    fi
    
    # Verifica se o build não está vazio
    if [ -z "$(ls -A "$build_dir" 2>/dev/null)" ]; then
        echo -e "${RED}❌ Diretório de build está vazio${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Build concluído com sucesso${NC}"
}

# Função para criar arquivo ZIP
create_zip() {
    local build_dir=$1
    local output_file=$2
    local project_dir=$3
    
    echo ""
    echo -e "${BLUE}📦 Criando arquivo ZIP...${NC}"
    
    # Gera nome do arquivo se não foi especificado
    if [ -z "$output_file" ]; then
        local project_name=$(basename "$project_dir")
        local timestamp=$(date +%Y%m%d-%H%M%S)
        output_file="${project_name}-build-${timestamp}.zip"
    fi
    
    # Garante que o caminho do arquivo é absoluto ou relativo ao diretório atual
    if [[ "$output_file" != /* ]]; then
        output_file="$(pwd)/$output_file"
    fi
    
    # Remove arquivo ZIP existente se houver
    if [ -f "$output_file" ]; then
        echo -e "${YELLOW}⚠️  Arquivo ZIP já existe. Removendo...${NC}"
        rm -f "$output_file"
    fi
    
    # Cria o ZIP
    # Entra no diretório de build para zipar o conteúdo, não o diretório em si
    cd "$project_dir/$build_dir"
    zip -r "$output_file" . -q
    cd "$project_dir"
    
    if [ ! -f "$output_file" ]; then
        echo -e "${RED}❌ Falha ao criar arquivo ZIP${NC}"
        exit 1
    fi
    
    # Obtém tamanho do arquivo
    local file_size=$(du -h "$output_file" | cut -f1)
    
    echo -e "${GREEN}✓ Arquivo ZIP criado: $output_file${NC}"
    echo -e "${BLUE}   Tamanho: $file_size${NC}"
    
    # Lista alguns arquivos incluídos
    echo ""
    echo "📄 Arquivos incluídos (primeiros 10):"
    unzip -l "$output_file" | head -13 | tail -10 | awk '{print "   " $4}'
    
    local total_files=$(unzip -l "$output_file" | tail -1 | awk '{print $2}')
    echo "   ... total de $total_files arquivos"
    
    # Remove diretório de build se não deve ser mantido
    if [ "$KEEP_BUILD_DIR" = false ]; then
        echo ""
        echo -e "${YELLOW}🧹 Removendo diretório de build...${NC}"
        rm -rf "$build_dir"
        echo -e "${GREEN}✓ Diretório de build removido${NC}"
    fi
    
    echo "$output_file"
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
        -d|--dir)
            PROJECT_DIR="$2"
            shift 2
            ;;
        -b|--build-dir)
            BUILD_DIR="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_ZIP="$2"
            shift 2
            ;;
        -m|--manager)
            PACKAGE_MANAGER="$2"
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --no-clean)
            CLEAN_BUILD=false
            shift
            ;;
        --keep-build-dir)
            KEEP_BUILD_DIR=true
            shift
            ;;
        -*)
            echo -e "${RED}❌ Opção desconhecida: $1${NC}"
            show_help
            exit 1
            ;;
        *)
            echo -e "${RED}❌ Argumento inesperado: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

echo "🔨 Build e Empacotamento de Front-end"
echo "======================================"
echo ""

# Verifica dependências
check_dependencies

# Expande caminhos relativos
PROJECT_DIR=$(cd "$PROJECT_DIR" && pwd)

# Verifica se o diretório do projeto existe
if [ ! -d "$PROJECT_DIR" ]; then
    echo -e "${RED}❌ Diretório do projeto não encontrado: $PROJECT_DIR${NC}"
    exit 1
fi

# Verifica se existe package.json
if [ ! -f "$PROJECT_DIR/package.json" ]; then
    echo -e "${RED}❌ package.json não encontrado em: $PROJECT_DIR${NC}"
    exit 1
fi

echo "📁 Diretório do projeto: $PROJECT_DIR"
echo "📁 Diretório de build: $BUILD_DIR"
[ -n "$OUTPUT_ZIP" ] && echo "📦 Arquivo ZIP: $OUTPUT_ZIP"
echo ""

# Detecta gerenciador de pacotes
detect_package_manager
check_package_manager

echo -e "${GREEN}✓ Gerenciador detectado: $PACKAGE_MANAGER${NC}"
echo ""

# Executa build se necessário
if [ "$SKIP_BUILD" = false ]; then
    run_build "$PROJECT_DIR" "$BUILD_DIR"
else
    echo -e "${YELLOW}⏭️  Pulando build (usando diretório existente)${NC}"
    
    # Verifica se o diretório de build existe
    if [ ! -d "$PROJECT_DIR/$BUILD_DIR" ]; then
        echo -e "${RED}❌ Diretório de build não encontrado: $PROJECT_DIR/$BUILD_DIR${NC}"
        exit 1
    fi
    
    if [ -z "$(ls -A "$PROJECT_DIR/$BUILD_DIR" 2>/dev/null)" ]; then
        echo -e "${RED}❌ Diretório de build está vazio${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Diretório de build encontrado${NC}"
fi

# Cria arquivo ZIP
ZIP_FILE=$(create_zip "$BUILD_DIR" "$OUTPUT_ZIP" "$PROJECT_DIR")

echo ""
echo -e "${GREEN}✅ Processo concluído com sucesso!${NC}"
echo ""
echo "📦 Arquivo ZIP criado:"
echo "   $ZIP_FILE"
echo ""
echo "💡 Você pode usar este arquivo para:"
echo "   - Deploy em servidor"
echo "   - Backup do build"
echo "   - Distribuição para outros ambientes"
