#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR=/var/backups/ufla-shop
mkdir -p "$BACKUP_DIR"
FILE="$BACKUP_DIR/loja-$(date +%F-%H%M).sql.gz"
TEMP=$(mktemp "$BACKUP_DIR/.loja-XXXXXX")
trap 'rm -f "$TEMP"' EXIT

pg_dump --dbname="${DATABASE_URL:-loja}" | gzip > "$TEMP"
mv -f -- "$TEMP" "$FILE"

# O nome contém data e hora em ordem cronológica; a ordenação reversa põe
# os sete arquivos mais recentes primeiro.
mapfile -t dumps < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'loja-*.sql.gz' -printf '%f\n' | sort -r)
for ((i=7; i<${#dumps[@]}; i++)); do
    rm -f -- "$BACKUP_DIR/${dumps[$i]}"
done

logger -t backup "Arquivo gerado: $FILE; tamanho: $(stat -c %s "$FILE") bytes"
