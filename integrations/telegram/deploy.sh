#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  IMPERIUM DEPLOY — One-Command Start
#  Starts: Harvey Bot + Stripe Webhook + GPE-Core Napoleon
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$(cd "$REPO_DIR/../.." && pwd)"
GPE_DIR="/root/gpe-core"
LOG_DIR="/root/logs/imperium"
PID_DIR="/root/pids/imperium"
ENV_FILE="$REPO_DIR/.env"

mkdir -p "$LOG_DIR" "$PID_DIR"

# ── Colors ───────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log()   { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ── Load .env ────────────────────────────────────────────────────
if [[ -f "$ENV_FILE" ]]; then
  set -a; source "$ENV_FILE"; set +a
  log "Loaded .env from $ENV_FILE"
else
  warn ".env nicht gefunden — stelle sicher dass env vars gesetzt sind"
fi

# ── Validate required env vars ───────────────────────────────────
MISSING=()
[[ -z "${TELEGRAM_BOT_TOKEN:-}" ]] && MISSING+=("TELEGRAM_BOT_TOKEN")
[[ -z "${ANTHROPIC_API_KEY:-}" ]] && MISSING+=("ANTHROPIC_API_KEY (für beste Analysen)")

if [[ ${#MISSING[@]} -gt 0 ]]; then
  warn "Fehlende env vars:"
  for v in "${MISSING[@]}"; do warn "  • $v"; done
fi

# ── Helper: start a background process ───────────────────────────
start_process() {
  local name="$1"; shift
  local pidfile="$PID_DIR/${name}.pid"
  local logfile="$LOG_DIR/${name}.log"

  if [[ -f "$pidfile" ]]; then
    local old_pid; old_pid=$(cat "$pidfile")
    if kill -0 "$old_pid" 2>/dev/null; then
      log "${name} läuft bereits (PID $old_pid)"
      return 0
    fi
    rm -f "$pidfile"
  fi

  nohup "$@" >> "$logfile" 2>&1 &
  local pid=$!
  echo "$pid" > "$pidfile"
  sleep 1
  if kill -0 "$pid" 2>/dev/null; then
    log "${GREEN}▶ ${name}${NC} gestartet (PID $pid) → $logfile"
  else
    error "${name} konnte nicht gestartet werden. Prüfe: tail -50 $logfile"
    return 1
  fi
}

# ── Stop all ─────────────────────────────────────────────────────
stop_all() {
  log "Stoppe alle Prozesse..."
  for pidfile in "$PID_DIR"/*.pid; do
    [[ -f "$pidfile" ]] || continue
    local name; name=$(basename "$pidfile" .pid)
    local pid; pid=$(cat "$pidfile")
    if kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" && log "⏹ $name (PID $pid) gestoppt"
    fi
    rm -f "$pidfile"
  done
  log "Alle Prozesse gestoppt."
}

# ── Status ───────────────────────────────────────────────────────
show_status() {
  echo -e "\n${BOLD}═══ IMPERIUM STATUS ═══${NC}"
  for pidfile in "$PID_DIR"/*.pid; do
    [[ -f "$pidfile" ]] || continue
    local name; name=$(basename "$pidfile" .pid)
    local pid; pid=$(cat "$pidfile")
    if kill -0 "$pid" 2>/dev/null; then
      echo -e "  ${GREEN}✓${NC} ${name} (PID $pid)"
    else
      echo -e "  ${RED}✗${NC} ${name} (dead)"
    fi
  done

  # Black Hole API check
  if curl -sf "http://localhost:8001/stats" >/dev/null 2>&1; then
    local bh_total; bh_total=$(curl -sf "http://localhost:8001/stats" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('total','?'))" 2>/dev/null || echo "?")
    echo -e "  ${GREEN}✓${NC} Black Hole API (port 8001) — ${bh_total} items"
  else
    echo -e "  ${YELLOW}?${NC} Black Hole API (port 8001) — nicht erreichbar"
  fi

  echo ""
}

# ── Main ─────────────────────────────────────────────────────────
case "${1:-start}" in

  start)
    echo -e "\n${BOLD}${BLUE}╔══════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║   IMPERIUM DEPLOY — START         ║${NC}"
    echo -e "${BOLD}${BLUE}╚══════════════════════════════════╝${NC}\n"

    # 1. Harvey Legal Bot
    if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
      BOT_PERSONA=harvey \
      TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN" \
      start_process "harvey" \
        npx tsx "$REPO_DIR/src/bot.ts"
    else
      warn "Harvey nicht gestartet — TELEGRAM_BOT_TOKEN fehlt"
    fi

    # 2. Stripe Webhook Server
    if [[ -n "${STRIPE_WEBHOOK_SECRET:-}" ]] || [[ -n "${STRIPE_PAYMENT_LINK:-}" ]]; then
      start_process "stripe_webhook" \
        npx tsx "$REPO_DIR/src/stripe_webhook.ts"
    else
      warn "Stripe Webhook nicht gestartet — STRIPE_WEBHOOK_SECRET fehlt"
    fi

    # 3. Black Hole API (if not already running)
    if ! curl -sf "http://localhost:8001/stats" >/dev/null 2>&1; then
      if [[ -f "/root/blackhole/api/server.py" ]]; then
        start_process "blackhole_api" \
          python3 -m uvicorn api.server:app --host 0.0.0.0 --port 8001 --app-dir /root/blackhole
      fi
    else
      log "Black Hole API läuft bereits (port 8001)"
    fi

    # 4. Napoleon (GPE-Core)
    if [[ -f "$GPE_DIR/napoleon_core.py" ]]; then
      start_process "napoleon" \
        python3 "$GPE_DIR/napoleon_core.py" --daemon
    fi

    sleep 2
    show_status
    log "${BOLD}Alles gestartet! Logs: $LOG_DIR${NC}"
    ;;

  stop)
    stop_all
    ;;

  restart)
    stop_all
    sleep 2
    exec "$0" start
    ;;

  status)
    show_status
    ;;

  logs)
    local service="${2:-harvey}"
    tail -f "$LOG_DIR/${service}.log"
    ;;

  *)
    echo "Usage: $0 {start|stop|restart|status|logs [service]}"
    exit 1
    ;;
esac
