#!/bin/bash
###############################################################################
#
#  🛡 MAC GUARDIAN AI - Self-Healing Performance System
#
#  COPY & PASTE THIS ENTIRE SCRIPT INTO YOUR TERMINAL:
#
#    bash <(curl -sL https://raw.githubusercontent.com/Maurice-AIEMPIRE/core/claude/fix-pc-performance-epsd4/scripts/mac-performance/mac-guardian-quickstart.sh)
#
#  What it does:
#  - Installs 8 AI-powered monitoring modules
#  - Prevents freezing, overheating, memory leaks, full disk
#  - Auto-heals your Mac 24/7 in the background
#  - Learns from your usage patterns
#  - Zero config needed - just run and forget
#
#  Made by @Maurice_AIEMPIRE with Claude Code
#
###############################################################################

set -euo pipefail

echo ""
echo "  🛡 MAC GUARDIAN AI - Quick Setup"
echo "  ═══════════════════════════════════"
echo ""

INSTALL_DIR="$HOME/.mac-guardian-setup"

# Cleanup alter Installationsversuch
rm -rf "$INSTALL_DIR" 2>/dev/null || true

echo "  [1/3] Downloading Mac Guardian..."
if command -v git &>/dev/null; then
    git clone --depth 1 -b claude/fix-pc-performance-epsd4 \
        https://github.com/Maurice-AIEMPIRE/core.git "$INSTALL_DIR" 2>/dev/null
else
    echo "  Git nicht gefunden. Bitte installiere Git: xcode-select --install"
    exit 1
fi

echo "  [2/3] Installing..."
cd "$INSTALL_DIR/scripts/mac-performance"
chmod +x *.sh modules/*.sh

echo "  [3/3] Running installer..."
./guardian-install.sh

# Cleanup
rm -rf "$INSTALL_DIR" 2>/dev/null || true

echo ""
echo "  Done! Run 'guardian status' to check."
echo ""
