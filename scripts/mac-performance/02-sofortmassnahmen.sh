#!/bin/bash
###############################################################################
# MAC SOFORTMASSNAHMEN - Performance sofort verbessern
# Fuehrt sichere Sofortmassnahmen durch, um den Mac sofort schneller zu machen.
# Ausfuehren: chmod +x 02-sofortmassnahmen.sh && ./02-sofortmassnahmen.sh
###############################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}"
echo "============================================="
echo "  MAC SOFORTMASSNAHMEN - Performance Fix"
echo "  $(date)"
echo "============================================="
echo -e "${NC}"

confirm() {
    echo -e "${YELLOW}$1${NC}"
    read -p "Ausfuehren? (j/n): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Jj]$ ]]
}

success() {
    echo -e "${GREEN}  ✓ $1${NC}"
}

skip() {
    echo -e "${YELLOW}  → Uebersprungen${NC}"
}

###############################################################################
echo -e "\n${BOLD}[1/8] RAM FREIGEBEN${NC}"
###############################################################################
if confirm "  Inaktiven Speicher freigeben (purge)?"; then
    sudo purge 2>/dev/null && success "RAM-Cache geleert" || echo "  Fehler - sudo-Rechte benoetigt"
else
    skip
fi

###############################################################################
echo -e "\n${BOLD}[2/8] CPU-FRESSER IDENTIFIZIEREN & BEENDEN${NC}"
###############################################################################
echo "  Prozesse mit hoher CPU-Last:"
HIGH_CPU_PROCS=$(ps aux -r | awk 'NR>1 && $3>30 && $11 !~ /WindowServer|kernel_task|hidd/' | head -10)

if [ -n "$HIGH_CPU_PROCS" ]; then
    echo "$HIGH_CPU_PROCS" | awk '{printf "    PID: %-8s CPU: %-6s Prozess: %s\n", $2, $3"%", $11}'
    echo ""
    if confirm "  Moechtest du einzelne Prozesse beenden?"; then
        echo "$HIGH_CPU_PROCS" | while IFS= read -r proc; do
            PID=$(echo "$proc" | awk '{print $2}')
            NAME=$(echo "$proc" | awk '{print $11}')
            CPU=$(echo "$proc" | awk '{print $3}')
            echo -e "    ${YELLOW}${NAME} (PID: ${PID}, CPU: ${CPU}%)${NC}"
            read -p "    Diesen Prozess beenden? (j/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Jj]$ ]]; then
                kill "$PID" 2>/dev/null && success "Beendet: ${NAME}" || echo "    Konnte nicht beendet werden"
            fi
        done
    else
        skip
    fi
else
    success "Keine Prozesse mit >30% CPU gefunden"
fi

###############################################################################
echo -e "\n${BOLD}[3/8] HAENGENDE APPS BEENDEN${NC}"
###############################################################################
# Apps die "Not Responding" sind
HUNG_APPS=""
for app in $(osascript -e 'tell application "System Events" to get name of every application process whose background only is false' 2>/dev/null | tr ',' '\n'); do
    app=$(echo "$app" | xargs)
    if [ -n "$app" ]; then
        # Pruefen ob App reagiert (timeout nach 2 Sekunden)
        if ! timeout 2 osascript -e "tell application \"$app\" to count windows" &>/dev/null; then
            HUNG_APPS="${HUNG_APPS}${app}\n"
        fi
    fi
done

if [ -n "$HUNG_APPS" ]; then
    echo -e "  Nicht reagierende Apps gefunden:"
    echo -e "$HUNG_APPS" | while IFS= read -r app; do
        [ -z "$app" ] && continue
        echo -e "    ${RED}${app}${NC}"
        read -p "    Force-Quit ${app}? (j/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Jj]$ ]]; then
            osascript -e "tell application \"$app\" to quit" 2>/dev/null
            sleep 1
            pkill -f "$app" 2>/dev/null || true
            success "${app} beendet"
        fi
    done
else
    success "Keine haengenden Apps gefunden"
fi

###############################################################################
echo -e "\n${BOLD}[4/8] BROWSER-TABS OPTIMIEREN${NC}"
###############################################################################
for browser in "Google Chrome" "Safari" "Firefox" "Microsoft Edge" "Arc" "Brave Browser"; do
    PROC_COUNT=$(pgrep -f "$browser" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$PROC_COUNT" -gt 20 ]; then
        BROWSER_MEM=$(ps aux | grep -i "$browser" | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}')
        echo -e "  ${YELLOW}${browser}: ~${PROC_COUNT} Prozesse, ${BROWSER_MEM}MB RAM${NC}"
        echo "  Tipp: Schliesse nicht benoetigte Tabs!"
    fi
done

###############################################################################
echo -e "\n${BOLD}[5/8] SYSTEM-CACHES BEREINIGEN${NC}"
###############################################################################
if confirm "  Benutzer-Caches bereinigen? (sicher, Apps erstellen diese neu)"; then
    # Nur alte/grosse Caches loeschen, nicht alles
    CACHE_SIZE_BEFORE=$(du -sh ~/Library/Caches 2>/dev/null | awk '{print $1}')

    # Alte Browser-Caches
    rm -rf ~/Library/Caches/Google/Chrome/Default/Cache/* 2>/dev/null
    rm -rf ~/Library/Caches/com.apple.Safari/WebKitCache/* 2>/dev/null
    rm -rf ~/Library/Caches/Firefox/Profiles/*/cache2/* 2>/dev/null

    # Allgemeine System-Caches (sicher zu loeschen)
    rm -rf ~/Library/Caches/com.apple.iconservices.store/* 2>/dev/null
    rm -rf ~/Library/Caches/com.apple.Safari/fsCachedData/* 2>/dev/null
    rm -rf ~/Library/Caches/CloudKit/* 2>/dev/null

    # Temporaere Dateien
    rm -rf /tmp/com.apple.* 2>/dev/null || true
    rm -rf "$TMPDIR"com.apple.* 2>/dev/null || true

    CACHE_SIZE_AFTER=$(du -sh ~/Library/Caches 2>/dev/null | awk '{print $1}')
    success "Caches bereinigt: ${CACHE_SIZE_BEFORE} -> ${CACHE_SIZE_AFTER}"
else
    skip
fi

###############################################################################
echo -e "\n${BOLD}[6/8] DNS-CACHE LEEREN${NC}"
###############################################################################
if confirm "  DNS-Cache leeren (hilft bei langsamen Webseiten)?"; then
    sudo dscacheutil -flushcache 2>/dev/null
    sudo killall -HUP mDNSResponder 2>/dev/null
    success "DNS-Cache geleert"
else
    skip
fi

###############################################################################
echo -e "\n${BOLD}[7/8] PAPIERKORB LEEREN${NC}"
###############################################################################
TRASH_SIZE=$(du -sh ~/.Trash 2>/dev/null | awk '{print $1}')
if [ -n "$TRASH_SIZE" ] && [ "$TRASH_SIZE" != "0B" ]; then
    if confirm "  Papierkorb leeren? (Aktuell: ${TRASH_SIZE})"; then
        rm -rf ~/.Trash/* 2>/dev/null
        success "Papierkorb geleert (${TRASH_SIZE} freigegeben)"
    else
        skip
    fi
else
    success "Papierkorb ist bereits leer"
fi

###############################################################################
echo -e "\n${BOLD}[8/8] SPOTLIGHT NEU STARTEN (falls es CPU frisst)${NC}"
###############################################################################
MDS_CPU=$(ps aux | grep "mds_stores" | grep -v grep | awk '{print $3}' | head -1)
MDS_INT=${MDS_CPU%.*}
if [ -n "$MDS_INT" ] && [ "$MDS_INT" -gt 15 ]; then
    echo -e "  ${YELLOW}Spotlight verbraucht ${MDS_CPU}% CPU${NC}"
    if confirm "  Spotlight-Indexierung neu starten?"; then
        sudo mdutil -i off / 2>/dev/null
        sleep 2
        sudo mdutil -i on / 2>/dev/null
        success "Spotlight-Indexierung neu gestartet"
    else
        skip
    fi
else
    success "Spotlight ist unauffaellig"
fi

###############################################################################
echo ""
echo -e "${GREEN}${BOLD}=============================================${NC}"
echo -e "${GREEN}${BOLD}  SOFORTMASSNAHMEN ABGESCHLOSSEN!${NC}"
echo -e "${GREEN}${BOLD}=============================================${NC}"
echo ""
echo -e "  Dein Mac sollte jetzt spuerbar schneller sein."
echo -e "  Fuer dauerhafte Optimierung fuehre aus:"
echo -e "  ${BOLD}./03-dauerhafte-optimierung.sh${NC}"
echo ""
