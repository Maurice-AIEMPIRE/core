#!/bin/bash
###############################################################################
# MEMORY GUARDIAN - Speicherleck-Erkennung & Auto-Fix
#
# - Erkennt Memory Leaks durch Trend-Analyse
# - Gibt RAM automatisch frei (mehrstufig)
# - Identifiziert Apps mit anomalem Speicherwachstum
# - Praeventive Speicherfreigabe basierend auf Mustern
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-common.sh"

MODULE="memory"
MEM_DATA="$GUARDIAN_DATA/memory"
mkdir -p "$MEM_DATA"

###############################################################################
# SPEICHER-METRIKEN
###############################################################################

get_ram_metrics() {
    local page_size
    page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
    local total_mem
    total_mem=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    local vm
    vm=$(vm_stat 2>/dev/null)

    local free_p active_p wired_p comp_p
    free_p=$(echo "$vm" | awk '/Pages free/ {print $3}' | tr -d '.')
    active_p=$(echo "$vm" | awk '/Pages active/ {print $3}' | tr -d '.')
    wired_p=$(echo "$vm" | awk '/Pages wired/ {print $4}' | tr -d '.')
    comp_p=$(echo "$vm" | awk '/occupied by compressor/ {print $5}' | tr -d '.')

    local free_mb active_mb wired_mb comp_mb total_mb used_mb used_pct
    free_mb=$(( (free_p * page_size) / 1048576 ))
    active_mb=$(( (active_p * page_size) / 1048576 ))
    wired_mb=$(( (wired_p * page_size) / 1048576 ))
    comp_mb=$(( (comp_p * page_size) / 1048576 ))
    total_mb=$((total_mem / 1048576))
    used_mb=$((active_mb + wired_mb + comp_mb))
    used_pct=$((used_mb * 100 / total_mb))

    # Swap
    local swap_used
    swap_used=$(sysctl -n vm.swapusage 2>/dev/null | awk '{gsub(/M/,""); print int($6)}')

    echo "$used_pct|$free_mb|$active_mb|$wired_mb|$comp_mb|$total_mb|${swap_used:-0}"
}

###############################################################################
# MEMORY LEAK ERKENNUNG
###############################################################################

# Speichere RAM-Verbrauch pro App (fuer Leak-Erkennung)
snapshot_app_memory() {
    local snapshot_file="$MEM_DATA/app_memory_$(date +%s).csv"
    ps aux -m | awk 'NR>1 {printf "%s|%s|%d\n", $2, $11, $6/1024}' > "$snapshot_file"

    # Alte Snapshots loeschen (nur letzte 60 behalten = 10 Minuten bei 10s)
    ls -t "$MEM_DATA"/app_memory_*.csv 2>/dev/null | tail -n +61 | xargs rm -f 2>/dev/null
}

# Erkennung: Welche App waechst staendig?
detect_memory_leaks() {
    local snapshots
    snapshots=$(ls -t "$MEM_DATA"/app_memory_*.csv 2>/dev/null | head -30)
    local snap_count
    snap_count=$(echo "$snapshots" | grep -c '.csv' 2>/dev/null)

    [ "$snap_count" -lt 6 ] && return  # Mindestens 6 Snapshots fuer Trend

    local oldest newest
    oldest=$(echo "$snapshots" | tail -1)
    newest=$(echo "$snapshots" | head -1)

    # Vergleiche: Welche PIDs sind in beiden und sind signifikant gewachsen?
    while IFS='|' read -r pid name mem_now; do
        [ -z "$pid" ] && continue
        local mem_then
        mem_then=$(grep "^${pid}|" "$oldest" 2>/dev/null | awk -F'|' '{print $3}')
        [ -z "$mem_then" ] && continue
        [ "$mem_then" -eq 0 ] && continue

        local growth=$((mem_now - mem_then))
        local growth_pct=$((growth * 100 / mem_then))

        # Wenn >20% Wachstum in 5 Minuten und >100MB Zuwachs = verdaechtig
        if [ "$growth_pct" -gt 20 ] && [ "$growth" -gt 100 ]; then
            guardian_log "$MODULE" "LEAK" "Moegliches Speicherleck: $name (PID:$pid) +${growth}MB (+${growth_pct}%) in 5min"
            guardian_notify "Speicherleck?" "$name waechst: +${growth}MB in 5 Minuten" "critical"
            guardian_record_event "memory_leak_suspected" "$name PID:$pid +${growth}MB" "notify"
            echo "$pid|$name|$mem_now|$growth|$growth_pct"
        fi
    done < "$newest"
}

###############################################################################
# SPEICHER-FREIGABE (mehrstufig)
###############################################################################

# Stufe 1: Sanft - Nur Caches
free_memory_soft() {
    guardian_log "$MODULE" "ACTION" "Stufe 1: Sanfte Speicherfreigabe"

    # System-Cache leeren
    sudo purge 2>/dev/null || true

    # Browser-Caches
    rm -rf ~/Library/Caches/Google/Chrome/Default/Cache/* 2>/dev/null
    rm -rf ~/Library/Caches/com.apple.Safari/WebKitCache/* 2>/dev/null
    rm -rf ~/Library/Caches/Firefox/Profiles/*/cache2/* 2>/dev/null

    # Temp-Dateien
    rm -rf /tmp/com.apple.* 2>/dev/null || true
    rm -rf "${TMPDIR}"com.apple.* 2>/dev/null || true

    guardian_record_event "memory_free_soft" "cache_purge" "purge+cache_cleanup"
}

# Stufe 2: Medium - Caches + inaktive Apps per Memory-Pressure
free_memory_medium() {
    guardian_log "$MODULE" "ACTION" "Stufe 2: Mittlere Speicherfreigabe"
    free_memory_soft

    # Grosse Caches loeschen
    rm -rf ~/Library/Caches/com.apple.iconservices.store/* 2>/dev/null
    rm -rf ~/Library/Caches/CloudKit/* 2>/dev/null
    rm -rf ~/Library/Caches/com.spotify.client/* 2>/dev/null
    rm -rf ~/Library/Caches/com.microsoft.teams/* 2>/dev/null
    rm -rf ~/Library/Caches/Slack/* 2>/dev/null

    # Memory Warning an Apps senden (Apps geben dann freiwillig Speicher frei)
    # Simuliert Memory Pressure
    sudo memory_pressure -l warn 2>/dev/null || true

    guardian_record_event "memory_free_medium" "extended_cleanup" "purge+caches+pressure_warn"
}

# Stufe 3: Aggressiv - Low-Priority-Apps beenden
free_memory_aggressive() {
    guardian_log "$MODULE" "ACTION" "Stufe 3: Aggressive Speicherfreigabe"
    free_memory_medium

    # Protected Apps Liste
    local protected="Finder|WindowServer|kernel_task|loginwindow|SystemUIServer|Dock|launchd|Terminal|iTerm2|Claude|Activity Monitor"

    # Low-Priority Apps mit hohem RAM beenden
    local low_priority="Slack|Discord|Spotify|Teams|zoom|Skype|Steam|Docker|Figma|Notion"

    ps aux -m | awk 'NR>1 && $6>524288 {print $2, $11, int($6/1024)}' | while read -r pid name mem_mb; do
        if echo "$name" | grep -qiE "$protected"; then
            continue
        fi
        if echo "$name" | grep -qiE "$low_priority"; then
            guardian_log "$MODULE" "KILL" "Beende RAM-Fresser: $name (PID:$pid, ${mem_mb}MB)"
            guardian_notify "App beendet" "$name (${mem_mb}MB RAM) fuer Speicherfreigabe beendet" "critical"
            kill "$pid" 2>/dev/null || true
            guardian_record_event "memory_kill" "$name PID:$pid ${mem_mb}MB" "kill_low_priority"
        fi
    done
}

# Stufe 4: Notfall - Groesste RAM-Verbraucher beenden
free_memory_emergency() {
    guardian_log "$MODULE" "ACTION" "Stufe 4: NOTFALL-Speicherfreigabe!"
    free_memory_aggressive

    local protected="Finder|WindowServer|kernel_task|loginwindow|SystemUIServer|Dock|launchd"

    # Die 3 groessten nicht-geschuetzten RAM-Verbraucher beenden
    local killed=0
    ps aux -m | awk 'NR>1 {print $2, $11, int($6/1024)}' | while read -r pid name mem_mb; do
        [ "$killed" -ge 3 ] && break
        if echo "$name" | grep -qiE "$protected"; then
            continue
        fi
        if [ "$mem_mb" -gt 200 ]; then
            guardian_log "$MODULE" "EMERGENCY_KILL" "NOTFALL: Beende $name (PID:$pid, ${mem_mb}MB)"
            guardian_notify "NOTFALL" "$name beendet - System drohte einzufrieren" "critical"
            kill -9 "$pid" 2>/dev/null || true
            killed=$((killed + 1))
            guardian_record_event "memory_emergency_kill" "$name PID:$pid ${mem_mb}MB" "force_kill"
        fi
    done
}

###############################################################################
# HAUPT-CHECK (wird vom Orchestrator aufgerufen)
###############################################################################

memory_check() {
    local metrics
    metrics=$(get_ram_metrics)

    local used_pct free_mb active_mb wired_mb comp_mb total_mb swap_mb
    IFS='|' read -r used_pct free_mb active_mb wired_mb comp_mb total_mb swap_mb <<< "$metrics"

    guardian_record_metric "ram_used_pct" "$used_pct"
    guardian_record_metric "ram_free_mb" "$free_mb"
    guardian_record_metric "swap_used_mb" "$swap_mb"

    # Snapshot fuer Leak-Erkennung (alle 10 Checks = 100 Sekunden)
    local check_count_file="$MEM_DATA/check_count"
    local check_count
    check_count=$(cat "$check_count_file" 2>/dev/null || echo 0)
    check_count=$((check_count + 1))
    echo "$check_count" > "$check_count_file"

    if [ $((check_count % 10)) -eq 0 ]; then
        snapshot_app_memory
    fi

    # Leak-Detection alle 30 Checks (5 Minuten)
    if [ $((check_count % 30)) -eq 0 ]; then
        detect_memory_leaks
    fi

    # Ausgabe fuer Orchestrator
    echo "$used_pct|$free_mb|$swap_mb"
}

# Direkter Aufruf
case "${1:-check}" in
    check)
        memory_check
        ;;
    free)
        case "${2:-soft}" in
            soft)     free_memory_soft ;;
            medium)   free_memory_medium ;;
            aggressive) free_memory_aggressive ;;
            emergency)  free_memory_emergency ;;
        esac
        ;;
    leaks)
        snapshot_app_memory
        detect_memory_leaks
        ;;
    info)
        IFS='|' read -r pct free active wired comp total swap <<< "$(get_ram_metrics)"
        echo "RAM: ${pct}% (${free}MB frei, ${active}MB aktiv, ${wired}MB wired, ${comp}MB komprimiert)"
        echo "Swap: ${swap}MB"
        ;;
    *)
        echo "Memory Guardian: $0 {check|free [soft|medium|aggressive|emergency]|leaks|info}"
        ;;
esac
