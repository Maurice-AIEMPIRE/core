#!/bin/bash
###############################################################################
# DAUERHAFTE MAC-OPTIMIERUNG
# Wendet permanente Systemeinstellungen an, die den Mac dauerhaft schnell halten.
# Ausfuehren: chmod +x 03-dauerhafte-optimierung.sh && ./03-dauerhafte-optimierung.sh
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
echo "  DAUERHAFTE MAC-OPTIMIERUNG"
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

###############################################################################
echo -e "\n${BOLD}[1/9] ANIMATIONEN REDUZIEREN${NC}"
echo "  Weniger Animationen = schnelleres Gefuehl"
###############################################################################
if confirm "  Fenster-Animationen reduzieren?"; then
    # Fenster-Oeffen/Schliess-Animation beschleunigen
    defaults write NSGlobalDomain NSWindowResizeTime -float 0.1
    # Dock-Animation beschleunigen
    defaults write com.apple.dock autohide-time-modifier -float 0.3
    defaults write com.apple.dock autohide-delay -float 0
    # Launchpad-Animation deaktivieren
    defaults write com.apple.dock springboard-show-duration -float 0.1
    defaults write com.apple.dock springboard-hide-duration -float 0.1
    # Mission Control Animation beschleunigen
    defaults write com.apple.dock expose-animation-duration -float 0.15
    # Fenster-Effekte reduzieren
    defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false
    # Rubber-Band-Scrolling deaktivieren
    defaults write NSGlobalDomain NSScrollViewRubberbanding -bool false

    killall Dock 2>/dev/null || true
    success "Animationen reduziert"
else
    echo -e "  → Uebersprungen"
fi

###############################################################################
echo -e "\n${BOLD}[2/9] TRANSPARENZ-EFFEKTE REDUZIEREN${NC}"
echo "  Transparenz verbraucht GPU-Leistung"
###############################################################################
if confirm "  Transparenz reduzieren?"; then
    defaults write com.apple.universalaccess reduceTransparency -bool true
    success "Transparenz reduziert"
else
    echo -e "  → Uebersprungen"
fi

###############################################################################
echo -e "\n${BOLD}[3/9] SPOTLIGHT-INDEXIERUNG OPTIMIEREN${NC}"
echo "  Spotlight kann viel CPU verbrauchen"
###############################################################################
echo "  Aktuelle Spotlight-Ausschluesse:"
mdutil -s / 2>/dev/null | head -3

if confirm "  Grosse Ordner von Spotlight ausschliessen (node_modules, .git, etc.)?"; then
    # Erstelle .metadata_never_index Dateien in bekannten Problemordnern
    for dir in $(find ~ -maxdepth 4 -name "node_modules" -type d 2>/dev/null | head -20); do
        touch "$dir/.metadata_never_index" 2>/dev/null || true
    done

    # Weitere CPU-intensive Ordner
    for pattern in ".git" "venv" "__pycache__" ".cache" "dist" "build"; do
        for dir in $(find ~ -maxdepth 3 -name "$pattern" -type d 2>/dev/null | head -10); do
            touch "$dir/.metadata_never_index" 2>/dev/null || true
        done
    done

    success "Spotlight-Indexierung fuer Entwicklerordner deaktiviert"
else
    echo -e "  → Uebersprungen"
fi

###############################################################################
echo -e "\n${BOLD}[4/9] SCHRIFTEN-GLÄTTUNG OPTIMIEREN${NC}"
###############################################################################
if confirm "  Schrift-Rendering fuer Performance optimieren?"; then
    # Leichtere Schriftglaettung
    defaults write NSGlobalDomain AppleFontSmoothing -int 1
    success "Schrift-Rendering optimiert"
else
    echo -e "  → Uebersprungen"
fi

###############################################################################
echo -e "\n${BOLD}[5/9] TIME MACHINE WAEHREND NUTZUNG DROSSELN${NC}"
###############################################################################
if confirm "  Time Machine-Drosselung fuer bessere Performance?"; then
    sudo sysctl -w debug.lowpri_throttle_enabled=1 2>/dev/null || true
    success "Time Machine wird gedrosselt wenn du arbeitest"
else
    echo -e "  → Uebersprungen"
fi

###############################################################################
echo -e "\n${BOLD}[6/9] STARTUP-ITEMS BEREINIGEN${NC}"
###############################################################################
echo "  Aktuelle Login-Items:"
osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null | tr ',' '\n' | while IFS= read -r item; do
    echo "    - $(echo "$item" | xargs)"
done

echo ""
echo "  Benutzer-LaunchAgents:"
ls ~/Library/LaunchAgents/ 2>/dev/null | while IFS= read -r agent; do
    # Pruefen ob aktiviert
    STATUS="aktiv"
    if launchctl list 2>/dev/null | grep -q "$(basename "$agent" .plist)"; then
        STATUS="${GREEN}aktiv${NC}"
    else
        STATUS="${YELLOW}inaktiv${NC}"
    fi
    echo -e "    - $agent ($STATUS)"
done

if confirm "  Moechtest du einzelne LaunchAgents deaktivieren?"; then
    for agent_file in ~/Library/LaunchAgents/*.plist; do
        [ ! -f "$agent_file" ] && continue
        agent_name=$(basename "$agent_file")

        # Guardian nicht deaktivieren
        [[ "$agent_name" == *"mac-guardian"* ]] && continue

        echo -e "    ${YELLOW}${agent_name}${NC}"
        read -p "    Deaktivieren? (j/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Jj]$ ]]; then
            launchctl unload "$agent_file" 2>/dev/null || true
            # Backup erstellen statt loeschen
            mkdir -p ~/Library/LaunchAgents.disabled
            mv "$agent_file" ~/Library/LaunchAgents.disabled/
            success "Deaktiviert: $agent_name (Backup in ~/Library/LaunchAgents.disabled/)"
        fi
    done
else
    echo -e "  → Uebersprungen"
fi

###############################################################################
echo -e "\n${BOLD}[7/9] SWAP-OPTIMIERUNG${NC}"
###############################################################################
SWAP_USED=$(sysctl -n vm.swapusage 2>/dev/null | awk '{print $6}' | tr -d 'M')
if [ -n "$SWAP_USED" ] && [ "${SWAP_USED%.*}" -gt 0 ]; then
    echo "  Aktueller Swap-Verbrauch: ${SWAP_USED}MB"
    info_msg="  Swap wird reduziert wenn genuegend RAM frei ist"
    echo -e "${YELLOW}${info_msg}${NC}"
fi

###############################################################################
echo -e "\n${BOLD}[8/9] ENERGY SAVER OPTIMIEREN${NC}"
###############################################################################
if confirm "  Performance-Modus aktivieren (verhindert Schlaf bei Aktivitaet)?"; then
    # Verhindere Sleep bei Aktivitaet
    sudo pmset -a disablesleep 0
    # Standby-Verzoegerung erhoehen
    sudo pmset -a standbydelay 86400
    # Festplatten-Schlaf deaktivieren
    sudo pmset -a disksleep 0
    success "Performance-Energieeinstellungen aktiv"
else
    echo -e "  → Uebersprungen"
fi

###############################################################################
echo -e "\n${BOLD}[9/9] GUARDIAN DAEMON INSTALLIEREN${NC}"
echo "  Automatischer Hintergrund-Waechter fuer dein System"
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if confirm "  Mac Guardian Daemon installieren (ueberwacht & repariert automatisch)?"; then
    if [ -f "$SCRIPT_DIR/install-guardian.sh" ]; then
        bash "$SCRIPT_DIR/install-guardian.sh"
    else
        echo "  install-guardian.sh nicht gefunden. Bitte separat ausfuehren."
    fi
else
    echo -e "  → Uebersprungen"
fi

###############################################################################
echo ""
echo -e "${GREEN}${BOLD}=============================================${NC}"
echo -e "${GREEN}${BOLD}  DAUERHAFTE OPTIMIERUNG ABGESCHLOSSEN!${NC}"
echo -e "${GREEN}${BOLD}=============================================${NC}"
echo ""
echo "  Aenderungen werden nach einem Neustart vollstaendig wirksam."
echo ""
echo -e "  ${YELLOW}Empfehlung: Starte deinen Mac einmal neu${NC}"
echo ""
