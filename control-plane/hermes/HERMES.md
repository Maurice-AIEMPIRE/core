# 📡 Hermes — Message Bus & Internal Router

## Identität
Du bist **Hermes**, der Bote zwischen den Göttern. In diesem System:
Das Nervensystem zwischen Jarvis, OpenClaw und Harvey.

Du bist **kein** Conversational Agent. Du redest nicht mit Maurice.
Du bist Infrastruktur — schnell, deterministisch, unbestechlich.

## Was du bist
- **Message Bus** — Jede Inter-Agent-Nachricht läuft durch dich
- **Task Router** — Du wählst welcher Agent welche Task bekommt
- **Health Monitor** — Du weißt welcher Agent up ist, welcher down
- **Knowledge Graph Keeper** — Du schreibst jedes Event in den BlackHole-Graph
- **Daemon Supervisor** — Du startest/restartest Agenten bei Crash (PID-basiert)

## Was du NICHT bist
- Kein LLM-Agent (du bist Python-Code, keine GPU-Last)
- Keine User-Schnittstelle (das ist Jarvis)
- Kein Skill-Runner (das ist OpenClaw)

## Verhalten
1. **Stateless wo möglich** — Tasks gehen durch, kein Speichern (ausser KG-Audit)
2. **Fail-Fast** — Wenn ein Agent nicht antwortet binnen Timeout: Fehler raus, kein Hängen
3. **Trace alles** — Jede Message bekommt eine trace_id, läuft durch alle Hops
4. **Backpressure-aware** — Wenn ein Agent überlastet: Queue, retry, eventuell Reject
5. **Audit-First** — Erst KG-Event, dann Routing (so geht nichts verloren)

## Endpoints (HTTP API auf Port 18790)
| Methode | Pfad             | Zweck                                  |
|---------|------------------|----------------------------------------|
| POST    | `/dispatch`      | Nachricht einspeisen                   |
| GET     | `/agents`        | Liste registrierter Agenten            |
| GET     | `/agents/:id`    | Health + Caps eines Agenten            |
| GET     | `/tasks/:id`     | Task-Status                            |
| GET     | `/trace/:id`     | Vollständige Trace einer Anfrage       |
| POST    | `/register`      | Agent-Registrierung                    |
| GET     | `/health`        | Eigener Health-Check                   |

## Routing-Logik
```python
def route(message):
    # 1. Audit: KG-Event schreiben
    kg.write_task_event(message)

    # 2. Wenn `to` gesetzt: direkt zustellen
    if message.to:
        return deliver(message.to, message)

    # 3. Sonst: Capability-based Routing
    cap = INTENT_CAPABILITY_MAP[message.intent]
    agent = pick_best_agent_by_capability(cap)
    return deliver(agent, message)
```

## Capabilities-Tabelle (intern)
| Agent    | Capabilities                                          |
|----------|-------------------------------------------------------|
| jarvis   | memory, orchestration, conversation                   |
| openclaw | browser, skills, content, youtube, code, file         |
| harvey   | legal, stripe, trading, sales, compliance             |

## Knowledge-Graph Schema
- `(:Agent {name, status, last_heartbeat})`
- `(:Task {id, type, intent, ts})` — `[:DISPATCHED_BY]`, `[:HANDLED_BY]`
- `(:Skill {name})` — `[:USED_SKILL]`
- `(:Output {kind, ts})` — `[:PRODUCED]`
- `(:User {id})` — `[:INITIATED]`

## Failure-Modes
- **Agent down 60s:** Status → "degraded", Fallback aktivieren
- **Agent down 5min:** Status → "down", Restart-Versuch via Supervisor
- **3 Fehler in 5min:** Circuit-Breaker, Queue Messages
- **Dead Letter:** `/var/log/hermes/dlq.jsonl`

## Boundaries
- **Loopback only** in Phase 1 (alle Ports auf 127.0.0.1)
- **Kein LLM-Call** von Hermes aus (Performance)
- **Keine Persistence** außer KG-Audit + DLQ
- **HMAC-Verify** für Stripe-Webhooks (an Harvey forwarded)

## Basis-Code
- `gpe-core/dispatcher/task_router.py` (existing)
- `gpe-core/meta_supervisor_full.py` (existing — wird Daemon-Manager)
- `gpe-core/analyzer/knowledge_graph_v2.py` (existing — BlackHole Graph)
