#!/usr/bin/env bash
# =============================================================================
# CORE - Initial SSL Certificate Setup
# =============================================================================
# Run this once on the server to get the initial Let's Encrypt certificate.
#
# Usage:
#   DOMAIN=core.example.com EMAIL=admin@example.com ./scripts/setup-ssl.sh
# =============================================================================

set -euo pipefail

DOMAIN="${DOMAIN:?Set DOMAIN environment variable}"
EMAIL="${EMAIL:-admin@${DOMAIN}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

cd "$PROJECT_DIR"

# Replace domain placeholder in nginx config
sed -i "s/DOMAIN_PLACEHOLDER/${DOMAIN}/g" nginx/conf.d/core.conf

log "Step 1: Starting temporary HTTP-only nginx for ACME challenge..."

# Create temporary nginx config
cat > nginx/conf.d/temp-acme.conf << TEMP
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    location /health {
        return 200 'ok';
        add_header Content-Type text/plain;
    }

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 200 'SSL setup in progress...';
        add_header Content-Type text/plain;
    }
}
TEMP

# Move SSL config temporarily
mv nginx/conf.d/core.conf nginx/conf.d/core.conf.bak

# Start nginx only
docker compose --env-file .env.production up -d nginx
sleep 5

log "Step 2: Requesting SSL certificate..."
docker compose --env-file .env.production run --rm certbot \
    certbot certonly --webroot -w /var/www/certbot \
    --email "${EMAIL}" \
    --agree-tos --no-eff-email \
    -d "${DOMAIN}"

log "Step 3: Restoring full nginx config..."
mv nginx/conf.d/core.conf.bak nginx/conf.d/core.conf
rm -f nginx/conf.d/temp-acme.conf

# Restart nginx with SSL
docker compose --env-file .env.production down
docker compose --env-file .env.production up -d

log "SSL setup complete! CORE is running at https://${DOMAIN}"
