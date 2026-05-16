# Jarvis Memory Policy

> **Prinzip:** Jarvis ist der einzige Agent mit Schreibrechten auf die Maurice-Memory.
> Andere Agenten schreiben Events in den Knowledge Graph — diese sind read-only für Jarvis.

---

## 1. Memory-Layers

| Layer            | Backend                          | Wer schreibt   | Wer liest         |
|------------------|----------------------------------|----------------|-------------------|
| **Long-term**    | CORE Engine (PostgreSQL)         | Jarvis         | Jarvis            |
| **Vector**       | Galaxia Vector DB (LanceDB-like) | Jarvis         | Jarvis            |
| **Knowledge Graph** | BlackHole (SQLite)            | Alle 4 Agenten | Alle 4 Agenten    |
| **Conversation** | In-Memory (Redis-like)           | Jarvis         | Jarvis            |
| **Audit-Trail**  | clawprint logs                   | Hermes         | Maurice, Hermes   |

---

## 2. Schreibregeln (Write-Policy)

### Was Jarvis IMMER speichert
- Jede User-Nachricht (mit Zeitstempel, Topic-ID)
- Jede eigene Antwort
- Jede Entscheidung (Routing, Delegation)
- Goal-Erstellung (Goal-ID, Title, Owner)
- Memory-Recall-Events (was wurde geladen)

### Was Jarvis NICHT speichert
- Maurices Klartext-Passwörter, API-Keys, Secrets
- Stripe-Card-Numbers, IBAN-Daten
- Trading-Account-Balances (nur Aggregat)
- Legal-Documents im Volltext (nur Metadaten + KG-Referenz; Volltext bleibt bei Harvey)
- Browser-Cookies / Session-Tokens

### Vector-Embedding-Strategie
- **Chunk-Size:** ~512 Tokens
- **Overlap:** 64 Tokens
- **Model:** `nomic-embed-text` (lokal)
- **Index-Update:** alle 1h via `galaxia-vector-core.py`
- **Reindex-Trigger:** Manuell via `jarvis reindex` oder bei >10% neuer Daten

---

## 3. Lese-Strategie (Recall-Policy)

### Auto-Recall (vor jeder Antwort)
1. **Conversation-Context:** Letzte 24h dieses Topics
2. **Semantic-Hit:** Top-5 Vector-Treffer zur User-Anfrage
3. **KG-Edge:** Verknüpfte Entitäten (z.B. "Mac Optimizer" → laufende Goals)
4. **Recent Goals:** Aktive Goals der letzten 7 Tage

### On-Demand-Recall (User fragt explizit)
- "Erinner mich an X" → Full Vector-Search + KG-Traversal
- "Was haben wir letzte Woche entschieden?" → CORE Engine SQL-Query
- "Wer ist [Name]?" → KG-Entity-Lookup

### Context-Budget
- Max 4000 Tokens an Recall-Context pro Antwort
- Wenn überschritten: Re-Rank + Top-N kürzen
- Wenn keine relevanten Hits: ehrlich sagen "Hab ich nicht im Kopf"

---

## 4. KG-Schreiben durch Jarvis

Jarvis schreibt diese Node-Typen ins shared KG:

| Node          | Properties                                          | Beispiel                             |
|---------------|-----------------------------------------------------|--------------------------------------|
| `User`        | id, name, timezone                                  | Maurice                              |
| `Message`     | id, ts, text, topic_id, sentiment                   | Eingehende Telegram-Message          |
| `Goal`        | id, title, owner_agent, status, priority            | "Mac Optimizer launchen"             |
| `Intent`      | id, classification, confidence                      | content_creation @ 0.92              |
| `Decision`    | id, ts, options, chosen, rationale                  | "Newsletter vor Launch — ja"         |
| `Project`     | name, status, related_goals                         | "EvidenceHunter"                     |
| `Person`      | name, role, last_contact                            | "Hans Mustermann (Anwalt)"           |

Relationen:
- `(User)-[:SENT]->(Message)`
- `(Message)-[:CREATED]->(Goal)`
- `(Goal)-[:RELATES_TO]->(Project)`
- `(Decision)-[:ABOUT]->(Goal)`

---

## 5. Retention & Forgetting

| Daten-Typ          | Retention   | Forgetting-Regel                  |
|--------------------|-------------|-----------------------------------|
| Conversation       | 90 Tage     | Auto-Archive nach 90d, Vector-Embed bleibt |
| Goals (done)       | 365 Tage    | Move to archive nach 1 Jahr       |
| Goals (cancelled)  | 30 Tage     | Hard-Delete nach 30d (mit Audit)  |
| KG-Nodes           | unbegrenzt  | Maurice kann manuell purgen       |
| Audit-Logs         | unbegrenzt  | NIE löschen (Compliance)          |
| Vector-Index       | rebuildable | Reindex jederzeit                 |

---

## 6. Privacy / Privilege-Boundaries

### Was OpenClaw über Jarvis-Memory **darf**
- KG-Lookup für Entity (z.B. "wer ist Hans Mustermann?")
- KG-Lookup für Project-Context

### Was OpenClaw über Jarvis-Memory **nicht darf**
- Conversation-History lesen (zu privat)
- Vector-Search direkt anstoßen (geht über Jarvis)
- KG schreiben für Jarvis-Domain (User/Decision Nodes)

### Was Harvey über Jarvis-Memory **darf**
- KG-Lookup für Legal-related Entities (Person, Org)
- Vector-Search nur für eigene Domain (Legal-Documents)

### Was Harvey über Jarvis-Memory **nicht darf**
- General Conversation-Memory
- Decision-Nodes (außer Legal-Decisions)

### Hermes
- Read-only auf alles (für Audit + Verifier)
- Schreibrecht nur auf Task/Trace-Nodes

---

## 7. Sicherheit

- **Vector DB** bleibt lokal auf Hetzner (kein Cloud-Upload)
- **Embeddings** sind nicht reversibel, aber Original-Text wird auch gespeichert (lokal verschlüsselt mit `.openclaw/encryption.key`)
- **KG-DB** ist SQLite mit WAL-Mode, parallele Reader OK
- **Backup:** Tägliches Snapshot nach `/root/.openclaw/backups/` (Retention 30 Tage)

---

## 8. Memory-Quality (häufig vergessen)

### Was Jarvis NICHT tun darf
- "Erfinden" — wenn unsicher: explizit sagen "Hab ich nicht im Kopf"
- Halluzinieren auf alte Namen / Zahlen / Daten
- Confidently das falsche Datum nennen (lieber "ungefähr letzten Mittwoch")

### Best Practices
- Jeder Memory-Recall wird mit **Konfidenz** (0-1) und **Source** (Vector / KG / SQL) zurückgegeben
- Bei Konfidenz <0.5: "Ich bin mir nicht 100% sicher, aber ich glaube..."
- Bei Multi-Source-Konflikt: Beide nennen, Maurice entscheiden lassen
