#!/bin/bash
set -euo pipefail

echo "========================================="
echo "  UserAI Empire - Installation Script"
echo "========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Bitte als root ausfuehren: sudo bash install.sh${NC}"
    exit 1
fi

# System update
echo -e "${GREEN}[1/7] System aktualisieren...${NC}"
apt-get update && apt-get upgrade -y

# Install Docker
echo -e "${GREEN}[2/7] Docker installieren...${NC}"
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | bash
    systemctl enable docker
    systemctl start docker
else
    echo "Docker bereits installiert."
fi

# Install Docker Compose
echo -e "${GREEN}[3/7] Docker Compose pruefen...${NC}"
if ! docker compose version &> /dev/null; then
    apt-get install -y docker-compose-plugin
fi

# Install rclone
echo -e "${GREEN}[4/7] rclone installieren...${NC}"
if ! command -v rclone &> /dev/null; then
    curl https://rclone.org/install.sh | bash
else
    echo "rclone bereits installiert."
fi

# Create empire directory
echo -e "${GREEN}[5/7] Empire-Verzeichnisse erstellen...${NC}"
mkdir -p /empire/{results,tasks,shared-kb,configs}
mkdir -p /empire/results/{ceo,research,product,marketing,sales,finance,legal,hr,customer,meta,x-analysis,bulk-queue}

# Copy empire files
echo -e "${GREEN}[6/7] Empire-Dateien kopieren...${NC}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMPIRE_DIR="$(dirname "$SCRIPT_DIR")"
cp -r "$EMPIRE_DIR"/* /empire/ 2>/dev/null || true

# Setup .env
echo -e "${GREEN}[7/7] Konfiguration...${NC}"
if [ ! -f /empire/.env ]; then
    cp /empire/.env.example /empire/.env
    echo -e "${YELLOW}WICHTIG: Bearbeite /empire/.env mit deinen API Keys!${NC}"
    echo -e "${YELLOW}  nano /empire/.env${NC}"
fi

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  Installation abgeschlossen!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "Naechste Schritte:"
echo ""
echo "1. API Keys eintragen:"
echo "   nano /empire/.env"
echo ""
echo "2. rclone konfigurieren (optional):"
echo "   rclone config"
echo "   -> iCloud: 'icloud' remote erstellen"
echo "   -> Dropbox: 'dropbox' remote erstellen"
echo ""
echo "3. Empire starten:"
echo "   cd /empire && docker compose up -d --build"
echo ""
echo "4. Logs pruefen:"
echo "   docker compose logs -f telegram-bot"
echo ""
echo "5. Portainer (Container-Management):"
echo "   https://DEINE-IP:9443"
echo ""
echo "6. Telegram Bot testen:"
echo "   -> Oeffne deinen Bot in Telegram"
echo "   -> Sende /start"
echo ""
