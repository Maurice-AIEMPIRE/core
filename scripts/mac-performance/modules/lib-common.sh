#!/bin/bash
###############################################################################
# GEMEINSAME BIBLIOTHEK - Wird von allen Modulen verwendet
###############################################################################

# Farben
export C_RED='\033[0;31m'
export C_GREEN='\033[0;32m'
export C_YELLOW='\033[1;33m'
export C_BLUE='\033[0;34m'
export C_MAGENTA='\033[0;35m'
export C_CYAN='\033[0;36m'
export C_BOLD='\033[1m'
export C_NC='\033[0m'

# Pfade
export GUARDIAN_HOME="$HOME/.mac-guardian"
export GUARDIAN_LOG="$GUARDIAN_HOME/logs"
export GUARDIAN_DATA="$GUARDIAN_HOME/data"
export GUARDIAN_CONFIG="$GUARDIAN_HOME/config"
export GUARDIAN_MODULES="$GUARDIAN_HOME/modules"
export GUARDIAN_HISTORY="$GUARDIAN_HOME/history"

# Verzeichnisse erstellen
mkdir -p "$GUARDIAN_LOG" "$GUARDIAN_DATA" "$GUARDIAN_CONFIG" "$GUARDIAN_MODULES" "$GUARDIAN_HISTORY"

# Logging
guardian_log() {
    local module="$1" level="$2" ; shift 2
    local msg="$*"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    local logfile="$GUARDIAN_LOG/${module}.log"
    echo "[$ts] [$level] $msg" >> "$logfile"
    # Master-Log
    echo "[$ts] [$module] [$level] $msg" >> "$GUARDIAN_LOG/master.log"
    # Log-Rotation (max 50MB pro Datei)
    if [ -f "$logfile" ]; then
        local sz
        sz=$(stat -f%z "$logfile" 2>/dev/null || stat -c%s "$logfile" 2>/dev/null || echo 0)
        if [ "$sz" -gt 52428800 ]; then
            mv "$logfile" "${logfile}.$(date +%Y%m%d).old"
            gzip "${logfile}.$(date +%Y%m%d).old" 2>/dev/null &
        fi
    fi
}

# macOS-Benachrichtigung
guardian_notify() {
    local title="$1" message="$2" urgency="${3:-normal}"
    local sound="Pop"
    [ "$urgency" = "critical" ] && sound="Basso"
    [ "$urgency" = "success" ] && sound="Glass"
    osascript -e "display notification \"$message\" with title \"🛡 Mac Guardian\" subtitle \"$title\" sound name \"$sound\"" 2>/dev/null || true
}

# Metrik speichern (fuer Trend-Analyse)
guardian_record_metric() {
    local metric_name="$1" value="$2"
    local ts
    ts=$(date +%s)
    echo "$ts,$value" >> "$GUARDIAN_DATA/${metric_name}.csv"
    # Nur letzte 24h behalten (8640 Eintraege bei 10s Interval)
    if [ -f "$GUARDIAN_DATA/${metric_name}.csv" ]; then
        tail -8640 "$GUARDIAN_DATA/${metric_name}.csv" > "$GUARDIAN_DATA/${metric_name}.csv.tmp"
        mv "$GUARDIAN_DATA/${metric_name}.csv.tmp" "$GUARDIAN_DATA/${metric_name}.csv"
    fi
}

# Trend berechnen (steigend/fallend/stabil)
guardian_get_trend() {
    local metric_name="$1" window="${2:-30}"
    local datafile="$GUARDIAN_DATA/${metric_name}.csv"
    [ ! -f "$datafile" ] && echo "unknown" && return
    local count
    count=$(wc -l < "$datafile" | tr -d ' ')
    [ "$count" -lt "$window" ] && echo "insufficient_data" && return
    # Vergleiche erste und letzte Haelfte des Fensters
    local half=$((window / 2))
    local first_avg last_avg
    first_avg=$(tail -"$window" "$datafile" | head -"$half" | awk -F',' '{sum+=$2} END {printf "%d", sum/NR}')
    last_avg=$(tail -"$half" "$datafile" | awk -F',' '{sum+=$2} END {printf "%d", sum/NR}')
    local diff=$((last_avg - first_avg))
    if [ "$diff" -gt 5 ]; then
        echo "rising"
    elif [ "$diff" -lt -5 ]; then
        echo "falling"
    else
        echo "stable"
    fi
}

# Event-History (fuer KI-Entscheidungen)
guardian_record_event() {
    local event_type="$1" details="$2" action_taken="${3:-none}"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$ts|$event_type|$details|$action_taken" >> "$GUARDIAN_HISTORY/events.log"
}

# Lese letzte Events eines Typs
guardian_count_recent_events() {
    local event_type="$1" minutes="${2:-60}"
    local cutoff
    cutoff=$(date -v-"${minutes}"M +%s 2>/dev/null || date -d "-${minutes} minutes" +%s 2>/dev/null || echo 0)
    [ ! -f "$GUARDIAN_HISTORY/events.log" ] && echo 0 && return
    awk -F'|' -v type="$event_type" -v cutoff="$cutoff" '
        $2 == type {
            cmd = "date -j -f \"%Y-%m-%d %H:%M:%S\" \"" $1 "\" +%s 2>/dev/null"
            cmd | getline ts
            close(cmd)
            if (ts > cutoff) count++
        }
        END {print count+0}
    ' "$GUARDIAN_HISTORY/events.log"
}

# System-Info Helfer
get_macos_version() {
    sw_vers -productVersion 2>/dev/null || echo "unknown"
}

is_apple_silicon() {
    [[ "$(uname -m)" == "arm64" ]]
}

get_total_ram_gb() {
    echo $(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
}

get_cpu_core_count() {
    sysctl -n hw.ncpu 2>/dev/null || echo 0
}
