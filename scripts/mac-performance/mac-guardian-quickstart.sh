#!/usr/bin/env bash
# ============================================================================
#
#   Mac Guardian - Quickstart Installer
#   Ein Befehl. Dein Mac friert nie mehr ein.
#
#   Usage:
#     bash <(curl -sL https://raw.githubusercontent.com/Maurice-AIEMPIRE/core/main/scripts/mac-performance/mac-guardian-quickstart.sh)
#
# ============================================================================
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

GUARDIAN_DIR="$HOME/.mac-guardian"
INSTALL_DIR="$GUARDIAN_DIR/bin"
REPO_URL="https://raw.githubusercontent.com/Maurice-AIEMPIRE/core/main/scripts/mac-performance"

# ============================================================================
# Banner
# ============================================================================
show_banner() {
    echo ""
    echo -e "${CYAN}${BOLD}"
    cat << 'BANNER'
    ╔══════════════════════════════════════════════════════╗
    ║                                                      ║
    ║   ███╗   ███╗ █████╗  ██████╗                        ║
    ║   ████╗ ████║██╔══██╗██╔════╝                        ║
    ║   ██╔████╔██║███████║██║                             ║
    ║   ██║╚██╔╝██║██╔══██║██║                             ║
    ║   ██║ ╚═╝ ██║██║  ██║╚██████╗                        ║
    ║   ╚═╝     ╚═╝╚═╝  ╚═╝ ╚═════╝                        ║
    ║                                                      ║
    ║    ██████╗ ██╗   ██╗ █████╗ ██████╗ ██████╗          ║
    ║   ██╔════╝ ██║   ██║██╔══██╗██╔══██╗██╔══██╗         ║
    ║   ██║  ███╗██║   ██║███████║██████╔╝██║  ██║         ║
    ║   ██║   ██║██║   ██║██╔══██║██╔══██╗██║  ██║         ║
    ║   ╚██████╔╝╚██████╔╝██║  ██║██║  ██║██████╔╝         ║
    ║    ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝          ║
    ║                                                      ║
    ║   AI-Powered Mac Performance Guardian                ║
    ║   Dein Mac friert nie mehr ein.                       ║
    ║                                                      ║
    ╚══════════════════════════════════════════════════════╝
BANNER
    echo -e "${NC}"
}

# ============================================================================
# Prerequisite Check
# ============================================================================
check_os() {
    if [[ "$(uname)" != "Darwin" ]]; then
        echo -e "${YELLOW}Hinweis: Mac Guardian ist fuer macOS optimiert.${NC}"
        echo -e "${YELLOW}Einige Funktionen sind auf $(uname) eingeschraenkt.${NC}"
        echo ""
        read -rp "Trotzdem fortfahren? (j/n): " confirm
        [[ "$confirm" != "j" ]] && exit 0
    fi
}

check_dependencies() {
    echo -e "${BLUE}[1/5] Pruefe Abhaengigkeiten...${NC}"

    local missing=()

    # Check for jq
    if ! command -v jq &>/dev/null; then
        missing+=("jq")
    fi

    # Check for bc
    if ! command -v bc &>/dev/null; then
        missing+=("bc")
    fi

    # Check for rsync (for cloud offload)
    if ! command -v rsync &>/dev/null; then
        missing+=("rsync")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${YELLOW}  Fehlende Pakete: ${missing[*]}${NC}"

        if command -v brew &>/dev/null; then
            echo -e "${BLUE}  Installiere mit Homebrew...${NC}"
            for pkg in "${missing[@]}"; do
                brew install "$pkg" 2>/dev/null || true
            done
        elif command -v apt-get &>/dev/null; then
            echo -e "${BLUE}  Installiere mit apt...${NC}"
            sudo apt-get update -qq && sudo apt-get install -y -qq "${missing[@]}" 2>/dev/null || true
        else
            echo -e "${RED}  Bitte installiere manuell: ${missing[*]}${NC}"
            echo "  macOS: brew install ${missing[*]}"
            echo "  Linux: sudo apt install ${missing[*]}"
        fi
    fi

    echo -e "${GREEN}  Abhaengigkeiten OK${NC}"
}

# ============================================================================
# Installation
# ============================================================================
install_scripts() {
    echo -e "${BLUE}[2/5] Installiere Mac Guardian...${NC}"

    mkdir -p "$INSTALL_DIR" "$GUARDIAN_DIR/logs" "$GUARDIAN_DIR/state"

    local scripts=("mac-guardian.sh" "cloud-offload.sh" "smart-monitor.sh")

    for script in "${scripts[@]}"; do
        echo -e "  Lade $script..."
        if curl -sL "${REPO_URL}/${script}" -o "${INSTALL_DIR}/${script}" 2>/dev/null; then
            chmod +x "${INSTALL_DIR}/${script}"
            echo -e "${GREEN}    $script installiert${NC}"
        else
            echo -e "${RED}    Download fehlgeschlagen: $script${NC}"
            echo -e "${YELLOW}    Versuche lokale Kopie...${NC}"

            # Fallback: check if running from repo
            local script_dir
            script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
            if [[ -f "$script_dir/$script" ]]; then
                cp "$script_dir/$script" "${INSTALL_DIR}/${script}"
                chmod +x "${INSTALL_DIR}/${script}"
                echo -e "${GREEN}    $script (lokal) installiert${NC}"
            fi
        fi
    done

    echo -e "${GREEN}  Installation abgeschlossen${NC}"
}

create_cli_wrapper() {
    echo -e "${BLUE}[3/5] Erstelle CLI-Befehle...${NC}"

    # Main CLI wrapper
    cat > "${INSTALL_DIR}/macguard" << 'WRAPPER'
#!/usr/bin/env bash
# Mac Guardian CLI
GUARDIAN_DIR="$HOME/.mac-guardian"
BIN_DIR="$GUARDIAN_DIR/bin"

case "${1:-help}" in
    start)    bash "$BIN_DIR/mac-guardian.sh" start ;;
    stop)     bash "$BIN_DIR/mac-guardian.sh" stop ;;
    status)   bash "$BIN_DIR/mac-guardian.sh" status ;;
    check)    bash "$BIN_DIR/mac-guardian.sh" check ;;
    clean)    bash "$BIN_DIR/mac-guardian.sh" clean ;;
    deep)     bash "$BIN_DIR/mac-guardian.sh" deep-clean ;;
    optimize) bash "$BIN_DIR/mac-guardian.sh" optimize ;;
    health)   bash "$BIN_DIR/smart-monitor.sh" health ;;
    trends)   bash "$BIN_DIR/smart-monitor.sh" trends ;;
    predict)  bash "$BIN_DIR/smart-monitor.sh" predict ;;
    watchdog) bash "$BIN_DIR/smart-monitor.sh" watchdog ;;
    report)   bash "$BIN_DIR/smart-monitor.sh" full ;;
    cloud)    bash "$BIN_DIR/cloud-offload.sh" "${@:2}" ;;
    offload)  bash "$BIN_DIR/cloud-offload.sh" interactive ;;
    install)  bash "$BIN_DIR/mac-guardian.sh" install ;;
    uninstall)
        bash "$BIN_DIR/mac-guardian.sh" uninstall
        echo "Entferne Mac Guardian..."
        rm -rf "$GUARDIAN_DIR"
        rm -f "$HOME/.local/bin/macguard"
        echo "Mac Guardian deinstalliert."
        ;;
    help|--help|-h|*)
        echo ""
        echo "  Mac Guardian - AI-Powered Mac Performance"
        echo "  =========================================="
        echo ""
        echo "  Schnellbefehle:"
        echo "    macguard status     - System-Status anzeigen"
        echo "    macguard health     - Health Score"
        echo "    macguard check      - Einmaliger System-Check"
        echo "    macguard clean      - Schnelle Bereinigung"
        echo "    macguard deep       - Tiefe Bereinigung"
        echo "    macguard optimize   - Volle Optimierung"
        echo ""
        echo "  Daemon:"
        echo "    macguard start      - Guardian-Daemon starten"
        echo "    macguard stop       - Guardian-Daemon stoppen"
        echo "    macguard install    - Autostart einrichten"
        echo ""
        echo "  Analyse:"
        echo "    macguard report     - Voller System-Bericht"
        echo "    macguard trends     - Trendanalyse"
        echo "    macguard predict    - Vorhersagen"
        echo "    macguard watchdog   - Prozess-Watchdog"
        echo ""
        echo "  Cloud:"
        echo "    macguard offload    - Dateien auf Cloud auslagern"
        echo "    macguard cloud setup - Hetzner konfigurieren"
        echo "    macguard cloud scan - Auslagerbare Dateien finden"
        echo "    macguard cloud list - Ausgelagerte Dateien zeigen"
        echo ""
        echo "  System:"
        echo "    macguard uninstall  - Mac Guardian entfernen"
        echo ""
        ;;
esac
WRAPPER
    chmod +x "${INSTALL_DIR}/macguard"

    # Add to PATH
    local shell_rc=""
    if [[ -f "$HOME/.zshrc" ]]; then
        shell_rc="$HOME/.zshrc"
    elif [[ -f "$HOME/.bashrc" ]]; then
        shell_rc="$HOME/.bashrc"
    elif [[ -f "$HOME/.bash_profile" ]]; then
        shell_rc="$HOME/.bash_profile"
    fi

    # Also install to ~/.local/bin
    mkdir -p "$HOME/.local/bin"
    ln -sf "${INSTALL_DIR}/macguard" "$HOME/.local/bin/macguard"

    if [[ -n "$shell_rc" ]]; then
        if ! grep -q "mac-guardian" "$shell_rc" 2>/dev/null; then
            echo "" >> "$shell_rc"
            echo "# Mac Guardian - AI Performance Monitor" >> "$shell_rc"
            echo 'export PATH="$HOME/.mac-guardian/bin:$HOME/.local/bin:$PATH"' >> "$shell_rc"
        fi
    fi

    export PATH="$INSTALL_DIR:$HOME/.local/bin:$PATH"

    echo -e "${GREEN}  CLI-Befehl 'macguard' verfuegbar${NC}"
}

initial_config() {
    echo -e "${BLUE}[4/5] Erstelle Konfiguration...${NC}"

    # Initialize guardian (creates config files)
    bash "${INSTALL_DIR}/mac-guardian.sh" status 2>/dev/null || true

    echo -e "${GREEN}  Konfiguration erstellt${NC}"
}

first_check() {
    echo -e "${BLUE}[5/5] Erster System-Check...${NC}"
    echo ""

    # Run health check
    bash "${INSTALL_DIR}/smart-monitor.sh" health 2>/dev/null || true

    # Quick optimization
    echo ""
    read -rp "Sofortige Optimierung durchfuehren? (j/n): " opt
    if [[ "$opt" == "j" ]] || [[ "$opt" == "J" ]]; then
        echo ""
        bash "${INSTALL_DIR}/mac-guardian.sh" optimize 2>/dev/null || true
    fi

    # Cloud setup
    echo ""
    read -rp "Hetzner Cloud-Auslagerung einrichten? (j/n): " cloud
    if [[ "$cloud" == "j" ]] || [[ "$cloud" == "J" ]]; then
        echo ""
        bash "${INSTALL_DIR}/cloud-offload.sh" setup 2>/dev/null || true
    fi

    # Auto-start
    echo ""
    read -rp "Guardian automatisch bei Login starten? (j/n): " autostart
    if [[ "$autostart" == "j" ]] || [[ "$autostart" == "J" ]]; then
        bash "${INSTALL_DIR}/mac-guardian.sh" install 2>/dev/null || true
    fi
}

# ============================================================================
# Main Installation
# ============================================================================
main() {
    show_banner
    check_os

    echo -e "${BOLD}Installation startet...${NC}"
    echo ""

    check_dependencies
    install_scripts
    create_cli_wrapper
    initial_config
    first_check

    echo ""
    echo -e "${GREEN}${BOLD}============================================${NC}"
    echo -e "${GREEN}${BOLD}  Mac Guardian erfolgreich installiert!     ${NC}"
    echo -e "${GREEN}${BOLD}============================================${NC}"
    echo ""
    echo -e "  ${CYAN}Schnellstart:${NC}"
    echo -e "    ${BOLD}macguard status${NC}    - System-Status"
    echo -e "    ${BOLD}macguard health${NC}    - Health Score"
    echo -e "    ${BOLD}macguard optimize${NC}  - Sofort optimieren"
    echo -e "    ${BOLD}macguard start${NC}     - Daemon starten (24/7 Schutz)"
    echo -e "    ${BOLD}macguard offload${NC}   - Dateien auf Cloud auslagern"
    echo ""
    echo -e "  ${YELLOW}Tipp: Starte eine neue Shell oder fuehre aus:${NC}"
    echo -e "    ${BOLD}source ${shell_rc:-~/.zshrc}${NC}"
    echo ""
    echo -e "  ${BLUE}Dein Mac ist jetzt geschuetzt.${NC}"
    echo ""
}

main "$@"
