#!/bin/bash
# HarveyHeavyLegalbot – Legal AI Assistant
# Konfiguration: lege eine .env Datei in diesem Verzeichnis an (siehe .env.example)
# oder setze TELEGRAM_BOT_TOKEN als Umgebungsvariable vor dem Start.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="/tmp/harvey-bot.log"
PID_FILE="/tmp/harvey-bot.pid"

# Kill existing instance
if [ -f "$PID_FILE" ]; then
  kill "$(cat "$PID_FILE")" 2>/dev/null
  rm -f "$PID_FILE"
fi

# Lade .env wenn vorhanden
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/.env"
  set +a
fi

# Harvey-spezifische Overrides
export BOT_PERSONA="harvey"
export TELEGRAM_TARGET_CHANNEL="${TELEGRAM_TARGET_CHANNEL:-}"

# Sicherheitscheck: Token muss gesetzt sein
if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
  echo "FEHLER: TELEGRAM_BOT_TOKEN ist nicht gesetzt."
  echo "Lege eine .env Datei an mit:"
  echo "  TELEGRAM_BOT_TOKEN=dein_token"
  echo "  OPENAI_API_KEY=gsk_..."
  echo "  AI_API_BASE=https://api.groq.com/openai/v1"
  echo "  AI_MODEL=llama-3.3-70b-versatile"
  exit 1
fi

# Provider anzeigen
if [ -n "$OLLAMA_BASE_URL" ]; then
  PROVIDER="Ollama ($OLLAMA_BASE_URL)"
elif [ -n "$ANTHROPIC_API_KEY" ]; then
  PROVIDER="Anthropic"
elif [ -n "$OPENAI_API_KEY" ]; then
  PROVIDER="OpenAI-compatible (${AI_API_BASE:-openai.com})"
else
  echo "FEHLER: Kein AI-Provider konfiguriert."
  echo "Setze OLLAMA_BASE_URL, ANTHROPIC_API_KEY oder OPENAI_API_KEY in .env"
  exit 1
fi

echo "Starte HarveyHeavyLegalbot..."
echo "Provider : $PROVIDER"
echo "Model    : ${AI_MODEL:-standard}"
echo "Log      : $LOG"
echo ""

cd "$SCRIPT_DIR"
npx tsx src/bot.ts >> "$LOG" 2>&1 &
echo $! > "$PID_FILE"
echo "Harvey Bot gestartet (PID: $(cat $PID_FILE))"
echo "Logs live: tail -f $LOG"
