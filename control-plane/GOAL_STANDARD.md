# Goal Standard — Wie ein `/goal` aussieht

> **Erfunden für:** Hermes Goal-Engine
> **Geschrieben von:** Jarvis (auf Basis Maurice-Input)
> **Verifiziert von:** Hermes Verifier

---

## 1. Was ist ein `/goal`?

Ein **Goal** ist die kleinste deklarierbare Einheit von Arbeit im Pfeifer Core.
Jeder User-Input wird von **Jarvis** in eine oder mehrere Goal-Cards übersetzt
und an **Hermes** übergeben. Hermes routet die Goal an den richtigen Agent
(OpenClaw oder Harvey), tracked Status und führt am Ende die **Verifier-Checks** aus.

**Ohne Verifier-Pass gibt es kein `done`.**

---

## 2. Pflicht-Felder

```yaml
id: goal_01HXYZ                  # auto-generated ULID
title: "Mac Optimizer v1.0 launchen"
created_by: jarvis
created_at: 2026-05-16T09:42:00Z
priority: P1                     # P0 = blocker, P1 = high, P2 = normal, P3 = nice-to-have
owner_agent: openclaw            # jarvis | hermes | openclaw | harvey
status: todo                     # todo | in_progress | review | done | blocked | cancelled
context:
  project: mac-optimizer
  why: "Erster bezahlter Sale getriggert"
  related_goals: [goal_01HXY0]
acceptance_criteria:
  - "Gumroad-Listing live"
  - "Setup-Script v1.0 tagged in Git"
  - "Sales-Page erreichbar unter /mac-optimizer"
  - "Stripe-Webhook getestet (Test-Sale durchgelaufen)"
verifier:
  type: composite               # simple | composite
  checks:
    - { kind: file_exists, path: "scripts/mac-optimizer/setup.sh" }
    - { kind: git_tag, pattern: "v1.0.*" }
    - { kind: http_status, url: "https://gumroad.com/l/mac-optimizer", expect: 200 }
    - { kind: stripe_test_event, event: "checkout.session.completed" }
deadline: 2026-05-20T18:00:00Z   # ISO 8601, optional
budget:
  spend_eur_max: 0               # null = keine Spend-Vorgabe; >0 = Limit
  human_confirmation_required: true   # >50€ default true
```

---

## 3. Optionale Felder

```yaml
sub_goals: []                    # für Composite-Goals
attachments:
  - path: "control-plane/reports/mac-optimizer-spec.md"
  - url: "https://github.com/Maurice-AIEMPIRE/core/pull/123"
notes: |
  Maurice will Launch am Freitag.
  Vorab: Newsletter-Ankündigung (Harvey).
audit:
  jarvis_input: |
    "Launch Mac Optimizer diese Woche"
  jarvis_breakdown: |
    1. Build prüfen (OpenClaw)
    2. Gumroad-Listing (OpenClaw Browser)
    3. Newsletter-Draft (Harvey)
    4. Stripe-Test (Harvey)
  hermes_routing: |
    Goal-Tree mit 4 Sub-Goals erzeugt, 2× OpenClaw, 2× Harvey
```

---

## 4. Goal-Lifecycle (Hermes-managed)

```
                ┌─────────┐
                │  todo   │ ← Jarvis erstellt
                └────┬────┘
                     │ Hermes: assign worker
                     ▼
              ┌─────────────┐
              │ in_progress │ ← Owner-Agent arbeitet
              └──────┬──────┘
                     │ Owner: "fertig"
                     ▼
                ┌─────────┐
                │  review │ ← Hermes Verifier läuft
                └──┬──────┘
       ┌──────────┘ │ └──────────┐
       ▼            ▼            ▼
  ┌───────┐    ┌────────┐   ┌─────────┐
  │ done  │    │blocked │   │cancelled│
  └───────┘    └────────┘   └─────────┘
   ↑ alle       ↑ Verifier   ↑ User-Stop
   Checks ok    fail oder    oder Deadline
                Konflikt     verfehlt
```

---

## 5. Verifier-Check-Typen

| Kind                | Schema                                                              | Beispiel                                            |
|---------------------|---------------------------------------------------------------------|-----------------------------------------------------|
| `file_exists`       | `{ path }`                                                          | `path: "REPORT.md"`                                 |
| `file_matches`      | `{ path, regex }`                                                   | `regex: "Status: done"`                             |
| `git_tag`           | `{ pattern }` (glob)                                                | `pattern: "v1.*"`                                   |
| `git_clean`         | `{}` (working tree clean)                                           | —                                                   |
| `command_passes`    | `{ cmd, expect_exit }`                                              | `cmd: "npm test", expect_exit: 0`                   |
| `http_status`       | `{ url, expect, timeout_s? }`                                       | `url: "https://x.com/health", expect: 200`          |
| `stripe_test_event` | `{ event }`                                                         | `event: "checkout.session.completed"`               |
| `kg_node_exists`    | `{ label, props }`                                                  | `label: "Output", props: {kind: "report"}`          |
| `human_signoff`     | `{ from_user_id, prompt }` (asks Maurice)                           | `prompt: "Mac Optimizer launched? (y/n)"`           |
| `composite`         | `{ checks: [...] }` — alle müssen passen                            | (siehe Pflichtfeld-Beispiel)                        |

→ Detail siehe [`hermes/verifier_rules.md`](./hermes/verifier_rules.md)

---

## 6. Goal-Typen (Templates)

### 6.1 `build` (Code/Content/Asset bauen)
- **Owner:** OpenClaw
- **Default Verifier:** `git_tag` + `command_passes` (test/build)

### 6.2 `publish` (etwas live schalten)
- **Owner:** OpenClaw (Browser) oder Harvey (Sales-Channel)
- **Default Verifier:** `http_status` + `human_signoff`

### 6.3 `legal_review` (Dokument prüfen)
- **Owner:** Harvey
- **Default Verifier:** `kg_node_exists` (Legal-Findings) + `file_exists` (Report)

### 6.4 `research` (Info recherchieren)
- **Owner:** Jarvis (delegiert via OpenClaw `seo-ranker` / Web)
- **Default Verifier:** `file_exists` (Report mit Sources)

### 6.5 `decide` (Maurice braucht Entscheidung)
- **Owner:** Jarvis
- **Default Verifier:** `human_signoff`

### 6.6 `monitor` (etwas im Auge behalten)
- **Owner:** OpenClaw (Trading-Monitor) oder Harvey (Compliance)
- **Default Verifier:** `composite` mit Periodicity

---

## 7. Datei-Layout

```
control-plane/goals/
├── README.md                              ← Goal-Engine Quickstart
├── _templates/
│   ├── build.yaml
│   ├── publish.yaml
│   ├── legal_review.yaml
│   ├── research.yaml
│   ├── decide.yaml
│   └── monitor.yaml
├── active/
│   ├── goal_01HXY1.yaml
│   └── goal_01HXY2.yaml
├── archive/
│   └── 2026-05/
│       └── goal_01HX...yaml
└── INDEX.md                               ← Kanban-View (regeneriert von Hermes)
```

---

## 8. Jarvis-Prompt für Goal-Generation

Wenn Maurice schreibt: "Launch Mac Optimizer diese Woche", muss Jarvis:

1. **Intent klassifizieren:** `publish` mit Sub-Goals
2. **Goal-Tree generieren:** Haupt-Goal + 3-5 Sub-Goals
3. **Owner-Agent zuweisen:** anhand Capability-Matrix
4. **Acceptance-Criteria formulieren** in Maurice-Sprache (Deutsch, präzise)
5. **Verifier-Checks ableiten** aus Acceptance-Criteria
6. **Dependencies setzen** (welche Sub-Goal blockt welche)
7. **Goal-Card als YAML schreiben** in `control-plane/goals/active/`
8. **An Hermes übergeben** via `POST /dispatch` (Type: `task`, intent: `create_goal`)

---

## 9. Anti-Patterns

| Pattern                                                       | Warum verboten                          |
|---------------------------------------------------------------|-----------------------------------------|
| Goal ohne `acceptance_criteria`                               | Verifier kann nichts prüfen             |
| Goal mit `verifier.type: "trust_me"`                          | Verifier ist Pflicht                    |
| Owner-Agent = "Jarvis" für Execution-Tasks                    | Jarvis macht nicht selbst               |
| `human_signoff` ohne `prompt`                                 | Maurice muss wissen wozu er signt       |
| Goal `done` ohne abgehakte Verifier-Checks                    | Hartes Architecture-Violation           |
| Mehrere Owner-Agents auf einem Goal                           | Statt Sub-Goals split                   |
| Spend ohne Budget-Limit                                       | Geld-Schutz                             |
| Trading-Live-Goal ohne Maurice-Freigabe                       | NIE                                     |

---

## 10. Status-Report-Format (Hermes → Jarvis → Maurice)

Wenn Maurice nach Status fragt, antwortet Jarvis im Format:

```
📊 Status: Mac Optimizer Launch (goal_01HXY1)
  ✅ Build geprüft         (openclaw, 12min)
  ⏳ Gumroad-Listing       (openclaw, in_progress, ETA 30min)
  ⏳ Newsletter-Draft      (harvey,   in_progress, ETA 1h)
  ⏸️  Stripe-Test          (harvey,   blocked — wartet auf Listing)
  ⏸️  Sales-Page Live      (openclaw, blocked — wartet auf Newsletter)

Nächster Schritt: Newsletter approven (Harvey hat Draft fertig in ~1h)
```
