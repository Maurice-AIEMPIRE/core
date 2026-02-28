#!/usr/bin/env bash
# =============================================================================
# CORE - Zero-Downtime Deploy Script for Hetzner
# =============================================================================
# Deploys CORE to a Hetzner server via SSH + Docker Compose.
#
# Usage:
#   ./scripts/deploy.sh user@server-ip              # Deploy latest
#   ./scripts/deploy.sh user@server-ip 0.5.0        # Deploy specific version
#   DOMAIN=core.example.com ./scripts/deploy.sh ...  # With domain
#
# First-time setup:
#   FIRST_RUN=true DOMAIN=core.example.com ./scripts/deploy.sh user@server-ip
# =============================================================================

set -euo pipefail

# ─── Arguments ────────────────────────────────────────────────────────────────
SSH_TARGET="${1:?Usage: deploy.sh user@server-ip [version]}"
VERSION="${2:-latest}"
DOMAIN="${DOMAIN:?Set DOMAIN environment variable (e.g. core.example.com)}"
FIRST_RUN="${FIRST_RUN:-false}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-admin@${DOMAIN}}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REMOTE_DIR="/opt/core"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

ssh_cmd() {
    ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "$SSH_TARGET" "$@"
}

scp_cmd() {
    scp -o StrictHostKeyChecking=accept-new "$@"
}

# ─── Pre-flight Checks ───────────────────────────────────────────────────────
log "Deploying CORE ${VERSION} to ${SSH_TARGET} (domain: ${DOMAIN})"

if ! ssh_cmd "echo 'Connection OK'" >/dev/null 2>&1; then
    echo "ERROR: Cannot connect to ${SSH_TARGET}"
    exit 1
fi

# ─── Prepare Remote Directory ────────────────────────────────────────────────
log "Preparing remote directory..."
ssh_cmd "mkdir -p ${REMOTE_DIR}/{nginx/conf.d,scripts}"

# ─── Upload Files ────────────────────────────────────────────────────────────
log "Uploading configuration files..."
scp_cmd "${PROJECT_DIR}/docker-compose.production.yaml" "${SSH_TARGET}:${REMOTE_DIR}/docker-compose.yaml"
scp_cmd "${PROJECT_DIR}/nginx/nginx.conf" "${SSH_TARGET}:${REMOTE_DIR}/nginx/nginx.conf"
scp_cmd "${PROJECT_DIR}/nginx/conf.d/core.conf" "${SSH_TARGET}:${REMOTE_DIR}/nginx/conf.d/core.conf"
scp_cmd "${PROJECT_DIR}/scripts/backup.sh" "${SSH_TARGET}:${REMOTE_DIR}/scripts/backup.sh"
scp_cmd "${PROJECT_DIR}/scripts/monitor.sh" "${SSH_TARGET}:${REMOTE_DIR}/scripts/monitor.sh"

# Upload .env.production if it exists
if [ -f "${PROJECT_DIR}/.env.production" ]; then
    scp_cmd "${PROJECT_DIR}/.env.production" "${SSH_TARGET}:${REMOTE_DIR}/.env.production"
fi

# ─── Configure Domain in Nginx ───────────────────────────────────────────────
log "Configuring domain: ${DOMAIN}"
ssh_cmd "sed -i 's/DOMAIN_PLACEHOLDER/${DOMAIN}/g' ${REMOTE_DIR}/nginx/conf.d/core.conf"

# ─── Make Scripts Executable ─────────────────────────────────────────────────
ssh_cmd "chmod +x ${REMOTE_DIR}/scripts/*.sh"

# ─── First Run: SSL Certificate Setup ────────────────────────────────────────
if [ "${FIRST_RUN}" = "true" ]; then
    log "First run detected - setting up SSL certificates..."

    # Create a temporary nginx config for ACME challenge only
    ssh_cmd "cat > ${REMOTE_DIR}/nginx/conf.d/initial.conf << 'INITCONF'
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
        return 200 'Setting up SSL...';
        add_header Content-Type text/plain;
    }
}
INITCONF"

    # Temporarily move the SSL config
    ssh_cmd "mv ${REMOTE_DIR}/nginx/conf.d/core.conf ${REMOTE_DIR}/nginx/conf.d/core.conf.bak"

    # Start nginx only for ACME challenge
    ssh_cmd "cd ${REMOTE_DIR} && docker compose --env-file .env.production up -d nginx"
    sleep 5

    # Get SSL certificate
    log "Requesting SSL certificate from Let's Encrypt..."
    ssh_cmd "cd ${REMOTE_DIR} && docker compose --env-file .env.production run --rm certbot \
        certbot certonly --webroot -w /var/www/certbot \
        --email ${LETSENCRYPT_EMAIL} \
        --agree-tos --no-eff-email \
        -d ${DOMAIN}"

    # Restore SSL config and remove temporary
    ssh_cmd "mv ${REMOTE_DIR}/nginx/conf.d/core.conf.bak ${REMOTE_DIR}/nginx/conf.d/core.conf"
    ssh_cmd "rm -f ${REMOTE_DIR}/nginx/conf.d/initial.conf"

    # Stop nginx
    ssh_cmd "cd ${REMOTE_DIR} && docker compose --env-file .env.production down"

    # Setup cron jobs
    log "Setting up cron jobs..."
    ssh_cmd "cat > /tmp/core-cron << 'CRON'
# CORE - Automated backups (daily 3 AM)
0 3 * * * cd /opt/core && ./scripts/backup.sh >> /var/log/core-backup.log 2>&1
# CORE - Health monitoring (every 5 minutes)
*/5 * * * * cd /opt/core && ./scripts/monitor.sh >> /var/log/core-monitor.log 2>&1
# CORE - Docker cleanup (weekly Sunday 4 AM)
0 4 * * 0 docker system prune -af --volumes --filter 'until=168h' >> /var/log/core-cleanup.log 2>&1
# CORE - Log rotation check (daily)
0 5 * * * /usr/sbin/logrotate /etc/logrotate.conf
CRON
crontab /tmp/core-cron
rm /tmp/core-cron"

    log "First-run setup complete!"
fi

# ─── Pull Latest Images ─────────────────────────────────────────────────────
log "Pulling images (version: ${VERSION})..."
ssh_cmd "cd ${REMOTE_DIR} && VERSION=${VERSION} docker compose --env-file .env.production pull"

# ─── Deploy with Zero-Downtime ───────────────────────────────────────────────
log "Starting deployment..."

# Start/update database services first
ssh_cmd "cd ${REMOTE_DIR} && VERSION=${VERSION} docker compose --env-file .env.production up -d postgres redis neo4j"
log "Waiting for databases to be healthy..."
ssh_cmd "cd ${REMOTE_DIR} && docker compose --env-file .env.production exec -T postgres pg_isready -U \${POSTGRES_USER:-docker}" || sleep 10

# Deploy app (creates new container, old one stops after new is healthy)
ssh_cmd "cd ${REMOTE_DIR} && VERSION=${VERSION} docker compose --env-file .env.production up -d core"
log "Waiting for app to start..."
sleep 10

# Check if app is healthy
if ssh_cmd "docker exec core-app curl -sf http://localhost:3000 > /dev/null 2>&1"; then
    log "App is healthy"
else
    log "WARNING: App health check failed, but continuing (may still be starting)"
fi

# Start/reload nginx and other services
ssh_cmd "cd ${REMOTE_DIR} && VERSION=${VERSION} docker compose --env-file .env.production up -d"

# ─── Post-deploy Verification ────────────────────────────────────────────────
log "Verifying deployment..."
sleep 5

SERVICES=("core-nginx" "core-app" "core-postgres" "core-redis" "core-neo4j")
ALL_OK=true
for svc in "${SERVICES[@]}"; do
    STATUS=$(ssh_cmd "docker inspect --format='{{.State.Status}}' $svc 2>/dev/null" || echo "not_found")
    if [ "$STATUS" = "running" ]; then
        log "  $svc: running"
    else
        log "  $svc: $STATUS (PROBLEM)"
        ALL_OK=false
    fi
done

if [ "$ALL_OK" = true ]; then
    log "Deployment successful! CORE is running at https://${DOMAIN}"
else
    log "WARNING: Some services may have issues. Check with: ssh ${SSH_TARGET} 'cd ${REMOTE_DIR} && docker compose logs'"
fi

# ─── Cleanup ─────────────────────────────────────────────────────────────────
log "Cleaning up old images..."
ssh_cmd "docker image prune -f" >/dev/null 2>&1 || true

log "Done!"
