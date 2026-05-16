# OpenClaw Execution Policy

> **Prinzip:** Tut, was Hermes sagt. Auditiert alles. Kein Eigenleben.

---

## 1. Was OpenClaw ausführen darf

### Browser
- Profile `openclaw` (isolated, CDP 18800) — frei
- Profile `work` (CDP 18801) — Maurices Workspace, gleiche Regeln
- Profile `chrome` (Extension-Relay, CDP 18792) — frei für Maurices laufende Tabs

### Files (im Repo + `/tmp/` + Workspace)
- `/openclaw/**` — read+write
- `/tmp/openclaw-*/` — read+write (Skill-Outputs)
- `~/Empire/02_Skills_Brain/**` — read+write (Maurices Skills-Vault)
- Repo: read+write außer `/control-plane/jarvis/` (Jarvis-only)

### Network
- HTTP/HTTPS frei
- Loopback (Hermes auf 18790)
- SSH: nur zu freigegebenen Hosts (siehe `.ssh/config`)
- VPN/Tor: gesperrt

### Shell
- Commands ausführen: **ja**, mit Audit
- `sudo`: **nein**, außer in `command_allowlist`
- `rm -rf /`: **NIE**, Pattern-Block

---

## 2. Was OpenClaw NICHT ausführen darf

| Aktion                                  | Grund                              |
|-----------------------------------------|-------------------------------------|
| Live-Trading-Execution                  | Safety Gate — nur Paper             |
| Echte Verträge versenden (Mail)         | Harvey-only, mit Maurice-Sign-off   |
| `rm -rf` auf Wurzel-Pfade               | Hard-Block                          |
| Datenbank-Drops                         | Hard-Block                          |
| Browser ohne Profile                    | Audit-Lücke                         |
| Skills aus dem Internet nachladen       | Supply-Chain-Risiko                 |
| Eigene LLM-API-Keys nutzen              | Nur Ollama, lokal                   |
| Schreiben in `/control-plane/jarvis/`   | Jarvis-only Memory                  |
| `confirmedBy: maurice` selbst setzen    | Maurice muss real bestätigen        |

---

## 3. Confirmation-Gates

Diese Aktionen erfordern Maurice-Confirmation (Hermes blockt bis `human_signoff`):

| Aktion-Typ                              | Beispiel                         |
|-----------------------------------------|----------------------------------|
| `publish` (extern sichtbar)             | X-Post live, YouTube upload      |
| `send_message` (extern)                 | E-Mail, Telegram-DM an Dritte    |
| `spend` (>0 €)                          | Meta Ads, jegliche Zahlung       |
| `delete_irreversible`                   | Files >100 MB, Git-Force-Push    |
| `legal_communication`                   | Brief an Anwalt versenden (Harvey, nicht OpenClaw, aber falls Browser-Klick nötig) |

Confirmation-Workflow:
1. OpenClaw stoppt vor Aktion
2. Schreibt Goal-Note: "Bestätigung nötig: {Aktion}"
3. Hermes pingt Jarvis (Topic 1) mit Frage
4. Maurice antwortet ja/nein
5. Hermes setzt `human_signoff_received` → OpenClaw fährt fort

---

## 4. Audit (Pflicht)

Jede Skill-Ausführung schreibt ein Audit-Event:

```json
{
  "ts": "2026-05-16T14:42:00Z",
  "agent": "openclaw",
  "skill": "x-twitter-browser",
  "goal_id": "goal_01HXY1",
  "args_hash": "sha256:...",
  "browser_profile": "openclaw",
  "duration_ms": 18420,
  "exit_status": "success",
  "side_effects": [
    { "kind": "http_post", "url": "https://api.x.com/...", "status": 200 },
    { "kind": "file_write", "path": "/tmp/openclaw-xpost-2026-05-16.json" }
  ],
  "confirmation": { "required": false, "received": null }
}
```

**Audit-Trail:** `clawprint` (existing System), zusätzlich KG-Event.

---

## 5. Safety-Pattern: Domain-Allowlist (Browser)

OpenClaw darf in Profile `openclaw`/`work` nur auf folgende Domain-Klassen:

| Klasse              | Beispiele                                | Default |
|---------------------|------------------------------------------|---------|
| `social_media`      | x.com, linkedin.com, threads.net         | allow   |
| `content_platforms` | youtube.com, medium.com, substack.com    | allow   |
| `dev_tools`         | github.com, gitlab.com, gist.github.com  | allow   |
| `analytics`         | google.com/analytics, ahrefs, semrush    | allow   |
| `ads`               | facebook.com/ads, ads.google.com         | ASK     |
| `banking`           | paypal.com, banking.*, *.bank            | DENY    |
| `payments`          | stripe.com, gumroad.com (own dashboard)  | allow   |
| `legal`             | court-systems, anwalt.de                 | DENY (Harvey only) |
| `government`        | bundes*.de, eu.europa.eu                 | ASK     |
| `unknown`           | alles andere                             | ASK     |

Override per Skill via `permissions.allowed_domains` möglich (mit Audit-Note).

---

## 6. Resource-Limits

| Resource          | Soft-Limit  | Hard-Limit | Action bei Hard          |
|-------------------|-------------|------------|--------------------------|
| RAM pro Skill     | 4 GB        | 8 GB       | Kill + Report            |
| CPU-Time          | 5 min       | 15 min     | Kill + Mark `timeout`    |
| File-Output-Size  | 100 MB      | 500 MB     | Abort + Cleanup          |
| Browser-Tabs      | 10          | 20         | Refuse new tab           |
| HTTP-Requests     | 1000/skill  | 5000/skill | Backoff + Refuse         |
| Parallel-Skills   | 5           | 10         | Queue                    |

---

## 7. Failure-Modes

| Failure                          | Default-Reaktion                   |
|----------------------------------|-------------------------------------|
| Skill wirft Exception            | Mark task `failed`, report to Hermes|
| Browser-Crash                    | Profile restart, retry 1×           |
| Network-Timeout                  | Backoff 30s, retry 3×               |
| LLM-Timeout (Ollama down)        | Wait 60s, ping `ollama list`, retry |
| Disk-Full                        | Cleanup `/tmp/openclaw-*` (>24h)    |
| Config-Mismatch                  | Refuse + alert Maurice              |

---

## 8. Inter-Agent-Rules

OpenClaw darf:
- **An Hermes** Results senden
- **An Hermes** Skill-Status melden (heartbeat, progress)
- **Aus KG lesen** (Read-Only)
- **In KG schreiben** für eigene Subgraph (`openclaw/`)

OpenClaw darf NICHT:
- Direkt an Jarvis senden (immer über Hermes)
- Direkt an Harvey senden (immer über Hermes)
- Jarvis Memory schreiben
- Harvey's Stripe-Logs lesen

---

## 9. Skill-Trust-Levels

| Level | Beispiele                            | Audit-Level | Approval                  |
|-------|--------------------------------------|-------------|---------------------------|
| `core`| pi-coder, content-engine, toggle-context | normal  | OpenClaw selbst entscheidet |
| `published`| x-twitter-browser, youtube-studio-uploader | full | Maurice-Confirm pro Run |
| `paid` | meta-ads                            | full       | Maurice + Budget          |
| `risky`| server-optimizer (Hetzner SSH)      | extra      | Maurice + Pre-Check       |

---

## 10. Was bei Updates / neuen Skills

- Neuer Skill kommt → muss in `/.openclaw/openclaw.json` registriert sein
- `SKILL.md` Pflicht (sonst Discovery scheitert)
- Security-Review: Skill liest System-Audit Skill durch (`system-audit`)
- 7-Tage-Probe-Phase mit `level: published` Audit + Maurice-Review
