# Shared Memory — Das geteilte Gehirn

> **Was hier liegt:** Komponenten, die von mehreren Agenten gelesen/geschrieben werden.
> **Was NICHT hier liegt:** Jarvis-Conversation-Memory (privat in `jarvis/memory/`).

---

## Komponenten

### Knowledge Graph (BlackHole)
- **Code:** `/gpe-core/analyzer/knowledge_graph_v2.py` (Quelle, wird in Phase 2 hierher gespiegelt)
- **DB:** `/root/.openclaw/knowledge_graph.db` (SQLite, WAL-Mode)
- **Schreibrechte:** alle 4 Agenten (jeder in eigenem Subgraph)
- **Leserechte:** alle 4 Agenten

#### Subgraphen

| Subgraph    | Writer       | Inhalt                            |
|-------------|--------------|-----------------------------------|
| `core/`     | Hermes       | Tasks, Traces, Agent-Health       |
| `jarvis/`   | Jarvis       | User, Decision, Project, Person   |
| `openclaw/` | OpenClaw     | Skill-Runs, Artifacts, Outputs    |
| `harvey/`   | Harvey       | LegalFinding, Risk, Lead, Customer|
| `sales/`    | Harvey       | Lead, Stage, Deal, Revenue        |
| `legal/`    | Harvey       | Case, Document, Evidence, Source  |

---

### Vector DB (Galaxia → Jarvis-managed)
- **Code:** `/galaxia/galaxia-vector-core.py`
- **DB-Pfad:** `/root/galaxia/vector_db` (LanceDB-like)
- **Schreibrechte:** Jarvis (primary), OpenClaw (eigener Index unter `openclaw/`)
- **Modell:** `nomic-embed-text` via Ollama
- **Reindex:** stündlich (autoIndex aus `.openclaw/openclaw.json`)

---

### Obsidian Vault (lokal)
- **Pfad:** `~/Empire/02_Knowledge_Vault/` (Maurices System)
- **Sync:** via `/integrations/obsidian-memory/` (Phase 3 implementieren)
- **Mode:** Pull-only durch Jarvis (Maurice schreibt manuell rein)
- **Embedding:** ja, in Vector DB (Subgraph `obsidian/`)

---

### Audit-Trail (clawprint)
- **Existing System:** im OpenClaw verkabelt
- **Schreibrechte:** Hermes (Pflicht), Andere (optional)
- **Format:** JSONL, immutable
- **Retention:** unbegrenzt (Compliance)

---

## Lese-Regeln (eiserne)

1. **KG lesen** — alle Agenten dürfen lesen (read-only)
2. **KG schreiben** — nur in eigenen Subgraph
3. **Vector DB lesen** — Jarvis frei, andere nur über Hermes-Proxy
4. **Vector DB schreiben** — nur Jarvis
5. **Audit-Trail lesen** — nur Hermes (für Verifier) + Maurice
6. **Audit-Trail schreiben** — append-only, alle Agenten via Hermes

---

## Phase 2: Was hier reinkommt

- `kg_schema.md` — Knowledge Graph Schema-Doku
- `kg_client.py` — Symlink/Spiegel zu `gpe-core/analyzer/knowledge_graph_v2.py`
- `vector_client.py` — Wrapper für Galaxia Vector Core
- `subgraph_writers.md` — Wer darf was in welchem Subgraph
