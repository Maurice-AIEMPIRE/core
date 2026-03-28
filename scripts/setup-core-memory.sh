#!/bin/bash
# ================================================================
# CORE Memory Agent - Hetzner Setup Script
# Integriert CORE als persistentes Gedächtnis für alle AI-Tools
# ================================================================
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CORE_DOCKER_DIR="$REPO_ROOT/hosting/docker"
ENV_FILE="$CORE_DOCKER_DIR/.env"

echo "================================================================"
echo "  CORE MEMORY AGENT - SETUP"
echo "================================================================"
echo ""

# --- 1. Voraussetzungen prüfen ---
echo -e "${YELLOW}[1/5] Prüfe Voraussetzungen...${NC}"

if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}  Docker nicht gefunden - installiere...${NC}"
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    echo -e "${GREEN}  Docker installiert${NC}"
else
    echo -e "${GREEN}  Docker: OK${NC}"
fi

if ! command -v docker compose &> /dev/null 2>&1 && ! docker compose version &> /dev/null 2>&1; then
    echo -e "${RED}  Docker Compose Plugin fehlt!${NC}"
    apt-get install -y docker-compose-plugin
fi

SERVER_IP=$(hostname -I | awk '{print $1}')
echo -e "${GREEN}  Server IP: $SERVER_IP${NC}"

# --- 2. .env konfigurieren ---
echo ""
echo -e "${YELLOW}[2/5] Konfiguriere .env...${NC}"

if grep -q "DEINE_SERVER_IP_HIER_EINTRAGEN" "$ENV_FILE"; then
    echo -e "${CYAN}  Ersetze Server-IP mit $SERVER_IP...${NC}"
    sed -i "s/DEINE_SERVER_IP_HIER_EINTRAGEN/$SERVER_IP/g" "$ENV_FILE"
    echo -e "${GREEN}  Server-IP gesetzt: $SERVER_IP${NC}"
fi

if grep -q "DEIN_OPENAI_API_KEY_HIER" "$ENV_FILE"; then
    echo ""
    echo -e "${RED}  OpenAI API Key fehlt!${NC}"
    echo -e "${CYAN}  Gib deinen OpenAI API Key ein (sk-...):${NC}"
    read -r OPENAI_KEY
    if [[ "$OPENAI_KEY" == sk-* ]]; then
        sed -i "s/DEIN_OPENAI_API_KEY_HIER/$OPENAI_KEY/" "$ENV_FILE"
        echo -e "${GREEN}  OpenAI Key gesetzt${NC}"
    else
        echo -e "${RED}  Ungültiger Key! Bitte manuell eintragen: nano $ENV_FILE${NC}"
        exit 1
    fi
fi

# Postgres Passwort sichern falls noch Standard
if grep -q "SICHERES_PASSWORT_HIER_EINTRAGEN" "$ENV_FILE"; then
    SECURE_PW=$(openssl rand -hex 24)
    sed -i "s/SICHERES_PASSWORT_HIER_EINTRAGEN/$SECURE_PW/" "$ENV_FILE"
    echo -e "${GREEN}  Postgres Passwort generiert${NC}"
fi

echo -e "${GREEN}  .env konfiguriert${NC}"

# --- 3. Firewall ---
echo ""
echo -e "${YELLOW}[3/5] Öffne Port 3033 in Firewall...${NC}"
if command -v ufw &> /dev/null; then
    ufw allow 3033/tcp comment 'CORE Memory Agent' 2>/dev/null || true
    echo -e "${GREEN}  Port 3033 geöffnet${NC}"
fi

# --- 4. Docker Container starten ---
echo ""
echo -e "${YELLOW}[4/5] Starte CORE Docker-Container...${NC}"
cd "$CORE_DOCKER_DIR"

docker compose pull
docker compose up -d

echo -e "${GREEN}  Container gestartet${NC}"
echo -e "${CYAN}  Warte auf Initialisierung (60s)...${NC}"
sleep 60

# Health Check
if curl -s "http://localhost:3033" > /dev/null 2>&1; then
    echo -e "${GREEN}  CORE läuft!${NC}"
else
    echo -e "${YELLOW}  CORE startet noch... (kann 2-3 Minuten dauern)${NC}"
    echo -e "${CYAN}  Log: docker compose -f $CORE_DOCKER_DIR/docker-compose.yaml logs -f core${NC}"
fi

# --- 5. MCP für Claude Code ---
echo ""
echo -e "${YELLOW}[5/5] MCP Konfiguration...${NC}"
MCP_URL="http://$SERVER_IP:3033/api/v1/mcp"

echo ""
echo "================================================================"
echo -e "${GREEN}  CORE MEMORY AGENT SETUP COMPLETE!${NC}"
echo "================================================================"
echo ""
echo -e "  Web-UI:    ${CYAN}http://$SERVER_IP:3033${NC}"
echo -e "  MCP URL:   ${CYAN}$MCP_URL${NC}"
echo ""
echo "  Claude Code verbinden (auf deinem Mac ausführen):"
echo -e "  ${CYAN}claude mcp add --transport http --scope user core-memory $MCP_URL${NC}"
echo ""
echo "  Dann im Claude Code:"
echo -e "  ${CYAN}/mcp${NC}  → core-memory → im Browser authentifizieren"
echo ""
echo "  Docker verwalten:"
echo "    Status:   docker compose -f $CORE_DOCKER_DIR/docker-compose.yaml ps"
echo "    Logs:     docker compose -f $CORE_DOCKER_DIR/docker-compose.yaml logs -f"
echo "    Stoppen:  docker compose -f $CORE_DOCKER_DIR/docker-compose.yaml down"
echo ""
