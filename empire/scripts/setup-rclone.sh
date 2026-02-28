#!/bin/bash
set -euo pipefail

echo "========================================="
echo "  rclone Setup - iCloud + Dropbox"
echo "========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Dropbox einrichten ===${NC}"
echo "1. Gehe zu: https://www.dropbox.com/developers/apps"
echo "2. Erstelle eine neue App (Full Dropbox access)"
echo "3. Kopiere App Key + App Secret"
echo ""
read -p "Bereit? (j/n): " ready
if [ "$ready" = "j" ]; then
    rclone config create dropbox dropbox
fi

echo ""
echo -e "${GREEN}=== iCloud einrichten ===${NC}"
echo "iCloud ueber rclone braucht einen WebDAV-Zugang."
echo "Option 1: Verwende 'rclone config' mit WebDAV + iCloud credentials"
echo "Option 2: Nutze einen iCloud-kompatiblen Proxy"
echo ""
echo "Fuer iCloud WebDAV:"
echo "  rclone config create icloud webdav \\"
echo "    --webdav-url https://caldav.icloud.com \\"
echo "    --webdav-vendor other \\"
echo "    --webdav-user DEINE_APPLE_ID \\"
echo "    --webdav-pass DEIN_APP_SPEZIFISCHES_PASSWORT"
echo ""
echo -e "${YELLOW}Tipp: Erstelle ein App-spezifisches Passwort unter:${NC}"
echo -e "${YELLOW}  https://appleid.apple.com/account/manage${NC}"
echo ""

# Test
echo -e "${GREEN}=== Remotes testen ===${NC}"
echo "Konfigurierte Remotes:"
rclone listremotes 2>/dev/null || echo "Keine Remotes konfiguriert."

echo ""
echo "Setup abgeschlossen. Teste mit:"
echo "  rclone ls dropbox:  # Dropbox Inhalt"
echo "  rclone ls icloud:   # iCloud Inhalt"
