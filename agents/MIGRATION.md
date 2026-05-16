# Migration: Galaxia OS → Core4

> **Datum:** 2026-05-16
> **Auslöser:** Galaxia 7-Agent-System ist nicht mehr greifbar — Reduktion auf 4 fokussierte Agenten.

---

## 1. Mapping: 7 Galaxia-Agents → 4 Core-Agents

| Galaxia-Agent | Rolle (alt)              | Neue Heimat   | Wie übernommen                                        |
|---------------|--------------------------|---------------|--------------------------------------------------------|
| Monica        | CEO/Orchestrator         | → **Jarvis**  | Komplett: Jarvis IST der neue Orchestrator             |
| Dwight        | Research                 | → **Jarvis**  | Als Skill `web-research` (Jarvis ruft via Hermes auf)  |
| Kelly         | X-Content                | → **OpenClaw** | Skill `content-engine` + `x-twitter-browser` (bereits da) |
| Pam           | Newsletter/Products      | → **OpenClaw** | Skill `content-engine` + `agent-earner` (bereits da)   |
| Ryan          | Code/Templates           | → **OpenClaw** | Skill `pi-coder` (bereits da)                          |
| Chandler      | Sales/Trading            | → **Harvey**  | Skills `trading-monitor` + `meta-ads` (umsiedeln)      |
| Ross          | YouTube                  | → **OpenClaw** | Skill `youtube-factory` + `thumbnail-optimizer` (bereits da) |

**Ergebnis:** Keine Funktion geht verloren — alles wird zu Skills unter den 4 Kern-Agenten.

---

## 2. Was bleibt 1:1

| Komponente                      | Pfad                                          | Status |
|---------------------------------|-----------------------------------------------|--------|
| OpenClaw Browser-System         | `/openclaw/browser/`, `.openclaw/profiles.json` | ✅ keep |
| 16 OpenClaw Skills              | `/openclaw/workspace/skills/*`                 | ✅ keep |
| OpenClaw Browser-Profile        | `openclaw`, `work`, `chrome`                   | ✅ keep |
| Telegram Bot Code               | `/integrations/telegram/`                      | ✅ keep |
| Harvey Legal Review Logic       | `/integrations/telegram/src/legal_review.ts`   | ✅ keep |
| Stripe Webhook                  | `/integrations/telegram/src/stripe_webhook.ts` | ✅ keep |
| CORE Memory Engine (Repo-Basis) | `/apps/webapp/`, `/packages/`                  | ✅ keep |
| GPE-Core Task Router            | `/gpe-core/dispatcher/task_router.py`          | 🔄 adapt → Hermes |
| GPE-Core Meta-Supervisor        | `/gpe-core/meta_supervisor_full.py`            | 🔄 adapt → Hermes |
| Black Hole Knowledge Graph      | `/gpe-core/analyzer/knowledge_graph_v2.py`     | ✅ keep |
| Ollama-Setup                    | `localhost:11434`                              | ✅ keep |

---

## 3. Was umsiedelt (mit Zielpfad)

### Galaxia Vector Core → Jarvis Memory
- **Quelle:** `/galaxia/galaxia-vector-core.py`
- **Ziel:** `/agents/jarvis/memory/vector_core.py` (Symlink für Phase 1)
- **Grund:** Jarvis braucht das für Memory-Recall

### Friends-Agent-Configs → Archiv
- **Quelle:** `/openclaw/agents/{monica,dwight,kelly,pam,ryan,chandler,ross}/`
- **Ziel:** `/openclaw/agents/_archive/` (nicht gelöscht — als Referenz)
- **Wann:** Sobald die 4 neuen Agenten produktiv laufen

### Telegram-Topics von 7 auf 4 reduzieren
- **Quelle:** `.openclaw/openclaw.json` → `channels.telegram._topics`
- **Aktion:** 7 Topics deaktivieren, 4 neue anlegen (Jarvis/Hermes/OpenClaw/Harvey)
- **User-Aktion nötig:** Telegram-Forum-Topics in der Gruppe manuell umbenennen

---

## 4. Was deprecated wird (nicht löschen, nur aus Routing nehmen)

| Element                          | Warum deprecated              | Wann löschen        |
|----------------------------------|-------------------------------|---------------------|
| `Pfeifer Profit Squad` Telegram-Gruppe (Inner Circle) | 7-Agent-Konzept verworfen | Nach 30 Tagen Stabilität |
| `GALAXIA_CORE.md` (DNA-File)     | Friends-Crew-System           | Nach Migration-Lock |
| `AGENTS.md` (Roster der 7)       | 7-Agent-Roster                | Nach Migration-Lock |
| Friends-Agent SOUL/configs       | Werden zu OpenClaw-Skills     | Nach 30 Tagen       |

---

## 5. Phasen-Plan

### Phase 1 — Setup (HEUTE) ✅
- [x] `/agents/` Struktur anlegen
- [x] `ARCHITECTURE.md` + `MIGRATION.md` + `BUS.md` schreiben
- [x] 4 Agent-SOULs + Configs schreiben
- [x] Task Router umbenennen/erweitern → Hermes
- [x] Commit + Push auf `claude/export-branches-kYh7h`

### Phase 2 — Hermes scharfschalten
- [ ] `gpe-core/` → `agents/hermes/runtime/` portieren
- [ ] Bus-Protokoll (HTTP API) implementieren
- [ ] Health-Check-Endpoint für alle 4 Agents
- [ ] Knowledge-Graph-Schema dokumentieren

### Phase 3 — Jarvis Memory verdrahten
- [ ] CORE Memory Engine als Jarvis-Backend einbinden
- [ ] Galaxia Vector Core importieren
- [ ] MCP-Server für Jarvis exposen (Cursor/Claude können Jarvis nutzen)

### Phase 4 — Telegram Bot umstellen
- [ ] `BOT_PERSONA=jarvis|hermes|openclaw|harvey` Logik
- [ ] 4 Topics statt 7
- [ ] Inter-Agent-Handoff via @-Mention

### Phase 5 — Galaxia ausmustern
- [ ] Friends-Agents in `_archive/` verschieben
- [ ] `GALAXIA_CORE.md` umbenennen zu `_LEGACY_GALAXIA.md`
- [ ] Final Cleanup nach 30 Tagen Stabilität

---

## 6. Rollback-Plan (falls was schiefgeht)

1. `git revert` auf den Pre-Migration-Commit
2. Alte Telegram-Topics reaktivieren (sind im Archiv)
3. Friends-Agent-Configs aus `_archive/` zurückholen
4. Ollama-Modelle laufen weiter — keine Daten gehen verloren

**Wichtig:** Keine Datei wird in Phase 1 gelöscht. Migration ist additiv.

---

## 7. Was Maurice manuell tun muss

1. **Telegram-Forum-Topics umbenennen** (4 statt 7) — in der Telegram-Gruppe selbst
2. **`.env` aktualisieren** wenn neue Variablen dazukommen (siehe `.env.example`)
3. **Ollama-Modelle bestätigen:** `ollama list` — alle gelisteten Modelle müssen da sein
4. **Erste Test-Conversation mit Jarvis** in Topic 1 nach Phase 3
