#!/bin/bash
# GPE-Core Schwarzes Loch - Start Script (v2 - Fixed)
# Fixes: proper nohup, PID management, no dead-child processes

set -euo pipefail

BASE_DIR="/root/gpe-core"
LOG_DIR="$BASE_DIR/logs"
PID_DIR="$BASE_DIR/pids"

mkdir -p "$LOG_DIR" "$PID_DIR"

log()  { echo "[$(date '+%H:%M:%S')] $1"; }
die()  { echo "[ERROR] $1" >&2; exit 1; }

start_service() {
    local name="$1"
    local script="$2"
    local pidfile="$PID_DIR/${name}.pid"
    local logfile="$LOG_DIR/${name}.log"

    # Prüfe ob bereits läuft
    if [[ -f "$pidfile" ]]; then
        local old_pid
        old_pid=$(cat "$pidfile")
        if kill -0 "$old_pid" 2>/dev/null; then
            log "⏩ $name läuft bereits (PID $old_pid)"
            return 0
        else
            log "🧹 Altes PID-File für $name entfernt (Prozess tot)"
            rm -f "$pidfile"
        fi
    fi

    log "▶ Starte $name..."
    nohup python3 "$script" >> "$logfile" 2>&1 &
    local pid=$!
    echo "$pid" > "$pidfile"
    log "✓ $name gestartet (PID $pid)"
}

stop_service() {
    local name="$1"
    local pidfile="$PID_DIR/${name}.pid"

    if [[ -f "$pidfile" ]]; then
        local pid
        pid=$(cat "$pidfile")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            log "⏹ $name gestoppt (PID $pid)"
        fi
        rm -f "$pidfile"
    fi
}

status() {
    echo ""
    echo "━━━ GPE-Core Status ━━━"
    for pidfile in "$PID_DIR"/*.pid; do
        [[ -f "$pidfile" ]] || continue
        local name
        name=$(basename "$pidfile" .pid)
        local pid
        pid=$(cat "$pidfile")
        if kill -0 "$pid" 2>/dev/null; then
            echo "  ✅ $name (PID $pid)"
        else
            echo "  ❌ $name (PID $pid — tot)"
        fi
    done
    echo ""
}

case "${1:-start}" in
    start)
        echo "🖤 Starte GPE-Core Schwarzes Loch..."
        echo ""

        # Prüfe Abhängigkeiten
        command -v python3 >/dev/null || die "python3 nicht gefunden"
        python3 -c "import requests" 2>/dev/null || pip3 install requests -q

        # Lade Venv wenn vorhanden
        if [[ -f "$BASE_DIR/crewai-venv/bin/activate" ]]; then
            # shellcheck disable=SC1091
            source "$BASE_DIR/crewai-venv/bin/activate"
        fi

        export PYTHONPATH="$BASE_DIR:$BASE_DIR/analyzer:$BASE_DIR/dispatcher"
        export OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"

        # 1. INTAKE LAYER
        log "[1/5] Intake Layer..."
        start_service "intake"      "$BASE_DIR/intake/file_scanner.py"
        sleep 1

        # 2. ANALYZER LAYER (nur data_cleaner und legal_parser — graph ist Library)
        log "[2/5] Analyzer Layer..."
        start_service "data_cleaner"  "$BASE_DIR/analyzer/data_cleaner.py"
        start_service "legal_parser"  "$BASE_DIR/analyzer/legal_parser.py"
        start_service "repo_analyzer" "$BASE_DIR/analyzer/repo_analyzer.py"
        sleep 2

        # 3. DISPATCHER
        log "[3/5] Dispatcher..."
        start_service "task_router"   "$BASE_DIR/dispatcher/task_router.py"
        sleep 1

        # 4. NAPOLEON CORE
        log "[4/5] Napoleon Core..."
        start_service "napoleon"      "$BASE_DIR/napoleon_core.py"
        sleep 1

        # 5. SELF-IMPROVEMENT (optional — nur wenn explizit aktiviert)
        if [[ "${ENABLE_SELF_IMPROVEMENT:-0}" == "1" ]]; then
            log "[5/5] Self-Improvement Loop..."
            start_service "skill_trainer"  "$BASE_DIR/self_improvement/skill_trainer.py"
            start_service "github_update"  "$BASE_DIR/self_improvement/github_update.py"
        else
            log "[5/5] Self-Improvement: deaktiviert (ENABLE_SELF_IMPROVEMENT=0)"
        fi

        echo ""
        echo "🖤 GPE-Core aktiv!"
        status
        echo "  Logs:    $LOG_DIR/"
        echo "  PIDs:    $PID_DIR/"
        echo "  Stop:    $BASE_DIR/start_all.sh stop"
        echo "  Status:  $BASE_DIR/start_all.sh status"
        ;;

    stop)
        echo "🛑 Stoppe GPE-Core..."
        for name in napoleon task_router legal_parser data_cleaner repo_analyzer intake skill_trainer github_update; do
            stop_service "$name"
        done
        echo "✓ Alle Prozesse gestoppt"
        ;;

    restart)
        "$0" stop
        sleep 2
        "$0" start
        ;;

    status)
        status
        ;;

    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
