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

# ---- Step 5: Install curl (needed for Ollama health checks) ----
log "curl installieren..."
apt-get install -y curl

# ---- Step 6: Create Empire directories ----
log "Empire-Verzeichnisse erstellen..."
mkdir -p /empire/{results,tasks,shared-kb,logs}
mkdir -p /empire/results/{ideas,research,engineering,marketing,x-analyses,queue,standups}
chmod -R 755 /empire

# ---- Step 7: Setup .env file ----
EMPIRE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
log "Empire-Verzeichnis: $EMPIRE_DIR"

if [ ! -f "$EMPIRE_DIR/.env" ]; then
    cp "$EMPIRE_DIR/.env.example" "$EMPIRE_DIR/.env"
    warn ".env Datei erstellt. Bitte Werte ausfüllen:"
    warn "  nano $EMPIRE_DIR/.env"
    echo ""
    echo "Benötigte Werte (ALLES KOSTENLOS):"
    echo "  - TELEGRAM_BOT_TOKEN (gratis von @BotFather in Telegram)"
    echo "  - TELEGRAM_ADMIN_CHAT_ID (deine Chat-ID von @userinfobot)"
    echo ""
    echo "OPTIONAL (für bessere KI-Qualität):"
    echo "  - ANTHROPIC_API_KEY (kostenpflichtig, console.anthropic.com)"
    echo ""
    echo "LLM läuft KOSTENLOS via Ollama (llama3.1:8b) - kein API Key nötig!"
    echo ""
    read -p "Möchtest du die .env jetzt bearbeiten? [Y/n] " edit_env
    if [[ "$edit_env" != "n" ]]; then
        nano "$EMPIRE_DIR/.env"
    fi
else
    log ".env existiert bereits."
fi

# ---- Step 8: Build & Start ----
log "Docker Container bauen und starten..."
log "HINWEIS: Ollama wird beim ersten Start das LLM-Modell herunterladen (~4.7GB für llama3.1:8b)"
log "Das kann einige Minuten dauern. Danach startet alles automatisch."
cd "$EMPIRE_DIR"
docker compose build
docker compose up -d

# Wait for Ollama model to be pulled
log "Warte auf Ollama Model Download..."
sleep 10
docker compose logs ollama-init --tail 5 2>/dev/null || true

# ---- Step 9: Create systemd service for auto-start ----
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

# ---- Step 10: Verify ----
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
