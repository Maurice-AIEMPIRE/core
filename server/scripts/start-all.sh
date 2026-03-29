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

# Load env vars for brain services
[ -f "$CORE_DOCKER_DIR/.env" ] && export $(grep -v '^#' "$CORE_DOCKER_DIR/.env" | grep -E "^(GALAXIA_BRAIN|MAC_)" | xargs) 2>/dev/null || true

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

echo -e "${YELLOW}[6/8] Start OpenClaw Brain Sync (→ CORE Memory)...${NC}"
if command -v npx > /dev/null 2>&1 && [ -f "$REPO_ROOT/openclaw/brain/sync-to-core.ts" ]; then
    pkill -f "sync-to-core" 2>/dev/null || true
    cd "$REPO_ROOT"
    nohup npx tsx openclaw/brain/sync-to-core.ts --daemon \
        >> /tmp/openclaw-brain.log 2>&1 &
    echo -e "${GREEN}OpenClaw Brain Sync Started (PID $!)${NC}"
else
    echo -e "${YELLOW}npx/tsx not found or sync-to-core.ts missing, skipping${NC}"
fi

echo -e "${YELLOW}[7/8] Start Galaxia Bridge (→ CORE Memory)...${NC}"
if command -v npx > /dev/null 2>&1 && [ -f "$REPO_ROOT/galaxia/brain/galaxia-bridge.ts" ]; then
    pkill -f "galaxia-bridge" 2>/dev/null || true
    cd "$REPO_ROOT"
    nohup npx tsx galaxia/brain/galaxia-bridge.ts --daemon \
        >> /tmp/galaxia-bridge.log 2>&1 &
    echo -e "${GREEN}Galaxia Bridge Started (PID $!)${NC}"
else
    echo -e "${YELLOW}npx/tsx not found or galaxia-bridge.ts missing, skipping${NC}"
fi

echo -e "${YELLOW}[8/8-a] Start Mac Brain iCloud Writer (Port 9001)...${NC}"
if command -v npx > /dev/null 2>&1 && [ -f "$REPO_ROOT/integrations/mac-brain/webhook-listener.ts" ]; then
    pkill -f "webhook-listener" 2>/dev/null || true
    cd "$REPO_ROOT"
    nohup npx tsx integrations/mac-brain/webhook-listener.ts \
        >> /tmp/mac-brain.log 2>&1 &
    echo -e "${GREEN}Mac Brain iCloud Writer Started (PID $!)${NC}"
else
    echo -e "${YELLOW}Mac Brain not started (npx not found or file missing)${NC}"
fi

echo -e "${YELLOW}[8/8-b] Start Clawprint (Audit Trail Daemon)...${NC}"
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
curl -s http://localhost:11434/api/tags > /dev/null 2>&1 && echo "  Ollama:            Running" || echo "  Ollama:            Down"
curl -s http://localhost:8503 > /dev/null 2>&1 && echo "  Dashboard:         Running" || echo "  Dashboard:         Down"
pgrep -f "clawprint record" > /dev/null 2>&1 && echo "  Clawprint:         Running" || echo "  Clawprint:         Waiting for gateway"
docker ps --filter "name=core-app" --format "{{.Status}}" 2>/dev/null | grep -q "Up" && \
    echo "  CORE Memory:       Running" || echo "  CORE Memory:       Down"
pgrep -f "sync-to-core" > /dev/null 2>&1 && echo "  OpenClaw Brain:    Syncing" || echo "  OpenClaw Brain:    Down"
pgrep -f "galaxia-bridge" > /dev/null 2>&1 && echo "  Galaxia Bridge:    Syncing" || echo "  Galaxia Bridge:    Down"
pgrep -f "webhook-listener" > /dev/null 2>&1 && echo "  Mac Brain:         Running (Port 9001)" || echo "  Mac Brain:         Down"
echo ""
echo "================================================================"
echo "  ALL SERVICES STARTED! — GALAXIA BRAIN ACTIVE"
echo "================================================================"
echo ""
echo "Dashboard:         http://$SERVER_IP:8503"
echo "CORE Memory:       http://$SERVER_IP:3033"
echo "MCP Endpoint:      http://$SERVER_IP:3033/api/v1/mcp"
echo "Mac Brain:         http://localhost:9001"
echo ""
echo "Logs:"
echo "  Models:        tail -f /tmp/models.log"
echo "  CORE:          tail -f /tmp/core-memory.log"
echo "  OpenClaw Sync: tail -f /tmp/openclaw-brain.log"
echo "  Galaxia Sync:  tail -f /tmp/galaxia-bridge.log"
echo "  Mac Brain:     tail -f /tmp/mac-brain.log"
echo "  Clawprint:     tail -f /var/log/clawprint.log"
echo ""
