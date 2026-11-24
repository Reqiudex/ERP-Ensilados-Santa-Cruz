#!/usr/bin/env bash
# Levanta una base PostgreSQL local desechable, aplica todas las migraciones, los catálogos y el seed, y corre las
# pruebas de la auditoría. Requiere PostgreSQL 15+ instalado (initdb, pg_ctl, psql). No toca Supabase.
set -euo pipefail
raiz="$(cd "$(dirname "$0")/../.." && pwd)"
datos="$(mktemp -d)"; puerto="${PUERTO:-5544}"
initdb -D "$datos" -A trust -U postgres >/dev/null
pg_ctl -D "$datos" -o "-k /tmp -p $puerto" -l "$datos/pg.log" start >/dev/null
trap 'pg_ctl -D "$datos" stop >/dev/null; rm -rf "$datos"' EXIT
P="psql -h /tmp -p $puerto -U postgres -q -v ON_ERROR_STOP=1"
$P -c "create database erp"
$P -d erp -f "$raiz/scripts/verificacion/entorno_supabase_minimo.sql" 2>/dev/null
for f in $(ls "$raiz/supabase/migrations" | sort); do
  # pg_net y pg_cron no existen en un PostgreSQL común: el entorno mínimo trae sustitutos.
  sed -e '/create extension if not exists pg_net/d' -e '/create extension if not exists pg_cron/d' \
      -e '/drop extension if exists pg_net/d' -e '/create extension pg_net/d' "$raiz/supabase/migrations/$f" > /tmp/migracion.sql
  $P -d erp -1 -f /tmp/migracion.sql >/dev/null 2>&1 || { echo "FALLA la migración $f"; exit 1; }
done
echo "Migraciones aplicadas: $(ls "$raiz/supabase/migrations" | wc -l)"
$P -d erp -f "$raiz/supabase/catalogos_base.sql"
$P -d erp -f "$raiz/supabase/seed.sql" 2>&1 | grep -i "seed:" || true
echo "=== Ataques de la auditoría (todos deben fallar)"
psql -h /tmp -p "$puerto" -U postgres -d erp -f "$raiz/scripts/verificacion/ataques_auditoria.sql" 2>&1 \
  | grep -E "^===|ERROR|42501|pendiente_aprobacion|= |: (true|false)" | sed 's/^psql:[^:]*:[0-9]*: //'
echo "=== Flujo sin conexión (todo debe responder)"
psql -h /tmp -p "$puerto" -U postgres -d erp -f "$raiz/scripts/verificacion/flujo_sin_conexion.sql" 2>&1 \
  | grep -v "^$" | sed 's/^psql:[^:]*:[0-9]*: //'
