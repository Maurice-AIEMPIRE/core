#!/bin/bash
# HarveyHeavyLegalbot – Legal AI Assistant
# Usage: ./run-harvey.sh
# Set TELEGRAM_BOT_TOKEN to your Harvey bot token before running,
# or paste it directly below.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="/tmp/harvey-bot.log"
PID_FILE="/tmp/harvey-bot.pid"

# Kill existing instance
if [ -f "$PID_FILE" ]; then
  kill "$(cat "$PID_FILE")" 2>/dev/null
  rm -f "$PID_FILE"
fi

# ── CONFIGURATION ──────────────────────────────────────────────
# Paste your @HarveyHeavyLegalbot token from BotFather here:
export TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-DEIN_HARVEY_BOT_TOKEN_HIER}"

# Ollama must be running locally: `ollama serve`
export OLLAMA_BASE_URL="http://localhost:11434/v1"

# Best model for legal reasoning — change if you have a different one
export AI_MODEL="${AI_MODEL:-glm4:9b-chat}"

# Harvey persona — overrides the default M0Claw system prompt
export BOT_PERSONA="harvey"

export TELEGRAM_TARGET_CHANNEL=""
# ───────────────────────────────────────────────────────────────

if [ "$TELEGRAM_BOT_TOKEN" = "DEIN_HARVEY_BOT_TOKEN_HIER" ]; then
  echo "FEHLER: Bitte setze TELEGRAM_BOT_TOKEN in run-harvey.sh oder als Umgebungsvariable."
  echo "  export TELEGRAM_BOT_TOKEN='1234567:ABC...'"
  echo "  ./run-harvey.sh"
  exit 1
fi

echo "Starte HarveyHeavyLegalbot..."
echo "Model : $AI_MODEL"
echo "Ollama: $OLLAMA_BASE_URL"
echo "Log   : $LOG"
echo ""

cd "$SCRIPT_DIR"
npx tsx src/bot.ts >> "$LOG" 2>&1 &
echo $! > "$PID_FILE"
echo "Harvey Bot gestartet (PID: $(cat $PID_FILE))"
echo "Logs live: tail -f $LOG"
