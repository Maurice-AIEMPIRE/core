# 🌌 Pfeifer Empire — Control Plane

> **Verfassung:** Jarvis versteht. Hermes organisiert. OpenClaw handelt. Harvey spezialisiert. Memory erinnert. Verifier entscheidet.

**Repo-Pendant zu** `~/Empire/01_Control_Plane/` auf Maurices System.

---

## Die 4 Kern-Agenten

| Agent           | Rolle                       | Port  | Telegram | Verfassung                                  |
|-----------------|-----------------------------|-------|----------|---------------------------------------------|
| 🧠 **Jarvis**   | Personal Chief of Staff     | 18791 | Topic 1  | Erste Anlaufstelle, Ziele verstehen         |
| 📡 **Hermes**   | Goal/Kanban/Worker-OS       | 18790 | Topic 2  | Routing, Tracking, Handoff, Verifier        |
| 🦅 **OpenClaw** | Execution Engine            | 18789 | Topic 3  | Browser, Files, Skills, Automation          |
| ⚖️ **Harvey**   | Legal / Business / Sales    | 18792 | Topic 4  | Verträge, Kunden, Verhandlung               |

---

## Hierarchie (5 Ebenen)

```
Ebene 1: Interface          Telegram • CLI • Obsidian • Web Dashboard
Ebene 2: Orchestrierung     Jarvis → Hermes
Ebene 3: Ausführung         OpenClaw • Codex • Claude Code • Shell • Browser
Ebene 4: Spezialintelligenz Harvey • Trading (Safety Gate) • Research (read-only)
Ebene 5: Memory             Obsidian • Vector Core • Knowledge Graph • Reports
```

---

## Verzeichnis-Layout

```
control-plane/
├── README.md                   ← hier
├── SYSTEM_INVENTORY.md         ← alle Repos/Configs/Agenten/Skills
├── CORE_ARCHITECTURE.md        ← Big Picture, Daten-Flow, Modelle
├── AGENT_ROLES.md              ← klare Rollendefinition
├── MIGRATION_PLAN.md           ← Galaxia → Core4 Phasen
├── LEGACY_MAP.md               ← KEEP/MERGE/ARCHIVE/DELETE-Klassifikation
├── GOAL_STANDARD.md            ← /goal-Format und Verfasserregeln
├── TELEGRAM_TOPICS.md          ← Topic-Layout neu (4 statt 7)
│
├── jarvis/
│   ├── JARVIS.md               ← Identität + Verhalten
│   ├── config.json             ← Modell, Memory, Bus
│   ├── router.yaml             ← Intent → Agent Routing
│   └── memory_policy.md        ← Read/Write-Regeln
│
├── hermes/
│   ├── HERMES.md               ← Identität + Verhalten
│   ├── config.json             ← Routing-Table, Agenten
│   ├── BUS.md                  ← HTTP-Protokoll
│   ├── goal_engine.yaml        ← Goal-Card Schema
│   └── verifier_rules.md       ← Done-Checks pro Goal-Typ
│
├── openclaw/
│   ├── OPENCLAW.md             ← Identität + Verhalten
│   ├── config.json             ← Bus, Capabilities
│   ├── skills_index.md         ← 16 Skills katalogisiert
│   └── execution_policy.md     ← Safety, Audit, Confirmation
│
├── harvey/
│   ├── HARVEY.md               ← Identität + Verhalten
│   ├── config.json             ← Bus, Stripe, Modelle
│   ├── legal_policy.md         ← Rechtsstreit-Regeln
│   └── business_policy.md      ← Sales, Kunden, Produkte
│
├── shared-memory/              ← Shared Brain (Knowledge Graph + Vault)
├── skills/                     ← Skills-Verzeichnis (Referenz)
├── telegram/                   ← Telegram-Topic-Configs
├── goals/                      ← /goal-Cards (Kanban)
└── reports/                    ← Status-Reports von Hermes
```

---

## Die Verfassung in 7 Sätzen

1. **Niemand redet direkt mit niemandem.** Alles geht durch Hermes.
2. **Jarvis ist Single-Point-of-Contact für Maurice.**
3. **Skills gehören OpenClaw.** Legal-Skills gehören Harvey.
4. **Memory ist Jarvis-only.** Andere schreiben Events in KG.
5. **Kein API-Geld.** Nur Ollama, nur Open Source.
6. **Human-in-the-Loop** bei Geld-Entscheidungen >50€.
7. **Hermes verifiziert.** Kein "fertig" ohne Done-Check.

---

## Quickstart-Reihenfolge

1. [`SYSTEM_INVENTORY.md`](./SYSTEM_INVENTORY.md) — Was existiert
2. [`CORE_ARCHITECTURE.md`](./CORE_ARCHITECTURE.md) — Wie es zusammenpasst
3. [`AGENT_ROLES.md`](./AGENT_ROLES.md) — Wer macht was
4. [`MIGRATION_PLAN.md`](./MIGRATION_PLAN.md) — Wie wir dahin kommen
5. [`LEGACY_MAP.md`](./LEGACY_MAP.md) — Was passiert mit altem Zeug
6. [`GOAL_STANDARD.md`](./GOAL_STANDARD.md) — Wie `/goal` aussieht
7. [`hermes/BUS.md`](./hermes/BUS.md) — Inter-Agent-Protokoll
