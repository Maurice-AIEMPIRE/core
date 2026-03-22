#!/bin/bash
set -e

echo "================================================================"
echo "  START MONEY-MACHINE SERVICES"
echo "================================================================"
echo ""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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

echo -e "${YELLOW}[5/5] Start Clawprint (Audit Trail Daemon)...${NC}"
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
echo ""
echo "Services Status:"
curl -s http://localhost:11434/api/tags > /dev/null 2>&1 && echo "  Ollama:     Running" || echo "  Ollama:     Down"
curl -s http://localhost:8503 > /dev/null 2>&1 && echo "  Dashboard:  Running" || echo "  Dashboard:  Down"
pgrep -f "clawprint record" > /dev/null 2>&1 && echo "  Clawprint:  Running" || echo "  Clawprint:  Waiting for gateway"
echo ""
echo "================================================================"
echo "  ALL SERVICES STARTED!"
echo "================================================================"
echo ""
echo "Dashboard: http://$(hostname -I | awk '{print $1}'):8503"
echo "Models log: tail -f /tmp/models.log"
echo "Clawprint:  tail -f /var/log/clawprint.log"
echo ""
