# Hermes Verifier Rules

> **Regel #1:** Kein `done` ohne Verifier-Pass.
> **Regel #2:** Verifier ist hart, nicht freundlich.

---

## 1. Was der Verifier ist

Der Verifier ist die letzte Instanz vor `done`. Wenn ein Agent (OpenClaw/Harvey)
sagt "Task fertig", **muss** Hermes dazu eine harte Prüfung ausführen. Nur wenn
alle Checks passen, wird der Goal-Status auf `done` gesetzt.

Der Verifier vertraut keinem Agent. Er checkt selbst.

---

## 2. Check-Typen (kanonisch)

### 2.1 `file_exists`
```yaml
- kind: file_exists
  path: "scripts/mac-optimizer/setup.sh"
```
Pass: `os.path.exists(path)` == True.
Failure: File nicht da → status `review` bleibt.

### 2.2 `file_matches`
```yaml
- kind: file_matches
  path: "REPORT.md"
  regex: "^Status:\\s*done"
  case_sensitive: false
```
Pass: Regex findet Match. Failure: kein Match → fail.

### 2.3 `git_tag`
```yaml
- kind: git_tag
  pattern: "v1.0.*"          # glob
  branch: main               # optional
```
Pass: Tag existiert lokal (oder remote bei `branch` gesetzt).

### 2.4 `git_clean`
```yaml
- kind: git_clean
  cwd: "."
```
Pass: `git status --porcelain` ist leer.

### 2.5 `command_passes`
```yaml
- kind: command_passes
  cmd: "npm test"
  cwd: "apps/webapp"
  timeout_seconds: 300
  expect_exit: 0
```
Pass: Exit-Code matched.
Output (stdout/stderr) wird in Report eingehängt.

### 2.6 `http_status`
```yaml
- kind: http_status
  url: "https://gumroad.com/l/mac-optimizer"
  expect: 200
  timeout_seconds: 10
  user_agent: "Hermes-Verifier/1.0"
```
Pass: HTTP-Status matched.

### 2.7 `stripe_test_event`
```yaml
- kind: stripe_test_event
  event: "checkout.session.completed"
  within_minutes: 60
```
Pass: Event wurde in Stripe-Webhook-Log innerhalb des Zeitfensters gesehen.
(Nutzt Harvey's Webhook-Log unter `~/.openclaw/legal_usage/`)

### 2.8 `kg_node_exists`
```yaml
- kind: kg_node_exists
  label: "Output"
  props:
    kind: "report"
    goal_id: "{this.id}"
```
Pass: Im BlackHole-KG existiert ein passender Node.

### 2.9 `human_signoff`
```yaml
- kind: human_signoff
  prompt: "Mac Optimizer launched? (y/n)"
  from_user_id: 8531161985        # Maurice
  timeout_minutes: 30
```
Pass: Maurice antwortet "ja"/"y"/"yes" innerhalb der Zeit.
Failure: Timeout → `blocked` mit Reason "waiting for human".

### 2.10 `composite`
```yaml
- kind: composite
  checks:
    - { kind: file_exists, path: "..." }
    - { kind: command_passes, cmd: "npm test", expect_exit: 0 }
  mode: all                       # all | any
```
Pass: Je nach `mode` alle oder mind. einer.

---

## 3. Standard-Verifier pro Goal-Typ

### `build` → `composite_build`
```yaml
- kind: composite
  mode: all
  checks:
    - { kind: file_exists, path: "{this.expected_output_path}" }
    - { kind: command_passes, cmd: "{this.test_command}", expect_exit: 0 }
    - { kind: git_clean }              # working tree clean nach build
```

### `publish` → `composite_publish`
```yaml
- kind: composite
  mode: all
  checks:
    - { kind: http_status, url: "{this.public_url}", expect: 200 }
    - { kind: kg_node_exists, label: "Output", props: { kind: "publish", goal_id: "{this.id}" } }
    - { kind: human_signoff, prompt: "Live und sichtbar? (y/n)" }
```

### `legal_review` → `composite_legal`
```yaml
- kind: composite
  mode: all
  checks:
    - { kind: file_exists, path: "control-plane/reports/{this.id}_legal.md" }
    - { kind: file_matches, path: "control-plane/reports/{this.id}_legal.md", regex: "Risiko:\\s*\\d+/10" }
    - { kind: file_matches, path: "control-plane/reports/{this.id}_legal.md", regex: "Empfehlung:" }
    - { kind: kg_node_exists, label: "LegalFinding", props: { goal_id: "{this.id}" } }
```

### `research` → `report_with_sources`
```yaml
- kind: composite
  mode: all
  checks:
    - { kind: file_exists, path: "control-plane/reports/{this.id}_research.md" }
    - { kind: file_matches, path: "control-plane/reports/{this.id}_research.md", regex: "## Quellen" }
    - { kind: file_matches, path: "control-plane/reports/{this.id}_research.md", regex: "https?://" }
```

### `decide` → `human_signoff_required`
```yaml
- kind: human_signoff
  prompt: "{this.decision_prompt}"
  timeout_minutes: 60
```

### `monitor` → `composite_monitor`
```yaml
- kind: composite
  mode: all
  checks:
    - { kind: file_exists, path: "control-plane/reports/monitor/{this.id}.json" }
    - { kind: file_matches, path: "control-plane/reports/monitor/{this.id}.json", regex: "\"status\":\\s*\"ok\"" }
```

---

## 4. Failure-Behavior

| Check-Failure       | Aktion                                         |
|---------------------|------------------------------------------------|
| 1× File missing     | Re-Trigger Owner-Agent (1 Retry erlaubt)       |
| 1× Command fail     | Re-Trigger Owner-Agent (mit Output an Owner)   |
| 1× HTTP 5xx         | Backoff 30s, retry 3×                          |
| 1× HTTP 4xx         | Status `blocked` (kein Retry, Owner muss fixen)|
| 1× Human Timeout    | Status `blocked`, Reason "waiting for human"   |
| Composite fail (any check) | `review` bleibt, alle Failures geloggt  |
| 3× Verifier-Failure | Goal eskaliert nach Jarvis ("Maurice, dieser Goal hängt") |

---

## 5. Verifier-Report-Format

Jeder Verifier-Lauf schreibt einen Report:

```yaml
goal_id: goal_01HXY1
verifier_run_id: vrun_01HXZ...
ts: 2026-05-16T18:42:00Z
overall: pass
checks:
  - id: chk_01
    kind: file_exists
    args: { path: "REPORT.md" }
    result: pass
    duration_ms: 4
  - id: chk_02
    kind: command_passes
    args: { cmd: "npm test" }
    result: pass
    duration_ms: 12480
    stdout_excerpt: "✓ 42 passing (12.4s)"
  - id: chk_03
    kind: http_status
    args: { url: "https://...", expect: 200 }
    result: fail
    actual: 502
    retry_count: 3
final_status: review              # 1 Fail → bleibt review
next_action: notify_owner_agent
```

Gespeichert unter:
```
control-plane/reports/verifier/{goal_id}/{vrun_id}.yaml
```

---

## 6. Was der Verifier NICHT macht

- **Keine Bewertung der Qualität** (außer regex-Match)
  → Qualität ist Owner-Agent-Verantwortung
- **Kein automatisches Fix** (er meldet nur, fixt nicht)
- **Kein LLM-Call** (Verifier ist deterministisch, kein Halluzinations-Risiko)
- **Kein Skip möglich** (außer via `cancelled` Status durch User)

---

## 7. Special Cases

### 7.1 Verifier kann nicht ausgeführt werden
Z.B. Network down für `http_status`:
- Mark check als `inconclusive`
- Retry nach 5min
- Nach 3× inconclusive → `blocked` mit Reason "infrastructure"

### 7.2 Goal ohne Verifier (verboten)
- Wird beim Goal-Create geblockt (`GOAL_STANDARD.md` Pflichtfeld)
- Notfall-Fallback: `verifier.type: human_signoff` mit `prompt: "Wirklich done? (y/n)"`

### 7.3 Verifier-Konflikt (Mix-Status)
Wenn ein `composite` mode=all 50% Pass + 50% Fail hat:
- Goal bleibt `review`
- Failure-Liste wird an Owner-Agent als "follow up" geschickt
- Owner darf nicht direkt "done" markieren — muss Verifier nochmal triggern
