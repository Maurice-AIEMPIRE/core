#!/bin/bash
set -euo pipefail

# ============================================
# AI EMPIRE - Hetzner Server Install Script
# ============================================
# Run this on a fresh Ubuntu 24.04 Hetzner server
# Usage: bash install.sh
# ============================================

echo "================================================"
echo "  AI EMPIRE - Installation"
echo "================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[EMPIRE]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check root
if [ "$EUID" -ne 0 ]; then
    err "Bitte als root ausführen: sudo bash install.sh"
    exit 1
fi

# ---- Step 1: System Updates ----
log "System Updates..."
apt-get update && apt-get upgrade -y

# ---- Step 2: Install Docker ----
log "Docker installieren..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    log "Docker installiert."
else
    log "Docker bereits installiert."
fi

# ---- Step 3: Install Docker Compose ----
log "Docker Compose prüfen..."
if ! docker compose version &> /dev/null; then
    apt-get install -y docker-compose-plugin
    log "Docker Compose installiert."
else
    log "Docker Compose bereits installiert."
fi

# ---- Step 4: Install rclone ----
log "rclone installieren..."
if ! command -v rclone &> /dev/null; then
    curl https://rclone.org/install.sh | bash
    log "rclone installiert."
else
    log "rclone bereits installiert."
fi

# ---- Step 5: Create Empire directories ----
log "Empire-Verzeichnisse erstellen..."
mkdir -p /empire/{results,tasks,shared-kb,logs}
mkdir -p /empire/results/{ideas,research,engineering,marketing,x-analyses,queue,standups}
chmod -R 755 /empire

# ---- Step 6: Setup .env file ----
EMPIRE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
log "Empire-Verzeichnis: $EMPIRE_DIR"

if [ ! -f "$EMPIRE_DIR/.env" ]; then
    cp "$EMPIRE_DIR/.env.example" "$EMPIRE_DIR/.env"
    warn ".env Datei erstellt. Bitte Werte ausfüllen:"
    warn "  nano $EMPIRE_DIR/.env"
    echo ""
    echo "Benötigte Werte:"
    echo "  - TELEGRAM_BOT_TOKEN (von @BotFather)"
    echo "  - TELEGRAM_ADMIN_CHAT_ID (deine Chat-ID)"
    echo "  - ANTHROPIC_API_KEY (von console.anthropic.com)"
    echo ""
    read -p "Möchtest du die .env jetzt bearbeiten? [Y/n] " edit_env
    if [[ "$edit_env" != "n" ]]; then
        nano "$EMPIRE_DIR/.env"
    fi
else
    log ".env existiert bereits."
fi

# ---- Step 7: Build & Start ----
log "Docker Container bauen und starten..."
cd "$EMPIRE_DIR"
docker compose build
docker compose up -d

# ---- Step 8: Create systemd service for auto-start ----
log "Systemd Service erstellen..."
cat > /etc/systemd/system/ai-empire.service << SVCEOF
[Unit]
Description=AI Empire Docker Compose
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=$EMPIRE_DIR
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable ai-empire.service
log "Systemd Service aktiviert (startet bei Reboot automatisch)."

# ---- Step 9: Verify ----
echo ""
echo "================================================"
echo "  Installation abgeschlossen!"
echo "================================================"
echo ""
docker compose ps
echo ""
log "Nächste Schritte:"
log "  1. .env Datei ausfüllen: nano $EMPIRE_DIR/.env"
log "  2. Container neustarten: docker compose restart"
log "  3. Telegram Bot testen: Sende /start an deinen Bot"
log "  4. rclone für iCloud einrichten: bash scripts/setup-rclone.sh"
echo ""
log "Portainer UI: https://$(hostname -I | awk '{print $1}'):9443"
log "Traefik Dashboard: http://$(hostname -I | awk '{print $1}'):8080"
echo ""
