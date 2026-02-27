#!/bin/bash
###############################################################################
# DISK GUARDIAN - Speicherplatz & SSD-Gesundheit
#
# - Automatische Bereinigung von Caches, Logs, Temp-Dateien
# - Grosse Dateien identifizieren
# - Downloads-Ordner Alterung
# - Papierkorb Auto-Leeren
# - SMART-Status Ueberwachung
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-common.sh"

MODULE="disk"

get_disk_usage() {
    df -H / 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%'
}

get_disk_free() {
    df -H / 2>/dev/null | awk 'NR==2 {print $4}'
}

###############################################################################
# AUTO-CLEANUP
###############################################################################

cleanup_caches() {
    local freed=0
    local before
    before=$(du -sk ~/Library/Caches 2>/dev/null | awk '{print $1}')

    # Browser-Caches
    rm -rf ~/Library/Caches/Google/Chrome/Default/Cache/* 2>/dev/null
    rm -rf ~/Library/Caches/Google/Chrome/Default/Code\ Cache/* 2>/dev/null
    rm -rf ~/Library/Caches/com.apple.Safari/WebKitCache/* 2>/dev/null
    rm -rf ~/Library/Caches/com.apple.Safari/fsCachedData/* 2>/dev/null
    rm -rf ~/Library/Caches/Firefox/Profiles/*/cache2/* 2>/dev/null
    rm -rf ~/Library/Caches/BraveSoftware/Brave-Browser/Default/Cache/* 2>/dev/null

    # App-Caches (sicher zu loeschen)
    rm -rf ~/Library/Caches/com.apple.iconservices.store/* 2>/dev/null
    rm -rf ~/Library/Caches/CloudKit/* 2>/dev/null
    rm -rf ~/Library/Caches/com.spotify.client/Data/* 2>/dev/null
    rm -rf ~/Library/Caches/com.microsoft.teams/* 2>/dev/null
    rm -rf ~/Library/Caches/Slack/* 2>/dev/null
    rm -rf ~/Library/Caches/com.docker.docker/* 2>/dev/null
    rm -rf ~/Library/Caches/com.microsoft.VSCode/* 2>/dev/null

    # System-Caches
    rm -rf ~/Library/Caches/com.apple.nsurlsessiond/* 2>/dev/null
    rm -rf ~/Library/Caches/com.apple.DiskImages/* 2>/dev/null

    local after
    after=$(du -sk ~/Library/Caches 2>/dev/null | awk '{print $1}')
    freed=$(( (before - after) / 1024 ))

    guardian_log "$MODULE" "CLEANUP" "Caches bereinigt: ${freed}MB freigegeben"
    echo "$freed"
}

cleanup_logs() {
    local freed=0

    # Alte System-Logs
    sudo rm -rf /private/var/log/asl/*.asl 2>/dev/null || true
    sudo rm -rf /Library/Logs/DiagnosticReports/* 2>/dev/null || true
    rm -rf ~/Library/Logs/DiagnosticReports/* 2>/dev/null

    # Alte Crash-Reports
    rm -rf ~/Library/Logs/CrashReporter/* 2>/dev/null

    # macOS Logarchive (koennen sehr gross werden)
    sudo rm -rf /private/var/folders/*/*/com.apple.nsurlsessiond/* 2>/dev/null || true

    guardian_log "$MODULE" "CLEANUP" "Logs bereinigt"
}

cleanup_temp() {
    # Temporaere Dateien
    rm -rf /tmp/com.apple.* 2>/dev/null || true
    rm -rf "${TMPDIR}"com.apple.* 2>/dev/null || true
    rm -rf "${TMPDIR}"*.tmp 2>/dev/null || true

    # Alte Xcode DerivedData
    if [ -d ~/Library/Developer/Xcode/DerivedData ]; then
        local dd_size
        dd_size=$(du -sh ~/Library/Developer/Xcode/DerivedData 2>/dev/null | awk '{print $1}')
        # Nur DerivedData aelter als 7 Tage loeschen
        find ~/Library/Developer/Xcode/DerivedData -maxdepth 1 -mindepth 1 -mtime +7 -exec rm -rf {} \; 2>/dev/null
        guardian_log "$MODULE" "CLEANUP" "Alte Xcode DerivedData bereinigt (war: $dd_size)"
    fi

    # npm/yarn caches
    npm cache clean --force 2>/dev/null || true
    yarn cache clean 2>/dev/null || true

    # pip cache
    pip cache purge 2>/dev/null || true

    # Homebrew cleanup
    brew cleanup --prune=7 2>/dev/null || true

    guardian_log "$MODULE" "CLEANUP" "Temp-Dateien bereinigt"
}

cleanup_trash() {
    local trash_size
    trash_size=$(du -sk ~/.Trash 2>/dev/null | awk '{print $1}')
    if [ -n "$trash_size" ] && [ "$trash_size" -gt 1024 ]; then
        local trash_mb=$((trash_size / 1024))
        rm -rf ~/.Trash/* 2>/dev/null
        guardian_log "$MODULE" "CLEANUP" "Papierkorb geleert: ${trash_mb}MB"
        echo "$trash_mb"
    else
        echo "0"
    fi
}

# Downloads: Alte Dateien (>30 Tage) in Unterordner verschieben
organize_downloads() {
    local dl_dir="$HOME/Downloads"
    local archive_dir="$dl_dir/_Alte_Downloads"
    mkdir -p "$archive_dir"

    local moved=0
    find "$dl_dir" -maxdepth 1 -mindepth 1 -mtime +30 ! -name "_Alte_Downloads" 2>/dev/null | while read -r f; do
        mv "$f" "$archive_dir/" 2>/dev/null && moved=$((moved + 1))
    done

    [ "$moved" -gt 0 ] && guardian_log "$MODULE" "ORGANIZE" "$moved alte Downloads verschoben"
}

###############################################################################
# SMART-CHECK
###############################################################################

check_disk_health() {
    local smart
    smart=$(diskutil info disk0 2>/dev/null | grep "SMART Status" | awk -F: '{print $2}' | xargs)

    if [ -n "$smart" ] && [ "$smart" != "Verified" ]; then
        guardian_log "$MODULE" "CRITICAL" "SSD SMART-Status: $smart"
        guardian_notify "SSD-WARNUNG!" "SMART-Status: $smart - Backup sofort machen!" "critical"
        guardian_record_event "disk_smart_warning" "$smart" "notify"
        echo "failing"
    else
        echo "ok"
    fi
}

###############################################################################
# HAUPT-CHECK
###############################################################################

disk_check() {
    local usage
    usage=$(get_disk_usage)
    guardian_record_metric "disk_used_pct" "$usage"

    local result="ok"

    # Automatische Bereinigung bei >85%
    if [ "$usage" -gt 95 ]; then
        guardian_log "$MODULE" "CRITICAL" "Festplatte bei ${usage}% - Notfall-Bereinigung!"
        guardian_notify "Festplatte fast voll!" "${usage}% belegt - bereinige automatisch" "critical"
        cleanup_caches
        cleanup_logs
        cleanup_temp
        cleanup_trash
        organize_downloads
        result="critical_cleaned"

    elif [ "$usage" -gt 85 ]; then
        guardian_log "$MODULE" "WARN" "Festplatte bei ${usage}% - Bereinigung"
        cleanup_caches
        cleanup_temp
        result="warning_cleaned"
    fi

    # SMART-Check (einmal pro Stunde)
    local last_smart="$GUARDIAN_DATA/last_smart_check"
    local now
    now=$(date +%s)
    local last_check
    last_check=$(cat "$last_smart" 2>/dev/null || echo 0)
    if [ $((now - last_check)) -gt 3600 ]; then
        check_disk_health
        echo "$now" > "$last_smart"
    fi

    echo "$usage|$result"
}

# Direkter Aufruf
case "${1:-check}" in
    check)    disk_check ;;
    clean)    cleanup_caches; cleanup_logs; cleanup_temp; cleanup_trash ;;
    smart)    check_disk_health ;;
    organize) organize_downloads ;;
    info)     echo "Disk: $(get_disk_usage)% belegt, $(get_disk_free) frei" ;;
    *)        echo "Disk Guardian: $0 {check|clean|smart|organize|info}" ;;
esac
