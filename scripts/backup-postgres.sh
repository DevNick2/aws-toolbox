#!/bin/bash
# Backup lógico do PostgreSQL em arquivo .zip (dump SQL via pg_dump, cliente inclui psql/pg_dump).
# Exige host, porta, usuário e banco; senha via PGPASSWORD ou prompt interativo.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PGHOST=""
PGPORT="5432"
PGUSER=""
PGDATABASE=""
BACKUP_DIR="./backups"

usage() {
    cat <<EOF
Uso:
  $(basename "$0") --host HOST --port PORTA --user USUARIO --database BANCO [--output-dir DIR]

Variáveis de ambiente úteis:
  PGPASSWORD   Senha (se vazia, o script pede sem ecoar no terminal)
  PGSSLMODE    Ex.: require, verify-full (para RDS, cloud, etc.)

O dump é gerado com pg_dump (mesma instalação de ferramentas que o psql) e compactado em .zip.

Exemplo:
  PGPASSWORD='***' $(basename "$0") --host db.exemplo.com --port 5432 --user app --database appdb
EOF
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo -e "${RED}Erro: comando '$1' não encontrado no PATH.${NC}" >&2
        exit 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)
            PGHOST="${2:?}"
            shift 2
            ;;
        --port)
            PGPORT="${2:?}"
            shift 2
            ;;
        --user)
            PGUSER="${2:?}"
            shift 2
            ;;
        --database)
            PGDATABASE="${2:?}"
            shift 2
            ;;
        --output-dir)
            BACKUP_DIR="${2:?}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Opção desconhecida: $1${NC}" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -z "$PGHOST" || -z "$PGUSER" || -z "$PGDATABASE" ]]; then
    echo -e "${RED}Erro: --host, --user e --database são obrigatórios.${NC}" >&2
    usage >&2
    exit 1
fi

require_cmd pg_dump
require_cmd zip

mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
SQL_TMP="${BACKUP_DIR}/.postgres_backup_${TIMESTAMP}_$$.sql"
ZIP_OUT="${BACKUP_DIR}/postgres_backup_${TIMESTAMP}.zip"

echo -e "${GREEN}=== Backup PostgreSQL → ZIP ===${NC}"
echo ""
echo -e "${GREEN}Conexão:${NC}"
echo "  Host:     $PGHOST"
echo "  Porta:    $PGPORT"
echo "  Usuário:  $PGUSER"
echo "  Banco:    $PGDATABASE"
echo "  Destino:  $ZIP_OUT"
echo ""

if [[ -z "${PGPASSWORD:-}" ]]; then
    read -rsp "Senha para o usuário '$PGUSER' (Enter se vazio): " PGPASSWORD
    echo ""
    export PGPASSWORD
else
    export PGPASSWORD
fi

echo -e "${YELLOW}Gerando dump SQL...${NC}"

pg_dump \
    -h "$PGHOST" \
    -p "$PGPORT" \
    -U "$PGUSER" \
    -d "$PGDATABASE" \
    --verbose \
    --clean \
    --if-exists \
    --create \
    --format=plain \
    --encoding=UTF8 \
    --no-owner \
    --no-privileges \
    -f "$SQL_TMP"

if [[ ! -s "$SQL_TMP" ]]; then
    echo -e "${RED}Erro: dump vazio ou arquivo não foi criado.${NC}" >&2
    exit 1
fi

echo -e "${YELLOW}Compactando em ZIP...${NC}"
if ! ( cd "$BACKUP_DIR" && zip -q -j "$ZIP_OUT" "$(basename "$SQL_TMP")" ); then
    echo -e "${RED}Erro ao criar o arquivo ZIP (dump SQL preservado em: $SQL_TMP).${NC}" >&2
    exit 1
fi

rm -f "$SQL_TMP"

unset PGPASSWORD

echo ""
echo -e "${GREEN}=== Backup concluído ===${NC}"
echo "  Arquivo: $ZIP_OUT"
echo "  Tamanho: $(du -h "$ZIP_OUT" | cut -f1)"
echo ""
echo -e "${YELLOW}Conteúdo do ZIP:${NC} um script SQL (pg_dump) com estrutura e dados."
echo -e "${YELLOW}Restaurar (exemplo):${NC} descompacte e execute com psql contra o banco alvo, ou:"
echo "  unzip -p \"$ZIP_OUT\" | psql -h HOST -p PORTA -U USUARIO -d postgres"
echo ""
