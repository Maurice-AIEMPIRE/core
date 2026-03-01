# OpenClaw Restart SOP

> Standard Operating Procedure fuer sicheres Stoppen und Neustarten von OpenClaw.
> Basiert auf `openclaw --help` (v2026.2.26).

---

## Voraussetzungen

- OpenClaw installiert (`which openclaw`)
- Config valid (`openclaw doctor`)

---

## 1. Pre-Restart: Backup

```bash
cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.bak.$(date +%Y%m%d_%H%M%S)
```

## 2. Gesundheitscheck vor Restart

```bash
openclaw doctor
```

```bash
openclaw status
```

Nur fortfahren wenn `doctor` keine kritischen Fehler zeigt.

## 3. Config validieren und fixen

```bash
openclaw doctor --fix
```

## 4. Gateway neu starten

`openclaw restart` existiert nicht. Stattdessen:

### Option A: Gateway mit --force (bevorzugt)

Killt den alten Gateway-Prozess auf dem Port und startet neu:

```bash
openclaw gateway --force
```

### Option B: Gateway manuell stoppen + starten

```bash
lsof -t -iTCP:18789 -sTCP:LISTEN | xargs kill -TERM 2>/dev/null; sleep 2; openclaw gateway
```

### Option C: Gateway im Hintergrund

```bash
openclaw gateway --force &
```

## 5. Post-Restart Verifizierung

```bash
openclaw doctor
```

```bash
openclaw status
```

```bash
lsof -nP -iTCP:18789 -sTCP:LISTEN
```

Erwartung:
- Doctor: keine kritischen Fehler
- Status: WhatsApp linked, Gateway connected
- Port 18789: openclaw Prozess lauscht

## 6. Modell konfigurieren

Korrekte Config-Pfade (Schema v2026.2.26):

```
agents.defaults.model.primary    → z.B. "ollama/qwen3:8b"
agents.defaults.model.fallbacks  → z.B. ["ollama/qwen3:4b"]
```

Per CLI setzen:

```bash
openclaw config set agents.defaults.model.primary "ollama/qwen3:8b"
```

Oder per JSON:

```bash
cat ~/.openclaw/openclaw.json | python3 -c "
import json, sys
cfg = json.load(sys.stdin)
cfg['agents']['defaults']['model']['primary'] = 'ollama/qwen3:8b'
json.dump(cfg, sys.stdout, indent=2)
" > /tmp/oc_tmp.json && mv /tmp/oc_tmp.json ~/.openclaw/openclaw.json
```

Danach validieren:

```bash
openclaw doctor --fix
```

## 7. sessions_spawn Konfiguration

### Option A: Agent-Allowlist (bevorzugt)

Ermittle verfuegbare Agents:

```bash
openclaw agents list
```

### Option B: Spawn deaktiviert lassen

Wenn unklar welche Agents erlaubt sein sollen, bleibt spawn `none`.
Stattdessen Cron-basierte Automatisierung nutzen:

```bash
openclaw cron --help
```

## 8. Port-Konflikt loesen

Falls Port 18789 belegt:

```bash
lsof -nP -iTCP:18789 -sTCP:LISTEN
```

### Option A: --force (raeumt den Port automatisch)

```bash
openclaw gateway --force
```

### Option B: Alternativen Port nutzen

```bash
openclaw gateway --port 18790
```

---

## Rollback

Falls etwas schiefgeht:

```bash
cp $(ls -t ~/.openclaw/openclaw.json.bak.* | head -1) ~/.openclaw/openclaw.json
```

```bash
openclaw doctor --fix
```

```bash
openclaw gateway --force
```

---

## Checkliste

- [ ] Backup erstellt
- [ ] Doctor clean vor Restart
- [ ] `openclaw gateway --force` erfolgreich
- [ ] Doctor clean nach Restart
- [ ] Port 18789 aktiv
- [ ] WhatsApp linked
