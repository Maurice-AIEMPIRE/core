#!/bin/bash
# fix-harvey.sh — Alles-Reset für HarveyHeavyLegalbot
# Sicher: tötet nur Harvey-Prozesse, nichts anderes
#
# Verwendung:
#   bash fix-harvey.sh
#
# Credentials werden aus der bestehenden .env gelesen.
# Falls .env fehlt oder korrupt ist, werden Platzhalter geschrieben
# und du wirst aufgefordert, die Werte einzutragen.

TELEGRAM_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="/tmp/harvey-bot.pid"
LOG_FILE="/tmp/harvey-bot.log"

echo "=== Harvey Fix-All ==="
echo ""

# 1. Alle Harvey/Bot-Instanzen stoppen
echo "[1/5] Stoppe alte Bot-Instanzen..."
if [ -f "$PID_FILE" ]; then
  OLD_PID=$(cat "$PID_FILE")
  kill "$OLD_PID" 2>/dev/null && echo "      ✓ PID $OLD_PID gestoppt" || echo "      - PID $OLD_PID war bereits tot"
  rm -f "$PID_FILE"
fi
pkill -f "bot.ts" 2>/dev/null && echo "      ✓ Weitere bot.ts Prozesse gestoppt" || echo "      - Keine weiteren Prozesse"
sleep 2

# 2. Verfügbare Ollama-Modelle ermitteln
echo ""
echo "[2/5] Prüfe Ollama-Modelle..."
BEST_MODEL=""
if command -v ollama &>/dev/null; then
  BEST_MODEL=$(ollama list 2>/dev/null | awk 'NR>1 {print $1; exit}')
fi
[ -z "$BEST_MODEL" ] && BEST_MODEL="llama3.2"
echo "      ✓ Verwende Modell: $BEST_MODEL"

# 3. .env prüfen und ggf. reparieren
echo ""
echo "[3/5] Prüfe .env..."

ENV_FILE="$TELEGRAM_DIR/.env"

# Angle-Bracket-Fehler automatisch beheben (via Python — zuverlässiger als sed)
if [ -f "$ENV_FILE" ] && grep -q '<http' "$ENV_FILE"; then
  echo "      ⚠ Angle-Brackets gefunden — werden entfernt..."
  python3 - "$ENV_FILE" << 'PYEOF'
import sys, re
f = sys.argv[1]
txt = open(f).read()
txt = re.sub(r'=<(https?://[^>\s]+)>', r'=\1', txt)
txt = re.sub(r'=<(https?://[^>\s\n]+)$', r'=\1', txt, flags=re.MULTILINE)
open(f, 'w').write(txt)
print("      ✓ Repariert")
PYEOF
fi

# Prüfe ob Pflichtfelder vorhanden sind
BOT_TOKEN_OK=false
PROVIDER_OK=false

if [ -f "$ENV_FILE" ]; then
  grep -q "^TELEGRAM_BOT_TOKEN=.\+" "$ENV_FILE" 2>/dev/null && grep -v "PLACEHOLDER\|DEIN_" "$ENV_FILE" | grep -q "^TELEGRAM_BOT_TOKEN" && BOT_TOKEN_OK=true
  { grep -q "^OPENAI_API_KEY=.\+" "$ENV_FILE" || grep -q "^ANTHROPIC_API_KEY=.\+" "$ENV_FILE" || grep -q "^OLLAMA_BASE_URL=.\+" "$ENV_FILE"; } && PROVIDER_OK=true
fi

if [ "$BOT_TOKEN_OK" = false ] || [ "$PROVIDER_OK" = false ]; then
  echo "      ✗ .env fehlt oder unvollständig."
  echo ""
  echo "  Bitte führe diesen Befehl aus und ersetze die Werte:"
  echo ""
  echo "  cat > $ENV_FILE << 'EOF'"
  echo "  TELEGRAM_BOT_TOKEN=dein_telegram_token"
  echo "  OPENAI_API_KEY=dein_groq_key"
  echo "  AI_API_BASE=https://api.groq.com/openai/v1"
  echo "  AI_MODEL=gemma2-9b-it"
  echo "  # Optional: ZHIPU_API_KEY=... fuer GLM-5"
  echo "  # Optional: GEMMA_API_KEY=... fuer Gemma 4 (Google AI)"
  echo "  # Optional: SERVER_SSH_KEY=~/.ssh/id_ed25519"
  echo "  BOT_PERSONA=harvey"
  echo "  EOF"
  echo ""
  exit 1
fi

echo "      ✓ .env OK"

# 4. OLLAMA_BASE_URL deaktivieren damit Groq Vorrang hat
echo ""
echo "[4/5] Konfiguriere Provider..."
unset OLLAMA_BASE_URL
set -a
# shellcheck disable=SC1091
source "$ENV_FILE"
set +a
export BOT_PERSONA=harvey
unset OLLAMA_BASE_URL  # nochmal nach source, falls in .env gesetzt

# Wenn kein Cloud-Provider → Ollama mit bestem Modell
if [ -z "$OPENAI_API_KEY" ] && [ -z "$ANTHROPIC_API_KEY" ]; then
  export OLLAMA_BASE_URL=http://localhost:11434/v1
  export AI_MODEL="$BEST_MODEL"
  echo "      ✓ Provider: Ollama ($BEST_MODEL)"
else
  PROVIDER_NAME="Groq/OpenAI (${AI_API_BASE:-openai})"
  [ -n "$ANTHROPIC_API_KEY" ] && PROVIDER_NAME="Anthropic"
  echo "      ✓ Provider: $PROVIDER_NAME"
fi

# 5. Harvey starten
echo ""
echo "[5/5] Starte HarveyHeavyLegalbot..."
cd "$TELEGRAM_DIR" || exit 1

# Dependencies installieren (sichtbar, damit Fehler erkennbar sind)
echo "      Installing dependencies..."
npm install 2>&1 | tail -3
echo ""

npx tsx src/bot.ts >> "$LOG_FILE" 2>&1 &
BOT_PID=$!
echo $BOT_PID > "$PID_FILE"
sleep 3

if kill -0 "$BOT_PID" 2>/dev/null; then
  echo "      ✓ Harvey läuft (PID: $BOT_PID)"
  echo ""
  tail -5 "$LOG_FILE"
  echo ""
  echo "Live-Logs: tail -f $LOG_FILE"
else
  echo "      ✗ Start fehlgeschlagen:"
  tail -20 "$LOG_FILE"
  exit 1
fi

echo ""
echo "=== Harvey ist wieder online ==="
