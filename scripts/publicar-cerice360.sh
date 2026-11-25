#!/usr/bin/env bash
# Compila el portal web y lo deja en publicado/web para que Coolify (rama cerice360-web) lo sirva.
# Uso: scripts/publicar-cerice360.sh   (luego: git add publicado && git commit && git push, y redesplegar en Coolify)
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(git branch --show-current)" = cerice360-web ] || { echo "Usar en la rama cerice360-web"; exit 1; }
flutter analyze --no-fatal-infos
flutter build web --release
rm -rf publicado/web && mkdir -p publicado && cp -r build/web publicado/web
echo "Listo: publicado/web actualizado ($(du -sh publicado/web | cut -f1))."
