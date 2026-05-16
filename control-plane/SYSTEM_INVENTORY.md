# System-Inventur — Stand 2026-05-16

> **Zweck:** Vollständige Auflistung aller relevanten Komponenten im Maurice-AIEMPIRE/core Repo.
> **Methode:** Direkte File-Inspektion auf Branch `claude/export-branches-kYh7h`.

---

## 1. Repositories & Submodules

| Pfad        | Typ        | Status   | Anmerkung                                            |
|-------------|------------|----------|------------------------------------------------------|
| `/`         | Hauptrepo  | active   | Maurice-AIEMPIRE/core (Fork von RedPlanetHQ/core)    |
| `/core`     | Submodule  | active   | Commit `7d5e96e1`, ungenutzt initialisiert (Pointer) |
| `/apps/webapp` | App-Workspace | active | CORE Memory Engine UI                              |
| `/packages/*` | Workspace | active | sdk, types, database, cli, providers, hook-utils, mcp-proxy, emails |

---

## 2. Configs

| Pfad                                | Zweck                                        |
|-------------------------------------|----------------------------------------------|
| `/.openclaw/openclaw.json`          | OpenClaw Master-Config (Modell, Browser, 16 Skills, Telegram, Memory) |
| `/.openclaw/profiles.json`          | 3 Browser-Profile: openclaw / work / chrome-extension |
| `/.openclaw/integrations.json`      | Telegram Bot-ID, Auto-Sync                   |
| `/.openclaw/pairing.json`           | Service-Pairing-Register                     |
| `/.env.example`                     | Template für Secrets (Stripe, Telegram, etc) |
| `/.configs/*`                       | Workspace-spezifische Configs                |
| `/.github/*`                        | GitHub Actions / Workflows                   |
| `/.claude-plugin/*`                 | Claude Code Plugin-Config                    |
| `/.claude.json`                     | Claude Session-Config                        |
| `/package.json` + `/turbo.json`     | Monorepo (pnpm + turbo)                      |

---

## 3. Agenten — Bestandsaufnahme

### 3.1 Aktuelle 4-Core-Welt (NEU)

| Agent     | SOUL                              | Config                              | Status         |
|-----------|-----------------------------------|-------------------------------------|----------------|
| Jarvis    | `control-plane/jarvis/JARVIS.md`  | `control-plane/jarvis/config.json`  | Specced (Phase 1) |
| Hermes    | `control-plane/hermes/HERMES.md`  | `control-plane/hermes/config.json`  | Specced + Code-Basis im Router |
| OpenClaw  | `control-plane/openclaw/OPENCLAW.md` | `control-plane/openclaw/config.json` | Running (existing) |
| Harvey    | `control-plane/harvey/HARVEY.md`  | `control-plane/harvey/config.json`  | Specced + Code-Basis in Telegram |

### 3.2 Galaxia 7-Agents Friends-Crew (LEGACY)

| Agent     | Config                                    | Status                |
|-----------|-------------------------------------------|-----------------------|
| Monica    | `/openclaw/agents/monica/config.json`     | Legacy — Skill in Jarvis |
| Dwight    | `/openclaw/agents/dwight/config.json`     | Legacy — Skill in Jarvis/Harvey |
| Kelly     | `/openclaw/agents/kelly/`                 | Legacy — Skill in Harvey |
| Pam       | `/openclaw/agents/pam/`                   | Legacy — Skill in Harvey |
| Ryan      | `/openclaw/agents/ryan/`                  | Legacy — Skill in OpenClaw |
| Chandler  | `/openclaw/agents/chandler/`              | Legacy — Skill in Harvey |
| Ross      | `/openclaw/agents/ross/`                  | Legacy — Skill in Harvey |

### 3.3 GPE-Core Multi-Agent-Layer

| Komponente              | Pfad                                              | Status             |
|-------------------------|---------------------------------------------------|--------------------|
| Task Router             | `/gpe-core/dispatcher/task_router.py`             | ✅ migriert → Hermes Core |
| Meta-Supervisor         | `/gpe-core/meta_supervisor_full.py`               | 🔄 adapt → Hermes Daemon-Manager |
| Knowledge Graph (BlackHole) | `/gpe-core/analyzer/knowledge_graph_v2.py`    | ✅ keep (shared brain) |
| Napoleon Core           | `/gpe-core/napoleon_core.py`                      | Legacy — wird Hermes-Komponente |
| Health Check            | `/gpe-core/health_check.py`                       | ✅ keep |
| Skill Index             | `/gpe-core/SKILL_INDEX.md`                        | ✅ keep (Source für skills_index) |
| Resolver/Reviews        | `/gpe-core/{resolver,reviews,evolution,failures}/`| Legacy — eindampfen oder behalten |
| Service-File            | `/gpe-core/gpe-core.service`                      | ✅ keep (systemd Unit) |

---

## 4. Skills — Bestandsaufnahme

### 4.1 OpenClaw Skills (16, aktiv in `.openclaw/openclaw.json`)

| Skill                       | Pfad in Workspace                                  | Domain   |
|-----------------------------|----------------------------------------------------|----------|
| `pi-coder`                  | `/openclaw/workspace/skills/pi-coder/SKILL.md`     | Code     |
| `content-engine`            | `/openclaw/workspace/skills/content-engine/SKILL.md` | Content  |
| `youtube-factory`           | (referenced)                                        | YouTube  |
| `thumbnail-optimizer`       | (referenced)                                        | Visual   |
| `youtube-studio-uploader`   | `/openclaw/workspace/skills/youtube-studio-uploader/SKILL.md` | YouTube |
| `x-twitter-browser`         | `/openclaw/workspace/skills/x-twitter-browser/SKILL.md` | Content |
| `meta-ads`                  | `/openclaw/workspace/skills/meta-ads/SKILL.md`     | Ads      |
| `seo-ranker`                | `/openclaw/workspace/skills/seo-ranker/SKILL.md`   | SEO      |
| `trading-monitor`           | `/openclaw/workspace/skills/trading-monitor/SKILL.md` | Trading |
| `agent-earner`              | (referenced)                                        | Sales    |
| `bookkeeper`                | (referenced)                                        | Revenue  |
| `agent-team-orchestration`  | (referenced)                                        | Meta     |
| `self-improving-agent`      | (referenced)                                        | Evolution |
| `laser-focus`               | (referenced)                                        | Discipline |
| `agent-memory-ultimate`     | (referenced)                                        | Memory   |
| `toggle-context`            | `/openclaw/workspace/skills/toggle-context/SKILL.md` | Context |
| `server-optimizer`          | `/openclaw/workspace/skills/server-optimizer/SKILL.md` | Ops     |

### 4.2 GPE-Core Skills (18 aktiv in SKILL_INDEX.md)

| Domain        | Skills                                                                  |
|---------------|-------------------------------------------------------------------------|
| Legal         | legal-opponent, legal-settlement, legal-claims, legal-evidence, legal-warroom, legal-consistency |
| Trading       | risk-monitor                                                            |
| Empire/Revenue| revenue-audit, sales-leadgen                                            |
| Evolution     | evolution-loop, repo-scout, repo-analyzer, self-patcher                 |
| System        | nucleus, data-ops, system-audit                                         |

### 4.3 Content Skill Graph

| Pfad                                          | Status |
|-----------------------------------------------|--------|
| `/skills/content-graph/index.md`              | active |
| `/skills/content-graph/engine/scheduling.md`  | active |
| `/skills/SKILL_content_skill_graph.md`        | active |
| `/skills/agents/SOUL.md`                      | Legacy (OpenClaw Master-Soul) |

---

## 5. Telegram-Komponenten

| Pfad                                                  | Zweck                              |
|-------------------------------------------------------|------------------------------------|
| `/integrations/telegram/src/bot.ts`                   | Haupt-Bot (Persona-Switch via env) |
| `/integrations/telegram/src/legal_review.ts`          | Harvey-Logic (PDF, Stripe, Paywall)|
| `/integrations/telegram/src/stripe_webhook.ts`        | Eingehende Payments                |
| `/integrations/telegram/src/chat.ts`                  | Conversation-Handling              |
| `/integrations/telegram/src/blackhole_client.ts`      | KG-Context-Builder                 |
| `/openclaw/telegram-topics/01-writing-content.md`     | Topic 1 (Legacy)                   |
| `/openclaw/telegram-topics/02-research-insights.md`   | Topic 2 (Legacy)                   |
| `/openclaw/telegram-topics/03-planning-strategy.md`   | Topic 3 (Legacy)                   |
| `/openclaw/telegram-topics/04-code-automation.md`     | Topic 4 (Legacy)                   |
| `/openclaw/telegram-topics/05-money-printer.md`       | Topic 5 (Legacy)                   |
| `/openclaw/telegram-topics/06-video-youtube.md`       | Topic 6 (Legacy)                   |
| `/scripts/setup-telegram-bot.sh`                      | Setup-Script                       |

---

## 6. Memory / Vector / Knowledge-Graph

| Komponente               | Pfad                                              | Status        |
|--------------------------|---------------------------------------------------|---------------|
| CORE Memory Engine       | `/apps/webapp/` + `/packages/database/`           | active (Repo-Basis) |
| Galaxia Vector Core      | `/galaxia/galaxia-vector-core.py`                 | Wird Jarvis Memory |
| Galaxia Vector DB        | `/root/galaxia/vector_db` (server-side)           | bleibt        |
| BlackHole Knowledge Graph| `/gpe-core/analyzer/knowledge_graph_v2.py`        | shared brain  |
| KG DB-Pfad               | `/root/.openclaw/knowledge_graph.db`              | active        |
| Vector Embed-Modell      | `nomic-embed-text` (Ollama)                       | active        |
| MCP-Proxy                | `/packages/mcp-proxy/`                            | active        |
| Obsidian Memory Integration | `/integrations/obsidian-memory/`               | active        |

---

## 7. Integrationen (read-write Sysytem boundary)

| Service            | Pfad                                | Zweck                  |
|--------------------|-------------------------------------|------------------------|
| Telegram           | `/integrations/telegram/`           | Hauptkanal             |
| GitHub             | `/integrations/github/`             | Repo-Operations        |
| GitHub Analytics   | `/integrations/github-analytics/`   | Stats / Reports        |
| Gmail              | `/integrations/gmail/`              | E-Mail                 |
| Google Calendar    | `/integrations/google-calendar/`    | Termine                |
| Google Docs/Sheets/Tasks | `/integrations/google-{docs,sheets,tasks}/` | Office     |
| Linear             | `/integrations/linear/`             | Project Management     |
| Notion             | `/integrations/notion/`             | Wiki                   |
| Slack              | `/integrations/slack/`              | Team-Chat              |
| Discord            | `/integrations/discord/`            | Community              |
| HubSpot            | `/integrations/hubspot/`            | CRM                    |
| Cal.com            | `/integrations/cal_com/`            | Scheduling             |
| Todoist            | `/integrations/todoist/`            | Tasks                  |
| Zoho Mail          | `/integrations/zoho-mail/`          | E-Mail (alternativ)    |
| Obsidian-Memory    | `/integrations/obsidian-memory/`    | Vault-Sync             |

---

## 8. Apps / Dashboards / Services

| Komponente            | Pfad                                      | Status   |
|-----------------------|-------------------------------------------|----------|
| Webapp (CORE UI)      | `/apps/webapp/`                           | active   |
| Dashboard (Python)    | `/dashboard/dashboard.py`                 | active   |
| Hosting (Docker)      | `/hosting/docker/`                        | active   |
| Server-Side Daemon    | `/server/{config,scripts,systemd}/`       | active   |
| Galaxia Launch Script | `/scripts/launch-galaxia.sh`              | Legacy   |
| Mac Optimizer         | `/scripts/mac-optimizer/`                 | Product (Gumroad) |
| Server Optimizer      | `/scripts/server-optimizer/`              | active   |
| ClawMaster Setup      | `/scripts/setup-clawmaster.sh`            | active   |
| Auto-Sales            | `/auto-sales-automation.sh`               | active   |

---

## 9. Galaxia-Bestandteile (wiederverwendbar)

| Galaxia-Komponente                 | Pfad                                          | Wiederverwendung           |
|------------------------------------|-----------------------------------------------|----------------------------|
| Vector Core                        | `/galaxia/galaxia-vector-core.py`             | → Jarvis Memory Backend    |
| Vector DB                          | `/root/galaxia/vector_db`                     | → Jarvis Memory Storage    |
| GALAXIA_CORE.md (DNA)              | `/openclaw/workspace/GALAXIA_CORE.md`         | → Inspirations-Quelle, dann archivieren |
| SOUL.md (PFEIFER GALAXIA OS)       | `/openclaw/workspace/SOUL.md`                 | → Legacy (kosmische Regeln teilweise übernommen in JARVIS.md) |
| AGENTS.md (7-Agent Roster)         | `/openclaw/workspace/AGENTS.md`               | → LEGACY_MAP Quelle        |
| TOOLS.md / USER.md / FREE-MODELS.md | `/openclaw/workspace/*.md`                   | ✅ keep (OpenClaw Wissensbasis) |
| CONTEXT_SNAPSHOT.md                | `/openclaw/workspace/CONTEXT_SNAPSHOT.md`     | ✅ keep                    |
| REVENUE-LOG.md                     | `/openclaw/workspace/REVENUE-LOG.md`          | ✅ keep (Harvey-Quelle)    |
| HEARTBEAT.md                       | `/openclaw/workspace/HEARTBEAT.md`            | ✅ keep                    |
| YOUTUBE_PIPELINE_SOP.md            | `/openclaw/workspace/YOUTUBE_PIPELINE_SOP.md` | ✅ keep (OpenClaw)         |
| THUMBNAIL_OPTIMIZER_SOP.md         | `/openclaw/workspace/THUMBNAIL_OPTIMIZER_SOP.md`| ✅ keep                  |
| BROWSER_INTEGRATION_MEGA.md        | `/openclaw/workspace/BROWSER_INTEGRATION_MEGA.md`| ✅ keep (OpenClaw)        |
| 16 Skills                          | `/openclaw/workspace/skills/`                 | ✅ keep — bleibt OpenClaw  |
| Telegram Topics 1-6                | `/openclaw/telegram-topics/`                  | 🔄 auf 4 Topics reduzieren |
| Friends-Agent-Configs              | `/openclaw/agents/{monica,...}/`              | → Archive nach Phase 5     |

---

## 10. Compute Layer

| Komponente          | Wo                                | Zweck                          |
|---------------------|-----------------------------------|--------------------------------|
| Ollama              | `localhost:11434`                 | LLM-Inferenz (100% lokal)     |
| Hetzner AX102       | 65.21.203.174                     | 128GB RAM Server               |
| Mac Mini (MinivonMaurice) | local                       | Browser-Gateway, OpenClaw Local|
| Docker              | `/docker/` + `/hosting/docker/`   | Container-Layer                |
| Neo4j               | `/docker/Dockerfile.neo4j`        | KG-Backend (optional)          |

---

## 11. Modelle (Ollama)

| Modell              | RAM   | Verwendung                                   |
|---------------------|-------|----------------------------------------------|
| `qwen3:32b`         | 20GB  | Jarvis Reasoning, Long-Form Content          |
| `qwen3-coder`       | 20GB  | OpenClaw Code-Skills                         |
| `deepseek-r1:32b`   | 20GB  | Harvey Deep Reasoning (Legal/Trading)        |
| `qwen3:14b`         | 10GB  | OpenClaw Schnell-Content                     |
| `llama4` (multimodal)| 15GB | Thumbnails, Screenshots                      |
| `nomic-embed-text`  | 0.5GB | Vector-Embeddings (Jarvis Memory)            |

**Peak RAM:** ~85GB von 128GB → 33% Buffer

---

## 12. Was schon JETZT funktioniert (Production-Pfade nicht anfassen)

- ✅ Telegram Bot (`integrations/telegram/`) — läuft
- ✅ Stripe Webhook + Legal Review (Harvey-Persona) — läuft
- ✅ OpenClaw Browser-Profile — läuft
- ✅ OpenClaw 16 Skills — definiert + ausführbar
- ✅ CORE Memory Engine (Webapp) — läuft
- ✅ Ollama-Setup — läuft
- ✅ Knowledge Graph (BlackHole) — läuft
- ✅ Meta-Supervisor (PID-tracking) — läuft

**→ Diese Pfade werden in Phase 1 NICHT angefasst.**
