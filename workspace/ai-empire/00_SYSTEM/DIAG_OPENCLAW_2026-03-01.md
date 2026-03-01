# OpenClaw Diagnose — 2026-03-01

> Generiert in CI-Umgebung. Kommandos unten auf dem Mac ausführen und Output hier einfügen.

## Umgebung

- **Platform:** macOS (User: maurice)
- **Erstellt:** 2026-03-01
- **Status:** Template — bitte Mac-Outputs einfügen

---

## Diagnose-Kommandos (auf Mac ausführen)

### 1. OpenClaw Binary

```bash
Mac: which -a openclaw
Mac: openclaw --version
```

**Output:**
```
# HIER EINFÜGEN
```

### 2. OpenClaw Doctor

```bash
Mac: openclaw doctor
```

**Output:**
```
# HIER EINFÜGEN
```

### 3. Port 18789 Check

```bash
Mac: lsof -nP -iTCP:18789 -sTCP:LISTEN
```

**Output:**
```
# HIER EINFÜGEN
```

### 4. OpenClaw Status

```bash
Mac: openclaw status
```

**Output:**
```
# HIER EINFÜGEN
```

### 5. Ollama Modelle

```bash
Mac: ollama list
```

**Output:**
```
# HIER EINFÜGEN
```

### 6. Disk Space

```bash
Mac: df -h /
```

**Output:**
```
# HIER EINFÜGEN
```

---

## Bekannte Probleme (aus User-Report)

| Problem | Status | Aktion |
|---------|--------|--------|
| "Gateway restart is disabled" | Offen | → Phase B: `commands.restart=true` setzen |
| "sessions_spawn forbidden (allowed: none)" | Offen | → Phase B: Agent-Allowlist prüfen |
| Config-Drift | Offen | → `openclaw doctor --fix` |
| Latenz im WhatsApp Chat | Offen | → Phase C: Schnelles Default-Modell |

---

## Schnell-Diagnose Script (Mac)

Einmal ausführen und Output oben einfügen:

```bash
Mac: echo "=== OPENCLAW DIAG $(date) ===" && \
  echo "--- which ---" && which -a openclaw 2>&1 && \
  echo "--- version ---" && openclaw --version 2>&1 && \
  echo "--- doctor ---" && openclaw doctor 2>&1 && \
  echo "--- port 18789 ---" && lsof -nP -iTCP:18789 -sTCP:LISTEN 2>&1 && \
  echo "--- status ---" && openclaw status 2>&1 && \
  echo "--- ollama ---" && ollama list 2>&1 && \
  echo "--- disk ---" && df -h /
```
