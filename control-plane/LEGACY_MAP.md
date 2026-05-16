# Legacy Map — Klassifikation aller alten Komponenten

> **Stand:** 2026-05-16
> **Klassen:** KEEP | MERGE | ARCHIVE | DELETE_CANDIDATE
> **Regel Phase 1:** Keine Löschung. Nur Klassifikation + Plan.

---

## Klassifikations-Schema

| Klasse              | Bedeutung                                                        | Aktion                       |
|---------------------|------------------------------------------------------------------|------------------------------|
| `KEEP`              | Wird unverändert weiter genutzt                                  | Nichts tun                   |
| `MERGE`             | Funktional wertvoll, wird in Core4 als Skill/Komponente eingebaut | Code-Path migrieren          |
| `ARCHIVE`           | Veraltet, aber als Referenz behalten                             | Verschieben nach `legacy/`   |
| `DELETE_CANDIDATE`  | Wahrscheinlich obsolet, Löschung nach Review möglich             | Markieren, Owner-Review      |

---

## 1. Friends-Agenten (Galaxia 7-Crew)

| Agent     | Klasse  | Neue Heimat                          | Begründung                          |
|-----------|---------|--------------------------------------|-------------------------------------|
| Monica    | MERGE   | Jarvis Planning-Skill                | War CEO → wird Orchestration-Logic  |
| Dwight    | MERGE   | Jarvis Research-Skill **oder** Harvey Research-Skill | Web-Research wandert              |
| Kelly     | MERGE   | Harvey Sales/Content-Skill           | X-Posts für Kunden = Sales-Content  |
| Pam       | MERGE   | Harvey Communication-Skill           | Newsletter = Kunden-Kommunikation   |
| Ryan      | MERGE   | OpenClaw Code-Builder-Skill          | Bleibt Code/Templates → OpenClaw    |
| Chandler  | MERGE   | Harvey Sales + Trading-Safety-Skill  | Sales + Trading-Signale             |
| Ross      | MERGE   | Harvey Content-Skill (YouTube/SEO)   | Marketing-Content                   |

**Wichtig:** Sie werden **Skills, keine Personen**. Keine eigenen LLM-Threads mehr.

---

## 2. Galaxia-System-Files

| File                                          | Klasse  | Neue Heimat                              |
|-----------------------------------------------|---------|------------------------------------------|
| `/openclaw/workspace/GALAXIA_CORE.md`         | ARCHIVE | `legacy/galaxia/GALAXIA_CORE.md`         |
| `/openclaw/workspace/SOUL.md` (Galaxia OS)    | ARCHIVE | `legacy/galaxia/SOUL_galaxia.md`         |
| `/openclaw/workspace/AGENTS.md` (7-Crew)      | ARCHIVE | `legacy/galaxia/AGENTS_friends.md`       |
| `/openclaw/agents/{monica,...}/config.json`   | ARCHIVE | `legacy/galaxia/friends/`                |
| `/galaxia/galaxia-vector-core.py`             | MERGE   | → `control-plane/jarvis/memory/vector_core.py` |
| `/galaxia/scripts/`                           | KEEP    | Bleibt, ist Operations                   |
| `/scripts/launch-galaxia.sh`                  | ARCHIVE | `legacy/galaxia/`                        |

---

## 3. GPE-Core Komponenten

| File                                            | Klasse | Neue Heimat                       |
|-------------------------------------------------|--------|-----------------------------------|
| `/gpe-core/dispatcher/task_router.py`           | MERGE  | Wird Hermes Core (bereits adapted)|
| `/gpe-core/meta_supervisor_full.py`             | MERGE  | Wird Hermes Daemon-Manager        |
| `/gpe-core/analyzer/knowledge_graph_v2.py`      | KEEP   | Shared Brain (BlackHole KG)       |
| `/gpe-core/napoleon_core.py`                    | MERGE  | Komponente in Hermes (Goal-Engine)|
| `/gpe-core/health_check.py`                     | KEEP   | Operations                        |
| `/gpe-core/SKILL_INDEX.md`                      | MERGE  | → `control-plane/openclaw/skills_index.md` (Quelle) |
| `/gpe-core/resolver/RESOLVER.yaml`              | KEEP   | Intent-Resolver-Tabelle           |
| `/gpe-core/reviews/`                            | ARCHIVE| Phase 4                           |
| `/gpe-core/evolution/`                          | KEEP   | Wird Skill `self-improving-agent` |
| `/gpe-core/failures/`                           | KEEP   | Audit-Trail                       |
| `/gpe-core/briefs/`                             | ARCHIVE| Phase 4 — Reports gehen jetzt nach `control-plane/reports/` |
| `/gpe-core/gpe-core.service`                    | KEEP   | systemd Unit (umbenennen zu hermes.service in Phase 2) |
| `/gpe-core/start_all.sh`                        | MERGE  | Wird Hermes-Startup-Script        |

---

## 4. Telegram-Topics (Legacy 6 → Neu 4)

| Alte Topic-Datei                                | Klasse  | Neue Zuordnung                  |
|-------------------------------------------------|---------|---------------------------------|
| `/openclaw/telegram-topics/01-writing-content.md`| MERGE  | → OpenClaw Skill `content-engine` / Harvey Sales |
| `/openclaw/telegram-topics/02-research-insights.md`| MERGE | → Jarvis Research-Skill        |
| `/openclaw/telegram-topics/03-planning-strategy.md`| MERGE | → Jarvis Orchestration         |
| `/openclaw/telegram-topics/04-code-automation.md` | MERGE  | → OpenClaw Topic 3              |
| `/openclaw/telegram-topics/05-money-printer.md`   | MERGE  | → Harvey Topic 4                |
| `/openclaw/telegram-topics/06-video-youtube.md`   | MERGE  | → OpenClaw Skill `youtube-factory` |

→ Detail siehe [`TELEGRAM_TOPICS.md`](./TELEGRAM_TOPICS.md)

---

## 5. OpenClaw — was bleibt 1:1

| Pfad                                               | Klasse | Anmerkung                       |
|----------------------------------------------------|--------|---------------------------------|
| `/.openclaw/openclaw.json`                         | KEEP   | Master-Config (kompatibel)      |
| `/.openclaw/profiles.json`                         | KEEP   | Browser-Profile                 |
| `/openclaw/browser/`                               | KEEP   | Browser-Runtime                 |
| `/openclaw/workspace/skills/*/SKILL.md`            | KEEP   | 16 Skills aktiv                 |
| `/openclaw/workspace/TOOLS.md`                     | KEEP   | Wissensbasis                    |
| `/openclaw/workspace/USER.md`                      | KEEP   | Wissensbasis                    |
| `/openclaw/workspace/FREE-MODELS.md`               | KEEP   | Modell-Referenz                 |
| `/openclaw/workspace/HEARTBEAT.md`                 | KEEP   | Operations                      |
| `/openclaw/workspace/REVENUE-LOG.md`               | KEEP   | Harvey-Datenquelle              |
| `/openclaw/workspace/YOUTUBE_PIPELINE_SOP.md`      | KEEP   | OpenClaw-SOP                    |
| `/openclaw/workspace/THUMBNAIL_OPTIMIZER_SOP.md`   | KEEP   | OpenClaw-SOP                    |
| `/openclaw/workspace/BROWSER_INTEGRATION_MEGA.md`  | KEEP   | OpenClaw-Wissen                 |
| `/openclaw/security/`                              | KEEP   | Security-Checklist              |
| `/openclaw/memory/`                                | KEEP   | OpenClaw-eigene Memory          |
| `/openclaw/cron/`                                  | KEEP   | Scheduled Tasks                 |

---

## 6. Harvey-Komponenten (already wired)

| Pfad                                                  | Klasse | Anmerkung                |
|-------------------------------------------------------|--------|--------------------------|
| `/integrations/telegram/src/legal_review.ts`          | KEEP   | Harvey-Core              |
| `/integrations/telegram/src/stripe_webhook.ts`        | KEEP   | Harvey-Stripe            |
| `/integrations/telegram/src/blackhole_client.ts`      | KEEP   | KG-Context               |
| `/integrations/telegram/src/legal_review.ts` Persona  | KEEP   | `BOT_PERSONA=harvey`     |

---

## 7. Repo-Basis (RedPlanetHQ/core Original)

| Pfad                                       | Klasse | Anmerkung                          |
|--------------------------------------------|--------|------------------------------------|
| `/apps/webapp/`                            | KEEP   | CORE Memory Engine (Jarvis-Backend)|
| `/packages/sdk/`                           | KEEP   | CORE SDK                           |
| `/packages/database/`                      | KEEP   | Prisma-Schema (Memory-Storage)     |
| `/packages/cli/`                           | KEEP   | CORE CLI                           |
| `/packages/providers/`                     | KEEP   | LLM Provider Abstraction           |
| `/packages/mcp-proxy/`                     | KEEP   | MCP-Server-Proxy                   |
| `/packages/hook-utils/`                    | KEEP   | Hook-System                        |
| `/packages/types/`                         | KEEP   | TypeScript Types                   |
| `/packages/emails/`                        | KEEP   | E-Mail Templates                   |
| `/turbo.json` + `/pnpm-workspace.yaml`     | KEEP   | Monorepo-Config                    |

---

## 8. Branches (165 auf GitHub) — Klassifikation pending

Eine vollständige Klassifikation aller 165 Branches kommt in **Phase 5**.
Heuristik schon erkennbar:

| Branch-Prefix                          | Wahrscheinliche Klasse |
|----------------------------------------|------------------------|
| `claude/fix-mac-*` (mehrere Versionen) | DELETE_CANDIDATE (Duplikate) |
| `claude/fix-mac-performance-*` (4×)    | DELETE_CANDIDATE (3 Duplikate, 1 keep) |
| `claude/openclaw-*`                    | MERGE (in main)        |
| `claude/galaxia-*`, `claude/imperium-*`| ARCHIVE                |
| `harshith/*` (Kollege?)                | KEEP (read-only)       |
| `manik/*`, `manoj/*` (Kollegen?)       | KEEP (read-only)       |
| `bug/*`, `fix-*`                       | KEEP (Pflege)          |
| `bert-docker`, `gmail*`, `space-v*`    | ARCHIVE (alt)          |

**Datenquelle:** `branches.json` (committed)

---

## 9. Top-level "Mac Optimizer" Artefakte

| Pfad                                       | Klasse  | Anmerkung                       |
|--------------------------------------------|---------|---------------------------------|
| `/PRODUCT.md` (Mac Optimizer)              | KEEP    | Product-Spec                    |
| `/scripts/mac-optimizer/`                  | KEEP    | Produkt-Code                    |
| `/Formula/`                                | KEEP    | Homebrew-Formulae               |
| `/auto-sales-automation.sh`                | KEEP    | Sales-Automation                |
| `/QUICK_AUTOMATION.md`                     | MERGE   | Inhalt → `control-plane/reports/` als Snapshot |
| `/pr-body.md`                              | ARCHIVE | Temporäre Datei                 |

---

## 10. Roadmap

| Phase | Aktion                                                   |
|-------|----------------------------------------------------------|
| **1** | Klassifikation (DIESES Dokument)                         |
| **2** | `MERGE`-Items in `control-plane/` einbauen               |
| **3** | `ARCHIVE`-Items in `legacy/` verschieben (mit git mv)    |
| **4** | `DELETE_CANDIDATE` Review mit Maurice — pro Item OK/NEIN |
| **5** | Branches durchgehen und auch dort klassifizieren         |

---

## 11. Verbote in Phase 1 (eiserne Regel)

🚫 **Keine Datei löschen**
🚫 **Keine Branch löschen**
🚫 **Keine produktiven Services anhalten**
🚫 **Keine Secrets ausgeben**
🚫 **Keine Live-Trading-Systeme verändern**
🚫 **Keine Rechtsstreit-Dokumente verändern**

✅ **Klassifizieren, dokumentieren, planen.**
