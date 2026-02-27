#!/bin/bash
###############################################################################
# PROCESS PRIORITY MANAGER - Intelligente CPU-Verteilung
#
# - Erkennt Vordergrund-Apps und gibt ihnen Prioritaet
# - Drosselt Hintergrund-Prozesse automatisch
# - Haengende Apps erkennen und beenden
# - Zombie-Prozesse bereinigen
# - Intelligente App-Kategorisierung
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-common.sh"

MODULE="process"
PROC_DATA="$GUARDIAN_DATA/process"
mkdir -p "$PROC_DATA"

# App-Kategorien (Prioritaet: 1=hoechste, 5=niedrigste)
declare -A APP_PRIORITY
APP_PRIORITY=(
    # System (nie anfassen)
    ["WindowServer"]=0 ["kernel_task"]=0 ["loginwindow"]=0
    ["Dock"]=0 ["Finder"]=0 ["SystemUIServer"]=0

    # Aktive Arbeit (hohe Prioritaet)
    ["Xcode"]=1 ["Code"]=1 ["Terminal"]=1 ["iTerm2"]=1
    ["Safari"]=1 ["Chrome"]=2 ["Firefox"]=2 ["Arc"]=2

    # Kommunikation (mittlere Prioritaet)
    ["Slack"]=3 ["Teams"]=3 ["Discord"]=3 ["Messages"]=2
    ["Mail"]=2 ["Outlook"]=3

    # Media/Entertainment (niedrig wenn im Hintergrund)
    ["Spotify"]=4 ["Music"]=3 ["VLC"]=3
    ["Photos"]=4 ["Preview"]=3

    # Schwere Apps (niedrig wenn im Hintergrund)
    ["Docker"]=4 ["Steam"]=5 ["Epic"]=5
    ["Premiere"]=3 ["After Effects"]=3 ["Photoshop"]=3
    ["Figma"]=3 ["Sketch"]=3

    # Development Tools
    ["node"]=3 ["python"]=3 ["ruby"]=3 ["java"]=3
    ["cargo"]=3 ["go"]=3 ["rustc"]=3

    # Sonstiges
    ["zoom.us"]=3 ["Skype"]=4 ["FaceTime"]=2
)

MAX_KILLS_PER_HOUR=5
PROTECTED_PATTERN="WindowServer|kernel_task|loginwindow|Finder|Dock|SystemUIServer|launchd|Claude|Activity.Monitor|Terminal|iTerm2"

###############################################################################
# VORDERGRUND-ERKENNUNG
###############################################################################

get_frontmost_app() {
    osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null
}

get_frontmost_pid() {
    local app
    app=$(get_frontmost_app)
    [ -z "$app" ] && return
    pgrep -x "$app" 2>/dev/null | head -1
}

###############################################################################
# PRIORITAETS-MANAGEMENT
###############################################################################

# Setze nice-Wert basierend auf App-Kategorie und Vordergrund-Status
adjust_priorities() {
    local frontmost
    frontmost=$(get_frontmost_app)

    ps aux -r | awk 'NR>1 && $3>5 {print $2, $11, $3}' | while read -r pid name cpu; do
        # System-Prozesse nie anfassen
        if echo "$name" | grep -qiE "$PROTECTED_PATTERN"; then
            continue
        fi

        local basename
        basename=$(basename "$name" 2>/dev/null)

        # Ist es die Vordergrund-App?
        if [ -n "$frontmost" ] && echo "$name" | grep -qi "$frontmost"; then
            # Hoechste Prioritaet fuer Vordergrund
            renice -5 "$pid" 2>/dev/null || true
            continue
        fi

        # Prioritaet basierend auf Kategorie
        local priority=3  # Standard: mittel
        for pattern in "${!APP_PRIORITY[@]}"; do
            if echo "$name" | grep -qi "$pattern"; then
                priority=${APP_PRIORITY[$pattern]}
                break
            fi
        done

        # Nice-Wert setzen (hoehere Zahl = niedrigere Prioritaet)
        case "$priority" in
            0) ;; # System - nicht aendern
            1) renice -2 "$pid" 2>/dev/null || true ;;
            2) renice 0 "$pid" 2>/dev/null || true ;;
            3) renice 5 "$pid" 2>/dev/null || true ;;
            4) renice 10 "$pid" 2>/dev/null || true ;;
            5) renice 15 "$pid" 2>/dev/null || true ;;
        esac
    done

    guardian_log "$MODULE" "PRIORITY" "Prioritaeten angepasst (Vordergrund: $frontmost)"
}

###############################################################################
# HAENGENDE APPS ERKENNEN
###############################################################################

detect_hung_apps() {
    local hung_list=""

    # GUI-Apps pruefen
    local apps
    apps=$(osascript -e 'tell application "System Events" to get name of every application process whose background only is false' 2>/dev/null | tr ',' '\n')

    while IFS= read -r app; do
        app=$(echo "$app" | xargs)
        [ -z "$app" ] && continue

        if echo "$app" | grep -qiE "$PROTECTED_PATTERN"; then
            continue
        fi

        # Timeout-Test: App muss in 3 Sekunden antworten
        if ! timeout 3 osascript -e "tell application \"$app\" to count windows" &>/dev/null 2>&1; then
            hung_list="${hung_list}${app}\n"
        fi
    done <<< "$apps"

    echo -e "$hung_list" | grep -v '^$'
}

# Haengende Apps behandeln
handle_hung_apps() {
    local hung
    hung=$(detect_hung_apps)
    [ -z "$hung" ] && return

    local kills_this_hour
    kills_this_hour=$(guardian_count_recent_events "process_kill_hung" 60)

    while IFS= read -r app; do
        [ -z "$app" ] && continue

        if [ "$kills_this_hour" -ge "$MAX_KILLS_PER_HOUR" ]; then
            guardian_log "$MODULE" "LIMIT" "Kill-Limit erreicht ($MAX_KILLS_PER_HOUR/h)"
            break
        fi

        guardian_log "$MODULE" "HUNG" "App reagiert nicht: $app"
        guardian_notify "App haengt" "$app reagiert nicht - wird beendet" "critical"

        # Erst freundlich
        osascript -e "tell application \"$app\" to quit" 2>/dev/null || true
        sleep 2

        # Dann Force-Quit
        if pgrep -x "$app" &>/dev/null; then
            pkill -9 -x "$app" 2>/dev/null || true
            guardian_log "$MODULE" "KILL" "Force-Quit: $app"
        fi

        guardian_record_event "process_kill_hung" "$app" "force_quit"
        kills_this_hour=$((kills_this_hour + 1))
    done <<< "$hung"
}

###############################################################################
# ZOMBIE-PROZESSE
###############################################################################

cleanup_zombies() {
    local zombies
    zombies=$(ps aux | awk '$8=="Z" {print $2, $11}')

    if [ -n "$zombies" ]; then
        local count
        count=$(echo "$zombies" | wc -l | tr -d ' ')
        guardian_log "$MODULE" "ZOMBIE" "$count Zombie-Prozesse gefunden"

        while read -r pid name; do
            # Parent-Prozess finden und signalisieren
            local ppid
            ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
            if [ -n "$ppid" ] && [ "$ppid" != "1" ]; then
                kill -SIGCHLD "$ppid" 2>/dev/null || true
            fi
        done <<< "$zombies"
    fi
}

###############################################################################
# RUNAWAY-PROZESS-ERKENNUNG
###############################################################################

detect_runaway() {
    # Prozesse die >100% CPU fuer >30 Sekunden verbrauchen
    ps aux -r | awk 'NR>1 && $3>100 {print $2, $11, $3, $10}' | while read -r pid name cpu time; do
        if echo "$name" | grep -qiE "$PROTECTED_PATTERN"; then
            continue
        fi

        guardian_log "$MODULE" "RUNAWAY" "Runaway-Prozess: $name (PID:$pid, ${cpu}% CPU)"
        echo "$pid|$name|$cpu"
    done
}

handle_runaway() {
    local runaways
    runaways=$(detect_runaway)
    [ -z "$runaways" ] && return

    while IFS='|' read -r pid name cpu; do
        [ -z "$pid" ] && continue

        # Erst drosseln
        renice 20 "$pid" 2>/dev/null || true
        guardian_log "$MODULE" "THROTTLE" "Runaway gedrosselt: $name (PID:$pid)"
        guardian_notify "Prozess gedrosselt" "$name verbraucht ${cpu}% CPU - gedrosselt" "critical"
        guardian_record_event "process_throttle_runaway" "$name PID:$pid ${cpu}%CPU" "renice_20"
    done <<< "$runaways"
}

###############################################################################
# HAUPT-CHECK
###############################################################################

process_check() {
    local check_file="$PROC_DATA/check_count"
    local count
    count=$(cat "$check_file" 2>/dev/null || echo 0)
    count=$((count + 1))
    echo "$count" > "$check_file"

    # Jeder Check: Runaway-Erkennung
    handle_runaway

    # Alle 6 Checks (1 Minute): Haengende Apps
    if [ $((count % 6)) -eq 0 ]; then
        handle_hung_apps
    fi

    # Alle 12 Checks (2 Minuten): Prioritaeten anpassen
    if [ $((count % 12)) -eq 0 ]; then
        adjust_priorities
    fi

    # Alle 30 Checks (5 Minuten): Zombies bereinigen
    if [ $((count % 30)) -eq 0 ]; then
        cleanup_zombies
    fi

    # Prozess-Anzahl
    local total_procs
    total_procs=$(ps aux | wc -l | tr -d ' ')
    guardian_record_metric "process_count" "$total_procs"

    echo "$total_procs"
}

# Direkter Aufruf
case "${1:-check}" in
    check)       process_check ;;
    priorities)  adjust_priorities ;;
    hung)        detect_hung_apps ;;
    zombies)     cleanup_zombies ;;
    runaway)     detect_runaway ;;
    kill-hung)   handle_hung_apps ;;
    *)           echo "Process Manager: $0 {check|priorities|hung|zombies|runaway|kill-hung}" ;;
esac
