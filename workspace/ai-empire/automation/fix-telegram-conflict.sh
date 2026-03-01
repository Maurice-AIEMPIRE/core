#!/bin/bash
#
# Fix: Telegram 409 Conflict + dmPolicy
# Loest alle bekannten Telegram-Probleme in einem Schritt.
#
set -euo pipefail

echo "=== Telegram Fix ==="

# 1. telegram_router Prozesse killen
echo "[1] Stoppe telegram_router..."
PIDS=$(pgrep -f telegram_router 2>/dev/null || true)
if [ -n "$PIDS" ]; then
    kill $PIDS 2>/dev/null || true
    sleep 1
    # Falls noch da, SIGKILL
    PIDS=$(pgrep -f telegram_router 2>/dev/null || true)
    if [ -n "$PIDS" ]; then
        kill -9 $PIDS 2>/dev/null || true
    fi
    echo "  Gestoppt"
else
    echo "  Nicht aktiv"
fi

# 2. Plists finden und loeschen (zsh-sicher)
echo "[2] Entferne Telegram-Router Plists..."
find ~/Library/LaunchAgents -name '*telegram*' -not -name '*Telegram.app*' 2>/dev/null | while read -r plist; do
    launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
    rm -f "$plist"
    echo "  Entfernt: $(basename "$plist")"
done

# 3. Auch das Runtime-Verzeichnis aufraumen
RUNTIME_DIR="$HOME/Library/Application Support/ai-empire/launchd-runtime"
if [ -d "$RUNTIME_DIR" ]; then
    echo "[3] Entferne Runtime-Skripte..."
    rm -f "$RUNTIME_DIR/telegram_router.py"
    rm -f "$RUNTIME_DIR/telegram_router_runner.sh"
    echo "  OK"
else
    echo "[3] Kein Runtime-Verzeichnis"
fi

# 4. dmPolicy fixen
echo "[4] Fixe dmPolicy..."
python3 << 'PYEOF'
import json, os
p = os.path.expanduser("~/.openclaw/openclaw.json")
try:
    c = json.load(open(p))
    tg = c.get("channels", {}).get("telegram", {})
    changed = False
    if tg.get("dmPolicy") not in ("pairing", "allowlist", "open", "disabled"):
        tg["dmPolicy"] = "pairing"
        changed = True
    if changed:
        json.dump(c, open(p, "w"), indent=2)
        print("  Gefixt: dmPolicy=pairing")
    else:
        print("  OK (dmPolicy bereits gueltig)")
except Exception as e:
    print(f"  FEHLER: {e}")
PYEOF

# 5. Pruefen
echo "[5] Status..."
REMAINING=$(pgrep -f telegram_router 2>/dev/null || true)
if [ -n "$REMAINING" ]; then
    echo "  WARNUNG: telegram_router laeuft noch: $REMAINING"
else
    echo "  OK: Kein telegram_router aktiv"
fi

echo ""
echo "=== Jetzt ausfuehren: ==="
echo "  openclaw gateway --force"
