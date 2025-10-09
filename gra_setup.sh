#!/usr/bin/env bash
set -Eeuo pipefail
# ── GRA Setup Quick Bootstrap (for gratech.sa) ────────────────
echo "[GRA] Starting full setup..."
ROOT="/opt/gratech"
DOMAIN="gratech.sa"
EMAIL="admin@gratech.sa"

mkdir -p "$ROOT"/{nginx/conf.d,certbot/{www,conf}}
cat > "$ROOT/nginx/conf.d/gratech.http.conf" <<'NGX'
server {
  listen 80;
  server_name gratech.sa www.gratech.sa;
  location ^~ /.well-known/acme-challenge/ {
    root /var/www/certbot;
    default_type "text/plain";
    try_files $uri =404;
  }
  location / {
    return 200 "GRA gateway: ACME in progress\n";
    add_header Content-Type text/plain;
  }
}
NGX

cat > "$ROOT/docker-compose.yml" <<'YML'
services:
  nginx:
    image: nginx:1.25-alpine
    container_name: nginx_gateway
    ports: ["80:80","443:443"]
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./certbot/www:/var/www/certbot
      - ./certbot/conf:/etc/letsencrypt
    restart: always
YML

if command -v docker >/dev/null 2>&1; then
  docker compose -f "$ROOT/docker-compose.yml" up -d nginx || docker-compose -f "$ROOT/docker-compose.yml" up -d nginx
else
  echo "[GRA] Docker not found — created config only."
fi

echo "[GRA] Done. You can now request SSL using:"
echo "docker run --rm -v \"$ROOT/certbot/www:/var/www/certbot\" -v \"$ROOT/certbot/conf:/etc/letsencrypt\" certbot/certbot certonly --webroot -w /var/www/certbot --email $EMAIL -d $DOMAIN -d www.$DOMAIN --agree-tos --no-eff-email --rsa-key-size 4096"
