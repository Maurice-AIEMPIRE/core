# 🌌 Pfeifer Core — Agents

> **Vier Agenten. Ein Bus. Ein Kern.**
> Aus dem Chaos der 7 Galaxia-Agents wurde ein fokussiertes Ökosystem.

---

## Der Kern

| Agent       | Rolle                      | Port  | Telegram |
|-------------|----------------------------|-------|----------|
| 🧠 **Jarvis**   | Personal Orchestrator      | 18791 | Topic 1  |
| 📡 **Hermes**   | Message Bus & Router       | 18790 | Topic 2  |
| 🦅 **OpenClaw** | Execution Engine           | 18789 | Topic 3  |
| ⚖️ **Harvey**   | Legal & Sales Counsel      | 18792 | Topic 4  |

---

## Quickstart

### Was zuerst lesen
1. **[ARCHITECTURE.md](./ARCHITECTURE.md)** — Big Picture, Daten-Flow, Modell-Routing
2. **[BUS.md](./BUS.md)** — Inter-Agent-Protokoll (Hermes API)
3. **[MIGRATION.md](./MIGRATION.md)** — Was passiert mit Galaxia / GPE-Core

### Pro Agent
Jeder Agent hat zwei Files:
- `SOUL.md` — Identität, Verhalten, Boundaries
- `config.json` — Modell, Ports, Capabilities

---

## Status

```
✅ Phase 1 — Setup        (DONE 2026-05-16)
   • /agents/ Struktur
   • SOULs + Configs
   • Task Router → Hermes Core4

⏳ Phase 2 — Hermes Live  (TODO)
⏳ Phase 3 — Jarvis Memory (TODO)
⏳ Phase 4 — Telegram 4-Topic (TODO)
⏳ Phase 5 — Galaxia Archive (TODO)
```

Siehe [MIGRATION.md § 5](./MIGRATION.md) für Detail-Plan.

---

## Eiserne Gesetze

1. **Niemand redet direkt mit niemandem** — Alles geht durch Hermes
2. **Jarvis ist Single-Point-of-Contact** für den User
3. **Skills gehören OpenClaw**, Legal-Skills gehören Harvey
4. **Memory ist Jarvis-only**
5. **Kein API-Geld** — Nur Ollama, nur Open Source
6. **Human-in-the-Loop** bei Geld-Entscheidungen >50€

---

## Datenfluss in 3 Sätzen

> Du redest mit **Jarvis**. Jarvis fragt **Hermes**, welcher Agent das kann.
> Hermes routet zu **OpenClaw** (Aktion) oder **Harvey** (Legal/Sales).
> Resultat geht zurück über Hermes an Jarvis, der dir antwortet.

---

## File-Layout

```
agents/
├── README.md          ← du bist hier
├── ARCHITECTURE.md    ← System-Overview
├── MIGRATION.md       ← Galaxia → Core4 Plan
├── BUS.md             ← Hermes Protokoll
├── jarvis/
│   ├── SOUL.md
│   └── config.json
├── hermes/
│   ├── SOUL.md
│   └── config.json
├── openclaw/
│   ├── SOUL.md        ← Verweis auf /openclaw/workspace/SOUL.md
│   └── config.json    ← Inherits /.openclaw/openclaw.json
└── harvey/
    ├── SOUL.md
    └── config.json
```

---

## Migration aus Galaxia (Friends-Crew)

Die 7 Friends-Agents (Monica, Dwight, Kelly, Pam, Ryan, Chandler, Ross)
wurden auf die 4 Core-Agents verteilt — siehe **[MIGRATION.md § 1](./MIGRATION.md)**.

**Keine Funktion geht verloren** — alles wird zu Skills unter den 4 neuen Kern-Agenten.
