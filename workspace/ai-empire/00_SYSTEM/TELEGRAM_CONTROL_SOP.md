# Telegram Bot-Steuerung

OpenClaw per Telegram steuern.
Optimiert fuer Terminus (iOS Terminal).

---

## Voraussetzungen

- OpenClaw v2026.2.26+
- Telegram Account
- Gateway laeuft

---

## Phase 1: Bot erstellen

### 1.1 Bei BotFather

1. Telegram oeffnen, `@BotFather` suchen
2. `/newbot` senden
3. Bot-Name + Username waehlen
4. Token kopieren (NICHT in Git!)

### 1.2 Bot-Rechte setzen

An @BotFather senden:

```
/setprivacy
```
-> Bot waehlen -> Disable

```
/setjoingroups
```
-> Bot waehlen -> Enable

```
/setcommands
```
-> Bot waehlen, dann senden:

```
status - OpenClaw Status
sync - Context Sync
help - Hilfe
```

---

## Phase 2: Token in OpenClaw setzen

> WICHTIG: `openclaw channels login --channel telegram`
> funktioniert NICHT. Token muss direkt gesetzt werden.

### Option A: Setup-Script (empfohlen)

```bash
bash ~/ai-empire-core/workspace/ai-empire/automation/telegram-setup.sh
```

Oder mit Token direkt (kein Prompt):

```bash
bash ~/ai-empire-core/workspace/ai-empire/automation/telegram-setup.sh --token DEIN_TOKEN
```

### Option B: Manuell per Python

```bash
python3 -c "
import json
p='$HOME/.openclaw/openclaw.json'
c=json.load(open(p))
t=c.setdefault('channels',{}).setdefault('telegram',{})
t['enabled']=True
t['botToken']=input('Token: ')
t['dmPolicy']='owner'
t['groupPolicy']='allowlist'
t['streaming']='off'
json.dump(c,open(p,'w'),indent=2)
print('OK')
"
```

### Validieren

```bash
openclaw doctor --fix
```

```bash
openclaw gateway --force
```

```bash
openclaw status
```

Erwartung: `Telegram: linked`

---

## Phase 3: DM-Pairing

### 3.1 Pairing starten

```bash
openclaw pairing approve --channel telegram
```

### 3.2 Ersten DM senden

1. Telegram oeffnen
2. Deinen Bot suchen
3. "Hello" senden
4. Agent sollte antworten

### 3.3 Owner verifizieren

```bash
openclaw directory self --channel telegram
```

---

## Phase 4: Gruppen (optional)

Gruppen auflisten:

```bash
openclaw directory groups --channel telegram
```

Dann Gruppe zur Allowlist hinzufuegen.

---

## Kommandos per Telegram

| Nachricht | Ergebnis |
|-----------|----------|
| Text | Agent antwortet |
| `/status` | OpenClaw Status |
| Datei/Bild | Agent verarbeitet |

Skills auflisten:

```bash
openclaw skills list
```

---

## Troubleshooting

### "Telegram: not configured"

Token fehlt. Setup-Script erneut ausfuehren:

```bash
bash ~/ai-empire-core/workspace/ai-empire/automation/telegram-setup.sh
```

### 409 Conflict (getUpdates)

Ein anderer Prozess pollt denselben Bot.
Typisch: `com.ai-empire.telegram-router`

Pruefen:

```bash
launchctl list | grep -i telegram
```

Stoppen:

```bash
launchctl bootout gui/$(id -u)/com.ai-empire.telegram-router
```

Dann Gateway neu starten:

```bash
openclaw gateway --force
```

### Bot antwortet nicht

1. Gateway laeuft?

```bash
openclaw status
```

2. Pairing ok?

```bash
openclaw pairing list --channel telegram
```

3. Logs pruefen:

```bash
openclaw logs --channel telegram
```

### Rate Limits

```bash
openclaw config set channels.telegram.debounceMs 500
```

---

## Sicherheit

- Bot-Token ist ein Secret — nie in Git
- dmPolicy: "owner" — nur du steuerst
- groupPolicy: "allowlist" — nur freigegebene Gruppen
- Token geleakt? -> @BotFather -> /revoke
- Audit: `openclaw security audit --deep`
