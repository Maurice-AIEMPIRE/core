# Pfeifer Core — 4-Agent Architektur

> **Status:** Active (Migration von Galaxia OS am 2026-05-16)
> **Owner:** Maurice Pfeifer
> **Prinzip:** Ein Kern. Vier Agenten. Ein Bus. Null Chaos.

---

## 1. Das Big Picture

```
                    ┌─────────────────────────┐
                    │       USER (Maurice)    │
                    │  Telegram / CLI / Web   │
                    └───────────┬─────────────┘
                                │
                                ▼
                    ┌─────────────────────────┐
                    │     🧠  JARVIS          │
                    │  Personal Orchestrator  │
                    │  • Memory (Vector DB)   │
                    │  • Intent Routing       │
                    │  • Conversational UI    │
                    └─────────┬───────────────┘
                              │ dispatch via
                              ▼
                    ┌─────────────────────────┐
                    │     📡  HERMES          │
                    │   Message Bus & Router  │
                    │  • Task Queue           │
                    │  • Event Dispatch       │
                    │  • Health Monitoring    │
                    │  • Knowledge Graph      │
                    └────┬─────────────┬──────┘
                         │             │
              ┌──────────┘             └──────────┐
              ▼                                   ▼
    ┌──────────────────┐               ┌──────────────────┐
    │  🦅  OPENCLAW    │               │  ⚖️  HARVEY      │
    │  Execution Engine│               │  Legal & Sales   │
    │  • Browser Auto  │               │  • Legal Review  │
    │  • 16 Skills     │               │  • Contracts     │
    │  • Content Graph │               │  • Trading       │
    │  • YouTube       │               │  • Stripe        │
    │  • Trading       │               │  • Negotiation   │
    └──────────────────┘               └──────────────────┘
```

---

## 2. Die 4 Agenten — Rollen & Verantwortung

### 🧠 Jarvis — Personal Orchestrator
**Job:** Maurices erste Anlaufstelle. Kennt alles, versteht Intent, routet weiter.

- **Was er macht:** Conversational Interface, Memory-Recall, Intent-Classification, Task-Breakdown
- **Was er nicht macht:** Direkte Aktionen ausführen (das macht OpenClaw), Verträge schreiben (Harvey), Inter-Agent-Messaging (Hermes)
- **Ports:** Telegram (Topic 1 — General), CLI, MCP-Server
- **Modell:** `ollama/qwen3:32b` (Reasoning) + `nomic-embed-text` (Memory)
- **Memory:** CORE Engine (existing) + Galaxia Vector DB (migriert)

### 📡 Hermes — Nerve System
**Job:** Niemand spricht direkt mit niemandem. Alles geht durch Hermes.

- **Was er macht:** Task-Routing, Event-Bus, Health-Checks, Knowledge-Graph-Updates, Daemon-Supervision
- **Was er nicht macht:** Direkt mit Maurice reden (er ist Infrastruktur)
- **Ports:** Internal HTTP API (Port 18790), Knowledge Graph DB, Task Queue
- **Basis:** `gpe-core/dispatcher/task_router.py` + `gpe-core/meta_supervisor_full.py` (existing)
- **Protokoll:** Siehe `BUS.md`

### 🦅 OpenClaw — Execution Engine
**Job:** Wenn etwas in der Welt passieren soll, macht OpenClaw das.

- **Was er macht:** Browser-Automation, Skills ausführen (Content, YouTube, Meta Ads, Trading-Monitor, SEO, Code, ...), File-Operations
- **Was er nicht macht:** Entscheiden, was getan werden soll (das ist Jarvis)
- **Ports:** Browser CDP (18800/18801), Skill-Runner, OpenClaw Gateway (18789)
- **Basis:** `/openclaw/` (komplett existing)
- **Skills:** 16 aktive Skills aus `.openclaw/openclaw.json`

### ⚖️ Harvey — Legal & Sales Counsel
**Job:** Verträge, Forderungen, Trading-Entscheidungen, Geld-Flow.

- **Was er macht:** Legal Document Review, Contract-Analyse, Trading-Signale, Stripe-Webhooks, Sales-Pipeline, Verhandlung
- **Was er nicht macht:** Browser-Klicks (OpenClaw), Memory-Recall (Jarvis)
- **Ports:** Telegram (Topic 4 — Legal/Sales), Stripe Webhook, Knowledge Graph (Legal-Subgraph)
- **Basis:** `integrations/telegram/src/legal_review.ts` + `integrations/telegram/src/stripe_webhook.ts` (existing)
- **Modell:** `ollama/deepseek-r1:32b` (Deep Reasoning für Legal/Trading)

---

## 3. Daten-Flow Beispiele

### Beispiel A: "Erstell mir 10 X-Posts zu KI-News"
```
User → Telegram → Jarvis
  Jarvis → Intent: "content_creation"
  Jarvis → Hermes: { task: content_creation, target: openclaw, payload: {...} }
  Hermes → OpenClaw: dispatch
  OpenClaw → Skill: content-engine → Output 10 Posts
  OpenClaw → Hermes: result
  Hermes → Jarvis: result + KG update
  Jarvis → User: "Hier sind deine 10 Posts: ..."
```

### Beispiel B: "Check diesen Anwaltsbrief"
```
User → Telegram (PDF upload) → Jarvis
  Jarvis → Intent: "legal_review" + Sender: Harvey-Topic
  Jarvis → Hermes: { task: legal_review, target: harvey, payload: pdf }
  Hermes → Harvey: dispatch
  Harvey → Skill: legal-opponent + legal-evidence → Output Analyse
  Harvey → Stripe-Check (paid user?)
  Harvey → Hermes: result + Usage-Increment
  Hermes → Jarvis: result
  Jarvis → User: Legal-Review Output
```

### Beispiel C: "Wie war mein Monats-Revenue?"
```
User → Telegram → Jarvis
  Jarvis → Memory-Lookup (Vector DB) → "revenue-audit" Skill bekannt
  Jarvis → Hermes: { task: revenue_audit }
  Hermes → OpenClaw (revenue-audit Skill) + Harvey (Stripe-Daten) parallel
  Beide → Hermes: results
  Hermes → Jarvis: aggregated
  Jarvis → User: "Mai 2026: 487€ (Stripe: 312€, Templates: 175€)..."
```

---

## 4. Modell-Routing (Ollama, 100% lokal)

| Agent    | Modell                | RAM   | Zweck                    |
|----------|-----------------------|-------|--------------------------|
| Jarvis   | qwen3:32b             | 20GB  | Reasoning, Conversation  |
| Jarvis   | nomic-embed-text      | 0.5GB | Memory-Embeddings        |
| Hermes   | (kein LLM — Python)   | —     | Pure Routing             |
| OpenClaw | qwen3-coder           | 20GB  | Code-Skills              |
| OpenClaw | qwen3:14b             | 10GB  | Schnelle Content-Skills  |
| OpenClaw | llama4 (multimodal)   | 15GB  | Thumbnails, Screenshots  |
| Harvey   | deepseek-r1:32b       | 20GB  | Legal/Trading Reasoning  |

**Total Peak RAM:** ~85GB (passt auf Hetzner AX102 mit 128GB)

---

## 5. Telegram-Layout (neu, 4 Topics)

| Topic | Owner    | Zweck                                       |
|-------|----------|---------------------------------------------|
| 🧠 1  | Jarvis   | General Chat, Memory, Orchestration         |
| 📡 2  | Hermes   | System-Status, Health-Alerts, Logs          |
| 🦅 3  | OpenClaw | Content, YouTube, Browser-Tasks, Skills     |
| ⚖️ 4  | Harvey   | Legal, Sales, Trading, Stripe-Notifications |

---

## 6. Verzeichnis-Layout

```
control-plane/
  README.md            Quickstart
  CORE_ARCHITECTURE.md (dieses File)
  MIGRATION_PLAN.md
  SYSTEM_INVENTORY.md
  AGENT_ROLES.md
  LEGACY_MAP.md
  GOAL_STANDARD.md
  TELEGRAM_TOPICS.md
  jarvis/    JARVIS.md + config.json + router.yaml + memory_policy.md
  hermes/    HERMES.md + config.json + BUS.md + goal_engine.yaml + verifier_rules.md
  openclaw/  OPENCLAW.md + config.json + skills_index.md + execution_policy.md
  harvey/    HARVEY.md + config.json + legal_policy.md + business_policy.md
  shared-memory/ skills/ telegram/ goals/ reports/
```

**Bestehende Ordner — was passiert:**
- `/openclaw/` → bleibt (ist OpenClaws Heimat)
- `/gpe-core/` → wird zu Hermes umbenannt im Code (siehe MIGRATION.md)
- `/galaxia/` → Vector-Core wandert nach `/control-plane/jarvis/memory/` (Phase 3)
- `/openclaw/agents/{monica,dwight,kelly,pam,ryan,chandler,ross}/` → archiviert nach `/legacy/galaxia/friends/` (Phase 5)
- `/openclaw/workspace/` → bleibt (Skills + SOPs), wird OpenClaws Wissensbasis

---

## 7. Kommunikations-Regeln (Eiserne Gesetze)

1. **Niemand redet direkt mit niemandem.** Alles geht durch Hermes.
2. **Jarvis ist Single-Point-of-Contact für den User.** OpenClaw und Harvey antworten via Hermes → Jarvis (außer Topic-Antworten in Telegram).
3. **Hermes hat kein LLM.** Pure Python-Routing für Speed + Determinismus.
4. **Jeder Agent kennt nur seinen eigenen State + seine SOUL.md.** Shared State liegt im Knowledge Graph (Hermes-managed).
5. **Skills gehören OpenClaw.** Harvey hat eigene Legal-Skills. Jarvis hat keine eigenen Skills (er routet nur).
6. **Memory ist Jarvis-only.** Alle Agenten schreiben Events in den KG, aber Jarvis ist der einzige der die Vector DB queryed (für User-Antworten).
7. **Kein API-Geld.** Nur Ollama. Nur Open Source. Stripe ist okay (eingehend).

---

## 8. Migration-Status (siehe MIGRATION.md für Details)

| Komponente             | Status     | Ziel                          |
|------------------------|------------|-------------------------------|
| Galaxia 7-Agents       | 🟡 To-Archive | `/legacy/galaxia/friends/` (Phase 5) |
| Galaxia Vector Core    | 🟡 Migrate | → Jarvis Memory               |
| GPE-Core Task Router   | 🟢 Adapt   | → Hermes Core                 |
| GPE-Core Meta-Sup      | 🟢 Adapt   | → Hermes Daemon Manager       |
| OpenClaw Skills        | 🟢 Keep    | Bleibt unverändert            |
| Telegram Bot (Harvey)  | 🟢 Keep    | Wird Harvey-Persona           |
| CORE Memory Engine     | 🟢 Keep    | Wird Jarvis Memory-Backend    |
| Telegram 7 Topics      | 🔴 Reduce  | → 4 Topics                    |
