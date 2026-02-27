#!/usr/bin/env bash
# ============================================================================
# Mac Guardian - AI-Powered Mac Performance Monitor & Optimizer
# Erkennt Probleme BEVOR sie auftreten. Killt hängende Apps. Räumt auf.
# ============================================================================
set -euo pipefail

GUARDIAN_DIR="$HOME/.mac-guardian"
LOG_DIR="$GUARDIAN_DIR/logs"
STATE_DIR="$GUARDIAN_DIR/state"
LEARNING_DB="$GUARDIAN_DIR/learning.json"
CONFIG_FILE="$GUARDIAN_DIR/config.json"
PID_FILE="$GUARDIAN_DIR/guardian.pid"
LOCK_FILE="$GUARDIAN_DIR/guardian.lock"

# Thresholds (overridable via config)
CPU_WARN_THRESHOLD=80
CPU_KILL_THRESHOLD=95
MEM_WARN_THRESHOLD=75
MEM_CRITICAL_THRESHOLD=90
DISK_WARN_THRESHOLD=80
DISK_CRITICAL_THRESHOLD=90
TEMP_WARN_THRESHOLD=75
TEMP_CRITICAL_THRESHOLD=90
CHECK_INTERVAL=30
HUNG_APP_TIMEOUT=60

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# Initialization
# ============================================================================
init_guardian() {
    mkdir -p "$LOG_DIR" "$STATE_DIR"

    if [[ ! -f "$LEARNING_DB" ]]; then
        cat > "$LEARNING_DB" << 'LEARN'
{
  "actions_taken": [],
  "app_patterns": {},
  "peak_hours": {},
  "known_resource_hogs": [],
  "auto_kill_whitelist": ["Finder", "loginwindow", "SystemUIServer", "Dock", "WindowServer"],
  "version": 1
}
LEARN
    fi

    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << 'CONF'
{
  "cpu_warn": 80,
  "cpu_kill": 95,
  "mem_warn": 75,
  "mem_critical": 90,
  "disk_warn": 80,
  "disk_critical": 90,
  "temp_warn": 75,
  "temp_critical": 90,
  "check_interval": 30,
  "auto_kill_hung": true,
  "auto_purge_memory": true,
  "auto_clear_caches": true,
  "cloud_offload_enabled": false,
  "hetzner_storage_box": "",
  "notifications_enabled": true
}
CONF
    fi

    load_config
}

load_config() {
    if command -v jq &>/dev/null && [[ -f "$CONFIG_FILE" ]]; then
        CPU_WARN_THRESHOLD=$(jq -r '.cpu_warn // 80' "$CONFIG_FILE")
        CPU_KILL_THRESHOLD=$(jq -r '.cpu_kill // 95' "$CONFIG_FILE")
        MEM_WARN_THRESHOLD=$(jq -r '.mem_warn // 75' "$CONFIG_FILE")
        MEM_CRITICAL_THRESHOLD=$(jq -r '.mem_critical // 90' "$CONFIG_FILE")
        DISK_WARN_THRESHOLD=$(jq -r '.disk_warn // 80' "$CONFIG_FILE")
        DISK_CRITICAL_THRESHOLD=$(jq -r '.disk_critical // 90' "$CONFIG_FILE")
        TEMP_WARN_THRESHOLD=$(jq -r '.temp_warn // 75' "$CONFIG_FILE")
        TEMP_CRITICAL_THRESHOLD=$(jq -r '.temp_critical // 90' "$CONFIG_FILE")
        CHECK_INTERVAL=$(jq -r '.check_interval // 30' "$CONFIG_FILE")
    fi
}

# ============================================================================
# Logging
# ============================================================================
log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $msg" >> "$LOG_DIR/guardian.log"

    case "$level" in
        ERROR)   echo -e "${RED}[$level] $msg${NC}" ;;
        WARN)    echo -e "${YELLOW}[$level] $msg${NC}" ;;
        ACTION)  echo -e "${GREEN}[$level] $msg${NC}" ;;
        INFO)    echo -e "${BLUE}[$level] $msg${NC}" ;;
        *)       echo -e "${CYAN}[$level] $msg${NC}" ;;
    esac
}

notify_user() {
    local title="$1"
    local message="$2"
    if command -v osascript &>/dev/null; then
        osascript -e "display notification \"$message\" with title \"$title\" sound name \"Submarine\"" 2>/dev/null || true
    fi
}

# ============================================================================
# System Metrics Collection
# ============================================================================
get_cpu_usage() {
    if [[ "$(uname)" == "Darwin" ]]; then
        top -l 1 -n 0 2>/dev/null | awk '/CPU usage/ {print 100 - $7}' | tr -d '%'
    else
        grep 'cpu ' /proc/stat 2>/dev/null | awk '{usage=($2+$4)*100/($2+$4+$5)} END {printf "%.1f", usage}'
    fi
}

get_memory_usage() {
    if [[ "$(uname)" == "Darwin" ]]; then
        local mem_info
        mem_info=$(vm_stat 2>/dev/null)
        local pages_free pages_active pages_speculative pages_wired page_size
        page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
        pages_free=$(echo "$mem_info" | awk '/Pages free/ {gsub(/\./,"",$3); print $3}')
        pages_active=$(echo "$mem_info" | awk '/Pages active/ {gsub(/\./,"",$3); print $3}')
        pages_speculative=$(echo "$mem_info" | awk '/Pages speculative/ {gsub(/\./,"",$3); print $3}')
        pages_wired=$(echo "$mem_info" | awk '/Pages wired/ {gsub(/\./,"",$4); print $4}')
        local total_mem
        total_mem=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
        local used_mem=$(( (pages_active + pages_wired) * page_size ))
        if [[ "$total_mem" -gt 0 ]]; then
            echo "scale=1; $used_mem * 100 / $total_mem" | bc 2>/dev/null || echo "0"
        else
            echo "0"
        fi
    else
        free 2>/dev/null | awk '/Mem:/ {printf("%.1f", $3/$2 * 100)}'
    fi
}

get_disk_usage() {
    df -h / 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}'
}

get_cpu_temp() {
    if [[ "$(uname)" == "Darwin" ]]; then
        # Try multiple methods for temperature
        if command -v osx-cpu-temp &>/dev/null; then
            osx-cpu-temp 2>/dev/null | tr -d '°C ' || echo "0"
        elif command -v istats &>/dev/null; then
            istats cpu temp --value-only 2>/dev/null | tr -d '°C ' || echo "0"
        elif command -v powermetrics &>/dev/null; then
            sudo powermetrics --samplers smc -i1 -n1 2>/dev/null | awk '/CPU die temperature/ {print $4}' || echo "0"
        else
            echo "0"
        fi
    else
        if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
            echo "scale=1; $(cat /sys/class/thermal/thermal_zone0/temp) / 1000" | bc 2>/dev/null || echo "0"
        else
            echo "0"
        fi
    fi
}

get_swap_usage() {
    if [[ "$(uname)" == "Darwin" ]]; then
        sysctl vm.swapusage 2>/dev/null | awk '{print $7}' | tr -d 'M'
    else
        free -m 2>/dev/null | awk '/Swap:/ {if($2>0) printf("%.1f", $3/$2*100); else print "0"}'
    fi
}

# ============================================================================
# Problem Detection (BEFORE they happen)
# ============================================================================
detect_memory_pressure() {
    local mem_usage
    mem_usage=$(get_memory_usage)
    local mem_int=${mem_usage%.*}

    if [[ "$mem_int" -ge "$MEM_CRITICAL_THRESHOLD" ]]; then
        log ERROR "KRITISCH: Speicher bei ${mem_usage}% - Sofortige Aktion noetig!"
        notify_user "Mac Guardian" "Speicher kritisch: ${mem_usage}% belegt!"
        auto_free_memory
        learn_action "memory_critical" "purged_memory" "$mem_usage"
        return 2
    elif [[ "$mem_int" -ge "$MEM_WARN_THRESHOLD" ]]; then
        log WARN "Speicher bei ${mem_usage}% - Praeventive Bereinigung"
        auto_free_memory_gentle
        learn_action "memory_warn" "gentle_purge" "$mem_usage"
        return 1
    fi
    return 0
}

detect_cpu_spikes() {
    local cpu_usage
    cpu_usage=$(get_cpu_usage)
    local cpu_int=${cpu_usage%.*}

    if [[ "$cpu_int" -ge "$CPU_KILL_THRESHOLD" ]]; then
        log ERROR "CPU bei ${cpu_usage}% - Suche haengende Prozesse"
        notify_user "Mac Guardian" "CPU kritisch: ${cpu_usage}%! Bereinige..."
        kill_hung_processes
        learn_action "cpu_critical" "killed_processes" "$cpu_usage"
        return 2
    elif [[ "$cpu_int" -ge "$CPU_WARN_THRESHOLD" ]]; then
        log WARN "CPU bei ${cpu_usage}% - Ueberwache genau"
        detect_runaway_processes
        return 1
    fi
    return 0
}

detect_disk_pressure() {
    local disk_usage
    disk_usage=$(get_disk_usage)
    local disk_int=${disk_usage%.*}

    if [[ "$disk_int" -ge "$DISK_CRITICAL_THRESHOLD" ]]; then
        log ERROR "DISK bei ${disk_usage}% - Notfall-Bereinigung!"
        notify_user "Mac Guardian" "Festplatte fast voll: ${disk_usage}%!"
        emergency_disk_cleanup
        learn_action "disk_critical" "emergency_cleanup" "$disk_usage"
        return 2
    elif [[ "$disk_int" -ge "$DISK_WARN_THRESHOLD" ]]; then
        log WARN "Disk bei ${disk_usage}% - Raeume auf"
        routine_disk_cleanup
        return 1
    fi
    return 0
}

detect_thermal_throttle() {
    local temp
    temp=$(get_cpu_temp)
    local temp_int=${temp%.*}

    if [[ "$temp_int" -ge "$TEMP_CRITICAL_THRESHOLD" ]]; then
        log ERROR "CPU Temperatur ${temp}C - UEBERHITZUNG! Drossle Prozesse"
        notify_user "Mac Guardian" "Ueberhitzung erkannt: ${temp}C!"
        throttle_heavy_processes
        learn_action "temp_critical" "throttled_processes" "$temp"
        return 2
    elif [[ "$temp_int" -ge "$TEMP_WARN_THRESHOLD" ]]; then
        log WARN "CPU Temperatur ${temp}C - Erhoehte Temperatur"
        return 1
    fi
    return 0
}

detect_runaway_processes() {
    if [[ "$(uname)" == "Darwin" ]]; then
        ps aux 2>/dev/null | awk 'NR>1 && $3>50 {print $11, $3"%"}' | while read -r proc cpu; do
            log WARN "Hohe CPU: $proc ($cpu)"
        done
    fi
}

# ============================================================================
# Automatic Actions
# ============================================================================
kill_hung_processes() {
    log ACTION "Suche haengende Prozesse..."
    local killed=0

    if [[ "$(uname)" == "Darwin" ]]; then
        # Find Not Responding apps
        local hung_apps
        hung_apps=$(osascript -e '
            tell application "System Events"
                set hungApps to {}
                repeat with p in (every process whose background only is false)
                    try
                        if not (exists (window 1 of p)) then
                            -- skip
                        end if
                    end try
                end repeat
            end tell
        ' 2>/dev/null || true)

        # Kill processes consuming >95% CPU for more than 60 seconds
        ps aux 2>/dev/null | awk -v threshold="$CPU_KILL_THRESHOLD" 'NR>1 && $3>threshold' | while read -r user pid cpu mem vsz rss tt stat started time command; do
            local proc_name
            proc_name=$(basename "$command" 2>/dev/null || echo "$command")

            # Check whitelist
            if is_whitelisted "$proc_name"; then
                log INFO "Ueberspringe geschuetzten Prozess: $proc_name"
                continue
            fi

            log ACTION "Beende haengenden Prozess: $proc_name (PID: $pid, CPU: ${cpu}%)"
            kill -15 "$pid" 2>/dev/null || true
            sleep 2
            kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
            killed=$((killed + 1))
        done
    fi

    log ACTION "$killed Prozess(e) beendet"
}

is_whitelisted() {
    local proc_name="$1"
    local whitelist=("Finder" "loginwindow" "SystemUIServer" "Dock" "WindowServer" "kernel_task" "launchd")
    for item in "${whitelist[@]}"; do
        if [[ "$proc_name" == *"$item"* ]]; then
            return 0
        fi
    done
    return 1
}

auto_free_memory() {
    log ACTION "Aggressive Speicherbereinigung..."

    # Purge inactive memory (macOS)
    if [[ "$(uname)" == "Darwin" ]]; then
        sudo purge 2>/dev/null && log ACTION "Inaktiver Speicher freigegeben" || true
    fi

    # Close tabs in browsers (if extremely critical)
    close_inactive_browser_tabs

    # Clear system caches
    clear_system_caches

    local after_mem
    after_mem=$(get_memory_usage)
    log ACTION "Speicher nach Bereinigung: ${after_mem}%"
}

auto_free_memory_gentle() {
    log ACTION "Sanfte Speicherbereinigung..."

    # Clear font caches
    if [[ "$(uname)" == "Darwin" ]]; then
        atsutil databases -remove 2>/dev/null || true
    fi

    # Clear DNS cache
    if [[ "$(uname)" == "Darwin" ]]; then
        sudo dscacheutil -flushcache 2>/dev/null || true
        sudo killall -HUP mDNSResponder 2>/dev/null || true
    fi

    log ACTION "Sanfte Bereinigung abgeschlossen"
}

close_inactive_browser_tabs() {
    if [[ "$(uname)" == "Darwin" ]]; then
        # Only if memory is truly critical
        log ACTION "Browser-Tab-Optimierung..."

        # Safari: close tabs older than 1h with no interaction
        osascript -e '
            tell application "System Events"
                if (exists process "Safari") then
                    tell application "Safari"
                        set tabCount to 0
                        repeat with w in windows
                            set tabCount to tabCount + (count of tabs of w)
                        end repeat
                        if tabCount > 20 then
                            -- Only suggest, dont force-close
                        end if
                    end tell
                end if
            end tell
        ' 2>/dev/null || true
    fi
}

clear_system_caches() {
    log ACTION "Bereinige System-Caches..."
    local freed=0

    # User caches
    if [[ -d "$HOME/Library/Caches" ]]; then
        local cache_size
        cache_size=$(du -sm "$HOME/Library/Caches" 2>/dev/null | awk '{print $1}')
        # Only clear caches older than 7 days
        find "$HOME/Library/Caches" -type f -mtime +7 -delete 2>/dev/null || true
        local new_size
        new_size=$(du -sm "$HOME/Library/Caches" 2>/dev/null | awk '{print $1}')
        freed=$(( cache_size - new_size ))
    fi

    # Xcode derived data
    if [[ -d "$HOME/Library/Developer/Xcode/DerivedData" ]]; then
        local xcode_size
        xcode_size=$(du -sm "$HOME/Library/Developer/Xcode/DerivedData" 2>/dev/null | awk '{print $1}')
        rm -rf "$HOME/Library/Developer/Xcode/DerivedData"/* 2>/dev/null || true
        freed=$((freed + xcode_size))
    fi

    # npm cache
    if command -v npm &>/dev/null; then
        npm cache clean --force 2>/dev/null || true
    fi

    # yarn cache
    if command -v yarn &>/dev/null; then
        yarn cache clean 2>/dev/null || true
    fi

    # pip cache
    if command -v pip3 &>/dev/null; then
        pip3 cache purge 2>/dev/null || true
    fi

    # Homebrew cleanup
    if command -v brew &>/dev/null; then
        brew cleanup --prune=7 2>/dev/null || true
    fi

    log ACTION "~${freed}MB Cache freigegeben"
}

# ============================================================================
# Disk Cleanup
# ============================================================================
emergency_disk_cleanup() {
    log ACTION "NOTFALL Disk-Bereinigung gestartet!"

    # 1. Trash leeren
    rm -rf "$HOME/.Trash/"* 2>/dev/null || true
    log ACTION "Papierkorb geleert"

    # 2. System Logs bereinigen
    sudo rm -rf /private/var/log/asl/*.asl 2>/dev/null || true
    log ACTION "System-Logs bereinigt"

    # 3. Alte iOS Backups
    if [[ -d "$HOME/Library/Application Support/MobileSync/Backup" ]]; then
        local backup_size
        backup_size=$(du -sm "$HOME/Library/Application Support/MobileSync/Backup" 2>/dev/null | awk '{print $1}')
        if [[ "$backup_size" -gt 5000 ]]; then
            log WARN "iOS Backups: ${backup_size}MB - Empfehle Auslagerung auf Cloud"
        fi
    fi

    # 4. Docker cleanup
    if command -v docker &>/dev/null; then
        docker system prune -f 2>/dev/null || true
        log ACTION "Docker bereinigt"
    fi

    # 5. Alte Downloads
    find "$HOME/Downloads" -type f -mtime +30 -name "*.dmg" -delete 2>/dev/null || true
    find "$HOME/Downloads" -type f -mtime +30 -name "*.zip" -delete 2>/dev/null || true
    find "$HOME/Downloads" -type f -mtime +30 -name "*.pkg" -delete 2>/dev/null || true
    log ACTION "Alte Installer in Downloads bereinigt"

    # 6. Core dumps
    find /cores -type f -delete 2>/dev/null || true

    # 7. Clear caches aggressively
    clear_system_caches

    local disk_after
    disk_after=$(get_disk_usage)
    log ACTION "Disk nach Notfall-Bereinigung: ${disk_after}%"
}

routine_disk_cleanup() {
    log ACTION "Routine Disk-Bereinigung..."

    # Papierkorb (nur Dateien aelter als 30 Tage)
    find "$HOME/.Trash" -mtime +30 -delete 2>/dev/null || true

    # Alte Logs
    find "$HOME/Library/Logs" -type f -mtime +14 -delete 2>/dev/null || true

    # Temp files
    find /tmp -type f -user "$(whoami)" -mtime +3 -delete 2>/dev/null || true

    clear_system_caches

    log ACTION "Routine-Bereinigung abgeschlossen"
}

# ============================================================================
# Thermal Management
# ============================================================================
throttle_heavy_processes() {
    log ACTION "Drossle ressourcenintensive Prozesse wegen Ueberhitzung..."

    if [[ "$(uname)" == "Darwin" ]]; then
        # Find top CPU consumers and reduce their priority
        ps aux 2>/dev/null | sort -nrk 3 | head -5 | awk 'NR>1 {print $2, $11, $3}' | while read -r pid proc cpu; do
            local proc_name
            proc_name=$(basename "$proc" 2>/dev/null || echo "$proc")

            if is_whitelisted "$proc_name"; then
                continue
            fi

            # Reduce process priority (renice)
            renice 20 "$pid" 2>/dev/null || true
            log ACTION "Gedrosselt: $proc_name (PID: $pid) von ${cpu}% CPU"
        done

        # Turbo Boost deaktivieren (wenn Tool installiert)
        if command -v turbo-boost-switcher &>/dev/null; then
            turbo-boost-switcher disable 2>/dev/null || true
            log ACTION "Turbo Boost deaktiviert"
        fi
    fi
}

# ============================================================================
# Learning System
# ============================================================================
learn_action() {
    local trigger="$1"
    local action="$2"
    local value="$3"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local hour
    hour=$(date '+%H')

    if command -v jq &>/dev/null && [[ -f "$LEARNING_DB" ]]; then
        local tmp_file
        tmp_file=$(mktemp)

        jq --arg trigger "$trigger" \
           --arg action "$action" \
           --arg value "$value" \
           --arg ts "$timestamp" \
           --arg hour "$hour" \
           '.actions_taken += [{"trigger": $trigger, "action": $action, "value": $value, "timestamp": $ts, "hour": $hour}] |
            .peak_hours[$hour] = ((.peak_hours[$hour] // 0) + 1)' \
           "$LEARNING_DB" > "$tmp_file" && mv "$tmp_file" "$LEARNING_DB"
    fi
}

get_learned_patterns() {
    if command -v jq &>/dev/null && [[ -f "$LEARNING_DB" ]]; then
        local current_hour
        current_hour=$(date '+%H')
        local peak_score
        peak_score=$(jq -r ".peak_hours[\"$current_hour\"] // 0" "$LEARNING_DB")

        if [[ "$peak_score" -gt 5 ]]; then
            log INFO "Lernmuster: Stunde $current_hour ist typische Problemzeit - Praeventive Checks"
            return 0
        fi
    fi
    return 1
}

# ============================================================================
# Cloud Offload (Hetzner Storage Box)
# ============================================================================
cloud_offload_check() {
    local hetzner_host
    hetzner_host=$(jq -r '.hetzner_storage_box // ""' "$CONFIG_FILE" 2>/dev/null)
    local cloud_enabled
    cloud_enabled=$(jq -r '.cloud_offload_enabled // false' "$CONFIG_FILE" 2>/dev/null)

    if [[ "$cloud_enabled" != "true" ]] || [[ -z "$hetzner_host" ]]; then
        return 1
    fi

    local disk_usage
    disk_usage=$(get_disk_usage)
    local disk_int=${disk_usage%.*}

    if [[ "$disk_int" -ge "$DISK_WARN_THRESHOLD" ]]; then
        log ACTION "Disk bei ${disk_usage}% - Starte Cloud-Auslagerung auf Hetzner"
        bash "$(dirname "$0")/cloud-offload.sh" auto 2>/dev/null || true
    fi
}

# ============================================================================
# Status Dashboard
# ============================================================================
show_status() {
    echo ""
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}       Mac Guardian - System Status         ${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""

    local cpu mem disk temp swap
    cpu=$(get_cpu_usage)
    mem=$(get_memory_usage)
    disk=$(get_disk_usage)
    temp=$(get_cpu_temp)
    swap=$(get_swap_usage)

    # CPU
    local cpu_color=$GREEN
    local cpu_int=${cpu%.*}
    [[ "$cpu_int" -ge "$CPU_WARN_THRESHOLD" ]] && cpu_color=$YELLOW
    [[ "$cpu_int" -ge "$CPU_KILL_THRESHOLD" ]] && cpu_color=$RED
    echo -e "  CPU:         ${cpu_color}${cpu}%${NC}"

    # Memory
    local mem_color=$GREEN
    local mem_int=${mem%.*}
    [[ "$mem_int" -ge "$MEM_WARN_THRESHOLD" ]] && mem_color=$YELLOW
    [[ "$mem_int" -ge "$MEM_CRITICAL_THRESHOLD" ]] && mem_color=$RED
    echo -e "  Speicher:    ${mem_color}${mem}%${NC}"

    # Disk
    local disk_color=$GREEN
    local disk_int=${disk%.*}
    [[ "$disk_int" -ge "$DISK_WARN_THRESHOLD" ]] && disk_color=$YELLOW
    [[ "$disk_int" -ge "$DISK_CRITICAL_THRESHOLD" ]] && disk_color=$RED
    echo -e "  Festplatte:  ${disk_color}${disk}%${NC}"

    # Temp
    if [[ "$temp" != "0" ]]; then
        local temp_color=$GREEN
        local temp_int=${temp%.*}
        [[ "$temp_int" -ge "$TEMP_WARN_THRESHOLD" ]] && temp_color=$YELLOW
        [[ "$temp_int" -ge "$TEMP_CRITICAL_THRESHOLD" ]] && temp_color=$RED
        echo -e "  Temperatur:  ${temp_color}${temp}°C${NC}"
    fi

    # Swap
    echo -e "  Swap:        ${BLUE}${swap}MB${NC}"

    echo ""

    # Top processes
    echo -e "  ${YELLOW}Top Prozesse:${NC}"
    ps aux 2>/dev/null | sort -nrk 3 | head -6 | awk 'NR>1 {printf "    %-20s CPU: %5s%%  MEM: %5s%%\n", $11, $3, $4}'

    echo ""

    # Learning stats
    if command -v jq &>/dev/null && [[ -f "$LEARNING_DB" ]]; then
        local total_actions
        total_actions=$(jq '.actions_taken | length' "$LEARNING_DB" 2>/dev/null || echo "0")
        echo -e "  ${GREEN}Gelernte Aktionen: ${total_actions}${NC}"
    fi

    echo ""
    echo -e "${CYAN}============================================${NC}"
}

# ============================================================================
# Main Loop
# ============================================================================
run_checks() {
    local issues=0

    detect_memory_pressure || issues=$((issues + $?))
    detect_cpu_spikes || issues=$((issues + $?))
    detect_disk_pressure || issues=$((issues + $?))
    detect_thermal_throttle || issues=$((issues + $?))

    # Cloud offload check
    cloud_offload_check || true

    # Learning-based preventive action
    if get_learned_patterns; then
        auto_free_memory_gentle
    fi

    return $issues
}

daemon_loop() {
    log INFO "Mac Guardian Daemon gestartet (PID: $$)"
    echo $$ > "$PID_FILE"

    trap 'log INFO "Guardian gestoppt"; rm -f "$PID_FILE" "$LOCK_FILE"; exit 0' SIGTERM SIGINT

    while true; do
        run_checks || true
        sleep "$CHECK_INTERVAL"
    done
}

# ============================================================================
# CLI Interface
# ============================================================================
usage() {
    echo -e "${CYAN}Mac Guardian - AI-Powered Performance Monitor${NC}"
    echo ""
    echo "Verwendung: $0 <befehl>"
    echo ""
    echo "Befehle:"
    echo "  start       - Guardian als Daemon starten"
    echo "  stop        - Guardian stoppen"
    echo "  status      - System-Status anzeigen"
    echo "  check       - Einmaligen Check durchfuehren"
    echo "  clean       - Sofortige Bereinigung"
    echo "  deep-clean  - Tiefe Bereinigung (aggressiv)"
    echo "  optimize    - Volle Optimierung durchfuehren"
    echo "  learn       - Lernstatistiken anzeigen"
    echo "  config      - Konfiguration bearbeiten"
    echo "  offload     - Cloud-Auslagerung starten"
    echo "  install     - Als LaunchAgent installieren"
    echo "  uninstall   - LaunchAgent entfernen"
    echo ""
}

install_launchagent() {
    local plist_path="$HOME/Library/LaunchAgents/com.macguardian.daemon.plist"
    local script_path
    script_path=$(realpath "$0")

    cat > "$plist_path" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.macguardian.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${script_path}</string>
        <string>start</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/stderr.log</string>
</dict>
</plist>
PLIST

    launchctl load "$plist_path" 2>/dev/null || true
    log ACTION "Mac Guardian als LaunchAgent installiert - Startet automatisch beim Login"
}

uninstall_launchagent() {
    local plist_path="$HOME/Library/LaunchAgents/com.macguardian.daemon.plist"
    launchctl unload "$plist_path" 2>/dev/null || true
    rm -f "$plist_path"
    log ACTION "LaunchAgent entfernt"
}

# ============================================================================
# Entry Point
# ============================================================================
init_guardian

case "${1:-help}" in
    start)
        if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            log WARN "Guardian laeuft bereits (PID: $(cat "$PID_FILE"))"
            exit 1
        fi
        daemon_loop
        ;;
    stop)
        if [[ -f "$PID_FILE" ]]; then
            kill "$(cat "$PID_FILE")" 2>/dev/null || true
            rm -f "$PID_FILE"
            log ACTION "Guardian gestoppt"
        else
            log WARN "Guardian laeuft nicht"
        fi
        ;;
    status)
        show_status
        ;;
    check)
        log INFO "Fuehre einmaligen Check durch..."
        run_checks
        log INFO "Check abgeschlossen"
        ;;
    clean)
        routine_disk_cleanup
        auto_free_memory_gentle
        ;;
    deep-clean)
        emergency_disk_cleanup
        auto_free_memory
        ;;
    optimize)
        log INFO "Volle Optimierung..."
        auto_free_memory
        routine_disk_cleanup
        clear_system_caches
        log ACTION "Optimierung abgeschlossen"
        show_status
        ;;
    learn)
        if command -v jq &>/dev/null && [[ -f "$LEARNING_DB" ]]; then
            echo -e "${CYAN}Lernstatistiken:${NC}"
            echo ""
            local total
            total=$(jq '.actions_taken | length' "$LEARNING_DB")
            echo "  Gesamte Aktionen: $total"
            echo ""
            echo "  Aktionen nach Typ:"
            jq -r '.actions_taken | group_by(.trigger) | map({trigger: .[0].trigger, count: length}) | sort_by(-.count) | .[] | "    \(.trigger): \(.count)x"' "$LEARNING_DB" 2>/dev/null
            echo ""
            echo "  Peak-Stunden:"
            jq -r '.peak_hours | to_entries | sort_by(-.value) | .[:5] | .[] | "    \(.key):00 Uhr: \(.value) Probleme"' "$LEARNING_DB" 2>/dev/null
        fi
        ;;
    config)
        ${EDITOR:-nano} "$CONFIG_FILE"
        ;;
    offload)
        bash "$(dirname "$0")/cloud-offload.sh" "${2:-interactive}"
        ;;
    install)
        install_launchagent
        ;;
    uninstall)
        uninstall_launchagent
        ;;
    help|--help|-h|*)
        usage
        ;;
esac
