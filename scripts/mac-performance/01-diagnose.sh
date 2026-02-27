#!/bin/bash
###############################################################################
# MAC PERFORMANCE DIAGNOSE-SKRIPT
# Fuehrt eine vollstaendige Systemanalyse durch und zeigt die Ergebnisse an.
# Ausfuehren: chmod +x 01-diagnose.sh && ./01-diagnose.sh
###############################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

REPORT_FILE="$HOME/Desktop/mac-diagnose-$(date +%Y%m%d-%H%M%S).txt"

log() {
    echo -e "$1"
    echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g' >> "$REPORT_FILE"
}

header() {
    log ""
    log "${BLUE}${BOLD}========================================${NC}"
    log "${BLUE}${BOLD}  $1${NC}"
    log "${BLUE}${BOLD}========================================${NC}"
}

warn() {
    log "${RED}  [PROBLEM] $1${NC}"
}

ok() {
    log "${GREEN}  [OK] $1${NC}"
}

info() {
    log "${YELLOW}  [INFO] $1${NC}"
}

echo "" > "$REPORT_FILE"
log "${BOLD}Mac Performance Diagnose - $(date)${NC}"

###############################################################################
header "1. SYSTEM-INFORMATIONEN"
###############################################################################
log "  macOS Version: $(sw_vers -productVersion 2>/dev/null || echo 'Unbekannt')"
log "  Modell: $(sysctl -n hw.model 2>/dev/null || echo 'Unbekannt')"
log "  CPU: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'Unbekannt')"
log "  CPU Kerne: $(sysctl -n hw.ncpu 2>/dev/null || echo 'Unbekannt')"
TOTAL_RAM=$(($(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824))
log "  RAM: ${TOTAL_RAM} GB"
log "  Uptime: $(uptime | sed 's/.*up /up /' | sed 's/,.*//')"

###############################################################################
header "2. CPU-AUSLASTUNG - Top 15 Prozesse"
###############################################################################
log ""
ps aux -r | head -16 | while IFS= read -r line; do
    log "  $line"
done

CPU_HOGS=$(ps aux -r | awk 'NR>1 && $3>50 {print $11, $3"%"}')
if [ -n "$CPU_HOGS" ]; then
    warn "Prozesse mit >50% CPU:"
    echo "$CPU_HOGS" | while IFS= read -r line; do
        warn "  $line"
    done
else
    ok "Keine einzelnen Prozesse mit >50% CPU"
fi

###############################################################################
header "3. RAM-NUTZUNG"
###############################################################################
# vm_stat basierte Analyse
PAGE_SIZE=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
VM_STATS=$(vm_stat 2>/dev/null)

if [ -n "$VM_STATS" ]; then
    FREE_PAGES=$(echo "$VM_STATS" | grep "Pages free" | awk '{print $3}' | tr -d '.')
    ACTIVE_PAGES=$(echo "$VM_STATS" | grep "Pages active" | awk '{print $3}' | tr -d '.')
    INACTIVE_PAGES=$(echo "$VM_STATS" | grep "Pages inactive" | awk '{print $3}' | tr -d '.')
    WIRED_PAGES=$(echo "$VM_STATS" | grep "Pages wired" | awk '{print $4}' | tr -d '.')
    COMPRESSED_PAGES=$(echo "$VM_STATS" | grep "Pages occupied by compressor" | awk '{print $5}' | tr -d '.')
    SWAP_USED=$(sysctl -n vm.swapusage 2>/dev/null | awk '{print $6}')

    FREE_MB=$(( (FREE_PAGES * PAGE_SIZE) / 1048576 ))
    ACTIVE_MB=$(( (ACTIVE_PAGES * PAGE_SIZE) / 1048576 ))
    WIRED_MB=$(( (WIRED_PAGES * PAGE_SIZE) / 1048576 ))
    COMPRESSED_MB=$(( (COMPRESSED_PAGES * PAGE_SIZE) / 1048576 ))

    log "  Frei:        ${FREE_MB} MB"
    log "  Aktiv:       ${ACTIVE_MB} MB"
    log "  Wired:       ${WIRED_MB} MB"
    log "  Komprimiert: ${COMPRESSED_MB} MB"
    log "  Swap:        ${SWAP_USED:-0}"

    USED_PERCENT=$(( (ACTIVE_MB + WIRED_MB + COMPRESSED_MB) * 100 / (TOTAL_RAM * 1024) ))
    if [ "$USED_PERCENT" -gt 85 ]; then
        warn "RAM-Nutzung bei ${USED_PERCENT}% - KRITISCH!"
    elif [ "$USED_PERCENT" -gt 70 ]; then
        info "RAM-Nutzung bei ${USED_PERCENT}% - Erhoehter Verbrauch"
    else
        ok "RAM-Nutzung bei ${USED_PERCENT}% - Normal"
    fi
fi

# Top RAM-Verbraucher
log ""
log "  Top 10 RAM-Verbraucher:"
ps aux -m | head -11 | awk 'NR>1 {printf "    %-40s %s MB\n", $11, int($6/1024)}' | while IFS= read -r line; do
    log "$line"
done

###############################################################################
header "4. FESTPLATTEN-SPEICHER"
###############################################################################
DISK_INFO=$(df -H / 2>/dev/null | awk 'NR==2')
DISK_USED_PERCENT=$(echo "$DISK_INFO" | awk '{print $5}' | tr -d '%')
DISK_AVAIL=$(echo "$DISK_INFO" | awk '{print $4}')

log "  Verfuegbar: ${DISK_AVAIL}"
log "  Belegt: ${DISK_USED_PERCENT}%"

if [ "$DISK_USED_PERCENT" -gt 90 ]; then
    warn "Festplatte zu ${DISK_USED_PERCENT}% voll - KRITISCH! macOS braucht mind. 10% frei!"
elif [ "$DISK_USED_PERCENT" -gt 80 ]; then
    info "Festplatte zu ${DISK_USED_PERCENT}% voll - Aufraeumen empfohlen"
else
    ok "Festplatte hat genuegend Platz (${DISK_USED_PERCENT}% belegt)"
fi

# Groesste Ordner im Home
log ""
log "  Groesste Ordner in ~/ :"
du -sh ~/Downloads ~/Library/Caches ~/Library/Application\ Support ~/.Trash ~/Documents ~/Desktop 2>/dev/null | sort -rh | head -10 | while IFS= read -r line; do
    log "    $line"
done

###############################################################################
header "5. NETZWERK-DIAGNOSE"
###############################################################################
# DNS-Geschwindigkeit
DNS_TIME=$(dig google.com +time=5 +tries=1 2>/dev/null | grep "Query time" | awk '{print $4}')
if [ -n "$DNS_TIME" ]; then
    if [ "$DNS_TIME" -gt 200 ]; then
        warn "DNS-Aufloesung langsam: ${DNS_TIME}ms (sollte <100ms sein)"
    else
        ok "DNS-Aufloesung: ${DNS_TIME}ms"
    fi
else
    info "DNS-Test konnte nicht durchgefuehrt werden"
fi

# Internet-Konnektivitaet
if ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
    PING_TIME=$(ping -c 3 -W 3 8.8.8.8 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
    if [ -n "$PING_TIME" ]; then
        PING_INT=${PING_TIME%.*}
        if [ "$PING_INT" -gt 100 ]; then
            warn "Hohe Latenz: ${PING_TIME}ms"
        else
            ok "Ping: ${PING_TIME}ms"
        fi
    fi
else
    warn "Keine Internet-Verbindung!"
fi

# Aktive Netzwerkverbindungen zaehlen
CONN_COUNT=$(netstat -an 2>/dev/null | grep ESTABLISHED | wc -l | tr -d ' ')
log "  Aktive Verbindungen: ${CONN_COUNT}"
if [ "$CONN_COUNT" -gt 200 ]; then
    warn "Sehr viele offene Verbindungen (${CONN_COUNT}) - moeglicherweise Malware oder haengende Apps"
fi

###############################################################################
header "6. LOGIN-ITEMS & AUTOSTART"
###############################################################################
log "  Login-Items (starten beim Hochfahren):"
osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null | tr ',' '\n' | while IFS= read -r item; do
    log "    - $(echo "$item" | xargs)"
done

# LaunchAgents
log ""
log "  Benutzer-LaunchAgents:"
ls ~/Library/LaunchAgents/ 2>/dev/null | while IFS= read -r agent; do
    log "    - $agent"
done

AGENT_COUNT=$(ls ~/Library/LaunchAgents/ 2>/dev/null | wc -l | tr -d ' ')
if [ "$AGENT_COUNT" -gt 10 ]; then
    warn "${AGENT_COUNT} LaunchAgents - Viele Hintergrundprozesse!"
fi

###############################################################################
header "7. BROWSER-CHECK"
###############################################################################
for browser in "Google Chrome" "Safari" "Firefox" "Microsoft Edge" "Brave Browser" "Arc"; do
    PID=$(pgrep -f "$browser" 2>/dev/null | head -1)
    if [ -n "$PID" ]; then
        BROWSER_CPU=$(ps -p "$PID" -o %cpu= 2>/dev/null | tr -d ' ')
        BROWSER_MEM=$(ps -p "$PID" -o rss= 2>/dev/null)
        BROWSER_MEM_MB=$((BROWSER_MEM / 1024))
        TAB_COUNT=$(pgrep -f "$browser" 2>/dev/null | wc -l | tr -d ' ')
        log "  ${browser}: ~${TAB_COUNT} Prozesse, ${BROWSER_MEM_MB}MB RAM, ${BROWSER_CPU}% CPU"

        if [ "$BROWSER_MEM_MB" -gt 4000 ]; then
            warn "${browser} verbraucht ueber 4GB RAM - Tabs schliessen!"
        fi
    fi
done

###############################################################################
header "8. THERMISCHE DROSSELUNG (Thermal Throttle)"
###############################################################################
THERMAL=$(pmset -g thermlog 2>/dev/null | tail -5)
if [ -n "$THERMAL" ]; then
    log "  $THERMAL"
    if echo "$THERMAL" | grep -qi "speed_limit"; then
        warn "CPU wird thermisch gedrosselt! Mac ueberhitzt."
    fi
else
    info "Thermal-Log nicht verfuegbar"
fi

# CPU-Temperatur (wenn moeglich)
CPU_DIE_TEMP=$(sudo powermetrics --samplers smc -i 1 -n 1 2>/dev/null | grep "CPU die temperature" | awk '{print $4}')
if [ -n "$CPU_DIE_TEMP" ]; then
    log "  CPU-Temperatur: ${CPU_DIE_TEMP}C"
fi

###############################################################################
header "9. SPOTLIGHT & INDEXIERUNG"
###############################################################################
SPOTLIGHT_STATUS=$(mdutil -s / 2>/dev/null)
log "  $SPOTLIGHT_STATUS"

if pgrep -x "mds_stores" &>/dev/null; then
    MDS_CPU=$(ps aux | grep "mds_stores" | grep -v grep | awk '{print $3}')
    if [ -n "$MDS_CPU" ]; then
        MDS_INT=${MDS_CPU%.*}
        if [ "$MDS_INT" -gt 20 ]; then
            warn "Spotlight-Indexierung laeuft und verbraucht ${MDS_CPU}% CPU!"
        fi
    fi
fi

###############################################################################
header "10. ZUSAMMENFASSUNG"
###############################################################################
log ""
log "  Diagnose-Report gespeichert unter:"
log "  ${BOLD}${REPORT_FILE}${NC}"
log ""
log "${GREEN}${BOLD}  Naechster Schritt: Fuehre 02-sofortmassnahmen.sh aus!${NC}"
log ""
