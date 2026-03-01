# OpenClaw Performance-Profil

> Optimiert fuer schnelle Antwortzeiten mit lokalen Modellen.
> Config-Pfade basieren auf OpenClaw v2026.2.26 Schema.

---

## Default Modell

| Setting | Config-Pfad | Wert |
|---------|-------------|------|
| **Primary Model** | `agents.defaults.model.primary` | `ollama/qwen3:8b` |
| **Fallback** | `agents.defaults.model.fallbacks` | `["ollama/qwen3:4b"]` |

### Per CLI setzen

```bash
openclaw config set agents.defaults.model.primary "ollama/qwen3:8b"
```

### Per JSON setzen

```bash
cat ~/.openclaw/openclaw.json | python3 -c "
import json, sys
cfg = json.load(sys.stdin)
cfg['agents']['defaults']['model']['primary'] = 'ollama/qwen3:8b'
cfg['agents']['defaults']['model']['fallbacks'] = ['ollama/qwen3:4b']
json.dump(cfg, sys.stdout, indent=2)
" > /tmp/oc_tmp.json && mv /tmp/oc_tmp.json ~/.openclaw/openclaw.json
```

Danach immer validieren:

```bash
openclaw doctor --fix
```

### Verfuegbare Modelle pruefen

```bash
ollama list
```

```bash
openclaw models list
```

---

## DeepWork Mode

Temporaer auf ein groesseres Modell umschalten fuer komplexe Aufgaben.

### Aktivieren

```bash
openclaw config set agents.defaults.model.primary "ollama/glm-4.7:cloud"
```

Oder per JSON:

```bash
cat ~/.openclaw/openclaw.json | python3 -c "
import json, sys
cfg = json.load(sys.stdin)
cfg['agents']['defaults']['model']['primary'] = 'ollama/glm-4.7:cloud'
json.dump(cfg, sys.stdout, indent=2)
" > /tmp/oc_tmp.json && mv /tmp/oc_tmp.json ~/.openclaw/openclaw.json
```

### Deaktivieren (zurueck zu Standard)

```bash
openclaw config set agents.defaults.model.primary "ollama/qwen3:8b"
```

### Shortcut-Scripts (Optional)

Erstelle zwei Aliases in `~/.zshrc`:

```bash
cat >> ~/.zshrc << 'ALIASES'

# OpenClaw DeepWork Toggle
alias deepwork-on='cat ~/.openclaw/openclaw.json | python3 -c "
import json, sys
cfg = json.load(sys.stdin)
cfg[\"agents\"][\"defaults\"][\"model\"][\"primary\"] = \"ollama/glm-4.7:cloud\"
json.dump(cfg, sys.stdout, indent=2)
" > /tmp/oc_tmp.json && mv /tmp/oc_tmp.json ~/.openclaw/openclaw.json && echo "DeepWork ON: glm-4.7:cloud"'

alias deepwork-off='cat ~/.openclaw/openclaw.json | python3 -c "
import json, sys
cfg = json.load(sys.stdin)
cfg[\"agents\"][\"defaults\"][\"model\"][\"primary\"] = \"ollama/qwen3:8b\"
json.dump(cfg, sys.stdout, indent=2)
" > /tmp/oc_tmp.json && mv /tmp/oc_tmp.json ~/.openclaw/openclaw.json && echo "DeepWork OFF: qwen3:8b"'
ALIASES
```

Dann aktivieren:

```bash
source ~/.zshrc
```

---

## Parallelitaet

| Setting | Empfehlung | Grund |
|---------|-----------|-------|
| **Max aktive Sessions** | 2-3 | RAM-Limit bei lokalen Modellen |
| **Ollama Parallel Requests** | 2 | `OLLAMA_NUM_PARALLEL=2` |
| **Context Window** | 4096 pro Session | Schnellere Inference |

### Ollama Parallel konfigurieren

```bash
launchctl setenv OLLAMA_NUM_PARALLEL 2
launchctl setenv OLLAMA_MAX_LOADED_MODELS 2
```

Oder in `~/.zshrc`:

```bash
export OLLAMA_NUM_PARALLEL=2
export OLLAMA_MAX_LOADED_MODELS=2
```

---

## Modell-Empfehlungen nach Aufgabe

| Aufgabe | Modell | Notizen |
|---------|--------|---------|
| Schneller Chat | `ollama/qwen3:8b` | Default, lokal, schnell |
| Code Review | `ollama/qwen3:8b` | Reicht fuer die meisten Reviews |
| Deep Analysis | `ollama/glm-4.7:cloud` | Via Ollama-Proxy, groesseres Modell |
| WhatsApp Auto-Reply | `ollama/qwen3:8b` | Minimal-Latenz wichtig |

### Verfuegbare Cloud-Modelle (via Ollama-Proxy)

Aus der Config:
- `glm-5:cloud` (200k context)
- `glm-4.7:cloud` (202k context)
- `deepseek-v3.1:671b-cloud` (128k context)
- `deepseek-v3.2:cloud` (128k context)
- `minimax-m2.5:cloud` (204k context, 128k output)
- `kimi-k2-thinking:cloud` (262k context)
- `kimi-k2.5:cloud` (262k context, multimodal)
- `qwen3-coder-next:cloud` (262k context)
- `qwen3-coder:480b-cloud` (262k context)
- `qwen3.5:cloud` (200k context, multimodal)

---

## Latenz-Checkliste

- [ ] Ollama laeuft: `ollama ps`
- [ ] Modell geladen: `ollama list | grep qwen3`
- [ ] Gateway laeuft: `openclaw status`
- [ ] RAM frei: `memory_pressure` (Ziel: < 75%)
