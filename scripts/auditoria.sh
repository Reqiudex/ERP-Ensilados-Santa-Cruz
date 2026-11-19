#!/usr/bin/env bash
# Ejecuta las 11 pruebas de auditoría  por la API y, si existe SUPABASE_DB_URL, por SQL directo.
# Genera build/informes/resultados_auditoria.md. Uso: scripts/auditoria.sh
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/informes
tmp=$(mktemp -d)
flutter test test/auditoria --reporter json > "$tmp/auditoria.json"; e=$?
sql=""
if [ -n "${SUPABASE_DB_URL:-}" ] && command -v psql >/dev/null; then
  psql "$SUPABASE_DB_URL" -X -q -v ON_ERROR_STOP=1 -P pager=off -f scripts/auditoria_sql.sql > "$tmp/sql.txt" 2>&1 && sql="$tmp/sql.txt"
fi
python3 scripts/informe_pruebas.py auditoria "$tmp/auditoria.json" $sql > build/informes/resultados_auditoria.md
grep -E '^\*\*Resumen' build/informes/resultados_auditoria.md
rm -rf "$tmp"
exit $e
