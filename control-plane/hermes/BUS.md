# Hermes Bus — Inter-Agent Protocol

> **Version:** 1.0
> **Owner:** Hermes
> **Transport:** HTTP/JSON (Phase 1), gRPC (optional Phase 4)
> **Port:** 18790 (Hermes API)

---

## 1. Grundregel

> **Niemand redet direkt mit niemandem.**
> Alle Inter-Agent-Kommunikation läuft über Hermes als Message-Bus.

Ausnahmen (direkter Pfad erlaubt):
- User ↔ Telegram (über Bot-Layer, kein Inter-Agent-Hop)
- Jarvis → User Antworten (via Telegram-Reply)
- Stripe-Webhooks → Harvey (eingehend, signiert)

---

## 2. Message-Envelope

Jede Bus-Nachricht hat dieses Format:

```json
{
  "id": "msg_01HXYZ...",
  "ts": "2026-05-16T09:42:00Z",
  "from": "jarvis",
  "to": "openclaw",
  "type": "task",
  "intent": "content_creation",
  "payload": {
    "skill": "content-engine",
    "args": { "topic": "KI-News", "platform": "x", "count": 10 }
  },
  "reply_to": "msg_01HXYZ_PREV",
  "trace_id": "trace_01HXYZ...",
  "priority": 5
}
```

**Pflichtfelder:** `id`, `ts`, `from`, `to`, `type`, `payload`
**Optional:** `intent`, `reply_to`, `trace_id`, `priority` (1-10, default 5)

---

## 3. Message-Typen

| Type        | Beschreibung                                            | Antwort erwartet |
|-------------|---------------------------------------------------------|------------------|
| `task`      | Agent soll etwas tun (Skill ausführen, Daten holen)     | ✅ ja (`result`)  |
| `result`    | Antwort auf einen `task`                                | ❌ nein          |
| `event`     | Etwas ist passiert (Stripe-Payment, Telegram-Message)   | ❌ nein          |
| `query`     | Read-only Daten anfragen (z.B. Memory-Lookup)           | ✅ ja (`result`)  |
| `health`    | Health-Check Ping                                       | ✅ ja (`health`)  |
| `broadcast` | An alle Agenten (z.B. Shutdown-Signal)                  | ❌ nein          |
| `error`     | Etwas ist schiefgelaufen                                | ❌ nein          |

---

## 4. Routing-Table (Hermes-intern)

```json
{
  "agents": {
    "jarvis":   { "url": "http://127.0.0.1:18791", "capabilities": ["memory", "orchestration", "conversation"] },
    "openclaw": { "url": "http://127.0.0.1:18789", "capabilities": ["browser", "skills", "content", "youtube", "code"] },
    "harvey":   { "url": "http://127.0.0.1:18792", "capabilities": ["legal", "stripe", "trading", "sales"] }
  },
  "fallback_order": ["openclaw", "jarvis", "harvey"]
}
```

Hermes selbst hört auf **Port 18790**.

---

## 5. HTTP-Endpoints (Hermes API)

| Methode | Pfad             | Zweck                                        |
|---------|------------------|----------------------------------------------|
| POST    | `/dispatch`      | Nachricht in den Bus einspeisen              |
| GET     | `/agents`        | Liste aller registrierten Agenten + Status   |
| GET     | `/agents/:id`    | Health + Capabilities eines Agenten          |
| GET     | `/tasks/:id`     | Status einer laufenden Task                  |
| GET     | `/trace/:id`     | Komplette Trace einer User-Anfrage           |
| POST    | `/register`      | Agent registriert sich (Heartbeat)           |
| GET     | `/health`        | Hermes selbst Health-Check                   |

---

## 6. Capability-Routing

Wenn `to` nicht gesetzt ist, routet Hermes anhand `intent` + Agent-Capabilities:

```python
INTENT_CAPABILITY_MAP = {
    "content_creation":  "skills",
    "browser_action":    "browser",
    "code_generation":   "skills",
    "legal_review":      "legal",
    "memory_recall":     "memory",
    "conversation":      "conversation",
    "trading_signal":    "trading",
    "payment_event":     "stripe",
    "youtube_publish":   "youtube",
}
```

Beispiel: `intent: "legal_review"` → matched `harvey` (hat `legal` capability).

---

## 7. Knowledge-Graph Updates

Jede Task die durch Hermes läuft schreibt ein Event in den Knowledge Graph (BlackHole):

```cypher
(:Task {id, type, intent, ts})
  -[:DISPATCHED_BY]-> (:Agent {name: "jarvis"})
  -[:HANDLED_BY]->    (:Agent {name: "openclaw"})
  -[:USED_SKILL]->    (:Skill {name: "content-engine"})
  -[:PRODUCED]->      (:Output {kind: "content", ts})
```

Das gibt vollständiges Audit + ermöglicht Jarvis später zu sagen:
> "Letzte Woche hast du 47 Content-Tasks gestartet, davon 31 erfolgreich."

---

## 8. Error-Handling

- **Timeout** (default 60s): Hermes sendet `error` zurück an Sender, markiert Empfänger als "degraded"
- **3 Fehler in 5min:** Agent → "down", Fallback aktivieren
- **Retry-Policy:** Exponential backoff (2s, 4s, 8s, 16s) — max 4 Versuche
- **Dead-Letter-Queue:** `/var/log/hermes/dlq.jsonl` — alle nicht-zustellbaren Messages

---

## 9. Security

- **Loopback-only** in Phase 1 (alle Ports binden auf 127.0.0.1)
- **HMAC-Signing** für Stripe-Webhooks (Harvey)
- **Rate-Limit** pro Agent: 100 msg/sec
- **Audit-Trail:** Jede Message wird in `clawprint` (existing audit log) festgeschrieben

---

## 10. Beispiel: End-to-End Flow

**User schreibt in Telegram Topic 1:** "Mach mir 10 X-Posts zu KI-News"

```
1. Telegram Bot → POST /dispatch
   { from: "telegram", to: "jarvis", type: "task",
     payload: { text: "Mach mir 10 X-Posts zu KI-News", topic_id: 1 } }

2. Hermes → Jarvis (HTTP POST http://127.0.0.1:18791/handle)
   Jarvis klassifiziert: intent="content_creation", target="openclaw"

3. Jarvis → POST /dispatch
   { from: "jarvis", to: "openclaw", type: "task",
     intent: "content_creation",
     payload: { skill: "content-engine", args: {...} } }

4. Hermes → OpenClaw (HTTP POST http://127.0.0.1:18789/handle)
   OpenClaw ruft Skill `content-engine` → produziert 10 Posts

5. OpenClaw → POST /dispatch
   { from: "openclaw", to: "jarvis", type: "result",
     reply_to: "msg_step3", payload: { posts: [...] } }

6. Hermes → Jarvis → formatiert Antwort
7. Jarvis → Telegram Bot → Topic 1 → User
```

Trace-ID läuft durch alle 7 Schritte. Auditierbar.
