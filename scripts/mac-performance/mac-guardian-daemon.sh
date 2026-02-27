#!/bin/bash
###############################################################################
# MAC GUARDIAN DAEMON - Automatisches Performance-Ueberwachungssystem
#
# Dieses Skript laeuft als Hintergrund-Daemon und ueberwacht:
# - CPU-Auslastung
# - RAM-Verbrauch
# - Haengende/eingefrorene Apps
# - Swap-Nutzung
# - Festplatten-Kapazitaet
#
# Wenn Probleme erkannt werden, greift es automatisch ein:
# - Stufe 1 (Warnung):    Benachrichtigung an den Benutzer
# - Stufe 2 (Eingriff):   RAM freigeben, Caches leeren
# - Stufe 3 (Notfall):    Ressourcen-Fresser beenden
# - Stufe 4 (Kritisch):   Haengende Apps force-quitten
#
# Installation: ./install-guardian.sh
# Manuell starten: ./mac-guardian-daemon.sh
# Stoppen: ./mac-guardian-daemon.sh --stop
###############################################################################

set -uo pipefail

# Konfiguration
GUARDIAN_DIR="$HOME/.mac-guardian"
LOG_FILE="$GUARDIAN_DIR/guardian.log"
PID_FILE="$GUARDIAN_DIR/guardian.pid"
CONFIG_FILE="$GUARDIAN_DIR/config.sh"
STATE_FILE="$GUARDIAN_DIR/state.json"

# Standard-Schwellwerte (koennen in config.sh ueberschrieben werden)
CHECK_INTERVAL=10                # Sekunden zwischen Checks
CPU_WARN_THRESHOLD=80            # % CPU fuer Warnung
CPU_CRITICAL_THRESHOLD=95        # % CPU fuer automatisches Eingreifen
RAM_WARN_THRESHOLD=85            # % RAM fuer Warnung
RAM_CRITICAL_THRESHOLD=93        # % RAM fuer automatisches Eingreifen
SWAP_WARN_MB=2048                # MB Swap fuer Warnung
APP_HUNG_TIMEOUT=30              # Sekunden bevor App als "haengend" gilt
MAX_KILLS_PER_HOUR=5             # Max. automatische Kills pro Stunde
DISK_WARN_THRESHOLD=90           # % Festplatte fuer Warnung

# Apps die NIEMALS automatisch beendet werden
PROTECTED_APPS=(
    "Finder"
    "WindowServer"
    "kernel_task"
    "loginwindow"
    "SystemUIServer"
    "Dock"
    "launchd"
    "Terminal"
    "iTerm2"
    "Claude"
    "Activity Monitor"
)

# Prioritaetsliste: Diese Apps werden zuerst beendet (wenn sie Ressourcen fressen)
LOW_PRIORITY_APPS=(
    "Slack"
    "Discord"
    "Spotify"
    "Microsoft Teams"
    "zoom.us"
    "Skype"
    "Steam"
    "Epic Games"
    "Adobe Premiere"
    "Adobe After Effects"
    "Docker"
)

###############################################################################
# Hilfsfunktionen
###############################################################################

mkdir -p "$GUARDIAN_DIR"

# Konfiguration laden falls vorhanden
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"

    # Log-Rotation: Max 10MB
    if [ -f "$LOG_FILE" ]; then
        local size
        size=$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$size" -gt 10485760 ]; then
            mv "$LOG_FILE" "${LOG_FILE}.old"
            log "INFO" "Log rotiert"
        fi
    fi
}

notify() {
    local title="$1"
    local message="$2"
    local urgency="${3:-normal}"

    if [ "$urgency" = "critical" ]; then
        local sound="Basso"
    else
        local sound="Pop"
    fi

    osascript -e "display notification \"$message\" with title \"🛡 Mac Guardian\" subtitle \"$title\" sound name \"$sound\"" 2>/dev/null || true
}

is_protected() {
    local app_name="$1"
    for protected in "${PROTECTED_APPS[@]}"; do
        if [[ "$app_name" == *"$protected"* ]]; then
            return 0
        fi
    done
    return 1
}

is_low_priority() {
    local app_name="$1"
    for lp in "${LOW_PRIORITY_APPS[@]}"; do
        if [[ "$app_name" == *"$lp"* ]]; then
            return 0
        fi
    done
    return 1
}

get_kill_count_this_hour() {
    local hour_key
    hour_key=$(date '+%Y%m%d%H')
    grep -c "\[$hour_key" "$GUARDIAN_DIR/kills.log" 2>/dev/null || echo 0
}

record_kill() {
    local app_name="$1"
    local reason="$2"
    echo "[$(date '+%Y%m%d%H%M%S')] Beendet: $app_name - Grund: $reason" >> "$GUARDIAN_DIR/kills.log"
}

###############################################################################
# System-Metriken sammeln
###############################################################################

get_cpu_usage() {
    # Gesamte CPU-Auslastung (idle subtrahiert von 100)
    local idle
    idle=$(top -l 1 -n 0 -s 0 2>/dev/null | grep "CPU usage" | awk '{print $7}' | tr -d '%')
    if [ -n "$idle" ]; then
        echo "$((100 - ${idle%.*}))"
    else
        echo "0"
    fi
}

get_ram_usage_percent() {
    local page_size
    page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
    local total_mem
    total_mem=$(sysctl -n hw.memsize 2>/dev/null || echo 0)

    local vm_stats
    vm_stats=$(vm_stat 2>/dev/null)

    local free_pages active_pages wired_pages compressed_pages
    free_pages=$(echo "$vm_stats" | awk '/Pages free/ {print $3}' | tr -d '.')
    active_pages=$(echo "$vm_stats" | awk '/Pages active/ {print $3}' | tr -d '.')
    wired_pages=$(echo "$vm_stats" | awk '/Pages wired/ {print $4}' | tr -d '.')
    compressed_pages=$(echo "$vm_stats" | awk '/occupied by compressor/ {print $5}' | tr -d '.')

    local used_bytes
    used_bytes=$(( (active_pages + wired_pages + compressed_pages) * page_size ))

    if [ "$total_mem" -gt 0 ]; then
        echo $(( used_bytes * 100 / total_mem ))
    else
        echo "0"
    fi
}

get_swap_mb() {
    sysctl -n vm.swapusage 2>/dev/null | awk '{
        val = $6;
        gsub(/M/, "", val);
        printf "%d", val
    }'
}

get_disk_usage_percent() {
    df -H / 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%'
}

###############################################################################
# Haengende Apps erkennen
###############################################################################

detect_hung_apps() {
    local hung_apps=""

    # Alle GUI-Apps holen
    local apps
    apps=$(osascript -e 'tell application "System Events" to get name of every application process whose background only is false' 2>/dev/null | tr ',' '\n')

    while IFS= read -r app; do
        app=$(echo "$app" | xargs)
        [ -z "$app" ] && continue

        if is_protected "$app"; then
            continue
        fi

        # Teste ob App reagiert (2 Sekunden Timeout)
        if ! timeout 2 osascript -e "tell application \"$app\" to count windows" &>/dev/null 2>&1; then
            hung_apps="${hung_apps}${app}\n"
        fi
    done <<< "$apps"

    echo -e "$hung_apps"
}

###############################################################################
# Top Ressourcen-Fresser finden
###############################################################################

get_top_cpu_hogs() {
    # Gibt PID, Name und CPU% zurueck fuer Prozesse ueber dem Schwellwert
    ps aux -r | awk -v threshold="$1" '
        NR>1 && $3>threshold {
            printf "%s|%s|%s\n", $2, $11, $3
        }
    ' | head -10
}

get_top_ram_hogs() {
    # Gibt PID, Name und RAM-MB zurueck, sortiert nach Verbrauch
    ps aux -m | awk '
        NR>1 {
            printf "%s|%s|%d\n", $2, $11, $6/1024
        }
    ' | head -10
}

###############################################################################
# Eingriffs-Stufen
###############################################################################

# Stufe 1: Warnung
action_warn() {
    local metric="$1"
    local value="$2"
    log "WARN" "$metric ist hoch: $value"
    notify "Warnung" "$metric bei $value - System wird langsamer" "normal"
}

# Stufe 2: Leichter Eingriff - RAM freigeben
action_free_memory() {
    log "ACTION" "Stufe 2: Speicher freigeben"
    notify "Eingriff" "Gebe Speicher frei..." "normal"

    # Inaktiven RAM freigeben
    sudo purge 2>/dev/null || true

    # Temporaere Dateien loeschen
    rm -rf /tmp/com.apple.* 2>/dev/null || true
    rm -rf "$TMPDIR"com.apple.* 2>/dev/null || true

    # Browser-Caches bereinigen
    rm -rf ~/Library/Caches/Google/Chrome/Default/Cache/* 2>/dev/null || true
    rm -rf ~/Library/Caches/com.apple.Safari/WebKitCache/* 2>/dev/null || true

    log "ACTION" "Speicher freigegeben"
}

# Stufe 3: Ressourcen-Fresser beenden (intelligent)
action_kill_resource_hogs() {
    local reason="$1"
    log "ACTION" "Stufe 3: Ressourcen-Fresser beenden (Grund: $reason)"

    local kills_this_hour
    kills_this_hour=$(get_kill_count_this_hour)

    if [ "$kills_this_hour" -ge "$MAX_KILLS_PER_HOUR" ]; then
        log "LIMIT" "Max. Kills pro Stunde erreicht ($MAX_KILLS_PER_HOUR)"
        notify "Limit erreicht" "Kann keine weiteren Apps beenden. Bitte manuell eingreifen!" "critical"
        return
    fi

    # Strategie: Zuerst Low-Priority-Apps mit hohem Verbrauch beenden
    local hogs
    hogs=$(get_top_cpu_hogs 50)

    while IFS='|' read -r pid name cpu; do
        [ -z "$pid" ] && continue

        if is_protected "$name"; then
            log "SKIP" "Geschuetzt: $name (PID: $pid, CPU: $cpu%)"
            continue
        fi

        if is_low_priority "$name"; then
            log "KILL" "Low-Priority App beenden: $name (PID: $pid, CPU: $cpu%)"
            notify "App beendet" "$name wurde beendet (${cpu}% CPU)" "critical"
            kill "$pid" 2>/dev/null || true
            record_kill "$name" "$reason - CPU: $cpu%"
            kills_this_hour=$((kills_this_hour + 1))

            if [ "$kills_this_hour" -ge "$MAX_KILLS_PER_HOUR" ]; then
                break
            fi
        fi
    done <<< "$hogs"

    # Wenn immer noch kritisch: Auch andere nicht-geschuetzte Apps beenden
    local current_cpu
    current_cpu=$(get_cpu_usage)
    if [ "$current_cpu" -gt "$CPU_CRITICAL_THRESHOLD" ]; then
        while IFS='|' read -r pid name cpu; do
            [ -z "$pid" ] && continue

            if is_protected "$name"; then
                continue
            fi

            log "KILL" "Nicht-geschuetzte App beenden: $name (PID: $pid, CPU: $cpu%)"
            notify "App beendet" "$name wurde beendet (${cpu}% CPU) - System-Notfall" "critical"
            kill "$pid" 2>/dev/null || true
            record_kill "$name" "NOTFALL $reason - CPU: $cpu%"
            kills_this_hour=$((kills_this_hour + 1))

            if [ "$kills_this_hour" -ge "$MAX_KILLS_PER_HOUR" ]; then
                break
            fi
        done <<< "$hogs"
    fi
}

# Stufe 4: Haengende Apps force-quitten
action_kill_hung_apps() {
    log "ACTION" "Stufe 4: Haengende Apps beenden"

    local hung_apps
    hung_apps=$(detect_hung_apps)

    while IFS= read -r app; do
        app=$(echo "$app" | xargs)
        [ -z "$app" ] && continue

        if is_protected "$app"; then
            log "SKIP" "Haengende aber geschuetzte App: $app"
            continue
        fi

        log "KILL" "Haengende App force-quit: $app"
        notify "Haengende App" "$app reagiert nicht - wird beendet" "critical"

        # Erst freundlich, dann force
        osascript -e "tell application \"$app\" to quit" 2>/dev/null || true
        sleep 2
        pkill -f "$app" 2>/dev/null || true

        record_kill "$app" "App reagierte nicht"
    done <<< "$hung_apps"
}

###############################################################################
# Hauptueberwachungs-Schleife
###############################################################################

monitor_loop() {
    local consecutive_cpu_high=0
    local consecutive_ram_high=0
    local last_memory_free=0
    local check_count=0

    log "INFO" "Guardian gestartet (PID: $$)"
    log "INFO" "CPU-Warn: ${CPU_WARN_THRESHOLD}%, CPU-Kritisch: ${CPU_CRITICAL_THRESHOLD}%"
    log "INFO" "RAM-Warn: ${RAM_WARN_THRESHOLD}%, RAM-Kritisch: ${RAM_CRITICAL_THRESHOLD}%"
    notify "Guardian aktiv" "Dein Mac wird jetzt ueberwacht" "normal"

    while true; do
        check_count=$((check_count + 1))

        # Metriken sammeln
        local cpu_usage ram_usage swap_mb disk_usage
        cpu_usage=$(get_cpu_usage)
        ram_usage=$(get_ram_usage_percent)
        swap_mb=$(get_swap_mb)
        disk_usage=$(get_disk_usage_percent)

        # Status loggen (alle 30 Checks = ca. 5 Minuten)
        if [ $((check_count % 30)) -eq 0 ]; then
            log "STATUS" "CPU: ${cpu_usage}% | RAM: ${ram_usage}% | Swap: ${swap_mb}MB | Disk: ${disk_usage}%"
        fi

        ########################################################################
        # CPU-Ueberwachung
        ########################################################################
        if [ "$cpu_usage" -gt "$CPU_CRITICAL_THRESHOLD" ]; then
            consecutive_cpu_high=$((consecutive_cpu_high + 1))
            log "ALERT" "CPU KRITISCH: ${cpu_usage}% (${consecutive_cpu_high}x hintereinander)"

            if [ "$consecutive_cpu_high" -ge 3 ]; then
                # 3x hintereinander kritisch = Eingreifen!
                action_kill_resource_hogs "CPU bei ${cpu_usage}% fuer ${consecutive_cpu_high} Checks"
                consecutive_cpu_high=0
            fi
        elif [ "$cpu_usage" -gt "$CPU_WARN_THRESHOLD" ]; then
            consecutive_cpu_high=$((consecutive_cpu_high + 1))
            if [ "$consecutive_cpu_high" -eq 3 ]; then
                action_warn "CPU-Auslastung" "${cpu_usage}%"
            fi
        else
            consecutive_cpu_high=0
        fi

        ########################################################################
        # RAM-Ueberwachung
        ########################################################################
        if [ "$ram_usage" -gt "$RAM_CRITICAL_THRESHOLD" ]; then
            consecutive_ram_high=$((consecutive_ram_high + 1))
            log "ALERT" "RAM KRITISCH: ${ram_usage}% (${consecutive_ram_high}x hintereinander)"

            if [ "$consecutive_ram_high" -ge 2 ]; then
                # Erst Speicher freigeben
                action_free_memory
                sleep 5

                # Nochmal pruefen
                ram_usage=$(get_ram_usage_percent)
                if [ "$ram_usage" -gt "$RAM_CRITICAL_THRESHOLD" ]; then
                    # Immer noch kritisch -> Apps beenden
                    action_kill_resource_hogs "RAM bei ${ram_usage}% nach purge"
                fi
                consecutive_ram_high=0
            fi
        elif [ "$ram_usage" -gt "$RAM_WARN_THRESHOLD" ]; then
            consecutive_ram_high=$((consecutive_ram_high + 1))
            if [ "$consecutive_ram_high" -eq 3 ]; then
                action_warn "RAM-Nutzung" "${ram_usage}%"
                # Praeventiv Speicher freigeben
                action_free_memory
            fi
        else
            consecutive_ram_high=0

            # RAM wurde frei: Speicher-Freigabe alle 10 Minuten wenn noetig
            if [ $((check_count % 60)) -eq 0 ] && [ "$ram_usage" -gt 70 ]; then
                action_free_memory
            fi
        fi

        ########################################################################
        # Swap-Ueberwachung
        ########################################################################
        if [ -n "$swap_mb" ] && [ "$swap_mb" -gt "$SWAP_WARN_MB" ]; then
            log "WARN" "Hohe Swap-Nutzung: ${swap_mb}MB"
            if [ $((check_count % 30)) -eq 0 ]; then
                action_warn "Swap-Nutzung" "${swap_mb}MB"
            fi
        fi

        ########################################################################
        # Haengende Apps pruefen (alle 60 Sekunden)
        ########################################################################
        if [ $((check_count % 6)) -eq 0 ]; then
            local hung
            hung=$(detect_hung_apps)
            if [ -n "$hung" ] && [ "$(echo "$hung" | grep -c .)" -gt 0 ]; then
                action_kill_hung_apps
            fi
        fi

        ########################################################################
        # Festplatten-Check (alle 5 Minuten)
        ########################################################################
        if [ $((check_count % 30)) -eq 0 ] && [ "$disk_usage" -gt "$DISK_WARN_THRESHOLD" ]; then
            action_warn "Festplatte" "${disk_usage}% voll"
        fi

        sleep "$CHECK_INTERVAL"
    done
}

###############################################################################
# Daemon-Steuerung
###############################################################################

start_daemon() {
    if [ -f "$PID_FILE" ]; then
        local old_pid
        old_pid=$(cat "$PID_FILE")
        if kill -0 "$old_pid" 2>/dev/null; then
            echo "Guardian laeuft bereits (PID: $old_pid)"
            echo "Zum Stoppen: $0 --stop"
            exit 0
        fi
    fi

    echo "Starte Mac Guardian Daemon..."
    monitor_loop &
    local daemon_pid=$!
    echo "$daemon_pid" > "$PID_FILE"
    echo "Guardian gestartet (PID: $daemon_pid)"
    echo "Log: $LOG_FILE"
    echo "Zum Stoppen: $0 --stop"
}

stop_daemon() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            rm -f "$PID_FILE"
            echo "Guardian gestoppt (PID: $pid)"
            log "INFO" "Guardian gestoppt"
            notify "Guardian gestoppt" "Ueberwachung deaktiviert" "normal"
        else
            echo "Guardian laeuft nicht (PID $pid nicht aktiv)"
            rm -f "$PID_FILE"
        fi
    else
        echo "Guardian laeuft nicht"
    fi
}

status_daemon() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Guardian laeuft (PID: $pid)"
            echo "Log (letzte 20 Zeilen):"
            tail -20 "$LOG_FILE" 2>/dev/null
        else
            echo "Guardian nicht aktiv (stale PID file)"
        fi
    else
        echo "Guardian nicht aktiv"
    fi
}

###############################################################################
# Hauptprogramm
###############################################################################

case "${1:-start}" in
    --stop|-stop|stop)
        stop_daemon
        ;;
    --status|-status|status)
        status_daemon
        ;;
    --start|-start|start)
        start_daemon
        ;;
    --foreground|-foreground|foreground)
        echo "Guardian im Vordergrund gestartet (Ctrl+C zum Stoppen)"
        echo $$ > "$PID_FILE"
        trap 'rm -f "$PID_FILE"; echo "Guardian gestoppt"; exit 0' INT TERM
        monitor_loop
        ;;
    *)
        echo "Verwendung: $0 [start|stop|status|foreground]"
        exit 1
        ;;
esac
