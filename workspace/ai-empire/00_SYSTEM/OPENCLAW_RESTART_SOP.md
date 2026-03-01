# OpenClaw Restart SOP

Sicheres Neustarten von OpenClaw.
Optimiert fuer Terminus (iOS Terminal).

---

## 1. Backup

```bash
cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.bak
```

## 2. Check vor Restart

```bash
openclaw doctor
```

```bash
openclaw status
```

Nur fortfahren wenn keine kritischen Fehler.

## 3. Config fixen

```bash
openclaw doctor --fix
```

## 4. Gateway neu starten

`openclaw restart` existiert NICHT.

### Standard (empfohlen):

```bash
openclaw gateway --force
```

### Manuell:

```bash
lsof -t -iTCP:18789 | xargs kill 2>/dev/null
```

```bash
openclaw gateway
```

### Im Hintergrund:

```bash
openclaw gateway --force &
```

## 5. Nach Restart pruefen

```bash
openclaw status
```

```bash
lsof -nP -iTCP:18789 -sTCP:LISTEN
```

Erwartung:
- WhatsApp: linked
- Telegram: linked
- Port 18789: openclaw lauscht

## 6. Modell setzen

Korrekter Pfad:

```
agents.defaults.model.primary
agents.defaults.model.fallbacks
```

Per CLI:

```bash
openclaw config set agents.defaults.model.primary "ollama/qwen3:8b"
```

## 7. Port-Konflikt

Port belegt?

```bash
openclaw gateway --force
```

Oder anderer Port:

```bash
openclaw gateway --port 18790
```

---

## Rollback

```bash
cp ~/.openclaw/openclaw.json.bak ~/.openclaw/openclaw.json
```

```bash
openclaw doctor --fix
```

```bash
openclaw gateway --force
```
