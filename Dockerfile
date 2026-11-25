# Portal web de erp.cerice360.com (rama cerice360-web). Coolify construye desde este archivo.
# La web se compila antes con scripts/publicar-cerice360.sh (Flutter no cabe en el disco del servidor
# dentro de Docker); aquí solo se sirve la carpeta publicado/web con nginx.
FROM nginx:alpine
RUN printf '%s\n' \
  'server {' \
  '  listen 80;' \
  '  server_name _;' \
  '  root /usr/share/nginx/html;' \
  '  index index.html;' \
  '  gzip on;' \
  '  gzip_types text/plain text/css application/json application/javascript application/wasm;' \
  '  add_header X-Content-Type-Options nosniff always;' \
  '  add_header Referrer-Policy strict-origin-when-cross-origin always;' \
  '  # HTML, JS y manifiestos sin hash: siempre se revalidan para que un despliegue nuevo no mezcle versiones.' \
  '  location ~* \.(?:html|js|json|mjs)$ {' \
  '    expires -1;' \
  '    try_files $uri =404;' \
  '  }' \
  '  location / {' \
  '    expires -1;' \
  '    try_files $uri $uri/ /index.html;' \
  '  }' \
  '}' > /etc/nginx/conf.d/default.conf
COPY publicado/web /usr/share/nginx/html
EXPOSE 80
