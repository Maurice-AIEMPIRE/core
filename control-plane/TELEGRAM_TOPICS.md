# Telegram Topics — 4-Agent Layout (neu)

> **Reduktion:** Von 6 Galaxia-Topics auf 4 Core4-Topics.
> **Prinzip:** Ein Topic pro Agent. Klar erkennbar wer antwortet.

---

## 1. Topic-Layout

| ID | Emoji | Name                       | Owner    | Inhalt                                         |
|----|-------|----------------------------|----------|------------------------------------------------|
| 1  | 🧠    | Jarvis — Personal          | Jarvis   | Chat, Goals erstellen, Status, Memory          |
| 2  | 📡    | Hermes — System Status     | Hermes   | Health, Alerts, Goal-Updates, CI-Logs          |
| 3  | 🦅    | OpenClaw — Execution       | OpenClaw | Content-Output, YouTube, Browser-Reports       |
| 4  | ⚖️    | Harvey — Legal & Sales     | Harvey   | Legal-Reviews, Stripe-Events, Trading, Customer|

---

## 2. Persona-Switch im Bot-Code

Aktueller Stand (in `integrations/telegram/src/bot.ts`):
```typescript
const isHarveyPersona = process.env.BOT_PERSONA === 'harvey';
```

Neue Persona-Liste (env-driven, **Phase 4**):

```bash
BOT_PERSONA=jarvis    # → Topic 1
BOT_PERSONA=hermes    # → Topic 2 (auto-only, keine Konversation)
BOT_PERSONA=openclaw  # → Topic 3
BOT_PERSONA=harvey    # → Topic 4 (existing)
```

**Default-Mapping:**
- Telegram-Forum mit 4 Topics
- Jeder Topic ist eine eigene Bot-Instanz (oder Single-Bot mit Routing-Logic basierend auf `message.message_thread_id`)

---

## 3. Default-Routing-Tabelle (Topic → Hermes-Intent)

| Topic            | Default Intent             | Standard-Agent  |
|------------------|----------------------------|-----------------|
| 1 (Jarvis)       | `conversation`             | jarvis          |
| 2 (Hermes)       | `system_status` (read-only)| hermes          |
| 3 (OpenClaw)     | `browser_action` / `content_creation` | openclaw |
| 4 (Harvey)       | `legal_review` / `sales`   | harvey          |

Jarvis kann via Intent-Classifier in Topic 1 trotzdem an OpenClaw/Harvey delegieren.
Topic 2/3/4 sind "spezifische Topic-Konversationen".

---

## 4. Legacy-Topics — Mapping

| Alte Topic-Datei                                | Inhalt (alt)            | Neue Heimat                     |
|-------------------------------------------------|-------------------------|---------------------------------|
| `01-writing-content.md` (Kelly/Pam)             | Content schreiben       | Topic 3 (OpenClaw) für interne Content / Topic 4 (Harvey) für Kunden-Content |
| `02-research-insights.md` (Dwight)              | Research                | Topic 1 (Jarvis delegiert → OpenClaw) |
| `03-planning-strategy.md` (Monica)              | Strategy                | Topic 1 (Jarvis)                |
| `04-code-automation.md` (Ryan)                  | Code                    | Topic 3 (OpenClaw)              |
| `05-money-printer.md` (Chandler)                | Sales/Trading           | Topic 4 (Harvey)                |
| `06-video-youtube.md` (Ross)                    | YouTube                 | Topic 3 (OpenClaw `youtube-factory`) |

---

## 5. Greeting / Personality pro Topic

### Topic 1 — Jarvis
```
🧠 Jarvis online.
Was steht heute an?
```
- Stil: Deutsch, direkt, kein Fluff
- Ende jeder Antwort: 1 Next-Action oder 1 Frage

### Topic 2 — Hermes
```
📡 Hermes Status (auto):
  ✅ Jarvis    healthy   (last ping 12s ago)
  ✅ OpenClaw  healthy   (last ping 8s ago)
  ⚠️  Harvey   degraded  (stripe webhook slow)
  Goals active: 4 in_progress, 2 review, 1 blocked
```
- Stil: maschinell, monospace, kein Smalltalk
- Auto-only, antwortet nicht auf User-Messages

### Topic 3 — OpenClaw
```
🦅 OpenClaw — Skill `content-engine` triggered.
Output: 10 X-Posts zu KI-News (1.234 chars)
File: /tmp/x-posts-2026-05-16.md
Review? [yes / edit / discard]
```
- Stil: kurz, Aktion-fokussiert, mit File-Pfaden / URLs

### Topic 4 — Harvey
```
⚖️ Harvey — Vertragsprüfung erhalten.
Dokument: Anwaltsbrief Mustermann GmbH (12 Seiten, PDF)
Risiko: 7/10
Empfehlung: Vergleich anbieten (siehe legal-settlement Skill)
Begründung:
  - §3 Schadensersatz: angreifbar (Beleg fehlt)
  - §7 Fristen: bereits abgelaufen
Nächster Schritt: ARAG-Mail draften? (Antwort: ja/nein)
```
- Stil: Harvey-Specter-Like, sachlich, Risiko-First

---

## 6. Cross-Topic-Mentions (Inter-Agent-Handoff)

Wenn Jarvis in Topic 1 sagt: "Schick das an Harvey", dann:

1. Jarvis schreibt Output in Topic 1
2. Jarvis pingt **gleichzeitig** Topic 4: `@harvey eingehender Handoff goal_01HXY1`
3. Harvey antwortet in Topic 4 mit Empfangsbestätigung
4. Maurice sieht in beiden Topics, was passiert (Cross-Reference per Goal-ID)

**Wichtig:** Inter-Agent-Mentions sind keine direkte Kommunikation — die geht über Hermes-Bus.
Telegram-Mentions sind nur für Maurices Übersicht.

---

## 7. Setup-Schritte (manuell für Maurice, Phase 4)

1. **Telegram-Gruppe öffnen** (Inner Circle Pfeifer Profit Squad)
2. **Bestehende Topics umbenennen** (oder neu anlegen + alte archivieren):
   - `01 Writing` → `🦅 OpenClaw — Execution`
   - `02 Research` → `🧠 Jarvis — Personal`
   - `03 Planning` → ❌ archivieren (verschmilzt in Jarvis)
   - `04 Code` → ❌ archivieren (verschmilzt in OpenClaw)
   - `05 Money` → `⚖️ Harvey — Legal & Sales`
   - `06 Video` → ❌ archivieren (verschmilzt in OpenClaw)
   - **NEU anlegen:** `📡 Hermes — System Status`
3. **Topic-IDs in Configs eintragen:**
   ```bash
   # control-plane/{jarvis,hermes,openclaw,harvey}/config.json
   "channels.telegram.topicId": <neue ID>
   ```
4. **`.env` setzen:**
   ```bash
   TELEGRAM_TOPIC_JARVIS=...
   TELEGRAM_TOPIC_HERMES=...
   TELEGRAM_TOPIC_OPENCLAW=...
   TELEGRAM_TOPIC_HARVEY=...
   ```

---

## 8. Was bleibt vom alten Telegram-Setup

| Komponente                                          | Status |
|-----------------------------------------------------|--------|
| `integrations/telegram/src/bot.ts`                  | KEEP   |
| `integrations/telegram/src/legal_review.ts`         | KEEP (Harvey-Core) |
| `integrations/telegram/src/stripe_webhook.ts`       | KEEP   |
| `integrations/telegram/src/blackhole_client.ts`     | KEEP   |
| `.openclaw/openclaw.json` → `channels.telegram`     | UPDATE (Topic-Namen) |
| `.openclaw/integrations.json` → `telegram`          | KEEP (Bot-ID) |
| Auto-Sync alle 15min                                | KEEP   |
| Browser-Verification via `openclaw` Profile         | KEEP   |
