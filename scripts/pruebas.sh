#!/usr/bin/env bash
# Ejecuta los 27 casos de prueba (9 unitarios en Dart puro + 18 de caja negra contra Supabase en línea)
# y genera build/informes/resultados_pruebas.md. Uso: scripts/pruebas.sh
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/informes
tmp=$(mktemp -d)
dart test test/unitarias --reporter json > "$tmp/unitarias.json"; e1=$?
flutter test test/integracion --reporter json > "$tmp/integracion.json"; e2=$?
python3 scripts/informe_pruebas.py pruebas "$tmp/unitarias.json" "$tmp/integracion.json" > build/informes/resultados_pruebas.md
grep -E '^\*\*Resumen' build/informes/resultados_pruebas.md
rm -rf "$tmp"
exit $(( e1 || e2 ))
