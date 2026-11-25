# Portal web de erp.cerice360.com (rama cerice360-web). Coolify construye desde este archivo.
FROM debian:bookworm-slim AS compilar
ARG FLUTTER_VERSION=3.50.0
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    | tar -xJ -C /opt && git config --global --add safe.directory /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}"
RUN flutter --disable-analytics && flutter precache --web --no-android --no-ios --no-linux --no-windows --no-macos
WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY . .
RUN flutter build web --release

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
COPY --from=compilar /app/build/web /usr/share/nginx/html
EXPOSE 80
