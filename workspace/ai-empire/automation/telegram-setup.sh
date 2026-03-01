#!/bin/bash
#
# Telegram Bot Setup fuer OpenClaw
# Setzt den Bot-Token sicher in die OpenClaw Config.
#
# Nutzung:  bash telegram-setup.sh
#           bash telegram-setup.sh --token 123456:ABC...  (non-interactive)
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

# --- Schritt 0: Konkurrierende Telegram-Dienste pruefen ---
echo "[0] Pruefe konkurrierende Telegram-Dienste..."
COMPETING=""
if command -v launchctl &>/dev/null; then
    # Suche nach laufenden Telegram-Router oder anderen Bot-Polling-Diensten
    for svc in $(launchctl list 2>/dev/null | grep -i telegram | awk '{print $3}'); do
        COMPETING="$COMPETING $svc"
    done
fi

if [ -n "$COMPETING" ]; then
    echo "  WARNUNG: Folgende Dienste koennten mit OpenClaw's Telegram kollidieren:"
    for svc in $COMPETING; do
        echo "    - $svc"
    done
    echo ""
    echo "  409-Conflict entsteht wenn zwei Prozesse denselben Bot pollen."
    echo "  Stoppe diese Dienste mit:"
    for svc in $COMPETING; do
        echo "    launchctl bootout gui/\$(id -u)/$svc"
    done
    echo ""
    read -p "  Soll ich sie jetzt stoppen? (j/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[jJyY]$ ]]; then
        UID_NUM=$(id -u)
        for svc in $COMPETING; do
            echo "  Stoppe $svc..."
            launchctl bootout "gui/$UID_NUM/$svc" 2>/dev/null || true
        done
        echo "  OK"
    fi
else
    echo "  Keine konkurrierenden Dienste gefunden."
fi
echo ""

# --- Schritt 1: Backup ---
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
cp "$OC_CFG" "${OC_CFG}.bak.${TIMESTAMP}"
echo "[1] Backup: ${OC_CFG}.bak.${TIMESTAMP}"
echo ""

# --- Schritt 2: Token einlesen ---
BOT_TOKEN=""

# Check --token flag
if [ "${1:-}" = "--token" ] && [ -n "${2:-}" ]; then
    BOT_TOKEN="$2"
    echo "[2] Token via --token Parameter erhalten."
else
    echo "[2] Bot-Token eingeben (von @BotFather)."
    echo "    Format: 123456789:ABCdefGHIjklMNOpqrSTUvwxYZ"
    echo ""
    # Einfaches read (OHNE -s) damit Paste funktioniert
    printf "    Token: "
    read -r BOT_TOKEN
fi
echo ""

# Whitespace trimmen
BOT_TOKEN=$(echo "$BOT_TOKEN" | xargs)

if [ -z "$BOT_TOKEN" ]; then
    echo "FEHLER: Kein Token eingegeben."
    exit 1
fi

# Token-Format pruefen
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

# --- Schritt 3: Token in Config setzen ---
echo "[3] Schreibe Token in Config..."
python3 << PYEOF
import json, sys

cfg_path = "$OC_CFG"
token = "$BOT_TOKEN"

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
tg["dmPolicy"] = "pairing"
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

print("  OK: Telegram Bot-Token konfiguriert")
print(f"  dmPolicy: pairing")
print(f"  groupPolicy: allowlist")
print(f"  plugin: enabled")
PYEOF

echo ""
echo "=== Naechste Schritte ==="
echo ""
echo "  1. openclaw gateway --force"
echo "  2. Oeffne Telegram und schreibe deinen Bot an"
echo "  3. openclaw status   (sollte 'Telegram: linked' zeigen)"
echo ""
echo "SICHERHEIT:"
echo "  - Token ist NUR in ~/.openclaw/openclaw.json (lokal)"
echo "  - NIEMALS in Git committen"
echo "  - Falls der Token in einem Terminal-Log sichtbar war:"
echo "    @BotFather -> /revoke -> neuen Token generieren"
