#!/bin/bash
# ================================================================
# iCloud Writer — Quick SSH Bridge
# Schreibt eine Markdown-Datei direkt in iCloud Drive auf dem Mac
#
# Usage:
#   ./icloud-writer.sh "Dokumenttitel" "Inhalt" [Ordner]
#   ./icloud-writer.sh --test
#
# Env:
#   MAC_SSH_HOST, MAC_SSH_USER, MAC_SSH_PORT, MAC_SSH_KEY
#   MAC_ICLOUD_PATH
# ================================================================

MAC_SSH_HOST="${MAC_SSH_HOST:-}"
MAC_SSH_USER="${MAC_SSH_USER:-maurice}"
MAC_SSH_PORT="${MAC_SSH_PORT:-22}"
MAC_SSH_KEY="${MAC_SSH_KEY:-/root/.ssh/mac_id_ed25519}"
MAC_ICLOUD_BASE="${MAC_ICLOUD_PATH:-/Users/maurice/Library/Mobile Documents/com~apple~CloudDocs}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "$MAC_SSH_HOST" ]; then
    echo -e "${RED}Error: MAC_SSH_HOST not set${NC}"
    exit 1
fi

# --- Test mode ---
if [ "$1" = "--test" ]; then
    echo -e "${YELLOW}Testing SSH connection to Mac...${NC}"
    ssh -i "$MAC_SSH_KEY" -p "$MAC_SSH_PORT" -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 "${MAC_SSH_USER}@${MAC_SSH_HOST}" \
        'echo "SSH OK: $(hostname)" && ls "$HOME/Library/Mobile Documents/" | head -5'
    STATUS=$?
    [ $STATUS -eq 0 ] && echo -e "${GREEN}Connection OK${NC}" || echo -e "${RED}Connection FAILED${NC}"
    exit $STATUS
fi

# --- Write document ---
TITLE="${1:-Untitled}"
CONTENT="${2:-}"
FOLDER="${3:-GalaxiaBrain}"

if [ -z "$CONTENT" ]; then
    echo -e "${RED}Error: No content provided${NC}"
    echo "Usage: $0 \"Title\" \"Content\" [Folder]"
    exit 1
fi

DATE=$(date +%Y-%m-%d)
SAFE_TITLE=$(echo "$TITLE" | tr -cd '[:alnum:][:space:]-_' | tr ' ' '-' | cut -c1-80)
FILENAME="${DATE}-${SAFE_TITLE}.md"
REMOTE_PATH="${MAC_ICLOUD_BASE}/${FOLDER}/${FILENAME}"

# Create directory and write file via SSH
ssh -i "$MAC_SSH_KEY" -p "$MAC_SSH_PORT" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 \
    "${MAC_SSH_USER}@${MAC_SSH_HOST}" \
    "mkdir -p \"${MAC_ICLOUD_BASE}/${FOLDER}\" && cat > \"${REMOTE_PATH}\"" << CONTENT_EOF
# ${TITLE}

_Generated: $(date '+%d.%m.%Y %H:%M') by Galaxia Brain_

${CONTENT}
CONTENT_EOF

STATUS=$?
if [ $STATUS -eq 0 ]; then
    echo -e "${GREEN}✓ Written to iCloud: ${FOLDER}/${FILENAME}${NC}"
else
    echo -e "${RED}✗ Failed to write to iCloud${NC}"
    exit $STATUS
fi
