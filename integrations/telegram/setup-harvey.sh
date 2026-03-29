#!/bin/bash
# setup-harvey.sh — Sicheres Setup für HarveyHeavyLegalbot
# Stört KEINE laufenden Prozesse. Startet Harvey nur wenn noch nicht aktiv.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
PID_FILE="/tmp/harvey-bot.pid"
LOG_FILE="/tmp/harvey-bot.log"

echo "=== HarveyHeavyLegalbot Setup ==="
echo ""

# ── Schritt 1: .env prüfen / reparieren ─────────────────────────────────────
write_env_template() {
  cat > "$ENV_FILE" << 'EOF'
TELEGRAM_BOT_TOKEN=DEIN_TELEGRAM_BOT_TOKEN
OPENAI_API_KEY=DEIN_GROQ_API_KEY
AI_API_BASE=https://api.groq.com/openai/v1
AI_MODEL=llama-3.3-70b-versatile
BOT_PERSONA=harvey
EOF
  echo "      ✗ Bitte trage deine Credentials in $ENV_FILE ein und starte erneut."
  exit 1
}

fix_angle_brackets() {
  # Entfernt < und > um URLs (bekanntes Copy-Paste-Problem)
  sed -i '' 's|=<\(https\?://[^>]*\)>|=\1|g' "$ENV_FILE"
  sed -i '' 's|=<\(https\?://[^>]*\)$|=\1|g' "$ENV_FILE"
}

if [ ! -f "$ENV_FILE" ]; then
  echo "[1/3] .env nicht gefunden — Template wird erstellt..."
  write_env_template
else
  # Prüfe ob angle-brackets in der Datei sind (bekanntes Problem)
  if grep -q '<http' "$ENV_FILE"; then
    echo "[1/3] .env enthält ungültige Zeichen (<>) — wird automatisch repariert..."
    fix_angle_brackets
    echo "      ✓ .env repariert"
  else
    echo "[1/3] .env OK ✓"
  fi
fi

# ── Schritt 2: Prüfe ob Harvey bereits läuft ────────────────────────────────
harvey_running=false
if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE")
  if kill -0 "$PID" 2>/dev/null; then
    harvey_running=true
    echo "[2/3] Harvey läuft bereits (PID: $PID) ✓"
    echo "      Kein Neustart nötig — laufende Prozesse werden nicht gestört."
  else
    echo "[2/3] Alte PID-Datei gefunden (Prozess tot) — wird aufgeräumt..."
    rm -f "$PID_FILE"
  fi
else
  echo "[2/3] Harvey läuft nicht — wird gestartet..."
fi

# ── Schritt 3: Harvey starten (nur wenn nicht schon aktiv) ──────────────────
if [ "$harvey_running" = false ]; then
  cd "$SCRIPT_DIR" || exit 1

  # .env laden
  set -a
  # shellcheck disable=SC1091
  source "$ENV_FILE"
  set +a

  export BOT_PERSONA="harvey"

  # Provider-Info anzeigen
  if [ -n "$OPENAI_API_KEY" ] && [ -n "$AI_API_BASE" ]; then
    PROVIDER="Groq / $AI_MODEL"
  elif [ -n "$OLLAMA_BASE_URL" ]; then
    PROVIDER="Ollama ($OLLAMA_BASE_URL)"
  elif [ -n "$ANTHROPIC_API_KEY" ]; then
    PROVIDER="Anthropic"
  else
    echo "      ✗ FEHLER: Kein AI-Provider in .env konfiguriert"
    exit 1
  fi

  npx tsx src/bot.ts >> "$LOG_FILE" 2>&1 &
  BOT_PID=$!
  echo $BOT_PID > "$PID_FILE"

  sleep 2
  if kill -0 "$BOT_PID" 2>/dev/null; then
    echo "[3/3] Harvey gestartet ✓"
    echo "      PID     : $BOT_PID"
    echo "      Provider: $PROVIDER"
    echo "      Logs    : tail -f $LOG_FILE"
  else
    echo "[3/3] ✗ Harvey-Start fehlgeschlagen — prüfe Logs:"
    tail -20 "$LOG_FILE"
    exit 1
  fi
else
  echo "[3/3] Übersprungen (läuft bereits) ✓"
fi

echo ""
echo "=== Setup abgeschlossen ==="
