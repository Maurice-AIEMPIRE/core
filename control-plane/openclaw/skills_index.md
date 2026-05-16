# OpenClaw Skills Index

> **Quelle:** `/openclaw/workspace/skills/` + `/.openclaw/openclaw.json`
> **Plus:** Migrierte Friends-Skills (Kelly, Pam, Ryan, Ross → OpenClaw)

---

## 1. Active Skills (16 + Migrierte)

### 1.1 Code & Templates (ehem. Ryan)

| Skill            | Pfad                                                 | Status | Trigger                          |
|------------------|------------------------------------------------------|--------|----------------------------------|
| `pi-coder`       | `/openclaw/workspace/skills/pi-coder/SKILL.md`       | ✅     | "code", "script", "implement"    |
| `code-reviewer`  | (in workspace inline)                                | ✅     | "review code", "check pr"        |
| `automation-builder` | (in workspace inline)                            | ✅     | "automate X", "build automation" |

### 1.2 Content (ehem. Kelly für internal, ehem. Ross für YouTube)

| Skill                       | Pfad                                                       | Status |
|-----------------------------|------------------------------------------------------------|--------|
| `content-engine`            | `/openclaw/workspace/skills/content-engine/SKILL.md`       | ✅     |
| `x-twitter-browser`         | `/openclaw/workspace/skills/x-twitter-browser/SKILL.md`    | ✅     |
| `youtube-factory`           | `/openclaw/workspace/skills/youtube-factory/`              | ✅     |
| `thumbnail-optimizer`       | (linked from YOUTUBE_PIPELINE_SOP.md)                      | ✅     |
| `youtube-studio-uploader`   | `/openclaw/workspace/skills/youtube-studio-uploader/SKILL.md` | ✅  |

**Hinweis:** Content **für Maurice / internal Logs** → OpenClaw.
Content **für Kunden / Sales / Newsletter** → Harvey.

### 1.3 Marketing / Ads

| Skill           | Pfad                                                  | Status |
|-----------------|-------------------------------------------------------|--------|
| `meta-ads`      | `/openclaw/workspace/skills/meta-ads/SKILL.md`        | ✅     |
| `seo-ranker`    | `/openclaw/workspace/skills/seo-ranker/SKILL.md`      | ✅     |

### 1.4 Trading & Monitoring

| Skill              | Pfad                                                   | Status | Safety       |
|--------------------|--------------------------------------------------------|--------|--------------|
| `trading-monitor`  | `/openclaw/workspace/skills/trading-monitor/SKILL.md`  | ✅     | READ-ONLY    |

> Trading-**Entscheidungen** liegen bei Harvey (`risk-monitor`).
> Trading-**Monitoring** (Charts beobachten) liegt bei OpenClaw.

### 1.5 Operations & Memory

| Skill                       | Pfad                                                              | Status |
|-----------------------------|-------------------------------------------------------------------|--------|
| `agent-team-orchestration`  | (inline in workspace)                                              | ✅     |
| `self-improving-agent`      | `/openclaw/workspace/skills/self-improving-agent/`                 | ✅     |
| `laser-focus`               | (workspace policy)                                                  | ✅     |
| `agent-memory-ultimate`     | (workspace policy)                                                  | ✅     |
| `toggle-context`            | `/openclaw/workspace/skills/toggle-context/SKILL.md`               | ✅     |
| `server-optimizer`          | `/openclaw/workspace/skills/server-optimizer/SKILL.md`             | ✅     |
| `bookkeeper`                | (inline, schreibt REVENUE-LOG.md)                                  | ✅     |
| `agent-earner`              | (inline, Template-Verkauf)                                          | ✅     |

---

## 2. Skill-Activation (Hermes → OpenClaw)

Hermes ruft Skill via Bus-Message:

```json
{
  "from": "hermes",
  "to": "openclaw",
  "type": "task",
  "intent": "content_creation",
  "payload": {
    "skill": "content-engine",
    "args": {
      "topic": "KI-News diese Woche",
      "platforms": ["x", "linkedin"],
      "count": 10
    },
    "goal_id": "goal_01HXY1"
  }
}
```

OpenClaw antwortet:
```json
{
  "from": "openclaw",
  "to": "hermes",
  "type": "result",
  "reply_to": "<msg_id>",
  "payload": {
    "status": "done",
    "skill": "content-engine",
    "artifacts": [
      { "kind": "file", "path": "/tmp/x-posts-2026-05-16.md" },
      { "kind": "file", "path": "/tmp/linkedin-posts-2026-05-16.md" }
    ],
    "stats": { "duration_ms": 18420, "tokens": 12480 }
  }
}
```

---

## 3. Skill-Definition (Standard-Format)

Jeder Skill in `/openclaw/workspace/skills/<name>/SKILL.md` folgt:

```markdown
# Skill: <name>

## Purpose
Ein-Satz-Beschreibung.

## Inputs
| Field    | Type   | Required | Beispiel                |
|----------|--------|----------|-------------------------|
| topic    | string | yes      | "KI-News diese Woche"   |
| platforms| array  | yes      | ["x", "linkedin"]       |

## Outputs
| Field      | Type   | Beschreibung                  |
|------------|--------|-------------------------------|
| artifacts  | array  | Liste von { kind, path }      |

## Steps
1. Step eins
2. Step zwei

## Model
- Primary: ollama/qwen3:14b
- Fallback: ollama/qwen3:32b

## Safety
- Required confirmations
- Boundaries
```

---

## 4. Friends-Skill-Migration-Status

| Alter Friends-Agent | Skill in OpenClaw                     | Migration-Status |
|---------------------|----------------------------------------|------------------|
| Monica              | → Jarvis (nicht OpenClaw)              | n/a              |
| Dwight              | → Jarvis/Harvey (nicht OpenClaw)       | n/a              |
| Kelly               | `content-engine` + `x-twitter-browser` | ✅ existiert     |
| Pam                 | → Harvey (nicht OpenClaw)              | n/a              |
| Ryan                | `pi-coder`                             | ✅ existiert     |
| Chandler            | → Harvey (nicht OpenClaw)              | n/a              |
| Ross                | `youtube-factory` + `thumbnail-optimizer` | ✅ existiert  |

---

## 5. Hinzukommende Skills (Phase 2+)

Diese Skills brauchen wir noch:

| Skill              | Owner    | Phase | Beschreibung                              |
|--------------------|----------|-------|-------------------------------------------|
| `obsidian-sync`    | OpenClaw | 3     | Sync Vault ↔ Knowledge Graph              |
| `codex-runner`     | OpenClaw | 3     | Codex CLI wrap                            |
| `claude-code-runner` | OpenClaw | 3   | Claude Code CLI wrap                      |
| `hetzner-deploy`   | OpenClaw | 4     | Deploy via SSH zum Server                 |
| `mcp-bridge`       | OpenClaw | 4     | Beliebige MCP-Server proxen              |

---

## 6. Skill-Discovery

OpenClaw kennt seine Skills aus zwei Quellen:

1. **Config:** `/.openclaw/openclaw.json` → `skills.entries` (statisch, 16 Stück)
2. **Discovery:** `/openclaw/workspace/skills/*/SKILL.md` (dynamisch, beim Start gescannt)

Bei Konflikt: **Config gewinnt** (Quelle of Truth = `.openclaw/openclaw.json`).

---

## 7. Skill-Permissions

| Skill                | Reads | Writes | Network | Browser | Spend |
|----------------------|-------|--------|---------|---------|-------|
| pi-coder             | ✅    | ✅     | ❌      | ❌      | ❌    |
| content-engine       | ✅    | ✅     | ❌      | ❌      | ❌    |
| x-twitter-browser    | ✅    | ❌     | ✅      | ✅      | ❌    |
| youtube-factory      | ✅    | ✅     | ✅      | ❌      | ❌    |
| youtube-studio-uploader | ✅ | ❌     | ✅      | ✅      | ❌    |
| meta-ads             | ✅    | ✅     | ✅      | ✅      | ⚠️ ASK |
| seo-ranker           | ✅    | ✅     | ✅      | ❌      | ❌    |
| trading-monitor      | ✅    | ❌     | ✅      | ❌      | ❌    |
| server-optimizer     | ✅    | ✅     | ❌      | ❌      | ❌    |
| bookkeeper           | ✅    | ✅     | ❌      | ❌      | ❌    |

⚠️ ASK = User-Confirmation erforderlich

---

## 8. Beziehung zu GPE-Core Skills

GPE-Core hatte 18 zusätzliche Skills (siehe `/gpe-core/SKILL_INDEX.md`).
Migration:

| GPE-Skill            | Neue Heimat            | Migration |
|----------------------|------------------------|-----------|
| legal-opponent       | Harvey                 | Phase 2   |
| legal-settlement     | Harvey                 | Phase 2   |
| legal-claims         | Harvey                 | Phase 2   |
| legal-evidence       | Harvey                 | Phase 2   |
| legal-warroom        | Harvey                 | Phase 2   |
| legal-consistency    | Harvey                 | Phase 2   |
| risk-monitor         | Harvey                 | Phase 2   |
| revenue-audit        | Harvey                 | Phase 2   |
| sales-leadgen        | Harvey                 | Phase 2   |
| evolution-loop       | OpenClaw (self-improving-agent) | bereits |
| repo-scout           | OpenClaw               | Phase 3   |
| repo-analyzer        | OpenClaw               | Phase 3   |
| self-patcher         | OpenClaw               | Phase 3   |
| nucleus              | Hermes (Goal-Orchestration) | Phase 2 |
| data-ops             | OpenClaw               | Phase 3   |
| system-audit         | Hermes                 | Phase 2   |
