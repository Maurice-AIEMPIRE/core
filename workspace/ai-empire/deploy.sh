#!/bin/bash
#
# AI Empire — Deploy Script
# Erstellt die gesamte Workspace-Struktur unter ~/.openclaw/workspace/ai-empire/
# und konfiguriert OpenClaw + launchd Scheduler.
#
# Nutzung:  bash deploy.sh
#
set -euo pipefail

DEST="$HOME/.openclaw/workspace/ai-empire"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== AI Empire Deploy ($TIMESTAMP) ==="
echo "Ziel: $DEST"
echo ""

# ──────────────────────────────────────────────
# 1. Verzeichnisstruktur
# ──────────────────────────────────────────────
echo "[1/6] Erstelle Verzeichnisse..."
mkdir -p "$DEST/00_SYSTEM"
mkdir -p "$DEST/automation"
mkdir -p "$DEST/shared-context"
mkdir -p "$DEST/memory"
echo "  OK"

# ──────────────────────────────────────────────
# 2. Dateien kopieren (aus dem geklonten Repo)
# ──────────────────────────────────────────────
echo "[2/6] Kopiere Dateien..."

copy_if_exists() {
    local src="$1"
    local dst="$2"
    if [ -f "$src" ]; then
        cp "$src" "$dst"
        echo "  -> $(basename "$dst")"
    fi
}

# Aus dem Repo-Verzeichnis (wo dieses Script liegt) kopieren
copy_if_exists "$SCRIPT_DIR/00_SYSTEM/DIAG_OPENCLAW_2026-03-01.md" "$DEST/00_SYSTEM/DIAG_OPENCLAW_2026-03-01.md"
copy_if_exists "$SCRIPT_DIR/00_SYSTEM/OPENCLAW_RESTART_SOP.md"     "$DEST/00_SYSTEM/OPENCLAW_RESTART_SOP.md"
copy_if_exists "$SCRIPT_DIR/00_SYSTEM/PERFORMANCE_PROFILE.md"      "$DEST/00_SYSTEM/PERFORMANCE_PROFILE.md"
copy_if_exists "$SCRIPT_DIR/00_SYSTEM/CONTEXT_TEST_PROMPTS.md"     "$DEST/00_SYSTEM/CONTEXT_TEST_PROMPTS.md"
copy_if_exists "$SCRIPT_DIR/automation/context_sync.py"            "$DEST/automation/context_sync.py"
copy_if_exists "$SCRIPT_DIR/AGENT_CONFIG.md"                       "$DEST/AGENT_CONFIG.md"
copy_if_exists "$SCRIPT_DIR/USER.md"                               "$DEST/USER.md"

echo "  OK"

# ──────────────────────────────────────────────
# 3. OpenClaw Config: Backup + Update
# ──────────────────────────────────────────────
OC_CFG="$HOME/.openclaw/openclaw.json"

if [ -f "$OC_CFG" ]; then
    echo "[3/6] OpenClaw Config..."
    cp "$OC_CFG" "${OC_CFG}.bak.${TIMESTAMP}"
    echo "  Backup: ${OC_CFG}.bak.${TIMESTAMP}"

    python3 << 'PYEOF'
import json, os, sys

cfg_path = os.path.expanduser("~/.openclaw/openclaw.json")
try:
    with open(cfg_path, "r") as f:
        cfg = json.load(f)
except Exception as e:
    print(f"  WARN: Konnte Config nicht lesen: {e}", file=sys.stderr)
    sys.exit(0)

# Restart aktivieren
cfg.setdefault("commands", {})["restart"] = True

# Schnelles Default-Modell
cfg.setdefault("models", {})["default"] = "ollama/qwen3:8b"
cfg["models"]["thinking"] = "minimal"
cfg["models"]["max_tokens"] = 2048

with open(cfg_path, "w") as f:
    json.dump(cfg, f, indent=2)

print("  restart=true, model=ollama/qwen3:8b, thinking=minimal")
PYEOF
    echo "  OK"
else
    echo "[3/6] OpenClaw Config nicht gefunden ($OC_CFG) — übersprungen."
fi

# ──────────────────────────────────────────────
# 4. launchd Scheduler (Context Sync stündlich)
# ──────────────────────────────────────────────
PLIST_NAME="ai.empire.contextsync.hourly"
PLIST_DST="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"

echo "[4/6] launchd Scheduler..."

# Python-Pfad ermitteln
PYTHON_PATH=$(which python3 2>/dev/null || echo "/usr/bin/python3")

cat > "$PLIST_DST" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_NAME}</string>

    <key>ProgramArguments</key>
    <array>
        <string>${PYTHON_PATH}</string>
        <string>${DEST}/automation/context_sync.py</string>
        <string>--base-dir</string>
        <string>${DEST}</string>
    </array>

    <key>StartInterval</key>
    <integer>3600</integer>

    <key>RunAtLoad</key>
    <true/>

    <key>StandardOutPath</key>
    <string>${DEST}/automation/context_sync.log</string>

    <key>StandardErrorPath</key>
    <string>${DEST}/automation/context_sync_error.log</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
PLISTEOF

echo "  Plist: $PLIST_DST"

# Vorhandenen Agent entladen (Fehler ignorieren)
launchctl bootout "gui/$(id -u)/${PLIST_NAME}" 2>/dev/null || true

# Neu laden
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST" 2>/dev/null || \
    launchctl load "$PLIST_DST" 2>/dev/null || \
    echo "  WARN: launchctl load fehlgeschlagen — manuell mit 'launchctl load $PLIST_DST' laden"

echo "  OK"

# ──────────────────────────────────────────────
# 5. Initialer Context Sync
# ──────────────────────────────────────────────
echo "[5/6] Initialer Context Sync..."
python3 "$DEST/automation/context_sync.py" --base-dir "$DEST" 2>/dev/null || echo "  WARN: Erster Sync erzeugt leeren Snapshot (normal bei Erstinstallation)"
echo "  OK"

# ──────────────────────────────────────────────
# 6. Verifizierung
# ──────────────────────────────────────────────
echo "[6/6] Verifizierung..."
echo ""

echo "  Dateien:"
for f in \
    "$DEST/USER.md" \
    "$DEST/AGENT_CONFIG.md" \
    "$DEST/00_SYSTEM/OPENCLAW_RESTART_SOP.md" \
    "$DEST/00_SYSTEM/PERFORMANCE_PROFILE.md" \
    "$DEST/automation/context_sync.py" \
    "$DEST/shared-context/CONTEXT_SNAPSHOT.md" \
; do
    if [ -f "$f" ]; then
        echo "    ✓ $(echo "$f" | sed "s|$DEST/||")"
    else
        echo "    ✗ $(echo "$f" | sed "s|$DEST/||") — FEHLT"
    fi
done

echo ""
echo "  launchd:"
if launchctl list 2>/dev/null | grep -q "$PLIST_NAME"; then
    echo "    ✓ $PLIST_NAME geladen"
else
    echo "    ✗ $PLIST_NAME nicht geladen"
fi

echo ""
echo "  OpenClaw Config:"
if [ -f "$OC_CFG" ]; then
    python3 -c "
import json
c = json.load(open('$OC_CFG'))
print(f\"    restart: {c.get('commands',{}).get('restart','NOT SET')}\")
print(f\"    model:   {c.get('models',{}).get('default','NOT SET')}\")
print(f\"    thinking:{c.get('models',{}).get('thinking','NOT SET')}\")
" 2>/dev/null || echo "    WARN: Konnte Config nicht lesen"
else
    echo "    Nicht gefunden"
fi

echo ""
echo "=== Deploy abgeschlossen ==="
echo ""
echo "Nächste Schritte:"
echo "  1. openclaw doctor --fix"
echo "  2. openclaw restart"
echo "  3. Test: python3 $DEST/automation/context_sync.py --dry-run"
