#!/bin/bash
# ════════════════════════════════════════════════
#  GPE-Core Start Script v3
#  Manages: napoleon, task_router, health_check, meta_supervisor
# ════════════════════════════════════════════════
set -euo pipefail

BASE_DIR="${GPE_CORE_DIR:-/home/user/core/gpe-core}"
LOG_DIR="$BASE_DIR/logs"
PID_DIR="$BASE_DIR/pids"

mkdir -p "$LOG_DIR" "$PID_DIR" "$BASE_DIR/missions" "$BASE_DIR/analyzer" "$BASE_DIR/snapshots"

export PYTHONPATH="$BASE_DIR:$BASE_DIR/analyzer:$BASE_DIR/dispatcher"
export GPE_CORE_DIR="$BASE_DIR"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

# ── Process Management ────────────────────────────────────────────────────────
start_service() {
    local name="$1"; local script="$2"
    local pidfile="$PID_DIR/${name}.pid"
    local logfile="$LOG_DIR/${name}.log"

    if [[ ! -f "$script" ]]; then
        warn "Skipping $name — $script nicht gefunden"
        return 0
    fi

    if [[ -f "$pidfile" ]]; then
        local old_pid; old_pid=$(cat "$pidfile")
        if kill -0 "$old_pid" 2>/dev/null; then
            log "⏩ $name läuft bereits (PID $old_pid)"
            return 0
        fi
        rm -f "$pidfile"
    fi

    nohup python3 "$script" >> "$logfile" 2>&1 &
    echo "$!" > "$pidfile"
    sleep 1
    local pid; pid=$(cat "$pidfile")
    if kill -0 "$pid" 2>/dev/null; then
        log "▶ $name gestartet (PID $pid)"
    else
        warn "$name crashed beim Start — prüfe: tail -20 $logfile"
    fi
}

stop_service() {
    local name="$1"
    local pidfile="$PID_DIR/${name}.pid"
    if [[ -f "$pidfile" ]]; then
        local pid; pid=$(cat "$pidfile")
        kill -TERM "$pid" 2>/dev/null && log "⏹ $name gestoppt (PID $pid)" || true
        rm -f "$pidfile"
    fi
}

status_service() {
    local name="$1"
    local pidfile="$PID_DIR/${name}.pid"
    if [[ -f "$pidfile" ]]; then
        local pid; pid=$(cat "$pidfile")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $name (PID $pid)"
        else
            echo -e "  ${RED}✗${NC} $name (dead — PID $pid)"
            rm -f "$pidfile"
        fi
    else
        echo -e "  ${RED}○${NC} $name (nicht gestartet)"
    fi
}

# ── Commands ─────────────────────────────────────────────────────────────────
case "${1:-start}" in

start)
    log "GPE-Core starten..."
    start_service "napoleon"        "$BASE_DIR/napoleon_core.py --daemon"
    # Napoleon needs daemon flag — rewrite:
    nohup python3 "$BASE_DIR/napoleon_core.py" --daemon >> "$LOG_DIR/napoleon.log" 2>&1 &
    echo "$!" > "$PID_DIR/napoleon.pid"

    start_service "task_router"    "$BASE_DIR/dispatcher/task_router.py"
    start_service "health_check"   "$BASE_DIR/health_check.py"
    start_service "meta_supervisor" "$BASE_DIR/meta_supervisor_full.py"

    sleep 2
    echo ""
    log "=== STATUS ==="
    status_service "napoleon"
    status_service "task_router"
    status_service "health_check"
    status_service "meta_supervisor"
    ;;

stop)
    log "GPE-Core stoppen..."
    for name in napoleon task_router health_check meta_supervisor; do
        stop_service "$name"
    done
    log "Alle gestoppt."
    ;;

restart)
    "$0" stop
    sleep 2
    "$0" start
    ;;

status)
    echo "GPE-Core Status:"
    for name in napoleon task_router health_check meta_supervisor; do
        status_service "$name"
    done
    ;;

*)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac
