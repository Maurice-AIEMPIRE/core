#!/usr/bin/env bash
# =============================================================================
# CORE - Hetzner Server Setup Script
# =============================================================================
# Dieses Script richtet CORE auf einem frischen Hetzner-Server (Ubuntu/Debian) ein.
#
# Verwendung:
#   curl -fsSL <raw-url>/setup.sh | bash
#   oder: bash setup.sh
#
# Voraussetzungen:
#   - Ubuntu 22.04+ oder Debian 12+
#   - Root-Zugriff
#   - Mindestens 8 GB RAM (empfohlen: 16 GB)
# =============================================================================

set -euo pipefail

# --- Konfiguration ---
INSTALL_DIR="/opt/core"
COMPOSE_VERSION="0.4.0"
DOMAIN=""  # Wird interaktiv abgefragt

# --- Farben ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${GREEN}[CORE]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# --- Root-Check ---
if [[ $EUID -ne 0 ]]; then
    error "Bitte als root ausführen: sudo bash setup.sh"
fi

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       CORE - Hetzner Server Setup            ║${NC}"
echo -e "${BLUE}║       Memory Agent + Actions for AI Tools    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# 1. System-Update & Abhängigkeiten
# =============================================================================
log "System wird aktualisiert..."
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    ufw \
    fail2ban \
    unattended-upgrades \
    apt-transport-https \
    software-properties-common

# =============================================================================
# 2. Docker installieren
# =============================================================================
if command -v docker &>/dev/null; then
    log "Docker ist bereits installiert: $(docker --version)"
else
    log "Docker wird installiert..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable docker
    systemctl start docker
    log "Docker installiert: $(docker --version)"
fi

# =============================================================================
# 3. Firewall konfigurieren
# =============================================================================
log "Firewall wird konfiguriert..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw allow 3033/tcp  # CORE App
ufw --force enable
log "Firewall aktiv (SSH, HTTP, HTTPS, 3033 offen)"

# =============================================================================
# 4. Fail2Ban aktivieren
# =============================================================================
log "Fail2Ban wird konfiguriert..."
systemctl enable fail2ban
systemctl start fail2ban

# =============================================================================
# 5. CORE-Verzeichnis erstellen
# =============================================================================
log "CORE wird in ${INSTALL_DIR} eingerichtet..."
mkdir -p "${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}/scripts"

# =============================================================================
# 6. Interaktive Konfiguration
# =============================================================================
echo ""
echo -e "${BLUE}--- Konfiguration ---${NC}"
echo ""

# Domain/IP
read -rp "Domain oder Server-IP (z.B. core.example.com oder 65.21.203.174): " DOMAIN
DOMAIN=${DOMAIN:-$(curl -s ifconfig.me)}

# OpenAI API Key
read -rp "OpenAI API Key (leer lassen für später): " OPENAI_KEY
OPENAI_KEY=${OPENAI_KEY:-""}

# Sichere Secrets generieren
SESSION_SECRET=$(openssl rand -hex 16)
ENCRYPTION_KEY=$(openssl rand -hex 16)
MAGIC_LINK_SECRET=$(openssl rand -hex 16)
POSTGRES_PASSWORD=$(openssl rand -hex 16)
NEO4J_PASSWORD=$(openssl rand -hex 16)

# =============================================================================
# 7. Docker Compose erstellen
# =============================================================================
log "Docker Compose wird konfiguriert..."

cat > "${INSTALL_DIR}/docker-compose.yaml" << 'COMPOSE_EOF'
x-logging: &logging-config
  driver: ${LOGGING_DRIVER:-local}
  options:
    max-size: ${LOGGING_MAX_SIZE:-20m}
    max-file: ${LOGGING_MAX_FILES:-5}
    compress: ${LOGGING_COMPRESS:-true}

version: "3.8"

services:
  core:
    container_name: core-app
    image: redplanethq/core:${VERSION}
    restart: unless-stopped
    logging: *logging-config
    environment:
      - NODE_ENV=${NODE_ENV}
      - DATABASE_URL=${DATABASE_URL}
      - DIRECT_URL=${DIRECT_URL}
      - SESSION_SECRET=${SESSION_SECRET}
      - ENCRYPTION_KEY=${ENCRYPTION_KEY}
      - MAGIC_LINK_SECRET=${MAGIC_LINK_SECRET}
      - LOGIN_ORIGIN=${CORE_LOGIN_ORIGIN}
      - APP_ORIGIN=${CORE_APP_ORIGIN}
      - REDIS_HOST=${REDIS_HOST}
      - REDIS_PORT=${REDIS_PORT}
      - REDIS_PASSWORD=${REDIS_PASSWORD}
      - REDIS_TLS_DISABLED=${REDIS_TLS_DISABLED}
      - NEO4J_URI=${NEO4J_URI}
      - NEO4J_USERNAME=${NEO4J_USERNAME}
      - NEO4J_PASSWORD=${NEO4J_PASSWORD}
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - AUTH_GOOGLE_CLIENT_ID=${AUTH_GOOGLE_CLIENT_ID}
      - AUTH_GOOGLE_CLIENT_SECRET=${AUTH_GOOGLE_CLIENT_SECRET}
      - ENABLE_EMAIL_LOGIN=${ENABLE_EMAIL_LOGIN}
      - OLLAMA_URL=${OLLAMA_URL}
      - EMBEDDING_MODEL=${EMBEDDING_MODEL}
      - EMBEDDING_MODEL_SIZE=${EMBEDDING_MODEL_SIZE}
      - MODEL=${MODEL}
      - TRIGGER_PROJECT_ID=${TRIGGER_PROJECT_ID}
      - TRIGGER_SECRET_KEY=${TRIGGER_SECRET_KEY}
      - TRIGGER_API_URL=${API_ORIGIN}
      - POSTGRES_DB=${POSTGRES_DB}
      - EMAIL_TRANSPORT=${EMAIL_TRANSPORT}
      - REPLY_TO_EMAIL=${REPLY_TO_EMAIL}
      - FROM_EMAIL=${FROM_EMAIL}
      - RESEND_API_KEY=${RESEND_API_KEY}
      - COHERE_API_KEY=${COHERE_API_KEY}
      - QUEUE_PROVIDER=${QUEUE_PROVIDER}
      - POSTHOG_PROJECT_KEY=${POSTHOG_PROJECT_KEY}
      - TELEMETRY_ENABLED=${TELEMETRY_ENABLED}
      - TELEMETRY_ANONYMOUS=${TELEMETRY_ANONYMOUS}
      - GRAPH_PROVIDER=${GRAPH_PROVIDER}
      - VECTOR_PROVIDER=${VECTOR_PROVIDER}
      - MODEL_PROVIDER=${MODEL_PROVIDER}
    ports:
      - "3033:3000"
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_started
      neo4j:
        condition: service_healthy
    networks:
      - core

  postgres:
    container_name: core-postgres
    image: pgvector/pgvector:pg18-trixie
    restart: unless-stopped
    logging: *logging-config
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
    ports:
      - "127.0.0.1:5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql
    networks:
      - core
    healthcheck:
      test: ["CMD-SHELL", "pg_isready"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s

  redis:
    container_name: core-redis
    image: redis:7
    restart: unless-stopped
    logging: *logging-config
    ports:
      - "127.0.0.1:6379:6379"
    networks:
      - core

  neo4j:
    container_name: core-neo4j
    image: redplanethq/neo4j:0.1.0
    restart: unless-stopped
    logging: *logging-config
    environment:
      - NEO4J_AUTH=${NEO4J_AUTH}
      - NEO4J_dbms_security_procedures_unrestricted=gds.*,apoc.*
      - NEO4J_dbms_security_procedures_allowlist=gds.*,apoc.*
      - NEO4J_apoc_export_file_enabled=true
      - NEO4J_apoc_import_file_enabled=true
      - NEO4J_apoc_import_file_use_neo4j_config=true
      - NEO4J_server_memory_heap_initial__size=2G
      - NEO4J_server_memory_heap_max__size=4G
    ports:
      - "127.0.0.1:7474:7474"
      - "127.0.0.1:7687:7687"
    volumes:
      - neo4j_data:/data
    networks:
      - core
    healthcheck:
      test: ["CMD-SHELL", "cypher-shell -u neo4j -p ${NEO4J_PASSWORD} 'RETURN 1'"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 20s

networks:
  core:
    name: core
    driver: bridge

volumes:
  postgres_data:
  neo4j_data:
COMPOSE_EOF

# =============================================================================
# 8. .env Datei erstellen
# =============================================================================
log "Umgebungsvariablen werden konfiguriert..."

cat > "${INSTALL_DIR}/.env" << ENV_EOF
# =============================================================================
# CORE - Umgebungsvariablen (generiert am $(date '+%Y-%m-%d %H:%M:%S'))
# =============================================================================

VERSION=${COMPOSE_VERSION}

# --- Datenbank ---
DB_HOST=postgres
DB_PORT=5432
POSTGRES_USER=core
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=core

DATABASE_URL=postgresql://core:${POSTGRES_PASSWORD}@postgres:5432/core?schema=core
DIRECT_URL=postgresql://core:${POSTGRES_PASSWORD}@postgres:5432/core?schema=core

# --- App ---
APP_ENV=production
NODE_ENV=production
CORE_APP_ORIGIN=http://${DOMAIN}:3033
API_BASE_URL=http://${DOMAIN}:3033
API_ORIGIN=http://${DOMAIN}:3033
CORE_LOGIN_ORIGIN=http://${DOMAIN}:3033

# --- Sicherheit ---
SESSION_SECRET=${SESSION_SECRET}
ENCRYPTION_KEY=${ENCRYPTION_KEY}
MAGIC_LINK_SECRET=${MAGIC_LINK_SECRET}

# --- Google OAuth (optional) ---
AUTH_GOOGLE_CLIENT_ID=
AUTH_GOOGLE_CLIENT_SECRET=

# --- Redis ---
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_TLS_DISABLED=true
REDIS_PASSWORD=

# --- Neo4j ---
NEO4J_URI=bolt://neo4j:7687
NEO4J_USERNAME=neo4j
NEO4J_PASSWORD=${NEO4J_PASSWORD}
NEO4J_AUTH=neo4j/${NEO4J_PASSWORD}

# --- AI ---
OPENAI_API_KEY=${OPENAI_KEY}
OLLAMA_URL=
EMBEDDING_MODEL=text-embedding-3-small
EMBEDDING_MODEL_SIZE=1536
MODEL=gpt-4.1-2025-04-14
MODEL_PROVIDER="vercel-ai"

# --- Providers ---
QUEUE_PROVIDER=bullmq
GRAPH_PROVIDER=neo4j
VECTOR_PROVIDER=pgvector

# --- Email (optional) ---
ENABLE_EMAIL_LOGIN=true
EMAIL_TRANSPORT=
REPLY_TO_EMAIL=
FROM_EMAIL=
RESEND_API_KEY=

# --- Telemetry ---
TELEMETRY_ENABLED=false
TELEMETRY_ANONYMOUS=true
POSTHOG_PROJECT_KEY=

# --- Optional ---
TRIGGER_PROJECT_ID=
TRIGGER_SECRET_KEY=
COHERE_API_KEY=
ENV_EOF

chmod 600 "${INSTALL_DIR}/.env"

# =============================================================================
# 9. Systemd Service erstellen
# =============================================================================
log "Systemd-Service wird erstellt..."

cat > /etc/systemd/system/core.service << 'SERVICE_EOF'
[Unit]
Description=CORE - Memory Agent + Actions for AI Tools
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/core
ExecStartPre=/usr/bin/docker compose pull
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
ExecReload=/usr/bin/docker compose pull && /usr/bin/docker compose up -d
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
SERVICE_EOF

systemctl daemon-reload
systemctl enable core.service

# =============================================================================
# 10. Update-Script erstellen
# =============================================================================
cat > "${INSTALL_DIR}/update.sh" << 'UPDATE_EOF'
#!/usr/bin/env bash
# CORE Update Script
set -euo pipefail

cd /opt/core

echo "Pulling latest images..."
docker compose pull

echo "Restarting services..."
docker compose up -d

echo "Cleaning up old images..."
docker image prune -f

echo "Update complete!"
docker compose ps
UPDATE_EOF
chmod +x "${INSTALL_DIR}/update.sh"

# =============================================================================
# 11. Backup-Script erstellen
# =============================================================================
cat > "${INSTALL_DIR}/backup.sh" << 'BACKUP_EOF'
#!/usr/bin/env bash
# CORE Backup Script
set -euo pipefail

BACKUP_DIR="/opt/core/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p "${BACKUP_DIR}"

echo "Backing up PostgreSQL..."
docker exec core-postgres pg_dump -U core core | gzip > "${BACKUP_DIR}/postgres_${TIMESTAMP}.sql.gz"

echo "Backing up .env..."
cp /opt/core/.env "${BACKUP_DIR}/env_${TIMESTAMP}.bak"

# Alte Backups löschen (älter als 7 Tage)
find "${BACKUP_DIR}" -type f -mtime +7 -delete

echo "Backup complete: ${BACKUP_DIR}"
ls -la "${BACKUP_DIR}"
BACKUP_EOF
chmod +x "${INSTALL_DIR}/backup.sh"

# Tägliches Backup via Cron
(crontab -l 2>/dev/null || true; echo "0 3 * * * /opt/core/backup.sh >> /var/log/core-backup.log 2>&1") | sort -u | crontab -

# =============================================================================
# 12. CORE starten
# =============================================================================
log "CORE wird gestartet..."
cd "${INSTALL_DIR}"
docker compose pull
docker compose up -d

# Auf Healthy warten
log "Warte auf Services..."
sleep 10

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           CORE Setup abgeschlossen!          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  App:        ${BLUE}http://${DOMAIN}:3033${NC}"
echo -e "  Status:     ${BLUE}docker compose -f ${INSTALL_DIR}/docker-compose.yaml ps${NC}"
echo -e "  Logs:       ${BLUE}docker compose -f ${INSTALL_DIR}/docker-compose.yaml logs -f${NC}"
echo -e "  Update:     ${BLUE}${INSTALL_DIR}/update.sh${NC}"
echo -e "  Backup:     ${BLUE}${INSTALL_DIR}/backup.sh${NC}"
echo ""
echo -e "  ${YELLOW}Wichtig: .env bearbeiten für API-Keys:${NC}"
echo -e "  ${BLUE}nano ${INSTALL_DIR}/.env${NC}"
echo ""

docker compose ps
