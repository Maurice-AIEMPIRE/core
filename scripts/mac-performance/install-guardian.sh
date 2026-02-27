#!/bin/bash
###############################################################################
# MAC GUARDIAN INSTALLER
# Installiert den Guardian Daemon als macOS LaunchAgent.
# Der Daemon startet automatisch beim Login und ueberwacht dein System.
#
# Ausfuehren: chmod +x install-guardian.sh && ./install-guardian.sh
###############################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARDIAN_INSTALL_DIR="$HOME/.mac-guardian"
PLIST_NAME="com.mac-guardian.daemon"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"

echo -e "${BOLD}${BLUE}"
echo "============================================="
echo "  MAC GUARDIAN - Installer"
echo "============================================="
echo -e "${NC}"

# Voraussetzungen pruefen
if [ ! -f "$SCRIPT_DIR/mac-guardian-daemon.sh" ]; then
    echo -e "${RED}Fehler: mac-guardian-daemon.sh nicht gefunden!${NC}"
    echo "Bitte stelle sicher, dass alle Dateien im selben Ordner liegen."
    exit 1
fi

echo "Das wird installiert:"
echo "  1. Guardian Daemon nach ~/.mac-guardian/"
echo "  2. LaunchAgent fuer automatischen Start beim Login"
echo "  3. Konfigurationsdatei fuer Anpassungen"
echo ""
read -p "Installation starten? (j/n): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Jj]$ ]]; then
    echo "Installation abgebrochen."
    exit 0
fi

###############################################################################
echo -e "\n${BOLD}[1/4] Installationsordner vorbereiten${NC}"
###############################################################################
mkdir -p "$GUARDIAN_INSTALL_DIR"
mkdir -p "$HOME/Library/LaunchAgents"

# Daemon-Skript kopieren
cp "$SCRIPT_DIR/mac-guardian-daemon.sh" "$GUARDIAN_INSTALL_DIR/mac-guardian-daemon.sh"
chmod +x "$GUARDIAN_INSTALL_DIR/mac-guardian-daemon.sh"
echo -e "${GREEN}  ✓ Daemon installiert nach $GUARDIAN_INSTALL_DIR${NC}"

###############################################################################
echo -e "\n${BOLD}[2/4] Konfiguration erstellen${NC}"
###############################################################################
if [ ! -f "$GUARDIAN_INSTALL_DIR/config.sh" ]; then
    cat > "$GUARDIAN_INSTALL_DIR/config.sh" << 'CONFIGEOF'
#!/bin/bash
###############################################################################
# MAC GUARDIAN - Konfiguration
# Passe diese Werte an deinen Mac an.
# Aenderungen werden beim naechsten Check-Zyklus aktiv (alle 10 Sekunden).
###############################################################################

# Wie oft pruefen (in Sekunden)
CHECK_INTERVAL=10

# CPU-Schwellwerte (in Prozent)
CPU_WARN_THRESHOLD=80          # Ab wann eine Warnung kommt
CPU_CRITICAL_THRESHOLD=95      # Ab wann automatisch eingegriffen wird

# RAM-Schwellwerte (in Prozent)
RAM_WARN_THRESHOLD=85          # Ab wann eine Warnung kommt
RAM_CRITICAL_THRESHOLD=93      # Ab wann automatisch eingegriffen wird

# Swap-Schwellwert (in MB)
SWAP_WARN_MB=2048

# Wie lange eine App nicht reagieren darf (Sekunden)
APP_HUNG_TIMEOUT=30

# Max. automatische App-Beendigungen pro Stunde (Sicherheitsgrenze)
MAX_KILLS_PER_HOUR=5

# Festplatten-Warnung (in Prozent)
DISK_WARN_THRESHOLD=90

# Apps die NIEMALS automatisch beendet werden
# Fuege hier deine wichtigen Apps hinzu
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
    "Xcode"
    "Visual Studio Code"
    "Code"
)

# Apps mit niedriger Prioritaet (werden zuerst beendet bei Engpaessen)
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
    "Figma"
    "Notion"
)
CONFIGEOF
    echo -e "${GREEN}  ✓ Konfiguration erstellt: $GUARDIAN_INSTALL_DIR/config.sh${NC}"
else
    echo -e "${YELLOW}  → Bestehende Konfiguration beibehalten${NC}"
fi

###############################################################################
echo -e "\n${BOLD}[3/4] LaunchAgent einrichten${NC}"
###############################################################################
# Bestehenden Agent stoppen falls vorhanden
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
        <string>${GUARDIAN_INSTALL_DIR}/mac-guardian-daemon.sh</string>
        <string>foreground</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>${GUARDIAN_INSTALL_DIR}/stdout.log</string>

    <key>StandardErrorPath</key>
    <string>${GUARDIAN_INSTALL_DIR}/stderr.log</string>

    <key>ProcessType</key>
    <string>Background</string>

    <key>LowPriorityIO</key>
    <true/>

    <key>Nice</key>
    <integer>10</integer>

    <key>ThrottleInterval</key>
    <integer>5</integer>
</dict>
</plist>
PLISTEOF

echo -e "${GREEN}  ✓ LaunchAgent erstellt: $PLIST_PATH${NC}"

###############################################################################
echo -e "\n${BOLD}[4/4] Guardian starten${NC}"
###############################################################################
launchctl load "$PLIST_PATH" 2>/dev/null
sleep 2

# Pruefen ob es laeuft
if pgrep -f "mac-guardian-daemon" &>/dev/null; then
    echo -e "${GREEN}  ✓ Guardian laeuft!${NC}"
else
    echo -e "${YELLOW}  Guardian wird beim naechsten Login automatisch starten${NC}"
fi

###############################################################################
echo ""
echo -e "${GREEN}${BOLD}=============================================${NC}"
echo -e "${GREEN}${BOLD}  INSTALLATION ERFOLGREICH!${NC}"
echo -e "${GREEN}${BOLD}=============================================${NC}"
echo ""
echo "  Guardian ueberwacht jetzt automatisch deinen Mac."
echo "  Er startet bei jedem Login automatisch."
echo ""
echo "  Befehle:"
echo "    Status:       ~/.mac-guardian/mac-guardian-daemon.sh status"
echo "    Stoppen:      ~/.mac-guardian/mac-guardian-daemon.sh stop"
echo "    Starten:      ~/.mac-guardian/mac-guardian-daemon.sh start"
echo "    Log ansehen:  tail -f ~/.mac-guardian/guardian.log"
echo "    Konfigurieren: nano ~/.mac-guardian/config.sh"
echo ""
echo "  Deinstallieren:"
echo "    launchctl unload ~/Library/LaunchAgents/${PLIST_NAME}.plist"
echo "    rm ~/Library/LaunchAgents/${PLIST_NAME}.plist"
echo "    rm -rf ~/.mac-guardian"
echo ""
echo -e "${BLUE}  Dein Mac wird ab jetzt automatisch ueberwacht und optimiert!${NC}"
echo ""
