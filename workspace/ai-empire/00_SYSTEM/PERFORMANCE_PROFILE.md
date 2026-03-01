# Performance-Profil

Schnelle Antworten mit lokalen Modellen.
Optimiert fuer Terminus (iOS Terminal).

---

## Default Modell

| Setting | Pfad | Wert |
|---------|------|------|
| Primary | `agents.defaults.model.primary` | `ollama/qwen3:8b` |
| Fallback | `agents.defaults.model.fallbacks` | `["ollama/qwen3:4b"]` |

Setzen:

```bash
openclaw config set agents.defaults.model.primary "ollama/qwen3:8b"
```

Pruefen:

```bash
ollama list
```

```bash
openclaw models list
```

---

## DeepWork Mode

Grosses Modell fuer komplexe Aufgaben.

An:

```bash
openclaw config set agents.defaults.model.primary "ollama/glm-4.7:cloud"
```

Aus:

```bash
openclaw config set agents.defaults.model.primary "ollama/qwen3:8b"
```

---

## Parallelitaet

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

## Modell-Empfehlungen

| Aufgabe | Modell |
|---------|--------|
| Chat | `ollama/qwen3:8b` |
| Code | `ollama/qwen3:8b` |
| Deep Analysis | `ollama/glm-4.7:cloud` |
| Auto-Reply | `ollama/qwen3:8b` |

Cloud-Modelle (via Proxy):

- `glm-5:cloud` (200k)
- `glm-4.7:cloud` (202k)
- `deepseek-v3.1:671b-cloud` (128k)
- `deepseek-v3.2:cloud` (128k)
- `minimax-m2.5:cloud` (204k)
- `kimi-k2-thinking:cloud` (262k)
- `kimi-k2.5:cloud` (262k)
- `qwen3-coder-next:cloud` (262k)
- `qwen3-coder:480b-cloud` (262k)
- `qwen3.5:cloud` (200k)

---

## Quick-Check

```bash
ollama ps
```

```bash
openclaw status
```

```bash
memory_pressure
```

Ziel: RAM < 75%
