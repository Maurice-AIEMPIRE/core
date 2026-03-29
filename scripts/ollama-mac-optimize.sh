#!/bin/bash
# ollama-mac-optimize.sh — Ollama CPU/RAM-Limits für Mac optimieren
# Stört KEINE laufenden Prozesse. Wirkt beim nächsten Ollama-Start.

echo "=== Ollama Mac Optimizer ==="
echo ""

# ── Aktuelle Last anzeigen ───────────────────────────────────────────────────
echo "[1/4] Aktuelle CPU-Last (Top 5 Prozesse):"
ps -Ao pid,pcpu,pmem,comm | sort -k2 -rn | head -6 | awk '{printf "  PID %-6s CPU %-5s MEM %-5s %s\n", $1, $2"%", $3"%", $4}'
echo ""

# ── RAM erkennen ─────────────────────────────────────────────────────────────
TOTAL_RAM_GB=$(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%d", $1/1024/1024/1024}')
echo "[2/4] Erkannter RAM: ${TOTAL_RAM_GB} GB"

# Empfohlene Werte je nach RAM
if [ "$TOTAL_RAM_GB" -ge 32 ]; then
  PARALLEL=4
  MAX_MODELS=3
  CTX_SIZE=8192
elif [ "$TOTAL_RAM_GB" -ge 16 ]; then
  PARALLEL=2
  MAX_MODELS=2
  CTX_SIZE=4096
else
  PARALLEL=1
  MAX_MODELS=1
  CTX_SIZE=2048
fi

echo "      Empfehlung: PARALLEL=$PARALLEL, MAX_MODELS=$MAX_MODELS, CTX=$CTX_SIZE"
echo ""

# ── Ollama-Umgebungsvariablen via launchctl setzen ───────────────────────────
echo "[3/4] Setze Ollama-Limits (wirkt beim nächsten Ollama-Start)..."

launchctl setenv OLLAMA_NUM_PARALLEL "$PARALLEL"
launchctl setenv OLLAMA_MAX_LOADED_MODELS "$MAX_MODELS"
launchctl setenv OLLAMA_NUM_CTX "$CTX_SIZE"

# Zusätzlich in ~/.zshrc / ~/.bashrc persistieren
SHELL_RC="$HOME/.zshrc"
[ ! -f "$SHELL_RC" ] && SHELL_RC="$HOME/.bashrc"

# Entferne alte Ollama-Einträge und füge neue ein
if [ -f "$SHELL_RC" ]; then
  sed -i '' '/OLLAMA_NUM_PARALLEL/d' "$SHELL_RC"
  sed -i '' '/OLLAMA_MAX_LOADED_MODELS/d' "$SHELL_RC"
  sed -i '' '/OLLAMA_NUM_CTX/d' "$SHELL_RC"
fi

cat >> "$SHELL_RC" << EOF

# Ollama Mac Performance (gesetzt von ollama-mac-optimize.sh)
export OLLAMA_NUM_PARALLEL=$PARALLEL
export OLLAMA_MAX_LOADED_MODELS=$MAX_MODELS
export OLLAMA_NUM_CTX=$CTX_SIZE
EOF

echo "      ✓ launchctl gesetzt"
echo "      ✓ $SHELL_RC aktualisiert"
echo ""

# ── Zusammenfassung ──────────────────────────────────────────────────────────
echo "[4/4] Optimierung abgeschlossen:"
echo "      OLLAMA_NUM_PARALLEL     = $PARALLEL  (war: 15)"
echo "      OLLAMA_MAX_LOADED_MODELS = $MAX_MODELS  (war: 5)"
echo "      OLLAMA_NUM_CTX          = $CTX_SIZE"
echo ""
echo "  Hinweis: Ollama einmal neu starten damit die Limits greifen:"
echo "  pkill ollama && sleep 2 && ollama serve &"
echo ""
echo "=== Fertig — laufende Prozesse wurden nicht gestört ==="
