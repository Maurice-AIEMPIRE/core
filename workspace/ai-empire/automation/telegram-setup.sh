#!/bin/bash
#
# Telegram Bot Setup fuer OpenClaw
# Setzt den Bot-Token sicher in die OpenClaw Config.
#
# Nutzung:  bash telegram-setup.sh
#
set -euo pipefail

OC_CFG="$HOME/.openclaw/openclaw.json"

echo "=== Telegram Bot Setup fuer OpenClaw ==="
echo ""

if [ ! -f "$OC_CFG" ]; then
    echo "FEHLER: OpenClaw Config nicht gefunden: $OC_CFG"
    echo "Fuehre zuerst 'openclaw setup' aus."
    exit 1
fi

# Backup
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
cp "$OC_CFG" "${OC_CFG}.bak.${TIMESTAMP}"
echo "Backup: ${OC_CFG}.bak.${TIMESTAMP}"
echo ""

# Token abfragen (ohne Echo)
echo "Bot-Token eingeben (von @BotFather):"
echo "(Token wird nicht angezeigt)"
read -rs BOT_TOKEN
echo ""

if [ -z "$BOT_TOKEN" ]; then
    echo "FEHLER: Kein Token eingegeben."
    exit 1
fi

# Token-Format pruefen (grob: Zahl:alphanumerisch)
if ! echo "$BOT_TOKEN" | grep -qE '^[0-9]+:[A-Za-z0-9_-]+$'; then
    echo "WARNUNG: Token sieht nicht nach einem Telegram Bot-Token aus."
    echo "Erwartetes Format: 123456789:ABCdefGHIjklMNOpqrSTUvwxYZ"
    echo ""
    read -p "Trotzdem fortfahren? (j/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[jJyY]$ ]]; then
        echo "Abgebrochen."
        exit 1
    fi
fi

# Token in Config setzen
python3 << PYEOF
import json, sys

cfg_path = "$OC_CFG"
token = """$BOT_TOKEN"""

try:
    with open(cfg_path, "r") as f:
        cfg = json.load(f)
except Exception as e:
    print(f"FEHLER: Config nicht lesbar: {e}", file=sys.stderr)
    sys.exit(1)

# Telegram Channel konfigurieren
tg = cfg.setdefault("channels", {}).setdefault("telegram", {})
tg["enabled"] = True
tg["botToken"] = token
tg["dmPolicy"] = "owner"
tg["groupPolicy"] = "allowlist"
tg["streaming"] = "off"

# Sicherstellen dass Telegram-Plugin erlaubt ist
plugins = cfg.setdefault("plugins", {})
allow = plugins.setdefault("allow", [])
if "telegram" not in allow:
    allow.append("telegram")

entries = plugins.setdefault("entries", {})
entries.setdefault("telegram", {})["enabled"] = True

with open(cfg_path, "w") as f:
    json.dump(cfg, f, indent=2)

print("OK: Telegram Bot-Token konfiguriert")
print(f"  dmPolicy: owner")
print(f"  groupPolicy: allowlist")
print(f"  plugin: enabled")
PYEOF

echo ""
echo "=== Naechste Schritte ==="
echo ""
echo "  1. openclaw doctor --fix"
echo "  2. openclaw gateway --force"
echo "  3. Oeffne Telegram und schreibe @M0Claw92bot"
echo "  4. openclaw status   (sollte 'Telegram: linked' zeigen)"
echo ""
echo "WICHTIG: Den Token NIEMALS in Git committen!"
echo "         Er ist jetzt nur in ~/.openclaw/openclaw.json (lokal)."
