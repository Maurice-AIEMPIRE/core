#!/bin/bash
set -euo pipefail

# ============================================
# AI EMPIRE - rclone Setup for iCloud
# ============================================

echo "================================================"
echo "  AI EMPIRE - iCloud Sync Setup (rclone)"
echo "================================================"
echo ""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[EMPIRE]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Check rclone
if ! command -v rclone &> /dev/null; then
    echo "rclone nicht gefunden. Installiere..."
    curl https://rclone.org/install.sh | bash
fi

echo ""
log "rclone iCloud Setup"
echo ""
echo "HINWEIS: iCloud erfordert App-spezifisches Passwort."
echo "Erstelle eines unter: https://appleid.apple.com/account/manage"
echo "  → Anmeldung und Sicherheit → App-spezifische Passwörter"
echo ""

read -p "Apple-ID (E-Mail): " apple_id
read -sp "App-spezifisches Passwort: " apple_pass
echo ""

# Create rclone config
mkdir -p /root/.config/rclone

# Check if icloud remote already exists
if rclone listremotes | grep -q "icloud:"; then
    warn "iCloud Remote existiert bereits. Überschreiben?"
    read -p "[y/N] " overwrite
    if [[ "$overwrite" != "y" ]]; then
        log "Abgebrochen."
        exit 0
    fi
fi

# Configure using rclone config
rclone config create icloud webdav \
    url "https://p46-caldav.icloud.com" \
    vendor "other" \
    user "$apple_id" \
    pass "$(rclone obscure "$apple_pass")"

echo ""
log "iCloud Remote konfiguriert."
echo ""

# Test connection
log "Teste Verbindung..."
if rclone lsd icloud: 2>/dev/null; then
    log "Verbindung erfolgreich!"
else
    warn "Verbindung fehlgeschlagen. Möglicherweise wird ein anderer WebDAV-Endpunkt benötigt."
    warn "Alternative: Nutze 'rclone config' manuell für detaillierte Einrichtung."
fi

echo ""
log "Test-Sync: rclone sync /empire/results/ icloud:AIEmpire/ --dry-run"
echo ""
log "Setup abgeschlossen. Cloud-Sync Container wird den Rest übernehmen."
