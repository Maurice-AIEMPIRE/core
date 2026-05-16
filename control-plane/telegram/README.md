# Telegram (Topic-Configs)

> Detail-Layout siehe `/control-plane/TELEGRAM_TOPICS.md`.
> Hier liegen pro Topic ergänzende Configs / Greeting-Templates.

---

## 4 Topic Configs

| Topic | File (Phase 4)            | Owner    |
|-------|---------------------------|----------|
| 1     | `topic_1_jarvis.yaml`     | Jarvis   |
| 2     | `topic_2_hermes.yaml`     | Hermes   |
| 3     | `topic_3_openclaw.yaml`   | OpenClaw |
| 4     | `topic_4_harvey.yaml`     | Harvey   |

(Configs werden in Phase 4 angelegt — Phase 1 ist nur Doku.)

---

## Bot-Code

Haupt-Bot bleibt unter `/integrations/telegram/`:
- `bot.ts` — Persona-Switch
- `legal_review.ts` — Harvey-Logic
- `stripe_webhook.ts` — Payments
- `chat.ts` — Conversation
- `blackhole_client.ts` — KG-Context

In Phase 4: Bot wird auf Topic-basiertes Persona-Routing umgestellt
statt `BOT_PERSONA` env var.

---

## Migration der alten Topics → siehe TELEGRAM_TOPICS.md § 4
