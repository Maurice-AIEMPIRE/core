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
3. Name: z.B. `AI Empire Bot`
4. Username: z.B. `ai_empire_maurice_bot` (muss auf `_bot` enden)
5. **Speichere den Bot-Token** (Format: `123456789:ABCdefGHIjklMNOpqrSTUvwxYZ`)

### 1.2 Bot-Rechte bei BotFather setzen

Sende diese Kommandos an @BotFather:

```
/setprivacy → ai_empire_maurice_bot → Disable
```

(Damit der Bot alle Nachrichten in Gruppen lesen kann, nicht nur /commands)

```
/setjoingroups → ai_empire_maurice_bot → Enable
```

```
/setcommands → ai_empire_maurice_bot
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

### 2.1 Telegram Channel konfigurieren

```bash
openclaw channels login --channel telegram
```

Wenn das interaktiv nach dem Token fragt, gib den BotFather-Token ein.

Falls es eine direkte Config-Option gibt:

```bash
openclaw config set channels.telegram.botToken "<DEIN_BOT_TOKEN>"
```

### 2.2 Alternativ: Config direkt setzen

```bash
cat ~/.openclaw/openclaw.json | python3 -c "
import json, sys
cfg = json.load(sys.stdin)
tg = cfg.setdefault('channels', {}).setdefault('telegram', {})
tg['enabled'] = True
tg['dmPolicy'] = 'owner'
tg['groupPolicy'] = 'allowlist'
tg['streaming'] = 'off'
json.dump(cfg, sys.stdout, indent=2)
" > /tmp/oc_tmp.json && mv /tmp/oc_tmp.json ~/.openclaw/openclaw.json
```

### 2.3 Validieren

```bash
openclaw doctor --fix
```

```bash
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
2. Suche deinen Bot (@ai_empire_maurice_bot)
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
