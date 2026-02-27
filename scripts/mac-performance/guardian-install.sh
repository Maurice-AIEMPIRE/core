#!/bin/bash
###############################################################################
# MAC GUARDIAN - ONE-CLICK INSTALLER
#
# Installiert das komplette Guardian-System mit allen Modulen.
# Ein einziger Befehl fuer alles:
#
#   curl -sL [REPO_URL]/guardian-install.sh | bash
#   ODER
#   ./guardian-install.sh
#
###############################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

GUARDIAN_HOME="$HOME/.mac-guardian"
MODULES_DIR="$GUARDIAN_HOME/modules"
CONFIG_DIR="$GUARDIAN_HOME/config"
LOG_DIR="$GUARDIAN_HOME/logs"
DATA_DIR="$GUARDIAN_HOME/data"
PLIST_NAME="com.mac-guardian.orchestrator"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"

echo -e "${BOLD}${CYAN}"
cat << 'BANNER'

  ╔═══════════════════════════════════════════════╗
  ║                                               ║
  ║   🛡  MAC GUARDIAN - AI Performance System    ║
  ║                                               ║
  ║   Automatischer Schutz vor:                   ║
  ║   • Einfrieren & Haenger                      ║
  ║   • Ueberhitzung & Throttling                 ║
  ║   • Speicherlecks & RAM-Mangel                ║
  ║   • Volle Festplatte                          ║
  ║   • Langsames Netzwerk                        ║
  ║   • Haengende Apps                            ║
  ║                                               ║
  ╚═══════════════════════════════════════════════╝

BANNER
echo -e "${NC}"

echo -e "${BOLD}System-Info:${NC}"
echo "  macOS:  $(sw_vers -productVersion 2>/dev/null || echo 'N/A')"
echo "  CPU:    $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'N/A')"
echo "  RAM:    $(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 )) GB"
echo "  Disk:   $(df -H / | awk 'NR==2 {print $4 " frei von " $2}')"
echo ""

read -p "$(echo -e "${GREEN}Guardian installieren? (j/n): ${NC}")" -n 1 -r
echo
[[ ! $REPLY =~ ^[Jj]$ ]] && echo "Abgebrochen." && exit 0

###############################################################################
echo -e "\n${BOLD}[1/6] Verzeichnisse erstellen${NC}"
###############################################################################
mkdir -p "$GUARDIAN_HOME" "$MODULES_DIR" "$CONFIG_DIR" "$LOG_DIR" "$DATA_DIR"
mkdir -p "$DATA_DIR/brain" "$DATA_DIR/memory" "$DATA_DIR/network" "$DATA_DIR/process"
mkdir -p "$GUARDIAN_HOME/history"
echo -e "${GREEN}  ✓ Verzeichnisse erstellt${NC}"

###############################################################################
echo -e "\n${BOLD}[2/6] Module installieren${NC}"
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Pruefen ob Module-Ordner existiert (lokale Installation)
if [ -d "$SCRIPT_DIR/modules" ]; then
    cp "$SCRIPT_DIR/modules/"*.sh "$MODULES_DIR/"
    echo -e "${GREEN}  ✓ Module aus lokalem Ordner kopiert${NC}"
else
    echo -e "${RED}  Module-Ordner nicht gefunden!${NC}"
    echo "  Stelle sicher, dass der 'modules/' Ordner neben diesem Skript liegt."
    exit 1
fi

chmod +x "$MODULES_DIR/"*.sh
echo -e "${GREEN}  ✓ Alle Module ausfuehrbar gemacht${NC}"

# Module auflisten
echo "  Installierte Module:"
for mod in "$MODULES_DIR/"*.sh; do
    echo -e "    ${CYAN}$(basename "$mod")${NC}"
done

###############################################################################
echo -e "\n${BOLD}[3/6] Konfiguration erstellen${NC}"
###############################################################################
if [ ! -f "$CONFIG_DIR/guardian.conf" ]; then
    cat > "$CONFIG_DIR/guardian.conf" << 'CONFEOF'
###############################################################################
# MAC GUARDIAN - Konfiguration
# Bearbeiten: nano ~/.mac-guardian/config/guardian.conf
###############################################################################

# Pruef-Intervall (Sekunden)
CHECK_INTERVAL=10

# CPU-Schwellwerte (Prozent)
CPU_WARN_THRESHOLD=80
CPU_CRITICAL_THRESHOLD=95

# RAM-Schwellwerte (Prozent)
RAM_WARN_THRESHOLD=85
RAM_CRITICAL_THRESHOLD=93

# Swap-Warnung (MB)
SWAP_WARN_MB=2048

# Festplatten-Warnung (Prozent)
DISK_WARN_THRESHOLD=85
DISK_CRITICAL_THRESHOLD=95

# Temperatur (Celsius)
TEMP_WARN=80
TEMP_CRITICAL=95

# Max. automatische App-Beendigungen pro Stunde
MAX_KILLS_PER_HOUR=5

# Tagesbericht-Stunde (24h Format)
DAILY_REPORT_HOUR=22

# Apps die NIEMALS beendet werden (eine pro Zeile, Pipe-getrennt)
PROTECTED_APPS="Finder|WindowServer|kernel_task|loginwindow|SystemUIServer|Dock|launchd|Terminal|iTerm2|Claude|Activity Monitor|Xcode|Visual Studio Code|Code"

# Apps mit niedriger Prioritaet (werden zuerst beendet)
LOW_PRIORITY_APPS="Slack|Discord|Spotify|Microsoft Teams|zoom.us|Skype|Steam|Epic Games|Docker|Figma|Notion"
CONFEOF
    echo -e "${GREEN}  ✓ Konfiguration erstellt${NC}"
else
    echo -e "${YELLOW}  → Bestehende Konfiguration beibehalten${NC}"
fi

###############################################################################
echo -e "\n${BOLD}[4/6] LaunchAgent einrichten (Autostart)${NC}"
###############################################################################
# Bestehenden Agent stoppen
if [ -f "$PLIST_PATH" ]; then
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
fi

cat > "$PLIST_PATH" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_NAME}</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${MODULES_DIR}/orchestrator.sh</string>
        <string>foreground</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>

    <key>StandardOutPath</key>
    <string>${LOG_DIR}/stdout.log</string>

    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/stderr.log</string>

    <key>ProcessType</key>
    <string>Background</string>

    <key>LowPriorityIO</key>
    <true/>

    <key>Nice</key>
    <integer>10</integer>

    <key>ThrottleInterval</key>
    <integer>5</integer>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>GUARDIAN_HOME</key>
        <string>${GUARDIAN_HOME}</string>
    </dict>
</dict>
</plist>
PLISTEOF

echo -e "${GREEN}  ✓ LaunchAgent erstellt (startet automatisch beim Login)${NC}"

###############################################################################
echo -e "\n${BOLD}[5/6] Kontroli-Skript erstellen${NC}"
###############################################################################
cat > "$GUARDIAN_HOME/guardian" << 'CTLEOF'
#!/bin/bash
# Mac Guardian Kontroll-Skript
# Verwendung: guardian {start|stop|status|audit|report|log|config|uninstall}

GUARDIAN_HOME="$HOME/.mac-guardian"
MODULES_DIR="$GUARDIAN_HOME/modules"
PLIST="$HOME/Library/LaunchAgents/com.mac-guardian.orchestrator.plist"

case "${1:-status}" in
    start)
        launchctl load "$PLIST" 2>/dev/null
        echo "Guardian gestartet"
        ;;
    stop)
        launchctl unload "$PLIST" 2>/dev/null
        echo "Guardian gestoppt"
        ;;
    restart)
        launchctl unload "$PLIST" 2>/dev/null
        sleep 1
        launchctl load "$PLIST" 2>/dev/null
        echo "Guardian neugestartet"
        ;;
    status)
        bash "$MODULES_DIR/orchestrator.sh" status
        ;;
    audit)
        echo "Starte vollstaendiges System-Audit..."
        bash "$MODULES_DIR/audit-engine.sh"
        ;;
    report)
        bash "$MODULES_DIR/orchestrator.sh" report
        ;;
    log)
        tail -f "$GUARDIAN_HOME/logs/master.log"
        ;;
    config)
        ${EDITOR:-nano} "$GUARDIAN_HOME/config/guardian.conf"
        ;;
    uninstall)
        echo "Mac Guardian deinstallieren?"
        read -p "Bist du sicher? (j/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Jj]$ ]]; then
            launchctl unload "$PLIST" 2>/dev/null || true
            rm -f "$PLIST"
            rm -rf "$GUARDIAN_HOME"
            rm -f /usr/local/bin/guardian 2>/dev/null || true
            echo "Guardian deinstalliert."
        fi
        ;;
    *)
        echo ""
        echo "🛡  Mac Guardian - Befehle:"
        echo ""
        echo "  guardian start      Starte Guardian"
        echo "  guardian stop       Stoppe Guardian"
        echo "  guardian restart    Neustarten"
        echo "  guardian status     Status & Metriken"
        echo "  guardian audit      Vollstaendiges System-Audit"
        echo "  guardian report     Tagesbericht"
        echo "  guardian log        Live-Log"
        echo "  guardian config     Konfiguration bearbeiten"
        echo "  guardian uninstall  Deinstallieren"
        echo ""
        ;;
esac
CTLEOF

chmod +x "$GUARDIAN_HOME/guardian"

# In PATH verlinken (optional, braucht sudo)
if [ -d "/usr/local/bin" ]; then
    sudo ln -sf "$GUARDIAN_HOME/guardian" /usr/local/bin/guardian 2>/dev/null || true
fi

echo -e "${GREEN}  ✓ Kontroll-Skript erstellt${NC}"

###############################################################################
echo -e "\n${BOLD}[6/6] Guardian starten${NC}"
###############################################################################
launchctl load "$PLIST_PATH" 2>/dev/null || true
sleep 2

if pgrep -f "orchestrator.sh" &>/dev/null; then
    echo -e "${GREEN}  ✓ Guardian laeuft!${NC}"
else
    echo -e "${YELLOW}  Guardian wird beim naechsten Login automatisch starten${NC}"
    echo "  Manuell starten: guardian start"
fi

###############################################################################
echo ""
echo -e "${GREEN}${BOLD}"
cat << 'DONE'
  ╔═══════════════════════════════════════════════╗
  ║                                               ║
  ║   🛡  INSTALLATION ERFOLGREICH!               ║
  ║                                               ║
  ║   Dein Mac wird jetzt automatisch             ║
  ║   ueberwacht und optimiert.                   ║
  ║                                               ║
  ║   Befehle:                                    ║
  ║     guardian status    - Status anzeigen       ║
  ║     guardian audit     - System-Audit          ║
  ║     guardian log       - Live-Log              ║
  ║     guardian config    - Einstellungen          ║
  ║     guardian stop      - Stoppen               ║
  ║     guardian uninstall - Deinstallieren         ║
  ║                                               ║
  ╚═══════════════════════════════════════════════╝

DONE
echo -e "${NC}"

# Erstes Audit vorschlagen
echo -e "${YELLOW}Tipp: Fuehre jetzt ein erstes System-Audit durch:${NC}"
echo -e "${BOLD}  guardian audit${NC}"
echo ""
