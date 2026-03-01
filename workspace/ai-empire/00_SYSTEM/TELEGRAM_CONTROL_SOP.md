# Telegram Bot-Steuerung fuer OpenClaw

> Eigenen Telegram Bot mit vollen Rechten an OpenClaw anbinden.
> Damit kannst du OpenClaw komplett ueber Telegram steuern.

---

## Voraussetzungen

- OpenClaw v2026.2.26+ installiert
- Telegram Account
- Gateway laeuft (`openclaw gateway --force`)

---

## Phase 1: Telegram Bot erstellen

### 1.1 Bot bei BotFather anlegen

1. Oeffne Telegram und suche `@BotFather`
2. Sende `/newbot`
3. Bot erstellt: **@M0Claw92bot**
4. Token lokal gespeichert (NIEMALS in Git committen)

### 1.2 Bot-Rechte bei BotFather setzen

Sende diese Kommandos an @BotFather:

```
/setprivacy → M0Claw92bot → Disable
```

(Damit der Bot alle Nachrichten in Gruppen lesen kann, nicht nur /commands)

```
/setjoingroups → M0Claw92bot → Enable
```

```
/setcommands → M0Claw92bot
```

Dann sende die Kommandoliste:

```
status - Zeige OpenClaw Status
deepwork - Wechsle zu DeepWork Modell
fast - Wechsle zu schnellem Modell
sync - Fuehre Context Sync aus
help - Zeige Hilfe
```

---

## Phase 2: OpenClaw mit Telegram verbinden

> `openclaw channels login --channel telegram` funktioniert NICHT fuer Telegram.
> Der Bot-Token muss direkt in die Config geschrieben werden.

### 2.1 Setup-Script ausfuehren (empfohlen)

```bash
bash ~/ai-empire-core/workspace/ai-empire/automation/telegram-setup.sh
```

Das Script:
- Fragt den Bot-Token ab (ohne Echo — Token wird nicht angezeigt)
- Prueft das Token-Format
- Setzt `channels.telegram.botToken` in der Config
- Setzt `dmPolicy: owner` (nur du kannst den Bot steuern)
- Erstellt ein Backup der Config

### 2.2 Alternativ: Token manuell in Config setzen

```bash
python3 -c "
import json
cfg = json.load(open('$HOME/.openclaw/openclaw.json'))
tg = cfg.setdefault('channels', {}).setdefault('telegram', {})
tg['enabled'] = True
tg['botToken'] = input('Bot-Token: ')
tg['dmPolicy'] = 'owner'
tg['groupPolicy'] = 'allowlist'
tg['streaming'] = 'off'
json.dump(cfg, open('$HOME/.openclaw/openclaw.json', 'w'), indent=2)
print('OK')
"
```

### 2.3 Validieren + Gateway neustarten

```bash
openclaw doctor --fix
openclaw gateway --force
openclaw status
```

Erwartung: `Telegram: linked` (statt `not configured`)

---

## Phase 3: DM-Pairing (Bot mit deinem Account verbinden)

### 3.1 Pairing starten

```bash
openclaw channels --help
```

```bash
openclaw pairing --help
```

Finde den richtigen Pairing-Befehl fuer Telegram. Typisch:

```bash
openclaw pairing approve --channel telegram
```

### 3.2 Ersten DM an Bot senden

1. Oeffne Telegram
2. Suche deinen Bot (@M0Claw92bot)
3. Sende eine Nachricht (z.B. "Hello")
4. OpenClaw sollte ueber den Agent antworten

### 3.3 Owner-Rechte verifizieren

```bash
openclaw directory self --channel telegram
```

Das zeigt deine Telegram User-ID. Notiere sie.

---

## Phase 4: Volle Steuerung (alle Rechte)

### 4.1 dmPolicy auf "owner" setzen

Damit nur DU den Bot steuern kannst (kein open access):

Die Config hat bereits `dmPolicy: "pairing"`. Fuer volle Kontrolle:

```bash
cat ~/.openclaw/openclaw.json | python3 -c "
import json, sys
cfg = json.load(sys.stdin)
cfg['channels']['telegram']['dmPolicy'] = 'owner'
json.dump(cfg, sys.stdout, indent=2)
" > /tmp/oc_tmp.json && mv /tmp/oc_tmp.json ~/.openclaw/openclaw.json
```

### 4.2 Gruppen-Steuerung (optional)

Falls du den Bot auch in Telegram-Gruppen nutzen willst:

```bash
openclaw directory groups --channel telegram
```

Dann die gewuenschte Gruppe zur Allowlist hinzufuegen.

---

## Phase 5: Kommandos ueber Telegram

Nachdem Pairing abgeschlossen ist, kannst du per Telegram-DM:

| Nachricht | Was passiert |
|-----------|-------------|
| Jede Textnachricht | Agent antwortet (wie WhatsApp) |
| `/status` | Bot zeigt OpenClaw Status |
| Dateien/Bilder senden | Agent verarbeitet (falls Skill vorhanden) |

### Custom Skills per Telegram triggern

```bash
openclaw skills list
```

Alle eligible Skills sind auch per Telegram nutzbar.

---

## Troubleshooting

### "Telegram: not configured"

Der Bot-Token fehlt oder ist ungueltig:

```bash
openclaw channels login --channel telegram --verbose
```

### Bot antwortet nicht

1. Gateway laeuft? `openclaw status`
2. Pairing abgeschlossen? `openclaw pairing list --channel telegram`
3. Logs pruefen: `openclaw logs --channel telegram`

### Rate Limits

Telegram hat eigene Rate Limits. Falls Nachrichten verloren gehen:

```bash
openclaw config set channels.telegram.debounceMs 500
```

---

## Sicherheitshinweise

- **Bot-Token ist ein Secret** — niemals in Logs, Git oder Output zeigen
- **dmPolicy: "owner"** — nur du kannst den Bot steuern
- **groupPolicy: "allowlist"** — Bot reagiert nur in freigegebenen Gruppen
- Regelmaessig pruefen: `openclaw security audit --deep`
