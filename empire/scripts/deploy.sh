#!/bin/bash
set -euo pipefail
# ============================================
# AI EMPIRE - One-Command Deploy
# ============================================
# Run this on your Hetzner server as root:
#   curl -sL <raw-url> | bash -s -- <BOT_TOKEN> <CHAT_ID>
#
# Or copy-paste the whole script and run:
#   bash deploy.sh <BOT_TOKEN> <CHAT_ID>
# ============================================

BOT_TOKEN="${1:-}"
CHAT_ID="${2:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[EMPIRE]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Check root
[ "$EUID" -ne 0 ] && err "Bitte als root ausführen!"

# Check args
if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    echo ""
    echo "========================================="
    echo "  AI EMPIRE - Deployment"
    echo "========================================="
    echo ""
    echo "Nutzung: bash deploy.sh <TELEGRAM_BOT_TOKEN> <TELEGRAM_CHAT_ID>"
    echo ""
    echo "Beispiel:"
    echo "  bash deploy.sh 123456:ABCdef... 987654321"
    echo ""
    echo "Bot Token: Von @BotFather in Telegram"
    echo "Chat ID:   Schreib @userinfobot in Telegram"
    echo ""
    exit 1
fi

log "AI Empire Deployment startet..."

# ---- System Setup ----
log "System Updates..."
apt-get update -qq && apt-get install -y -qq git curl docker.io docker-compose-plugin > /dev/null 2>&1

# Start Docker
systemctl enable docker
systemctl start docker

# ---- Clone Repo ----
log "Repository klonen..."
EMPIRE_DIR="/opt/ai-empire"
rm -rf "$EMPIRE_DIR"
git clone --depth 1 -b claude/ai-empire-telegram-setup-1p7V7 \
    https://github.com/Maurice-AIEMPIRE/core.git "$EMPIRE_DIR" 2>/dev/null

# ---- Create directories ----
log "Empire-Verzeichnisse erstellen..."
mkdir -p /empire/{results,tasks,shared-kb,logs}
mkdir -p /empire/results/{ideas,research,engineering,marketing,x-analyses,queue,standups}
mkdir -p /root/.config/rclone
chmod -R 755 /empire

# ---- Write .env ----
log "Konfiguration schreiben..."
cat > "$EMPIRE_DIR/empire/.env" << ENVEOF
# AI EMPIRE - Auto-Generated Config
TELEGRAM_BOT_TOKEN=${BOT_TOKEN}
TELEGRAM_ADMIN_CHAT_ID=${CHAT_ID}
OLLAMA_HOST=http://ollama:11434
OLLAMA_MODEL=llama3.1:8b
REDIS_URL=redis://redis:6379/0
ICLOUD_ENABLED=false
ICLOUD_REMOTE_NAME=icloud
DROPBOX_ENABLED=false
DROPBOX_REMOTE_NAME=dropbox
X_ANALYSIS_ENABLED=true
WHISPER_MODEL=base
EMPIRE_DATA_DIR=/empire
SERVER_TIMEZONE=Europe/Berlin
PORTAINER_ADMIN_PASSWORD=$(openssl rand -hex 12)
ENVEOF

# ---- Build & Start ----
log "Docker Container bauen (das dauert 2-5 Minuten beim ersten Mal)..."
cd "$EMPIRE_DIR/empire"
docker compose build --quiet 2>&1 | tail -5
log "Container starten..."
docker compose up -d

# ---- Systemd Service ----
log "Systemd Service für Auto-Start..."
cat > /etc/systemd/system/ai-empire.service << SVCEOF
[Unit]
Description=AI Empire Docker Compose
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=$EMPIRE_DIR/empire
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable ai-empire.service > /dev/null 2>&1

# ---- Wait & Verify ----
log "Warte auf Services..."
sleep 15

echo ""
echo "========================================="
echo "  AI EMPIRE - Deployment Ergebnis"
echo "========================================="
echo ""
docker compose ps --format "table {{.Name}}\t{{.Status}}" 2>/dev/null || docker compose ps
echo ""

# Test bot
log "Teste Telegram Bot..."
RESPONSE=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getMe" 2>/dev/null || echo "failed")
if echo "$RESPONSE" | grep -q '"ok":true'; then
    BOT_NAME=$(echo "$RESPONSE" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
    log "Bot @${BOT_NAME} ist erreichbar!"

    # Send test message
    curl -s "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "parse_mode=HTML" \
        -d "text=🏢 <b>AI Empire erfolgreich deployed!</b>

🤖 Bot: @${BOT_NAME}
🖥️ Server: $(hostname -I | awk '{print $1}')
🧠 LLM: Ollama (llama3.1:8b wird geladen...)
💰 Kosten: \$0

⏳ Ollama lädt gerade das LLM-Modell herunter (~4.7GB).
Das dauert ein paar Minuten. Danach sende /start!" > /dev/null 2>&1

    log "Test-Nachricht an Telegram geschickt!"
else
    warn "Bot-Token Verbindung fehlgeschlagen. Prüfe den Token."
fi

echo ""
log "==========================================="
log "  DEPLOYMENT FERTIG!"
log "==========================================="
log ""
log "Dein Bot: https://t.me/${BOT_NAME:-M4st3rh34dsh0tbot}"
log "Portainer: https://$(hostname -I | awk '{print $1}'):9443"
log "Traefik:   http://$(hostname -I | awk '{print $1}'):8080"
log ""
log "Ollama Model wird im Hintergrund geladen."
log "In ca. 5 Min sende /start an deinen Bot!"
log ""
