#!/usr/bin/env bash
############################################
# GALAXIA OS - Server Setup Script
# Deploys Jarvis Kernel on Hetzner server
# using EXISTING infrastructure:
#   - Redis (core-redis / localhost:6379)
#   - LiteLLM (localhost:4000)
#   - Neo4j (core-neo4j)
#   - Ollama (localhost:11434)
############################################
set -euo pipefail

GALAXIA_DIR="/opt/galaxia"
REPO_URL="https://github.com/Maurice-AIEMPIRE/core.git"
BRANCH="claude/fix-systeme-io-login-VStsj"
VENV_DIR="$GALAXIA_DIR/.venv"
SERVICE_NAME="galaxia-jarvis"

echo "╔══════════════════════════════════════╗"
echo "║   GALAXIA OS - SERVER SETUP v1.0     ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ------------------------------------------
# STEP 1: Clone or update repo
# ------------------------------------------
echo "[1/8] Setting up code..."
if [ -d "$GALAXIA_DIR/.git" ]; then
    echo "  Repo exists, pulling latest..."
    cd "$GALAXIA_DIR"
    git fetch origin "$BRANCH"
    git checkout "$BRANCH"
    git pull origin "$BRANCH"
else
    echo "  Cloning repo to $GALAXIA_DIR..."
    # If directory exists but isn't a git repo, back it up
    if [ -d "$GALAXIA_DIR" ]; then
        mv "$GALAXIA_DIR" "${GALAXIA_DIR}.bak.$(date +%s)" 2>/dev/null || true
    fi
    git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$GALAXIA_DIR"
fi

GALAXIA_SRC="$GALAXIA_DIR/integrations/galaxia-os"
echo "  Source: $GALAXIA_SRC"

# ------------------------------------------
# STEP 2: Verify infrastructure
# ------------------------------------------
echo ""
echo "[2/8] Verifying infrastructure..."

# Redis
REDIS_URL="redis://localhost:6379/0"
if redis-cli ping 2>/dev/null | grep -q PONG; then
    echo "  ✓ Redis: OK (localhost:6379)"
else
    # Try docker redis
    REDIS_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' core-redis 2>/dev/null || echo "")
    if [ -n "$REDIS_IP" ]; then
        REDIS_URL="redis://${REDIS_IP}:6379/0"
        echo "  ✓ Redis: OK (core-redis @ $REDIS_IP)"
    else
        echo "  ✗ Redis: NOT FOUND - starting standalone..."
        docker run -d --name galaxia-redis --restart unless-stopped \
            -p 16379:6379 redis:7-alpine redis-server --appendonly yes
        REDIS_URL="redis://localhost:16379/0"
    fi
fi

# LiteLLM
if curl -s --max-time 5 http://localhost:4000/health 2>/dev/null | grep -q -i "healthy\|ok\|running" || curl -s --max-time 5 http://localhost:4000/models >/dev/null 2>&1; then
    echo "  ✓ LiteLLM: OK (localhost:4000)"
    LITELLM_URL="http://localhost:4000"
else
    echo "  ⚠ LiteLLM not responding - Jarvis will use Ollama directly"
    LITELLM_URL="http://localhost:11434"
fi

# Ollama
if curl -s --max-time 5 http://localhost:11434/api/tags >/dev/null 2>&1; then
    MODELS=$(curl -s --max-time 5 http://localhost:11434/api/tags | python3 -c "import sys,json; print(len(json.load(sys.stdin)['models']))" 2>/dev/null || echo "?")
    echo "  ✓ Ollama: OK ($MODELS models)"
else
    echo "  ✗ Ollama: NOT FOUND"
fi

# Neo4j
NEO4J_STATUS=$(docker inspect -f '{{.State.Status}}' core-neo4j 2>/dev/null || echo "not found")
echo "  ✓ Neo4j: $NEO4J_STATUS"

# ------------------------------------------
# STEP 3: Python venv
# ------------------------------------------
echo ""
echo "[3/8] Setting up Python environment..."
apt-get install -y -qq python3-venv python3-pip >/dev/null 2>&1 || true

if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
    echo "  Created venv at $VENV_DIR"
fi

source "$VENV_DIR/bin/activate"
pip install --quiet --upgrade pip
pip install --quiet -r "$GALAXIA_SRC/requirements.txt"
echo "  ✓ Dependencies installed"

# ------------------------------------------
# STEP 4: Environment config
# ------------------------------------------
echo ""
echo "[4/8] Configuring environment..."

ENV_FILE="$GALAXIA_SRC/.env"
if [ ! -f "$ENV_FILE" ]; then
    cat > "$ENV_FILE" <<ENVEOF
# Galaxia OS Environment
REDIS_URL=$REDIS_URL
LITELLM_URL=$LITELLM_URL
LITELLM_API_KEY=sk-galaxia-local
DEFAULT_MODEL=ollama/qwen3:14b
LOG_LEVEL=INFO
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN:-}
NEO4J_URI=bolt://localhost:7687
NEO4J_USER=neo4j
NEO4J_PASSWORD=${NEO4J_PASSWORD:-neo4j}
ENVEOF
    echo "  Created $ENV_FILE"
else
    echo "  .env exists, keeping current config"
fi

# ------------------------------------------
# STEP 5: Port conflict check
# ------------------------------------------
echo ""
echo "[5/8] Checking port conflicts..."

check_port() {
    local port=$1
    local name=$2
    if ss -tlnp | grep -q ":${port} "; then
        local proc=$(ss -tlnp | grep ":${port} " | head -1 | sed 's/.*users:(("//' | sed 's/".*//')
        echo "  ⚠ Port $port ($name) in use by: $proc"
        return 1
    fi
    echo "  ✓ Port $port ($name) free"
    return 0
}

# Jarvis metrics port - use 8180 to avoid conflicts
METRICS_PORT=8180
check_port 8180 "Jarvis metrics" || METRICS_PORT=8280
echo "  → Jarvis metrics will use port $METRICS_PORT"

# ------------------------------------------
# STEP 6: Create systemd service
# ------------------------------------------
echo ""
echo "[6/8] Creating systemd service..."

cat > /etc/systemd/system/${SERVICE_NAME}.service <<SVCEOF
[Unit]
Description=Galaxia OS - Jarvis Kernel
After=network.target docker.service
Wants=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=$GALAXIA_SRC
EnvironmentFile=$ENV_FILE
Environment=PYTHONPATH=$GALAXIA_SRC
Environment=METRICS_PORT=$METRICS_PORT
ExecStart=$VENV_DIR/bin/python -m kernel.main
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
echo "  ✓ Service created: $SERVICE_NAME"

# ------------------------------------------
# STEP 7: Start Jarvis
# ------------------------------------------
echo ""
echo "[7/8] Starting Jarvis Kernel..."

systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
systemctl restart "$SERVICE_NAME"
sleep 3

if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "  ✓ Jarvis is RUNNING"
else
    echo "  ✗ Jarvis failed to start. Checking logs..."
    journalctl -u "$SERVICE_NAME" --no-pager -n 20
fi

# ------------------------------------------
# STEP 8: Management CLI
# ------------------------------------------
echo ""
echo "[8/8] Creating management CLI..."

cat > /usr/local/bin/galaxia <<'CLIEOF'
#!/usr/bin/env bash
SERVICE="galaxia-jarvis"
case "${1:-status}" in
    status)  systemctl status $SERVICE --no-pager ;;
    start)   systemctl start $SERVICE && echo "Started" ;;
    stop)    systemctl stop $SERVICE && echo "Stopped" ;;
    restart) systemctl restart $SERVICE && echo "Restarted" ;;
    logs)    journalctl -u $SERVICE -f --no-pager -n ${2:-50} ;;
    health)  curl -s http://localhost:${METRICS_PORT:-8180}/health 2>/dev/null || echo "Not reachable" ;;
    *)       echo "Usage: galaxia {status|start|stop|restart|logs|health}" ;;
esac
CLIEOF
chmod +x /usr/local/bin/galaxia

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  ✅ GALAXIA OS DEPLOYED                       ║"
echo "╠══════════════════════════════════════════════╣"
echo "║  Service: systemctl status $SERVICE_NAME     ║"
echo "║  Logs:    galaxia logs                        ║"
echo "║  CLI:     galaxia {status|start|stop|restart} ║"
echo "║  Metrics: http://localhost:$METRICS_PORT/metrics ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "Using:"
echo "  Redis:   $REDIS_URL"
echo "  LiteLLM: $LITELLM_URL"
echo "  Model:   ollama/qwen3:14b"
echo ""
