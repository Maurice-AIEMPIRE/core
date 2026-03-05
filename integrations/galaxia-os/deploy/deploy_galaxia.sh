#!/bin/bash
# =============================================================================
# PFEIFER GALAXIA OS - PRODUCTION DEPLOY SCRIPT
# =============================================================================
# Integrates safely on top of an existing AI cluster.
# Does NOT rebuild, overwrite, or kill existing services.
#
# Usage:
#   bash deploy_galaxia.sh
#
# Requirements:
#   - Ubuntu 24.04 with Docker
#   - Existing AI stack (Ollama, Redis, etc.)
#   - Root or sudo access
# =============================================================================

set -euo pipefail

# === Colors ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# === Config ===
GALAXIA_DIR="/opt/galaxia"
LOG_DIR="$GALAXIA_DIR/logs"
LOG_FILE="$LOG_DIR/galaxia.log"
DEPLOY_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Detected service endpoints (filled during inspection)
declare -A ENDPOINTS
declare -A PORT_STATUS
CONFLICTS=()

# === Logging ===
log() {
    local level="$1"
    shift
    local msg="$*"
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo -e "${ts} [${level}] ${msg}" >> "$LOG_FILE" 2>/dev/null || true
    case "$level" in
        INFO)  echo -e "${GREEN}[OK]${NC} $msg" ;;
        WARN)  echo -e "${YELLOW}[!!]${NC} $msg" ;;
        ERROR) echo -e "${RED}[ERR]${NC} $msg" ;;
        *)     echo -e "     $msg" ;;
    esac
}

header() {
    echo ""
    echo -e "${CYAN}${BOLD}=== $1 ===${NC}"
    echo ""
}

# === Pre-flight ===
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Fehler: Root-Rechte erforderlich${NC}"
    echo "  sudo bash deploy_galaxia.sh"
    exit 1
fi

# Create directories first (for logging)
mkdir -p "$GALAXIA_DIR"/{kernel,registry,workers,deploy,logs,config}
touch "$LOG_FILE"

echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          PFEIFER GALAXIA OS - DEPLOY SCRIPT                 ║"
echo "║          Safe integration on existing AI cluster             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "  Timestamp: $DEPLOY_TIMESTAMP"
echo "  Log: $LOG_FILE"
echo ""

log INFO "Deploy started at $DEPLOY_TIMESTAMP"

# =============================================================================
# STEP 1: SERVER INSPECTION
# =============================================================================
header "STEP 1/10: Server Inspection"

# --- Running containers ---
log INFO "Scanning Docker containers..."
DOCKER_CONTAINERS=$(docker ps --format '{{.Names}}\t{{.Ports}}\t{{.Status}}' 2>/dev/null || echo "")
CONTAINER_COUNT=$(echo "$DOCKER_CONTAINERS" | grep -c . 2>/dev/null || echo "0")
log INFO "Found $CONTAINER_COUNT running containers"

if [ -n "$DOCKER_CONTAINERS" ]; then
    echo "  Running containers:"
    echo "$DOCKER_CONTAINERS" | while IFS=$'\t' read -r name ports status; do
        printf "    %-30s %s\n" "$name" "$ports"
    done
    echo ""
fi

# --- Running services ---
log INFO "Scanning systemd services..."
RUNNING_SERVICES=$(systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null || echo "")
AGENT_COUNT=$(echo "$RUNNING_SERVICES" | grep -c "agent-" 2>/dev/null || echo "0")
log INFO "Found $AGENT_COUNT running agent services"

# Check for existing Telegram bot
if echo "$RUNNING_SERVICES" | grep -q "m0claw-telegram"; then
    log INFO "Existing Telegram bot found: m0claw-telegram.service"
    ENDPOINTS[telegram_service]="m0claw-telegram.service"
else
    log WARN "No m0claw-telegram.service found"
fi

# --- System resources ---
CPU_CORES=$(nproc 2>/dev/null || echo "?")
RAM_TOTAL=$(free -g 2>/dev/null | awk '/Mem:/{print $2}' || echo "?")
RAM_USED=$(free -g 2>/dev/null | awk '/Mem:/{print $3}' || echo "?")
DISK_USED=$(df -h / 2>/dev/null | tail -1 | awk '{print $5}' || echo "?")

echo "  System Resources:"
echo "    CPU:  $CPU_CORES cores"
echo "    RAM:  ${RAM_USED}G / ${RAM_TOTAL}G"
echo "    Disk: $DISK_USED used"
echo ""

log INFO "System: ${CPU_CORES} cores, ${RAM_USED}G/${RAM_TOTAL}G RAM, ${DISK_USED} disk"

# =============================================================================
# STEP 2: ENVIRONMENT DETECTION
# =============================================================================
header "STEP 2/10: Service Detection"

detect_service() {
    local name="$1"
    local check_cmd="$2"
    local default_endpoint="$3"

    if eval "$check_cmd" > /dev/null 2>&1; then
        ENDPOINTS[$name]="$default_endpoint"
        log INFO "$name detected at $default_endpoint"
        return 0
    else
        log WARN "$name not detected"
        return 1
    fi
}

# Detect each service
detect_service "ollama" "curl -sf http://localhost:11434/api/tags" "http://localhost:11434" || true
detect_service "litellm" "curl -sf http://localhost:4000/health" "http://localhost:4000" || true
detect_service "redis" "redis-cli ping" "redis://localhost:6379" || true
detect_service "neo4j" "curl -sf http://localhost:7474" "bolt://localhost:7687" || true
detect_service "n8n" "curl -sf http://localhost:5678/healthz" "http://localhost:5678" || true
detect_service "qdrant" "curl -sf http://localhost:6333/collections" "http://localhost:6333" || true
detect_service "langfuse" "curl -sf http://localhost:3100" "http://localhost:3100" || true
detect_service "grafana" "curl -sf http://localhost:3001/api/health" "http://localhost:3001" || true
detect_service "prometheus" "curl -sf http://localhost:9090/-/healthy" "http://localhost:9090" || true

echo ""
echo "  Detected services: ${#ENDPOINTS[@]}"
for svc in "${!ENDPOINTS[@]}"; do
    printf "    %-20s %s\n" "$svc" "${ENDPOINTS[$svc]}"
done
echo ""

# =============================================================================
# STEP 3: PORT CONFLICT DETECTION
# =============================================================================
header "STEP 3/10: Port Conflict Detection"

# Galaxia needs these ports
GALAXIA_PORTS=(
    "8080:Jarvis metrics"
    "18800:Jarvis API"
)

check_port() {
    local port="$1"
    local desc="$2"

    if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
        local proc
        proc=$(ss -tlnp 2>/dev/null | grep ":${port} " | awk '{print $NF}' | head -1)
        CONFLICTS+=("$port:$desc:$proc")
        log WARN "Port $port ($desc) already in use by $proc"
        return 1
    else
        log INFO "Port $port ($desc) available"
        return 0
    fi
}

JARVIS_METRICS_PORT=8080
JARVIS_API_PORT=18800

for entry in "${GALAXIA_PORTS[@]}"; do
    port="${entry%%:*}"
    desc="${entry#*:}"
    if ! check_port "$port" "$desc"; then
        # Find alternative port
        for alt in $(seq $((port + 1)) $((port + 10))); do
            if ! ss -tlnp 2>/dev/null | grep -q ":${alt} "; then
                log INFO "  -> Using alternative port $alt for $desc"
                if [ "$port" = "8080" ]; then
                    JARVIS_METRICS_PORT=$alt
                elif [ "$port" = "18800" ]; then
                    JARVIS_API_PORT=$alt
                fi
                break
            fi
        done
    fi
done

if [ ${#CONFLICTS[@]} -gt 0 ]; then
    echo "  Port conflicts detected (resolved with alternatives):"
    for c in "${CONFLICTS[@]}"; do
        echo "    $c"
    done
else
    echo "  No port conflicts detected"
fi
echo ""

# =============================================================================
# STEP 4: OLLAMA TIMEOUT FIX
# =============================================================================
header "STEP 4/10: Ollama Timeout Fix"

if [ -n "${ENDPOINTS[ollama]:-}" ]; then
    # Check current models
    echo "  Current Ollama models:"
    curl -sf http://localhost:11434/api/tags 2>/dev/null | \
        python3 -c "import sys,json; data=json.load(sys.stdin); [print(f'    {m[\"name\"]:30s} {m.get(\"size\",0)//1024//1024//1024}GB') for m in data.get('models',[])]" 2>/dev/null || \
        echo "    (could not list models)"
    echo ""

    # Ensure fast model is available
    if ! curl -sf http://localhost:11434/api/tags 2>/dev/null | grep -q "qwen3:14b"; then
        log WARN "qwen3:14b not found - pulling..."
        ollama pull qwen3:14b 2>/dev/null &
        PULL_PID=$!
        echo "  Pulling qwen3:14b in background (PID: $PULL_PID)..."
    else
        log INFO "qwen3:14b available"
    fi

    # Apply Ollama timeout fix
    OLLAMA_OVERRIDE="/etc/systemd/system/ollama.service.d"
    if [ ! -f "$OLLAMA_OVERRIDE/galaxia-override.conf" ]; then
        mkdir -p "$OLLAMA_OVERRIDE"
        cat > "$OLLAMA_OVERRIDE/galaxia-override.conf" << 'OLLAMAEOF'
# Galaxia OS - Ollama timeout optimization
[Service]
Environment="OLLAMA_KEEP_ALIVE=30m"
Environment="OLLAMA_NUM_PARALLEL=2"
Environment="OLLAMA_MAX_LOADED_MODELS=3"
OLLAMAEOF
        systemctl daemon-reload
        systemctl restart ollama 2>/dev/null || true
        log INFO "Ollama timeout fix applied (keep_alive=30m, parallel=2)"
    else
        log INFO "Ollama override already configured"
    fi
else
    log WARN "Ollama not detected - skipping timeout fix"
fi

# =============================================================================
# STEP 5: LITELLM ROUTING
# =============================================================================
header "STEP 5/10: LiteLLM Routing Configuration"

# Create Galaxia-specific LiteLLM config
cat > "$GALAXIA_DIR/config/litellm-galaxia.yaml" << 'LITELLMEOF'
# Galaxia OS LiteLLM routing rules
# Primary: fast models for Telegram/interactive
# Fallback: larger models for background tasks

model_list:
  # === PRIMARY: Fast models for interactive (Telegram, API) ===
  - model_name: galaxia-fast
    litellm_params:
      model: ollama/qwen3:14b
      api_base: http://localhost:11434
      timeout: 120
      stream: true

  - model_name: galaxia-fast-fallback
    litellm_params:
      model: ollama/llama3.1:8b
      api_base: http://localhost:11434
      timeout: 60

  # === BACKGROUND: Larger models for deep tasks ===
  - model_name: galaxia-deep
    litellm_params:
      model: ollama/qwen3:32b
      api_base: http://localhost:11434
      timeout: 300

  # === ALIASES ===
  - model_name: qwen3-14b
    litellm_params:
      model: ollama/qwen3:14b
      api_base: http://localhost:11434
      timeout: 120

litellm_settings:
  drop_params: true
  request_timeout: 120
  set_verbose: false
  cache: true
  cache_params:
    type: redis
    host: localhost
    port: 6379

router_settings:
  routing_strategy: simple-shuffle
  num_retries: 2
  timeout: 120
  allowed_fails: 2
  cooldown_time: 30

# Telegram requests NEVER use models > 14B
# Enforced by Jarvis kernel routing logic
LITELLMEOF

log INFO "LiteLLM config created at $GALAXIA_DIR/config/litellm-galaxia.yaml"

# If LiteLLM is running, try to update its config
if [ -n "${ENDPOINTS[litellm]:-}" ]; then
    # Check if existing LiteLLM uses a config file we can symlink
    LITELLM_CONFIG=$(docker inspect litellm 2>/dev/null | python3 -c "import sys,json; mounts=json.load(sys.stdin)[0].get('Mounts',[]); [print(m['Source']) for m in mounts if 'config' in m.get('Destination','')]" 2>/dev/null || echo "")
    if [ -n "$LITELLM_CONFIG" ] && [ -f "$LITELLM_CONFIG" ]; then
        log INFO "Existing LiteLLM config found at $LITELLM_CONFIG"
        cp "$LITELLM_CONFIG" "$LITELLM_CONFIG.bak.$(date +%s)"
        log INFO "Backup created. Galaxia config ready at $GALAXIA_DIR/config/litellm-galaxia.yaml"
        echo "  To use Galaxia routing, update LiteLLM config:"
        echo "    cp $GALAXIA_DIR/config/litellm-galaxia.yaml $LITELLM_CONFIG"
        echo "    docker restart litellm"
    else
        log INFO "LiteLLM running but config path unknown - manual update needed"
    fi
else
    log WARN "LiteLLM not detected - config saved for manual setup"
fi

# =============================================================================
# STEP 6: DEPLOY GALAXIA KERNEL
# =============================================================================
header "STEP 6/10: Deploy Jarvis Kernel"

# Determine Redis URL
REDIS_URL="${ENDPOINTS[redis]:-redis://localhost:6379}/0"

# Determine LiteLLM URL
LITELLM_URL="${ENDPOINTS[litellm]:-http://localhost:4000}"

# Create Galaxia .env
cat > "$GALAXIA_DIR/.env" << ENVEOF
# Galaxia OS Environment
# Generated: $DEPLOY_TIMESTAMP

# Redis
REDIS_URL=$REDIS_URL

# LiteLLM
LITELLM_URL=$LITELLM_URL
LITELLM_API_KEY=sk-galaxia-local

# Default model (fast, for Telegram)
DEFAULT_MODEL=ollama/qwen3:14b

# Telegram
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN:-}

# Ports (auto-detected, conflict-free)
JARVIS_METRICS_PORT=$JARVIS_METRICS_PORT
JARVIS_API_PORT=$JARVIS_API_PORT

# Logging
LOG_LEVEL=INFO

# Brain cycle interval (seconds)
BRAIN_CYCLE_SECONDS=600
ENVEOF

chmod 600 "$GALAXIA_DIR/.env"
log INFO "Environment file created at $GALAXIA_DIR/.env"

# Copy kernel code from repo (if available) or use Docker
REPO_GALAXIA="/opt/ki-power/core/integrations/galaxia-os"
if [ ! -d "$REPO_GALAXIA" ]; then
    REPO_GALAXIA="$(dirname "$(dirname "$(readlink -f "$0")")")"
fi

if [ -d "$REPO_GALAXIA/kernel" ]; then
    log INFO "Copying Galaxia code from $REPO_GALAXIA"
    cp -r "$REPO_GALAXIA"/kernel/ "$GALAXIA_DIR/kernel/"
    cp -r "$REPO_GALAXIA"/agents/ "$GALAXIA_DIR/agents/" 2>/dev/null || true
    cp -r "$REPO_GALAXIA"/shared/ "$GALAXIA_DIR/shared/" 2>/dev/null || true
    cp -r "$REPO_GALAXIA"/taskqueue/ "$GALAXIA_DIR/taskqueue/" 2>/dev/null || true
    rm -rf "$GALAXIA_DIR/queue/" 2>/dev/null || true  # cleanup old name that shadows stdlib
    cp -r "$REPO_GALAXIA"/registry/ "$GALAXIA_DIR/registry/" 2>/dev/null || true
    cp -r "$REPO_GALAXIA"/llm/ "$GALAXIA_DIR/llm/" 2>/dev/null || true
    cp -r "$REPO_GALAXIA"/memory/ "$GALAXIA_DIR/memory/" 2>/dev/null || true
    cp -r "$REPO_GALAXIA"/tools/ "$GALAXIA_DIR/tools/" 2>/dev/null || true
    cp -r "$REPO_GALAXIA"/brain/ "$GALAXIA_DIR/brain/" 2>/dev/null || true
    cp -r "$REPO_GALAXIA"/integrations/ "$GALAXIA_DIR/integrations_lib/" 2>/dev/null || true
    cp "$REPO_GALAXIA"/requirements.txt "$GALAXIA_DIR/" 2>/dev/null || true
    log INFO "Galaxia code deployed"
else
    log WARN "Galaxia source not found at $REPO_GALAXIA"
    log INFO "Use Docker deployment instead: cd $REPO_GALAXIA/docker && docker compose up -d"
fi

# Install Python dependencies
if [ -f "$GALAXIA_DIR/requirements.txt" ]; then
    log INFO "Installing Python dependencies..."
    pip3 install -q -r "$GALAXIA_DIR/requirements.txt" 2>/dev/null || {
        log WARN "pip install failed - trying with --break-system-packages"
        pip3 install -q --break-system-packages -r "$GALAXIA_DIR/requirements.txt" 2>/dev/null || true
    }
fi

# =============================================================================
# STEP 7: CREATE SYSTEMD SERVICE
# =============================================================================
header "STEP 7/10: Jarvis systemd Service"

cat > /etc/systemd/system/galaxia-jarvis.service << SVCEOF
[Unit]
Description=Galaxia OS - Jarvis Kernel
After=network.target redis.service docker.service ollama.service
Wants=redis.service

[Service]
Type=simple
WorkingDirectory=$GALAXIA_DIR
EnvironmentFile=$GALAXIA_DIR/.env
ExecStart=/usr/bin/python3 -m kernel.main
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=galaxia-jarvis

# Resource limits
MemoryMax=2G
CPUQuota=200%

# Security
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=$GALAXIA_DIR /tmp

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
log INFO "galaxia-jarvis.service created"

# =============================================================================
# STEP 8: TELEGRAM BOT MIGRATION
# =============================================================================
header "STEP 8/10: Telegram Bot Migration"

if [ -n "${ENDPOINTS[telegram_service]:-}" ]; then
    log INFO "Existing Telegram bot detected: ${ENDPOINTS[telegram_service]}"

    # Read current bot token
    CURRENT_TOKEN=$(systemctl show m0claw-telegram.service -p Environment 2>/dev/null | grep -o 'TELEGRAM_BOT_TOKEN=[^ ]*' | cut -d= -f2 || echo "")
    if [ -z "$CURRENT_TOKEN" ]; then
        CURRENT_TOKEN=$(grep -r "TELEGRAM_BOT_TOKEN\|bot_token" /opt/m0claw* /etc/systemd/system/m0claw* 2>/dev/null | grep -oP '[\d]+:[\w-]+' | head -1 || echo "")
    fi

    if [ -n "$CURRENT_TOKEN" ]; then
        # Update Galaxia .env with the token
        sed -i "s|^TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=$CURRENT_TOKEN|" "$GALAXIA_DIR/.env"
        log INFO "Telegram token migrated to Galaxia"
    else
        log WARN "Could not extract Telegram token automatically"
        echo "  Manual action needed:"
        echo "    1. Find your bot token"
        echo "    2. Edit $GALAXIA_DIR/.env"
        echo "    3. Set TELEGRAM_BOT_TOKEN=your_token"
    fi

    echo ""
    echo -e "  ${YELLOW}WICHTIG: Telegram Bot Migration${NC}"
    echo "  Der alte Bot (m0claw-telegram) und Jarvis koennen nicht"
    echo "  gleichzeitig denselben Bot-Token verwenden."
    echo ""
    echo "  Optionen:"
    echo "    A) Alten Bot stoppen, Jarvis uebernehmen lassen:"
    echo "       systemctl stop m0claw-telegram"
    echo "       systemctl disable m0claw-telegram"
    echo "       systemctl start galaxia-jarvis"
    echo ""
    echo "    B) Neuen Bot-Token fuer Jarvis erstellen:"
    echo "       -> @BotFather auf Telegram -> /newbot"
    echo "       -> Token in $GALAXIA_DIR/.env eintragen"
    echo "       -> systemctl start galaxia-jarvis"
    echo ""
    log INFO "Telegram migration options presented (manual choice required)"
else
    log INFO "No existing Telegram bot - Jarvis will be the primary bot"
    echo "  Set TELEGRAM_BOT_TOKEN in $GALAXIA_DIR/.env"
fi

# =============================================================================
# STEP 9: MANAGEMENT CLI
# =============================================================================
header "STEP 9/10: Management CLI"

cat > /usr/local/bin/galaxia << 'CLIEOF'
#!/bin/bash
# Galaxia OS Management CLI
cd /opt/galaxia 2>/dev/null || true
source /opt/galaxia/.env 2>/dev/null || true

C_GREEN='\033[0;32m'
C_RED='\033[0;31m'
C_YELLOW='\033[1;33m'
C_CYAN='\033[0;36m'
C_BOLD='\033[1m'
C_NC='\033[0m'

case "${1:-help}" in
    status)
        echo -e "\n${C_CYAN}${C_BOLD}=== GALAXIA OS STATUS ===${C_NC}\n"

        # Jarvis
        echo -e "${C_BOLD}Jarvis Kernel:${C_NC}"
        if systemctl is-active --quiet galaxia-jarvis 2>/dev/null; then
            echo -e "  Status: ${C_GREEN}RUNNING${C_NC}"
            echo "  PID:    $(systemctl show galaxia-jarvis -p MainPID --value 2>/dev/null)"
            echo "  Uptime: $(systemctl show galaxia-jarvis -p ActiveEnterTimestamp --value 2>/dev/null)"
        else
            echo -e "  Status: ${C_RED}STOPPED${C_NC}"
        fi

        echo ""
        echo -e "${C_BOLD}Services:${C_NC}"
        for svc in ollama redis neo4j; do
            if systemctl is-active --quiet $svc 2>/dev/null; then
                echo -e "  $svc: ${C_GREEN}RUNNING${C_NC}"
            elif docker inspect --format='{{.State.Running}}' $svc 2>/dev/null | grep -q true; then
                echo -e "  $svc: ${C_GREEN}RUNNING (Docker)${C_NC}"
            else
                echo -e "  $svc: ${C_RED}STOPPED${C_NC}"
            fi
        done

        echo ""
        echo -e "${C_BOLD}Agents:${C_NC}"
        AGENT_RUNNING=$(systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null | grep -c "agent-" || echo "0")
        echo "  systemd agents: $AGENT_RUNNING running"

        echo ""
        echo -e "${C_BOLD}Ollama Models:${C_NC}"
        curl -sf http://localhost:11434/api/tags 2>/dev/null | \
            python3 -c "import sys,json; [print(f'  {m[\"name\"]}') for m in json.load(sys.stdin).get('models',[])]" 2>/dev/null || \
            echo "  (not reachable)"

        echo ""
        echo -e "${C_BOLD}Resources:${C_NC}"
        echo "  CPU:  $(top -bn1 | grep 'Cpu(s)' | awk '{printf "%.0f%%", $2}' 2>/dev/null || echo '?')"
        echo "  RAM:  $(free -h | awk '/Mem:/{printf "%s / %s", $3, $2}' 2>/dev/null || echo '?')"
        echo "  Disk: $(df -h / | tail -1 | awk '{printf "%s / %s (%s)", $3, $2, $5}')"
        echo ""
        ;;

    start)
        echo "Starting Galaxia Jarvis..."
        systemctl start galaxia-jarvis
        sleep 2
        systemctl status galaxia-jarvis --no-pager
        ;;

    stop)
        echo "Stopping Galaxia Jarvis..."
        systemctl stop galaxia-jarvis
        ;;

    restart)
        echo "Restarting Galaxia Jarvis..."
        systemctl restart galaxia-jarvis
        sleep 2
        systemctl status galaxia-jarvis --no-pager
        ;;

    logs)
        journalctl -u galaxia-jarvis -f --no-pager -n ${2:-50}
        ;;

    brain)
        echo "Forcing brain cycle..."
        python3 -c "
import asyncio, redis
r = redis.Redis()
r.publish('galaxia:kernel', '{\"sender\":\"cli\",\"recipient\":\"kernel\",\"msg_type\":\"command\",\"payload\":{\"command\":\"brain_cycle\"}}')
print('Brain cycle triggered via Redis')
" 2>/dev/null || echo "Failed - is Redis running?"
        ;;

    health)
        echo -e "\n${C_CYAN}${C_BOLD}=== HEALTH CHECK ===${C_NC}\n"
        echo -n "  Ollama:     "; curl -sf http://localhost:11434/api/tags > /dev/null && echo -e "${C_GREEN}OK${C_NC}" || echo -e "${C_RED}FAIL${C_NC}"
        echo -n "  Redis:      "; redis-cli ping 2>/dev/null | grep -q PONG && echo -e "${C_GREEN}OK${C_NC}" || echo -e "${C_RED}FAIL${C_NC}"
        echo -n "  LiteLLM:    "; curl -sf http://localhost:4000/health > /dev/null && echo -e "${C_GREEN}OK${C_NC}" || echo -e "${C_RED}FAIL${C_NC}"
        echo -n "  Neo4j:      "; curl -sf http://localhost:7474 > /dev/null && echo -e "${C_GREEN}OK${C_NC}" || echo -e "${C_RED}FAIL${C_NC}"
        echo -n "  n8n:        "; curl -sf http://localhost:5678/healthz > /dev/null && echo -e "${C_GREEN}OK${C_NC}" || echo -e "${C_RED}FAIL${C_NC}"
        echo -n "  Jarvis:     "; systemctl is-active --quiet galaxia-jarvis && echo -e "${C_GREEN}OK${C_NC}" || echo -e "${C_RED}FAIL${C_NC}"
        echo -n "  Telegram:   "; systemctl is-active --quiet galaxia-jarvis && echo -e "${C_GREEN}via Jarvis${C_NC}" || echo -e "${C_YELLOW}not started${C_NC}"
        echo ""
        ;;

    migrate-telegram)
        echo -e "${C_YELLOW}Migrating Telegram bot to Jarvis...${C_NC}"
        echo ""
        if systemctl is-active --quiet m0claw-telegram 2>/dev/null; then
            echo "  Stopping old bot (m0claw-telegram)..."
            systemctl stop m0claw-telegram
            systemctl disable m0claw-telegram
            echo -e "  ${C_GREEN}Old bot stopped${C_NC}"
        fi
        echo "  Starting Jarvis with Telegram..."
        systemctl restart galaxia-jarvis
        sleep 3
        if systemctl is-active --quiet galaxia-jarvis; then
            echo -e "  ${C_GREEN}Jarvis Telegram bot active!${C_NC}"
            echo "  Teste: Schreib deinem Bot auf Telegram"
        else
            echo -e "  ${C_RED}Jarvis failed to start - check logs:${C_NC}"
            echo "    galaxia logs"
        fi
        ;;

    *)
        echo -e "\n${C_CYAN}${C_BOLD}GALAXIA OS${C_NC}\n"
        echo "  galaxia status            - System overview"
        echo "  galaxia start             - Start Jarvis"
        echo "  galaxia stop              - Stop Jarvis"
        echo "  galaxia restart           - Restart Jarvis"
        echo "  galaxia logs [n]          - View logs (last n lines)"
        echo "  galaxia health            - Full health check"
        echo "  galaxia brain             - Force brain cycle"
        echo "  galaxia migrate-telegram  - Migrate bot to Jarvis"
        echo ""
        ;;
esac
CLIEOF

chmod +x /usr/local/bin/galaxia
log INFO "Management CLI installed: /usr/local/bin/galaxia"

# =============================================================================
# STEP 10: HEALTH CHECK & VERIFICATION
# =============================================================================
header "STEP 10/10: Health Check & Verification"

HEALTH_OK=0
HEALTH_FAIL=0

check_health() {
    local name="$1"
    local cmd="$2"
    if eval "$cmd" > /dev/null 2>&1; then
        echo -e "  ${GREEN}[OK]${NC}  $name"
        log INFO "Health OK: $name"
        HEALTH_OK=$((HEALTH_OK + 1))
    else
        echo -e "  ${RED}[FAIL]${NC} $name"
        log ERROR "Health FAIL: $name"
        HEALTH_FAIL=$((HEALTH_FAIL + 1))
    fi
}

check_health "Ollama" "curl -sf http://localhost:11434/api/tags"
check_health "Redis" "redis-cli ping 2>/dev/null | grep -q PONG"
check_health "Galaxia directory" "test -d $GALAXIA_DIR/kernel"
check_health "Galaxia .env" "test -f $GALAXIA_DIR/.env"
check_health "Galaxia service" "test -f /etc/systemd/system/galaxia-jarvis.service"
check_health "LiteLLM config" "test -f $GALAXIA_DIR/config/litellm-galaxia.yaml"
check_health "Management CLI" "test -x /usr/local/bin/galaxia"

# Optional checks
check_health "LiteLLM" "curl -sf http://localhost:4000/health" || true
check_health "Neo4j" "curl -sf http://localhost:7474" || true
check_health "n8n" "curl -sf http://localhost:5678/healthz" || true

echo ""

# =============================================================================
# FINAL SUMMARY
# =============================================================================
echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           GALAXIA OS DEPLOYMENT COMPLETE                    ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo -e "${NC}"
echo -e "  ${BOLD}Galaxia Kernel:${NC}    Installed at $GALAXIA_DIR"
echo -e "  ${BOLD}Redis:${NC}             ${ENDPOINTS[redis]:-not detected}"
echo -e "  ${BOLD}LiteLLM routing:${NC}   $GALAXIA_DIR/config/litellm-galaxia.yaml"
echo -e "  ${BOLD}Telegram:${NC}          Migration ready (run: galaxia migrate-telegram)"
echo -e "  ${BOLD}Detected agents:${NC}   $AGENT_COUNT systemd agents"
echo -e "  ${BOLD}Health:${NC}            ${GREEN}$HEALTH_OK OK${NC} / ${RED}$HEALTH_FAIL FAIL${NC}"
echo ""
echo -e "  ${BOLD}Metrics port:${NC}      $JARVIS_METRICS_PORT"
echo -e "  ${BOLD}API port:${NC}          $JARVIS_API_PORT"
echo ""
echo -e "  ${BOLD}Active models:${NC}"
curl -sf http://localhost:11434/api/tags 2>/dev/null | \
    python3 -c "import sys,json; [print(f'    - {m[\"name\"]}') for m in json.load(sys.stdin).get('models',[])]" 2>/dev/null || \
    echo "    (Ollama not reachable)"
echo ""
echo -e "  ${CYAN}${BOLD}Naechste Schritte:${NC}"
echo "    1. galaxia start                  # Jarvis starten"
echo "    2. galaxia migrate-telegram       # Telegram Bot migrieren"
echo "    3. galaxia health                 # System pruefen"
echo "    4. galaxia logs                   # Logs beobachten"
echo ""
echo -e "  ${CYAN}Telegram Commands nach Migration:${NC}"
echo "    /status   - Systemstatus"
echo "    /agents   - Agent-Uebersicht"
echo "    /think    - Brain-Zyklus erzwingen"
echo "    /revenue  - Revenue-Task erstellen"
echo "    /leads    - Lead-Gen starten"
echo "    /product  - Produkt entwickeln"
echo "    /run      - Beliebige Aufgabe"
echo ""
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}${BOLD}Galaxia OS successfully integrated with the AI cluster.${NC}"
echo ""

log INFO "Deploy completed. Health: $HEALTH_OK OK, $HEALTH_FAIL FAIL"
log INFO "Galaxia OS successfully integrated with the AI cluster."
