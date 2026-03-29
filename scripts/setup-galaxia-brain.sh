#!/bin/bash
# ================================================================
# GALAXIA BRAIN — Master Setup Script
#
# Verbindet alle Subsysteme mit dem CORE Memory Server:
# - OpenClaw Brain → CORE
# - Galaxia Vector → CORE
# - Mac Brain / iCloud Writer
# - Claude Code MCP Konfiguration
#
# Einmaliges Setup. Danach startet start-all.sh alles automatisch.
# ================================================================
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$REPO_ROOT/hosting/docker/.env"

echo ""
echo -e "${BOLD}================================================================${NC}"
echo -e "${BOLD}  GALAXIA BRAIN — Unified Memory Architecture Setup${NC}"
echo -e "${BOLD}================================================================${NC}"
echo ""

SERVER_IP=$(hostname -I | awk '{print $1}')

# ============================================================
# 1. Prüfe ob CORE läuft
# ============================================================
echo -e "${YELLOW}[1/6] Prüfe CORE Memory Server...${NC}"

if curl -s "http://localhost:3033" > /dev/null 2>&1; then
    echo -e "${GREEN}  ✓ CORE läuft auf Port 3033${NC}"
else
    echo -e "${RED}  ✗ CORE nicht erreichbar!${NC}"
    echo ""
    echo "  Starte CORE zuerst:"
    echo "  cd $REPO_ROOT/hosting/docker && docker compose up -d"
    echo ""
    read -rp "  CORE starten? (j/n): " START_CORE
    if [[ "$START_CORE" == "j" || "$START_CORE" == "J" ]]; then
        cd "$REPO_ROOT/hosting/docker"
        docker compose up -d
        echo -e "${CYAN}  Warte 60s auf CORE Initialisierung...${NC}"
        sleep 60
    else
        echo -e "${RED}  Bitte CORE zuerst starten und dieses Script erneut ausführen.${NC}"
        exit 1
    fi
fi

# ============================================================
# 2. CORE API Token
# ============================================================
echo ""
echo -e "${YELLOW}[2/6] CORE API Token konfigurieren...${NC}"

if grep -q "CORE_API_TOKEN_HIER" "$ENV_FILE" 2>/dev/null || ! grep -q "GALAXIA_BRAIN_TOKEN" "$ENV_FILE" 2>/dev/null; then
    echo ""
    echo -e "${CYAN}  Öffne jetzt: http://$SERVER_IP:3033${NC}"
    echo -e "${CYAN}  → Account erstellen oder einloggen${NC}"
    echo -e "${CYAN}  → Settings → API Key → Kopieren${NC}"
    echo ""
    read -rp "  Füge deinen CORE API Token ein: " CORE_TOKEN

    if [[ -z "$CORE_TOKEN" ]]; then
        echo -e "${RED}  Kein Token eingegeben. Manuell in $ENV_FILE eintragen: GALAXIA_BRAIN_TOKEN=...${NC}"
        exit 1
    fi

    # Add or update token in .env
    if grep -q "^GALAXIA_BRAIN_TOKEN=" "$ENV_FILE"; then
        sed -i "s|^GALAXIA_BRAIN_TOKEN=.*|GALAXIA_BRAIN_TOKEN=$CORE_TOKEN|" "$ENV_FILE"
    else
        echo "" >> "$ENV_FILE"
        echo "# Galaxia Brain" >> "$ENV_FILE"
        echo "GALAXIA_BRAIN_URL=http://localhost:3033" >> "$ENV_FILE"
        echo "GALAXIA_BRAIN_TOKEN=$CORE_TOKEN" >> "$ENV_FILE"
    fi

    echo -e "${GREEN}  ✓ API Token gespeichert${NC}"
else
    echo -e "${GREEN}  ✓ GALAXIA_BRAIN_TOKEN bereits konfiguriert${NC}"
    CORE_TOKEN=$(grep "^GALAXIA_BRAIN_TOKEN=" "$ENV_FILE" | cut -d= -f2)
fi

# Export für dieses Script
export GALAXIA_BRAIN_URL="http://localhost:3033"
export GALAXIA_BRAIN_TOKEN="$CORE_TOKEN"

# ============================================================
# 3. Mac SSH & iCloud Konfiguration
# ============================================================
echo ""
echo -e "${YELLOW}[3/6] Mac Brain / iCloud konfigurieren...${NC}"

MAC_HOST=$(grep "^MAC_SSH_HOST=" "$ENV_FILE" 2>/dev/null | cut -d= -f2)

if [[ -z "$MAC_HOST" ]]; then
    echo -e "${CYAN}  Trage deine Mac IP oder Tailscale Hostname ein (leer lassen zum Überspringen):${NC}"
    read -rp "  Mac SSH Host: " MAC_HOST

    if [[ -n "$MAC_HOST" ]]; then
        sed -i "s|^MAC_SSH_HOST=.*|MAC_SSH_HOST=$MAC_HOST|" "$ENV_FILE" 2>/dev/null || \
            echo "MAC_SSH_HOST=$MAC_HOST" >> "$ENV_FILE"
        echo -e "${GREEN}  ✓ Mac SSH Host: $MAC_HOST${NC}"

        # Add iCloud path if not set
        if ! grep -q "^MAC_ICLOUD_PATH=" "$ENV_FILE"; then
            echo "MAC_ICLOUD_PATH=/Users/maurice/Library/Mobile Documents/com~apple~CloudDocs" >> "$ENV_FILE"
        fi
    else
        echo -e "${YELLOW}  ~ Mac Brain übersprungen (kein SSH Host)${NC}"
    fi
else
    echo -e "${GREEN}  ✓ Mac SSH Host: $MAC_HOST${NC}"
fi

# Create iCloud folder via SSH if Mac is configured
if [[ -n "$MAC_HOST" ]]; then
    MAC_USER=$(grep "^MAC_SSH_USER=" "$ENV_FILE" 2>/dev/null | cut -d= -f2 || echo "maurice")
    MAC_KEY=$(grep "^MAC_SSH_KEY=" "$ENV_FILE" 2>/dev/null | cut -d= -f2 || echo "/root/.ssh/mac_id_ed25519")
    ICLOUD_BASE=$(grep "^MAC_ICLOUD_PATH=" "$ENV_FILE" 2>/dev/null | cut -d= -f2 || echo "/Users/maurice/Library/Mobile Documents/com~apple~CloudDocs")

    echo -e "${CYAN}  Erstelle GalaxiaBrain Ordner in iCloud...${NC}"
    ssh -i "$MAC_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
        "${MAC_USER}@${MAC_HOST}" \
        "mkdir -p \"${ICLOUD_BASE}/GalaxiaBrain\"" 2>/dev/null && \
        echo -e "${GREEN}  ✓ iCloud Ordner erstellt${NC}" || \
        echo -e "${YELLOW}  ~ SSH nicht erreichbar — iCloud Ordner muss manuell erstellt werden${NC}"
fi

# ============================================================
# 4. CORE Webhook für Mac Brain registrieren
# ============================================================
echo ""
echo -e "${YELLOW}[4/6] Registriere CORE Webhook für Mac Brain...${NC}"

WEBHOOK_RESPONSE=$(curl -s -X POST "http://localhost:3033/api/v1/webhooks" \
    -H "Authorization: Bearer $CORE_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"url\":\"http://localhost:9001/core-webhook\",\"eventTypes\":[\"activity.created\"]}" 2>/dev/null)

if echo "$WEBHOOK_RESPONSE" | grep -q '"success":true'; then
    WEBHOOK_ID=$(echo "$WEBHOOK_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    echo -e "${GREEN}  ✓ Webhook registriert (ID: $WEBHOOK_ID)${NC}"
else
    echo -e "${YELLOW}  ~ Webhook konnte nicht registriert werden (CORE evtl. noch nicht bereit)${NC}"
    echo -e "${YELLOW}    Manuell ausführen nach Start: bash scripts/setup-galaxia-brain.sh${NC}"
fi

# ============================================================
# 5. Erster Sync aller Brains
# ============================================================
echo ""
echo -e "${YELLOW}[5/6] Starte ersten Brain-Sync...${NC}"

# Check if node is available
if command -v node &> /dev/null && command -v npx &> /dev/null; then
    # Compile and run OpenClaw sync
    echo -e "${CYAN}  Kompiliere OpenClaw Brain Sync...${NC}"
    cd "$REPO_ROOT/openclaw/brain"
    npx tsx sync-to-core.ts 2>/dev/null && \
        echo -e "${GREEN}  ✓ OpenClaw Brain sync abgeschlossen${NC}" || \
        echo -e "${YELLOW}  ~ OpenClaw sync fehlgeschlagen (tsx nicht verfügbar — läuft später automatisch)${NC}"

    echo -e "${CYAN}  Kompiliere Galaxia Bridge...${NC}"
    cd "$REPO_ROOT/galaxia/brain"
    npx tsx galaxia-bridge.ts 2>/dev/null && \
        echo -e "${GREEN}  ✓ Galaxia Bridge sync abgeschlossen${NC}" || \
        echo -e "${YELLOW}  ~ Galaxia sync fehlgeschlagen (tsx nicht verfügbar — läuft später automatisch)${NC}"
else
    echo -e "${YELLOW}  ~ node/npx nicht gefunden. Brain-Sync startet nach nächstem start-all.sh${NC}"
fi

# ============================================================
# 6. Claude Code MCP Setup
# ============================================================
echo ""
echo -e "${YELLOW}[6/6] Claude Code MCP Konfiguration...${NC}"

echo ""
echo -e "${BOLD}================================================================${NC}"
echo -e "${GREEN}${BOLD}  GALAXIA BRAIN SETUP COMPLETE!${NC}"
echo -e "${BOLD}================================================================${NC}"
echo ""
echo -e "  CORE Memory Web-UI:  ${CYAN}http://$SERVER_IP:3033${NC}"
echo -e "  Mac Brain:           ${CYAN}http://localhost:9001${NC} (nach start-all.sh)"
echo ""
echo -e "${BOLD}  Claude Code MCP verbinden (auf deinem Mac ausführen):${NC}"
echo -e "  ${CYAN}claude mcp add --transport http --scope user core-memory http://$SERVER_IP:3033/api/v1/mcp${NC}"
echo ""
echo -e "  Dann in Claude Code:"
echo -e "  ${CYAN}/mcp${NC} → core-memory → Im Browser authentifizieren"
echo ""
echo -e "${BOLD}  Alle Services starten:${NC}"
echo -e "  ${CYAN}bash server/scripts/start-all.sh${NC}"
echo ""
echo -e "${BOLD}  Brain-Sync Logs:${NC}"
echo -e "  tail -f /tmp/openclaw-brain.log"
echo -e "  tail -f /tmp/galaxia-bridge.log"
echo -e "  tail -f /tmp/mac-brain.log"
echo ""
