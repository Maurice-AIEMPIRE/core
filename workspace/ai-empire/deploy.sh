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
# 0. Konkurrierende Dienste pruefen
# ──────────────────────────────────────────────
echo "[0] Dienst-Konflikte..."
CONFLICTS=""
if command -v launchctl &>/dev/null; then
    for svc in $(launchctl list 2>/dev/null | grep -i 'telegram' | awk '{print $3}'); do
        CONFLICTS="$CONFLICTS $svc"
    done
fi

if [ -n "$CONFLICTS" ]; then
    echo "  WARNUNG: Telegram-Dienste aktiv:"
    for svc in $CONFLICTS; do
        echo "    - $svc"
    done
    echo ""
    echo "  Diese verursachen 409-Conflict mit OpenClaw."
    echo "  Stoppe nach dem Deploy mit:"
    for svc in $CONFLICTS; do
        echo "    launchctl bootout gui/\$(id -u)/$svc"
    done
else
    echo "  OK (keine Konflikte)"
fi
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
copy_if_exists "$SCRIPT_DIR/automation/telegram-setup.sh"          "$DEST/automation/telegram-setup.sh"
[ -f "$DEST/automation/telegram-setup.sh" ] && chmod +x "$DEST/automation/telegram-setup.sh"
copy_if_exists "$SCRIPT_DIR/00_SYSTEM/TELEGRAM_CONTROL_SOP.md"     "$DEST/00_SYSTEM/TELEGRAM_CONTROL_SOP.md"
copy_if_exists "$SCRIPT_DIR/00_SYSTEM/TERMINUS_QUICKREF.md"        "$DEST/00_SYSTEM/TERMINUS_QUICKREF.md"
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
import json, os, sys, re

cfg_path = os.path.expanduser("~/.openclaw/openclaw.json")

# Try to load JSON; if broken, attempt basic repair
try:
    with open(cfg_path, "r") as f:
        raw = f.read()
    try:
        cfg = json.loads(raw)
    except json.JSONDecodeError:
        # Common fix: missing comma/brace in plugins block
        # Try adding missing commas before closing braces
        fixed = re.sub(r'(true|false|null|"[^"]*"|\d+)\s*\n(\s*")', r'\1,\n\2', raw)
        try:
            cfg = json.loads(fixed)
            print("  REPAIRED: Fixed JSON syntax (missing commas)")
        except json.JSONDecodeError as e2:
            print(f"  WARN: Config JSON kaputt und nicht reparierbar: {e2}", file=sys.stderr)
            print("  Fuehre 'openclaw doctor --fix' aus um die Config zu reparieren.", file=sys.stderr)
            sys.exit(0)
except Exception as e:
    print(f"  WARN: Konnte Config nicht lesen: {e}", file=sys.stderr)
    sys.exit(0)

changed = []

# Remove invalid top-level model keys (from older deploy versions)
models = cfg.get("models", {})
for bad_key in ("default", "thinking", "max_tokens"):
    if bad_key in models:
        del models[bad_key]
        changed.append(f"removed models.{bad_key}")

# Set default model via agents.defaults.model.primary
agents = cfg.setdefault("agents", {})
defaults = agents.setdefault("defaults", {})
model = defaults.setdefault("model", {})
if model.get("primary") != "ollama/qwen3:8b":
    model["primary"] = "ollama/qwen3:8b"
    changed.append("agents.defaults.model.primary=ollama/qwen3:8b")

if "fallbacks" not in model:
    model["fallbacks"] = ["ollama/qwen3:4b"]
    changed.append("agents.defaults.model.fallbacks=[qwen3:4b]")

# Enable restart command
commands = cfg.setdefault("commands", {})
if commands.get("restart") is not True:
    commands["restart"] = True
    changed.append("commands.restart=true")

# Fix plugins.entries structure
plugins = cfg.get("plugins", {})
entries = plugins.get("entries", {})
for name in ("whatsapp", "telegram"):
    if name in entries and not isinstance(entries[name], dict):
        entries[name] = {"enabled": True}
        changed.append(f"fixed plugins.entries.{name}")

# Always write (json.dump produces valid JSON even if input was broken)
with open(cfg_path, "w") as f:
    json.dump(cfg, f, indent=2)

if changed:
    print("  " + ", ".join(changed))
else:
    print("  Config already correct — no changes needed")
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
    "$DEST/automation/telegram-setup.sh" \
    "$DEST/00_SYSTEM/TELEGRAM_CONTROL_SOP.md" \
    "$DEST/00_SYSTEM/TERMINUS_QUICKREF.md" \
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
model = c.get('agents',{}).get('defaults',{}).get('model',{})
print(f\"    primary model: {model.get('primary','NOT SET')}\")
print(f\"    fallbacks:     {model.get('fallbacks','NOT SET')}\")
print(f\"    restart:       {c.get('commands',{}).get('restart','NOT SET')}\")
" 2>/dev/null || echo "    WARN: Konnte Config nicht lesen"
else
    echo "    Nicht gefunden"
fi

echo ""
echo "=== Deploy abgeschlossen ==="
echo ""
echo "Nächste Schritte:"
echo "  1. openclaw doctor --fix"
echo "  2. openclaw gateway --force    (startet Gateway neu)"
echo "  3. Test: python3 $DEST/automation/context_sync.py --dry-run"
