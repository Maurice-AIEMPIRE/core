# Goals — Kanban für den Pfeifer Core

> **Vollständiges Schema:** Siehe `/control-plane/GOAL_STANDARD.md`
> **Engine-Config:** Siehe `/control-plane/hermes/goal_engine.yaml`
> **Verifier-Rules:** Siehe `/control-plane/hermes/verifier_rules.md`

---

## Verzeichnis-Layout

```
goals/
├── README.md              ← hier
├── INDEX.md               ← Live-Kanban-View (von Hermes generiert)
├── _templates/            ← Goal-Templates (build, publish, legal_review, ...)
│   └── (Phase 2 anlegen)
├── active/                ← Goals in todo / in_progress / review / blocked
│   └── (leer)
└── archive/               ← Done + Cancelled Goals
    └── (leer)
```

---

## Lifecycle in Kürze

```
Jarvis erstellt Goal-Card  →  active/goal_<ulid>.yaml
        ↓
Hermes routet zu Owner-Agent
        ↓
Owner arbeitet, ändert Status: in_progress → review
        ↓
Hermes Verifier läuft (Done-Checks)
        ↓
Pass:  active/ → archive/{YYYY-MM}/
Fail:  bleibt review, Owner muss fixen
```

---

## Aktuelle Goals

Status: **0 aktive Goals** (System ist Phase 1 — Doku only)

Erste Goals kommen in Phase 2, wenn Hermes scharfgeschaltet wird.

---

## Wie ein Goal angelegt wird

1. Maurice schreibt in Topic 1: "Mac Optimizer launchen"
2. Jarvis klassifiziert Intent → `publish` mit Sub-Goals
3. Jarvis generiert Goal-Card YAML (siehe GOAL_STANDARD.md § 2)
4. Speichert nach `active/goal_<ulid>.yaml`
5. Übergibt an Hermes via `POST http://127.0.0.1:18790/dispatch`
6. Hermes routet, tracked, verifiziert
7. Bei `done` → `archive/{YYYY-MM}/`
