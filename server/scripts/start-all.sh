#!/bin/bash
set -e

echo "================================================================"
echo "  START MONEY-MACHINE SERVICES"
echo "================================================================"
echo ""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CORE_DOCKER_DIR="$REPO_ROOT/hosting/docker"

echo -e "${YELLOW}[1/5] Start Ollama...${NC}"
systemctl restart ollama
sleep 3
echo -e "${GREEN}Ollama Started${NC}"

echo -e "${YELLOW}[2/5] Pull Models (Background)...${NC}"
ollama pull glm4:9b-chat > /tmp/models.log 2>&1 &
echo -e "${GREEN}Models Downloading...${NC}"

echo -e "${YELLOW}[3/5] Start Telegram Bot...${NC}"
cd "$REPO_ROOT/integrations/telegram"
if [ -f start.sh ]; then
    bash start.sh > /tmp/telegram-bot.log 2>&1 &
    echo -e "${GREEN}Telegram Bot Started${NC}"
else
    echo -e "${YELLOW}Telegram Bot start.sh not found, skipping${NC}"
fi

echo -e "${YELLOW}[4/5] Start Dashboard...${NC}"
if [ -f "$REPO_ROOT/dashboard/dashboard.py" ]; then
    cd "$REPO_ROOT/dashboard"
    streamlit run dashboard.py --server.port 8503 --server.address 0.0.0.0 > /tmp/dashboard.log 2>&1 &
    echo -e "${GREEN}Dashboard Started${NC}"
else
    echo -e "${YELLOW}Dashboard not found, skipping${NC}"
fi

echo -e "${YELLOW}[5/6] Start CORE Memory Agent (Docker)...${NC}"
if [ -f "$CORE_DOCKER_DIR/docker-compose.yaml" ] && command -v docker > /dev/null 2>&1; then
    cd "$CORE_DOCKER_DIR"
    # Prüfe ob .env konfiguriert ist
    if grep -q "DEINE_SERVER_IP_HIER_EINTRAGEN" .env 2>/dev/null; then
        echo -e "${RED}  CORE: .env nicht konfiguriert! Bitte Server-IP und API-Key eintragen.${NC}"
        echo -e "${RED}  Datei: $CORE_DOCKER_DIR/.env${NC}"
    elif grep -q "DEIN_OPENAI_API_KEY_HIER" .env 2>/dev/null; then
        echo -e "${RED}  CORE: OpenAI API Key fehlt in $CORE_DOCKER_DIR/.env${NC}"
    else
        docker compose up -d >> /tmp/core-memory.log 2>&1 && \
            echo -e "${GREEN}CORE Memory Agent Started${NC}" || \
            echo -e "${RED}CORE Memory Agent Fehler - Log: tail -f /tmp/core-memory.log${NC}"
    fi
else
    echo -e "${YELLOW}CORE Docker-Compose nicht gefunden oder Docker nicht installiert, skipping${NC}"
fi

echo -e "${YELLOW}[6/6] Start Clawprint (Audit Trail Daemon)...${NC}"
if command -v clawprint > /dev/null 2>&1; then
    mkdir -p "$REPO_ROOT/clawprints"
    # Kill any stale instance
    pkill -f "clawprint record" 2>/dev/null || true
    sleep 1
    nohup clawprint record \
        --gateway ws://127.0.0.1:18789 \
        --out "$REPO_ROOT/clawprints" \
        >> /var/log/clawprint.log 2>&1 &
    echo -e "${GREEN}Clawprint Daemon Started (PID $!)${NC}"
else
    echo -e "${YELLOW}clawprint not found, skipping${NC}"
fi

sleep 2
SERVER_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "Services Status:"
curl -s http://localhost:11434/api/tags > /dev/null 2>&1 && echo "  Ollama:       Running" || echo "  Ollama:       Down"
curl -s http://localhost:8503 > /dev/null 2>&1 && echo "  Dashboard:    Running" || echo "  Dashboard:    Down"
pgrep -f "clawprint record" > /dev/null 2>&1 && echo "  Clawprint:    Running" || echo "  Clawprint:    Waiting for gateway"
docker ps --filter "name=core-app" --format "{{.Status}}" 2>/dev/null | grep -q "Up" && \
    echo "  CORE Memory:  Running" || echo "  CORE Memory:  Down (run: docker compose -f $CORE_DOCKER_DIR/docker-compose.yaml up -d)"
echo ""
echo "================================================================"
echo "  ALL SERVICES STARTED!"
echo "================================================================"
echo ""
echo "Dashboard:    http://$SERVER_IP:8503"
echo "CORE Memory:  http://$SERVER_IP:3033"
echo "MCP Endpoint: http://$SERVER_IP:3033/api/v1/mcp"
echo ""
echo "Models log:   tail -f /tmp/models.log"
echo "CORE log:     tail -f /tmp/core-memory.log"
echo "Clawprint:    tail -f /var/log/clawprint.log"
echo ""
