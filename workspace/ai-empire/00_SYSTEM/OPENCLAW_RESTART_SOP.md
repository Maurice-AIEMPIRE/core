# OpenClaw Restart SOP

> Standard Operating Procedure für sicheres Stoppen und Neustarten von OpenClaw.

---

## Voraussetzungen

- `commands.restart=true` in `~/.openclaw/openclaw.json` gesetzt
- Backup der Config existiert (siehe unten)

---

## 1. Pre-Restart: Backup

```bash
cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.bak.$(date +%Y%m%d_%H%M%S)
```

## 2. Gesundheitscheck vor Restart

```bash
openclaw doctor
openclaw status
```

Nur fortfahren wenn `doctor` keine kritischen Fehler zeigt.

## 3. Config validieren und fixen

```bash
openclaw doctor --fix
openclaw doctor
```

Prüfe Output: Alle Checks sollten PASS zeigen.

## 4. Restart aktivieren (einmalig)

Falls noch nicht gesetzt:

```bash
cat ~/.openclaw/openclaw.json | python3 -c "
import json, sys
cfg = json.load(sys.stdin)
cfg.setdefault('commands', {})['restart'] = True
json.dump(cfg, sys.stdout, indent=2)
" > /tmp/openclaw_tmp.json && mv /tmp/openclaw_tmp.json ~/.openclaw/openclaw.json
```

Verifizieren:

```bash
python3 -c "import json; c=json.load(open('$HOME/.openclaw/openclaw.json')); print('restart:', c.get('commands',{}).get('restart','NOT SET'))"
```

## 5. Sicherer Restart

```bash
openclaw restart
```

Falls `openclaw restart` nicht verfügbar:

```bash
openclaw stop && sleep 2 && openclaw start
```

## 6. Post-Restart Verifizierung

```bash
openclaw doctor
openclaw status
lsof -nP -iTCP:18789 -sTCP:LISTEN
```

Erwartung:
- Doctor: alle Checks PASS
- Status: Gateway connected
- Port 18789: openclaw Prozess lauscht

## 7. sessions_spawn Konfiguration

### Option A: Agent-Allowlist (bevorzugt)

Ermittle verfügbare Agents:

```bash
openclaw agents list
```

Setze Allowlist (ersetze AGENT_ID durch tatsächliche ID):

```bash
cat ~/.openclaw/openclaw.json | python3 -c "
import json, sys
cfg = json.load(sys.stdin)
cfg.setdefault('sessions', {})['spawn'] = {'allowed': ['AGENT_ID']}
json.dump(cfg, sys.stdout, indent=2)
" > /tmp/openclaw_tmp.json && mv /tmp/openclaw_tmp.json ~/.openclaw/openclaw.json
```

### Option B: Spawn deaktiviert lassen

Wenn unklar welche Agents erlaubt sein sollen → spawn bleibt `none`.
Stattdessen Cron/Jobs für automatisierte Tasks nutzen (siehe Phase D).

**Dokumentation:** sessions_spawn bleibt deaktiviert weil:
- Sicherheitsrisiko bei offener Allowlist
- Cron-basierte Automatisierung ist vorhersagbarer
- Explizite Agent-Zuweisung ist sicherer

## 8. Port-Konflikt lösen

Falls Port 18789 belegt:

```bash
lsof -nP -iTCP:18789 -sTCP:LISTEN
```

### Option A: Blockierenden Prozess beenden

```bash
kill -TERM $(lsof -t -iTCP:18789 -sTCP:LISTEN)
```

### Option B: Alternativen Port nutzen

```bash
cat ~/.openclaw/openclaw.json | python3 -c "
import json, sys
cfg = json.load(sys.stdin)
cfg.setdefault('gateway', {})['port'] = 18790
json.dump(cfg, sys.stdout, indent=2)
" > /tmp/openclaw_tmp.json && mv /tmp/openclaw_tmp.json ~/.openclaw/openclaw.json
openclaw restart
```

---

## Rollback

Falls etwas schiefgeht:

```bash
ls -t ~/.openclaw/openclaw.json.bak.* | head -1
cp $(ls -t ~/.openclaw/openclaw.json.bak.* | head -1) ~/.openclaw/openclaw.json
openclaw restart
```

---

## Checkliste

- [ ] Backup erstellt
- [ ] Doctor clean vor Restart
- [ ] Restart erfolgreich
- [ ] Doctor clean nach Restart
- [ ] Port 18789 aktiv
- [ ] Gateway connected
