#!/bin/bash
###############################################################################
# MASTER ORCHESTRATOR - Verbindet alle Module
#
# Der Orchestrator ist das Gehirn des gesamten Systems:
# - Fuehrt alle Module zyklisch aus
# - Nutzt die AI-Brain fuer Entscheidungen
# - Koordiniert Aktionen zwischen Modulen
# - Erstellt Tagesberichte
# - Selbstheilung bei Modul-Ausfaellen
###############################################################################

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-common.sh"

MODULE="orchestrator"
PID_FILE="$GUARDIAN_HOME/orchestrator.pid"

# Lade Config
CONFIG_FILE="$GUARDIAN_CONFIG/guardian.conf"
CHECK_INTERVAL=${CHECK_INTERVAL:-10}
DAILY_REPORT_HOUR=${DAILY_REPORT_HOUR:-22}  # 22 Uhr Tagesbericht

###############################################################################
# MODUL-LOADER
###############################################################################

load_module() {
    local module_file="$SCRIPT_DIR/$1"
    if [ -f "$module_file" ]; then
        source "$module_file"
        return 0
    else
        guardian_log "$MODULE" "ERROR" "Modul nicht gefunden: $1"
        return 1
    fi
}

###############################################################################
# AKTIONS-EXECUTOR
# Fuehrt die vom AI-Brain empfohlene Aktion aus
###############################################################################

execute_action() {
    local decision="$1" urgency="$2" reason="$3"

    guardian_log "$MODULE" "EXEC" "Aktion: $decision (Dringlichkeit: $urgency, Grund: $reason)"

    case "$decision" in
        "none")
            return 0
            ;;

        "emergency_kill")
            guardian_notify "SYSTEM-NOTFALL" "$reason - Notfall-Massnahmen aktiv!" "critical"
            # Speicher freigeben
            source "$SCRIPT_DIR/memory-guardian.sh"
            free_memory_emergency
            # Thermisch abkuehlen
            source "$SCRIPT_DIR/thermal-guardian.sh"
            reduce_cpu_load "heavy"
            ;;

        "kill_cpu_hogs")
            source "$SCRIPT_DIR/process-manager.sh"
            handle_runaway
            source "$SCRIPT_DIR/memory-guardian.sh"
            free_memory_soft
            ;;

        "free_memory_aggressive")
            source "$SCRIPT_DIR/memory-guardian.sh"
            free_memory_aggressive
            ;;

        "free_memory_soft")
            source "$SCRIPT_DIR/memory-guardian.sh"
            free_memory_soft
            ;;

        "preventive_action")
            guardian_notify "Praevention" "$reason" "normal"
            source "$SCRIPT_DIR/memory-guardian.sh"
            free_memory_soft
            source "$SCRIPT_DIR/process-manager.sh"
            adjust_priorities
            ;;

        "investigate_anomaly")
            guardian_log "$MODULE" "ANOMALY" "Anomalie wird untersucht: $reason"
            guardian_notify "Anomalie erkannt" "$reason" "normal"
            # Snapshot fuer spaetere Analyse
            ps aux --sort=-%cpu > "$GUARDIAN_DATA/anomaly_snapshot_$(date +%s).txt" 2>/dev/null
            ;;

        "soft_intervention")
            source "$SCRIPT_DIR/process-manager.sh"
            adjust_priorities
            source "$SCRIPT_DIR/memory-guardian.sh"
            free_memory_soft
            ;;

        "thermal_mitigation")
            source "$SCRIPT_DIR/thermal-guardian.sh"
            reduce_cpu_load "medium"
            ;;

        *)
            guardian_log "$MODULE" "WARN" "Unbekannte Aktion: $decision"
            ;;
    esac

    guardian_record_event "action_executed" "$decision|$reason" "$urgency"
}

###############################################################################
# FEEDBACK-LOOP
# Pruefen ob die letzte Aktion erfolgreich war
###############################################################################

evaluate_last_action() {
    local last_action_file="$GUARDIAN_DATA/last_action"
    [ ! -f "$last_action_file" ] && return

    IFS='|' read -r action cpu_before ram_before ts <<< "$(cat "$last_action_file")"
    local now
    now=$(date +%s)

    # Warte 30 Sekunden nach Aktion fuer Evaluation
    [ $((now - ts)) -lt 30 ] && return

    # Aktuelle Werte holen
    local cpu_now ram_now
    cpu_now=$(top -l 1 -n 0 -s 0 2>/dev/null | grep "CPU usage" | awk '{print $7}' | tr -d '%')
    cpu_now=$((100 - ${cpu_now%.*}))

    source "$SCRIPT_DIR/memory-guardian.sh"
    local mem_info
    mem_info=$(get_ram_metrics)
    ram_now=$(echo "$mem_info" | cut -d'|' -f1)

    # AI-Brain: Aktion bewerten
    source "$SCRIPT_DIR/ai-brain.sh"
    if [ "$cpu_now" -lt "$cpu_before" ] || [ "$ram_now" -lt "$ram_before" ]; then
        brain_learn "$(echo "$action" | cut -d'_' -f1)" "$action" "success"
        guardian_log "$MODULE" "FEEDBACK" "Erfolg: $action (CPU: $cpu_before->$cpu_now%, RAM: $ram_before->$ram_now%)"
    else
        brain_learn "$(echo "$action" | cut -d'_' -f1)" "$action" "failure"
        guardian_log "$MODULE" "FEEDBACK" "Wirkungslos: $action (CPU: $cpu_before->$cpu_now%, RAM: $ram_before->$ram_now%)"
    fi

    rm -f "$last_action_file"
}

###############################################################################
# HAUPT-UEBERWACHUNGSSCHLEIFE
###############################################################################

monitoring_loop() {
    guardian_log "$MODULE" "START" "Orchestrator gestartet (PID: $$)"
    guardian_notify "Guardian aktiv" "Alle Module geladen - System wird ueberwacht" "success"

    local cycle=0
    local last_daily_report=""

    while true; do
        cycle=$((cycle + 1))

        #######################################################################
        # 1. METRIKEN SAMMELN
        #######################################################################

        # CPU
        local cpu_idle
        cpu_idle=$(top -l 1 -n 0 -s 0 2>/dev/null | grep "CPU usage" | awk '{print $7}' | tr -d '%')
        local cpu_pct=$((100 - ${cpu_idle%.*}))
        guardian_record_metric "cpu_total" "$cpu_pct"

        # RAM
        source "$SCRIPT_DIR/memory-guardian.sh"
        local mem_result
        mem_result=$(memory_check)
        local ram_pct
        ram_pct=$(echo "$mem_result" | cut -d'|' -f1)
        local swap_mb
        swap_mb=$(echo "$mem_result" | cut -d'|' -f3)

        # Temperatur
        local temp=0
        source "$SCRIPT_DIR/thermal-guardian.sh"
        local thermal_result
        thermal_result=$(thermal_check 2>/dev/null)
        temp=$(cat "$GUARDIAN_DATA/cpu_temp.csv" 2>/dev/null | tail -1 | cut -d',' -f2)
        temp=${temp:-0}

        # Disk (alle 30 Zyklen = 5 Minuten)
        local disk_pct=0
        if [ $((cycle % 30)) -eq 0 ]; then
            source "$SCRIPT_DIR/disk-guardian.sh"
            local disk_result
            disk_result=$(disk_check)
            disk_pct=$(echo "$disk_result" | cut -d'|' -f1)
        else
            disk_pct=$(cat "$GUARDIAN_DATA/disk_used_pct.csv" 2>/dev/null | tail -1 | cut -d',' -f2)
            disk_pct=${disk_pct:-0}
        fi

        # Network (alle 12 Zyklen = 2 Minuten)
        if [ $((cycle % 12)) -eq 0 ]; then
            source "$SCRIPT_DIR/network-optimizer.sh"
            network_check >/dev/null 2>&1
        fi

        # Prozesse
        source "$SCRIPT_DIR/process-manager.sh"
        process_check >/dev/null 2>&1

        #######################################################################
        # 2. AI-BRAIN ENTSCHEIDUNG
        #######################################################################

        source "$SCRIPT_DIR/ai-brain.sh"
        local brain_result
        brain_result=$(brain_decide "$cpu_pct" "$ram_pct" "${swap_mb:-0}" "$temp" "$disk_pct")

        IFS='|' read -r decision urgency reason root_cause <<< "$brain_result"

        #######################################################################
        # 3. AKTION AUSFUEHREN (wenn noetig)
        #######################################################################

        if [ "$decision" != "none" ]; then
            # Vorher-Zustand speichern (fuer Feedback-Loop)
            echo "${decision}|${cpu_pct}|${ram_pct}|$(date +%s)" > "$GUARDIAN_DATA/last_action"

            execute_action "$decision" "$urgency" "$reason"
        fi

        #######################################################################
        # 4. FEEDBACK-LOOP
        #######################################################################

        evaluate_last_action

        #######################################################################
        # 5. STATUS-LOG (alle 30 Zyklen = 5 Minuten)
        #######################################################################

        if [ $((cycle % 30)) -eq 0 ]; then
            guardian_log "$MODULE" "STATUS" \
                "Zyklus=$cycle CPU=${cpu_pct}% RAM=${ram_pct}% Swap=${swap_mb:-0}MB Temp=${temp}C Disk=${disk_pct}% Decision=$decision"
        fi

        #######################################################################
        # 6. TAGESBERICHT (einmal taeglich)
        #######################################################################

        local current_hour
        current_hour=$(date +%H)
        local today
        today=$(date +%Y%m%d)

        if [ "$current_hour" = "$DAILY_REPORT_HOUR" ] && [ "$last_daily_report" != "$today" ]; then
            source "$SCRIPT_DIR/ai-brain.sh"
            brain_daily_report
            last_daily_report="$today"
            guardian_notify "Tagesbericht" "Guardian-Tagesbericht erstellt" "success"
        fi

        #######################################################################
        # 7. SELBSTHEILUNG: Log-Rotation, Daten-Bereinigung
        #######################################################################

        if [ $((cycle % 360)) -eq 0 ]; then  # Alle 60 Minuten
            # Alte Anomalie-Snapshots loeschen (>24h)
            find "$GUARDIAN_DATA" -name "anomaly_snapshot_*" -mtime +1 -delete 2>/dev/null || true
            # Alte Metriken trimmen (werden in lib-common gemacht)
            guardian_log "$MODULE" "MAINTENANCE" "Wartung durchgefuehrt"
        fi

        sleep "$CHECK_INTERVAL"
    done
}

###############################################################################
# DAEMON-STEUERUNG
###############################################################################

start() {
    if [ -f "$PID_FILE" ]; then
        local old_pid
        old_pid=$(cat "$PID_FILE")
        if kill -0 "$old_pid" 2>/dev/null; then
            echo "Orchestrator laeuft bereits (PID: $old_pid)"
            exit 0
        fi
    fi

    echo "Starte Mac Guardian Orchestrator..."
    monitoring_loop &
    echo $! > "$PID_FILE"
    echo "Gestartet (PID: $!)"
    echo "Log: tail -f $GUARDIAN_LOG/master.log"
}

stop() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            # Auch Kind-Prozesse beenden
            pkill -P "$pid" 2>/dev/null || true
            rm -f "$PID_FILE"
            echo "Orchestrator gestoppt (PID: $pid)"
            guardian_log "$MODULE" "STOP" "Orchestrator gestoppt"
            guardian_notify "Guardian gestoppt" "Ueberwachung deaktiviert" "normal"
        else
            rm -f "$PID_FILE"
            echo "Orchestrator war nicht aktiv"
        fi
    else
        echo "Kein PID-File gefunden"
    fi
}

status() {
    echo ""
    echo "═══════════════════════════════════════"
    echo "  MAC GUARDIAN - Status"
    echo "═══════════════════════════════════════"

    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "  Status: AKTIV (PID: $pid)"
        else
            echo "  Status: INAKTIV (stale PID)"
        fi
    else
        echo "  Status: INAKTIV"
    fi

    # Letzte Metriken
    echo ""
    for metric in cpu_total ram_used_pct cpu_temp disk_used_pct; do
        local val
        val=$(tail -1 "$GUARDIAN_DATA/${metric}.csv" 2>/dev/null | cut -d',' -f2)
        [ -n "$val" ] && echo "  $metric: $val"
    done

    echo ""
    echo "  Letzte 10 Log-Eintraege:"
    tail -10 "$GUARDIAN_LOG/master.log" 2>/dev/null | while IFS= read -r line; do
        echo "    $line"
    done
    echo ""
}

foreground() {
    echo "Orchestrator im Vordergrund (Ctrl+C zum Stoppen)"
    echo $$ > "$PID_FILE"
    trap 'rm -f "$PID_FILE"; guardian_log "$MODULE" "STOP" "Orchestrator gestoppt (Signal)"; exit 0' INT TERM
    monitoring_loop
}

case "${1:-start}" in
    start)      start ;;
    stop)       stop ;;
    status)     status ;;
    foreground) foreground ;;
    audit)
        source "$SCRIPT_DIR/audit-engine.sh"
        ;;
    report)
        source "$SCRIPT_DIR/ai-brain.sh"
        brain_daily_report
        ;;
    *)
        echo "Mac Guardian Orchestrator"
        echo "Usage: $0 {start|stop|status|foreground|audit|report}"
        ;;
esac
