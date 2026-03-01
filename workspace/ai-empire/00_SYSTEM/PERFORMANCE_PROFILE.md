# OpenClaw Performance-Profil

> Optimiert für schnelle Antwortzeiten mit lokalen Modellen.

---

## Default Modell

| Setting | Wert |
|---------|------|
| **Default Model** | `ollama/qwen3:8b` |
| **Fallback Model** | `ollama/llama3.1:8b` |
| **Thinking Mode** | `minimal` / `low` |
| **Max Tokens** | `2048` (Standard-Chat) |

### Setzen auf dem Mac

```bash
Mac: cat ~/.openclaw/openclaw.json | python3 -c "
import json, sys
cfg = json.load(sys.stdin)
cfg.setdefault('models', {})['default'] = 'ollama/qwen3:8b'
cfg.setdefault('models', {})['thinking'] = 'minimal'
cfg.setdefault('models', {})['max_tokens'] = 2048
json.dump(cfg, sys.stdout, indent=2)
" > /tmp/openclaw_tmp.json && mv /tmp/openclaw_tmp.json ~/.openclaw/openclaw.json
```

### Verfügbare Modelle prüfen

```bash
Mac: ollama list
```

Falls `qwen3:8b` nicht installiert:

```bash
Mac: ollama pull qwen3:8b
```

---

## DeepWork Mode

Temporär auf ein größeres Modell umschalten für komplexe Aufgaben.

### Aktivieren

```bash
Mac: cat ~/.openclaw/openclaw.json | python3 -c "
import json, sys
cfg = json.load(sys.stdin)
cfg.setdefault('models', {})['default'] = 'ollama/qwen3:32b'
cfg.setdefault('models', {})['thinking'] = 'high'
cfg.setdefault('models', {})['max_tokens'] = 8192
json.dump(cfg, sys.stdout, indent=2)
" > /tmp/openclaw_tmp.json && mv /tmp/openclaw_tmp.json ~/.openclaw/openclaw.json
```

### Deaktivieren (zurück zu Standard)

```bash
Mac: cat ~/.openclaw/openclaw.json | python3 -c "
import json, sys
cfg = json.load(sys.stdin)
cfg.setdefault('models', {})['default'] = 'ollama/qwen3:8b'
cfg.setdefault('models', {})['thinking'] = 'minimal'
cfg.setdefault('models', {})['max_tokens'] = 2048
json.dump(cfg, sys.stdout, indent=2)
" > /tmp/openclaw_tmp.json && mv /tmp/openclaw_tmp.json ~/.openclaw/openclaw.json
```

### Shortcut-Scripts (Optional)

Erstelle zwei Aliases in `~/.zshrc`:

```bash
Mac: cat >> ~/.zshrc << 'ALIASES'

# OpenClaw DeepWork Toggle
alias deepwork-on='python3 -c "
import json
cfg=json.load(open(\"$HOME/.openclaw/openclaw.json\"))
cfg.setdefault(\"models\",{})[\"default\"]=\"ollama/qwen3:32b\"
cfg[\"models\"][\"thinking\"]=\"high\"
cfg[\"models\"][\"max_tokens\"]=8192
json.dump(cfg,open(\"$HOME/.openclaw/openclaw.json\",\"w\"),indent=2)
print(\"DeepWork ON: qwen3:32b, thinking=high\")
"'

alias deepwork-off='python3 -c "
import json
cfg=json.load(open(\"$HOME/.openclaw/openclaw.json\"))
cfg.setdefault(\"models\",{})[\"default\"]=\"ollama/qwen3:8b\"
cfg[\"models\"][\"thinking\"]=\"minimal\"
cfg[\"models\"][\"max_tokens\"]=2048
json.dump(cfg,open(\"$HOME/.openclaw/openclaw.json\",\"w\"),indent=2)
print(\"DeepWork OFF: qwen3:8b, thinking=minimal\")
"'
ALIASES
Mac: source ~/.zshrc
```

---

## Parallelität

| Setting | Empfehlung | Grund |
|---------|-----------|-------|
| **Max aktive Sessions** | 2–3 | RAM-Limit bei lokalen Modellen |
| **Ollama Parallel Requests** | 2 | `OLLAMA_NUM_PARALLEL=2` |
| **Context Window** | 4096 pro Session | Schnellere Inference |

### Ollama Parallel konfigurieren

```bash
Mac: launchctl setenv OLLAMA_NUM_PARALLEL 2
Mac: launchctl setenv OLLAMA_MAX_LOADED_MODELS 2
```

Oder in `~/.zshrc`:

```bash
export OLLAMA_NUM_PARALLEL=2
export OLLAMA_MAX_LOADED_MODELS=2
```

---

## Modell-Empfehlungen nach Aufgabe

| Aufgabe | Modell | Thinking | Tokens |
|---------|--------|----------|--------|
| Schneller Chat | `ollama/qwen3:8b` | minimal | 2048 |
| Code Review | `ollama/qwen3:8b` | low | 4096 |
| Architektur / Deep Analysis | `ollama/qwen3:32b` | high | 8192 |
| Zusammenfassungen | `ollama/qwen3:8b` | minimal | 1024 |
| WhatsApp Auto-Reply | `ollama/qwen3:8b` | off | 512 |

---

## Latenz-Checkliste

- [ ] Ollama läuft: `Mac: ollama ps`
- [ ] Modell geladen: `Mac: ollama list | grep qwen3`
- [ ] Keine GPU-Konkurrenz: `Mac: ps aux | grep -i gpu`
- [ ] RAM frei: `Mac: memory_pressure` (Ziel: < 75%)
- [ ] OpenClaw Gateway connected: `Mac: openclaw status`
