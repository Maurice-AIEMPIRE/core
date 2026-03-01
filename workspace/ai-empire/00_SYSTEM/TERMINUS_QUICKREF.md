# Terminus Quick Reference

Alle wichtigen Befehle auf einen Blick.
Zum Kopieren in Terminus optimiert.

---

## Status

```bash
openclaw status
```

```bash
openclaw doctor
```

```bash
ollama ps
```

---

## Gateway

Starten:

```bash
openclaw gateway --force
```

Stoppen:

```bash
lsof -t -iTCP:18789 | xargs kill
```

Logs:

```bash
openclaw logs
```

---

## Telegram

Setup:

```bash
bash ~/ai-empire-core/workspace/ai-empire/automation/telegram-setup.sh
```

409-Fix (anderer Bot-Poller aktiv):

```bash
launchctl list | grep telegram
```

```bash
launchctl bootout gui/$(id -u)/com.ai-empire.telegram-router
```

---

## Modell wechseln

Schnell (default):

```bash
openclaw config set agents.defaults.model.primary "ollama/qwen3:8b"
```

DeepWork:

```bash
openclaw config set agents.defaults.model.primary "ollama/glm-4.7:cloud"
```

---

## Context Sync

Manuell:

```bash
python3 ~/.openclaw/workspace/ai-empire/automation/context_sync.py --dry-run
```

---

## Deploy (nach git pull)

```bash
cd ~/ai-empire-core && git pull origin claude/openclaw-stability-context-UHuJv
```

```bash
bash ~/ai-empire-core/workspace/ai-empire/deploy.sh
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

---

## Troubleshooting

Config kaputt:

```bash
openclaw doctor --fix
```

Port belegt:

```bash
openclaw gateway --force
```

Dienst-Konflikte:

```bash
launchctl list | grep -i 'telegram\|openclaw\|empire'
```
