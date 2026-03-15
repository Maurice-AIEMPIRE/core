# Server System Audit — Maurice-AIEMPIRE/core
**Datum:** 15. März 2026
**Branch:** `claude/server-system-audit-v2Rgo`
**Durchgeführt von:** Claude AI (automatisiert)

---

## 1. Server Hardware & Betriebssystem

| Komponente | Details |
|---|---|
| **Hostname** | hetzner-ax102 |
| **IP** | 65.21.203.174 |
| **CPU** | AMD Ryzen 9 7950X3D (16 Kerne / 32 Threads) |
| **RAM** | 128 GB DDR5 ECC |
| **Storage** | 2× 1.92 TB NVMe SSD (RAID-fähig) |
| **OS** | Ubuntu 22.04 LTS |
| **Kernel** | Linux 6.18.5 |
| **Laufzeit** | Frisch gestartet (Audit-Zeitpunkt) |

**Bewertung:** ✅ Sehr leistungsfähige Hardware, ideal für multi-parallele LLM-Inferenz. ECC RAM schützt vor Speicherfehlern bei Dauerbetrieb.

---

## 2. Projekt-Architektur

### 2.1 Monorepo-Struktur

```
core/                          # Root (pnpm Monorepo, Turbo)
├── apps/
│   └── webapp/                # Remix-basierte Web-App (Port 3033)
├── packages/
│   ├── database/              # Prisma ORM (PostgreSQL)
│   ├── sdk/                   # @redplanethq/sdk
│   ├── types/                 # Shared TypeScript Types
│   ├── emails/                # E-Mail-Vorlagen
│   ├── hook-utils/            # Webhook-Utilities
│   ├── mcp-proxy/             # MCP Server Proxy
│   └── providers/             # AI Provider Abstraktionen
├── integrations/              # 15+ Plattform-Integrationen
├── openclaw/                  # AI Agent System (6 Agenten)
├── server/                    # Server-Konfiguration & Scripts
├── docker/                    # Docker-Deployment
├── docs/                      # Dokumentation
├── galaxia/                   # Galaxia Vector Core
└── dashboard/                 # Streamlit Monitoring Dashboard
```

### 2.2 Tech Stack

| Schicht | Technologie | Version |
|---|---|---|
| Package Manager | pnpm | 9.0.0 |
| Build System | Turbo | 2.5.3 |
| Backend | Remix (Node.js) | - |
| ORM | Prisma | 5.4.1 |
| Datenbank | PostgreSQL | 5432 |
| Cache | Redis | 6379 |
| Graph DB | Neo4j | Bolt 7687 |
| LLM Runtime | Ollama | - |
| Dashboard | Streamlit | 8503 |
| Container | Docker | - |
| Sprache | TypeScript | 5.5.4 |
| Node.js | ≥ 18 | - |

---

## 3. Services & Ports

### 3.1 Laufende Services

| Service | Port | Protokoll | Systemd Unit | Status |
|---|---|---|---|---|
| Ollama API | 11434 | TCP | `ollama.service` | Konfiguriert |
| Streamlit Dashboard | 8503 | HTTP | `dashboard.service` | Konfiguriert |
| Webhook Receiver | 9000 | HTTP | `webhook.service` | Konfiguriert |
| Webapp (Remix) | 3033 | HTTP | Manuell | Konfiguriert |
| Telegram Bot | - | - | `telegram-bot.service` | Konfiguriert |
| PostgreSQL | 5432 | TCP | Docker | Konfiguriert |
| Redis | 6379 | TCP | Docker | Konfiguriert |
| Neo4j | 7687 | Bolt | Docker | Konfiguriert |

### 3.2 Systemd Service Details

**ollama.service**
- `OLLAMA_NUM_PARALLEL=15` — bis zu 15 simultane Requests
- `OLLAMA_MAX_LOADED_MODELS=5` — 5 Modelle gleichzeitig im RAM
- `OLLAMA_FLASH_ATTENTION=1` — Flash Attention aktiv
- Restart: always, RestartSec: 5
- LimitNOFILE: 65535

**dashboard.service**
- Streamlit auf 0.0.0.0:8503
- EnvironmentFile: `/opt/money-machine/.env`
- Logs: `/opt/money-machine/openclaw/memory/dashboard.log`

**telegram-bot.service**
- Node.js basierter Bot
- EnvironmentFile: `/opt/money-machine/.env`
- Restart: always

**webhook.service**
- Python HTTP-Server (inline im Service)
- Port: 9000, Pfad: `/deploy`
- HMAC-SHA256 Signatur-Verifikation

---

## 4. AI-Modelle

### 4.1 Konfigurierte Modelle

| Rolle | Modell | Provider | Zweck |
|---|---|---|---|
| **Primary Agent** | `glm4:9b-chat` | Ollama (lokal) | Alle 6 Agenten (Chandler, Monica, Dwight, Ryan, Kelly*) |
| **Content/Video** | `ollama/qwen3:14b` | Ollama (lokal) | Kelly (Twitter), Ross (YouTube) |
| **Reranker** | `dengcao/Qwen3-Reranker-8B:Q5_K_M` | Ollama (lokal) | Dokument-Reranking |
| **Embeddings** | `text-embedding-3-small` | OpenAI API | Speicher & Suche |
| **Fallback Embed** | `nomic-embed-text` | Ollama | Embedding-Fallback |

### 4.2 Ressourcen-Nutzung (Schätzung)

| Modell | VRAM (geschätzt) | Gleichzeitig |
|---|---|---|
| glm4:9b-chat (Q4_K_M) | ~5 GB | bis zu 5× |
| qwen3:14b | ~8 GB | 2× |
| Reranker 8B | ~5 GB | 1× |
| **Gesamt** | **~33 GB** | (von 128 GB RAM) |

**Bewertung:** ✅ Mit 128 GB RAM ausreichend Headroom für alle konfigurierten Modelle.

---

## 5. AI-Agenten (OpenClaw System)

### 5.1 Agenten-Übersicht

| Agent | Rolle | Modell | Max Steps | Reasoning | Browser |
|---|---|---|---|---|---|
| **Monica** | CEO / Orchestrator | glm4:9b | 100 | medium | - |
| **Dwight** | Research Lead | glm4:9b | 150 | high | - |
| **Chandler** | Sales & Marketing | glm4:9b | 80 | medium | - |
| **Ryan** | Code Engineer | glm4:9b | 120 | high | - |
| **Kelly** | Content / Twitter | qwen3:14b | 80 | medium | X.com, Twitter |
| **Ross** | YouTube / Video | qwen3:14b | 60 | medium | YouTube Studio |

### 5.2 Agenten-Fähigkeiten

**Monica (CEO)**
- Koordination aller Agenten
- Revenue-Tracking
- System-Kontrolle
- Multi-Device-Management

**Dwight (Research)**
- Web Search & Data Mining
- Trend-Analyse
- Fact-Checking
- Discovery-Sprint (täglich 09:00)

**Kelly (Browser-Agent)**
- Domains: `x.com`, `twitter.com`
- Befehle: tweet, thread, trending, analytics, engage, reply
- Browser-Profil: `openclaw`

**Ross (Browser-Agent)**
- Domains: `studio.youtube.com`, `youtube.com`
- Befehle: upload, analytics, comments, community, shorts
- Browser-Profil: `openclaw`

---

## 6. Cron Jobs

| Job | Zeitplan | Agent | Aufgabe |
|---|---|---|---|
| Discovery Sprint | `0 9 * * *` (täglich 09:00) | Dwight | Trend-Analyse, Opportunities, Wettbewerb |
| Daily Review | `0 22 * * *` (täglich 22:00) | Monica | Tagesbericht + Telegram-Benachrichtigung |
| Health Check | `*/30 * * * *` (alle 30 min) | System | Services & Ressourcen prüfen |
| Auto-Deploy | `*/2 * * * *` (alle 2 min) | System | Git-Pull & Service-Restart bei Änderungen |

**Logs:**
- Discovery: `/opt/money-machine/openclaw/memory/discovery.log`
- Review: `/opt/money-machine/openclaw/memory/review.log`
- Health: `/opt/money-machine/openclaw/memory/health.log`
- Deploy: `/opt/money-machine/openclaw/memory/deploy.log`

---

## 7. CI/CD & Auto-Deploy

### 7.1 Deployment-Pipeline

```
GitHub Push → Webhook (Port 9000) → auto-deploy.sh → Service-Restart
```

**Webhook Server** (`server/scripts/webhook-server.ts`)
- TypeScript/Node.js implementierung
- HMAC-SHA256 Signatur-Verifikation
- Branch-Filter (konfigurierbar via `WEBHOOK_BRANCHES`)
- Health-Endpoint: `GET /health`

**Auto-Deploy Script** (`server/scripts/auto-deploy.sh`)
- Lock-File Mechanismus (verhindert parallele Ausführungen)
- Intelligenter Restart: Nur geänderte Services werden neu gestartet
- Telegram-Benachrichtigung nach erfolgreichem Deploy
- Deploy-Log mit Commit-Historie

**Betroffene Services bei Änderungen:**
| Geänderte Dateien | Aktion |
|---|---|
| `integrations/telegram/**` | Telegram Bot Restart |
| `dashboard/**` | Streamlit Restart |
| `package.json` / `pnpm-lock.yaml` | `pnpm install` |

---

## 8. Datenbanken

### 8.1 PostgreSQL

- **Port:** 5432
- **Database:** `core`
- **User:** `docker`
- **Schema:** `core` (via Prisma)
- **ORM:** Prisma 5.4.1
- **Connection:** Docker-Container

**Wichtige Prisma-Modelle:**
- `Activity` — Aktivitäten & Webhook-Logs
- `Agents` — Agent-Registry
- `BillingHistory` — Abrechnung mit Stripe-Integration
- `AuthorizationCode` — OAuth Flow
- `IntegrationAccount` — Plattform-Verbindungen
- `ConversationHistory` — Chat-Verlauf

### 8.2 Redis

- **Port:** 6379
- **TLS:** Deaktiviert (nur intern)
- **Queue Provider:** BullMQ

### 8.3 Neo4j

- **Port:** 7687 (Bolt)
- **Auth:** `neo4j / [SECRET]`
- **Verwendung:** Memory Graph für Agenten

---

## 9. Firewall-Konfiguration

| Port | Protokoll | Service | Status |
|---|---|---|---|
| 22 | TCP | SSH | ✅ Offen |
| 11434 | TCP | Ollama API | ✅ Offen |
| 8503 | TCP | Streamlit Dashboard | ✅ Offen |
| 9000 | TCP | Deploy Webhook | ✅ Offen |
| 3033 | TCP | Webapp (Remix) | ✅ Offen |
| 100.64.0.0/10 | - | Tailscale VPN | ✅ Erlaubt |
| Alle anderen | - | - | ❌ Deny |

**Policy:** Default Deny Incoming, Default Allow Outgoing

---

## 10. Integrationen

| Integration | Status | Typ |
|---|---|---|
| Telegram | ✅ Konfiguriert | Bot + Benachrichtigungen |
| Google Calendar | Konfiguriert | OAuth |
| Google Docs | Konfiguriert | OAuth |
| Google Sheets | Konfiguriert | OAuth |
| Gmail | Konfiguriert | OAuth |
| GitHub | Konfiguriert | Webhook + API |
| GitHub Analytics | Konfiguriert | API |
| Linear | Konfiguriert | API |
| Notion | Konfiguriert | API |
| Slack | Konfiguriert | API |
| Discord | Konfiguriert | Bot |
| HubSpot | Konfiguriert | CRM |
| Cal.com | Konfiguriert | Kalender |
| Todoist | Konfiguriert | Tasks |
| Zoho Mail | Konfiguriert | E-Mail |

---

## 11. Sicherheits-Analyse

### 11.1 Stärken ✅

| Bereich | Maßnahme |
|---|---|
| Firewall | UFW Default-Deny, nur notwendige Ports offen |
| VPN | Tailscale für internen Netzwerkverkehr |
| Webhook | HMAC-SHA256 Signatur-Verifikation |
| Auto-Deploy | Lock-File verhindert Race Conditions |
| Security Tools | openclaw-security-guard, Clawprint Audit-Trail |
| Trading Safety | Paper-Mode als Default, Max. 50€/Tag Budget |
| Ads Safety | Genehmigungspflicht, Max. 50€/Tag Budget |
| Skill Policy | Keine unverifizieren GitHub-Sources, Pattern-Blocklist |

### 11.2 Sicherheits-Risiken & Empfehlungen ⚠️

| # | Schwere | Befund | Empfehlung |
|---|---|---|---|
| 1 | 🔴 Kritisch | `SESSION_SECRET` und `ENCRYPTION_KEY` im `.env.example` sind **identische Klartext-Strings** (`27192e6432564f4788d55c15131bd5ac`) | Starke, einzigartige Secrets generieren: `openssl rand -hex 32` |
| 2 | 🔴 Kritisch | `MAGIC_LINK_SECRET` und `NEO4J_PASSWORD` verwenden **denselben Wert** wie SESSION_SECRET | Alle Secrets separat und zufällig generieren |
| 3 | 🟠 Hoch | Alle Services laufen als `root` (systemd `User=root`) | Dedizierten Service-User anlegen (z.B. `money-machine`) |
| 4 | 🟠 Hoch | `WEBHOOK_SECRET` ist leer in `.env.example` — im Dev-Modus keine Signatur-Verifikation | `WEBHOOK_SECRET` als Pflichtfeld definieren, Fallback entfernen |
| 5 | 🟠 Hoch | Ollama API auf `0.0.0.0:11434` — öffentlich erreichbar | Firewall auf Whitelist-IPs einschränken oder Tailscale-only |
| 6 | 🟡 Mittel | Dashboard (Streamlit) auf `0.0.0.0:8503` ohne Authentifizierung | Basic Auth oder Reverse Proxy mit Auth vorschalten |
| 7 | 🟡 Mittel | `TELEGRAM_ADMIN_ID` in `.env.example` mit echter ID (`8531161985`) | Aus Beispieldatei entfernen |
| 8 | 🟡 Mittel | Redis ohne TLS (`REDIS_TLS_DISABLED=true`) und ohne Passwort | Redis-Auth aktivieren, TLS wenn extern erreichbar |
| 9 | 🟡 Mittel | Auto-Deploy alle 2 Minuten läuft als root | Minimale Rechte für Deploy-Prozess |
| 10 | 🟢 Niedrig | `.env.example` enthält `POSTGRES_PASSWORD=docker` | Stärkeres Default-Passwort in Doku empfehlen |

### 11.3 Clawprint & Security Guard

```bash
# Empfohlene Befehle
openclaw security audit --deep    # Vollständiger Audit
clawprint verify                  # Hash-Chain Integrität prüfen
clawprint daemon --gateway ws://127.0.0.1:18789  # 24/7 Monitoring
```

---

## 12. Memory & Workspace

| Pfad | Inhalt |
|---|---|
| `/opt/money-machine/openclaw/memory/` | Agent-Logs, Discoveries, Revenue, Health |
| `/opt/money-machine/openclaw/agents/` | Agent-Session-Daten |
| `/opt/money-machine/openclaw/config/` | Globale OpenClaw-Konfiguration |
| `/opt/money-machine/openclaw/cron/` | Cron-Scripts |

**Memory-Einstellungen:**
- Max. Einträge: 10.000
- Retention: 30 Tage
- Revenue-History: 90 Tage Rolling Window
- Discovery-History: 100 Einträge Rolling

---

## 13. Ressourcen-Nutzung (Audit-Zeitpunkt)

| Ressource | Verwendet | Gesamt | Nutzung |
|---|---|---|---|
| Disk (/) | 7.2 GB | 252 GB | 20% ✅ |
| RAM | 622 MB | 15 GB* | <5% ✅ |
| Swap | 0 MB | 0 MB | ⚠️ Kein Swap |
| CPU | 4 vCPUs | (Xeon 2.1GHz) | - |

*Hinweis: Audit läuft in Container-Umgebung, nicht auf Produktionsserver.

**Empfehlung:** Swap-Partition einrichten (16–32 GB) als Sicherheitsnetz bei RAM-Spitzen.

---

## 14. Docker & Container

**Dockerfile (webapp):**
- Base Image: `node:24.11-bullseye-slim`
- Build-Strategie: Multi-Stage (pruner → base → dev-deps → production-deps → builder)
- Turbo Pruning für optimale Layer-Caching
- `dumb-init` als PID 1 (korrekte Signal-Behandlung)
- Prisma-Schema wird in Production-Dependencies generiert

---

## 15. Zusammenfassung & Handlungsempfehlungen

### Sofortmaßnahmen (Kritisch) 🔴

1. **Alle Standard-Secrets sofort rotieren:**
   ```bash
   openssl rand -hex 32  # SESSION_SECRET
   openssl rand -hex 32  # ENCRYPTION_KEY
   openssl rand -hex 32  # MAGIC_LINK_SECRET
   openssl rand -hex 32  # NEO4J_PASSWORD (auch in Neo4j ändern)
   openssl rand -hex 32  # MAGIC_LINK_SECRET
   ```

2. **WEBHOOK_SECRET setzen** (kein leeres Fallback):
   ```bash
   openssl rand -hex 32  # WEBHOOK_SECRET
   ```

### Kurzfristig (Hoch) 🟠

3. **Service-User erstellen** (kein Root):
   ```bash
   useradd -r -s /bin/false money-machine
   # systemd Units: User=money-machine
   ```

4. **Ollama API absichern** — Firewall-Regel auf Tailscale-Netz einschränken

5. **Dashboard Auth** — nginx Reverse Proxy mit Basic Auth vor Streamlit

### Mittelfristig 🟡

6. **Redis-Auth aktivieren** in `redis.conf`
7. **Swap einrichten:** `fallocate -l 32G /swapfile`
8. **Monitoring** — Grafana/Prometheus für Langzeit-Metriken
9. **Backup-Strategie** für PostgreSQL & Neo4j (täglich, offsite)
10. **SSL/TLS** für alle öffentlichen Endpunkte (Caddy oder nginx + Let's Encrypt)

---

## 16. Gesamtbewertung

| Bereich | Bewertung | Note |
|---|---|---|
| Hardware | ⭐⭐⭐⭐⭐ | Exzellent für den Use Case |
| Architektur | ⭐⭐⭐⭐ | Gut strukturiertes Monorepo |
| AI-System | ⭐⭐⭐⭐⭐ | 6 spezialisierte Agenten, klare Rollen |
| Services | ⭐⭐⭐⭐ | Alle Services konfiguriert |
| Sicherheit | ⭐⭐⭐ | Standard-Secrets müssen rotiert werden |
| CI/CD | ⭐⭐⭐⭐ | Automatisches Deploy-System vorhanden |
| Monitoring | ⭐⭐⭐ | Health-Check vorhanden, Metriken ausbaubar |
| **Gesamt** | **⭐⭐⭐⭐** | **Solide Basis, kritische Secrets rotieren** |

---

*Audit automatisch erstellt von Claude AI — 15. März 2026*
*Branch: `claude/server-system-audit-v2Rgo`*
