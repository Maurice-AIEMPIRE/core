#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  BRAIN SYSTEM — Starter
#  Einfach ausführen:  bash brain-system/start.sh
# ════════════════════════════════════════════════════════════

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$DIR/config.env"

# ── Config laden ─────────────────────────────────────────────
if [[ ! -f "$CONFIG" ]]; then
  echo "❌  config.env nicht gefunden: $CONFIG"
  exit 1
fi

# Prüfen ob noch Platzhalter drin sind
if grep -q "HIER_EINTRAGEN" "$CONFIG"; then
  echo ""
  echo "⚠️  Du hast noch nicht alle Pflichtfelder ausgefüllt!"
  echo "   Öffne:  $CONFIG"
  echo "   Trage mindestens TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID"
  echo "   und TELEGRAM_ADMIN_IDS ein, dann nochmal starten."
  echo ""
  grep "HIER_EINTRAGEN" "$CONFIG" | grep -v "^#" | cut -d= -f1 | while read -r key; do
    echo "   → $key"
  done
  echo ""
  exit 1
fi

# Variablen exportieren
set -o allexport
# shellcheck disable=SC1090
source "$CONFIG"
set +o allexport

echo ""
echo "✅  Config geladen"
echo "   Bot-Token: ${TELEGRAM_BOT_TOKEN:0:10}…"
echo "   Chat-ID:   $TELEGRAM_CHAT_ID"
echo "   Admin-IDs: $TELEGRAM_ADMIN_IDS"
echo ""

# ── Telegram Bridge starten ───────────────────────────────────
echo "🚀  Starte Telegram Bridge (Daemon)…"
echo "   Beenden mit Ctrl+C"
echo ""

python3 "$DIR/telegram_bridge.py" --daemon
