# Skills (Referenz-Index)

> **Hinweis:** Skills selbst liegen in `/openclaw/workspace/skills/`.
> Dieser Ordner ist Index + Cross-Reference, **kein** Skill-Storage.

---

## Master-Index

Siehe `/control-plane/openclaw/skills_index.md` für die komplette Liste der 16 OpenClaw-Skills + Migrationsstatus aus GPE-Core.

---

## Skill-Owner-Mapping

| Skill                    | Owner-Agent | Domain          |
|--------------------------|-------------|-----------------|
| pi-coder                 | OpenClaw    | Code            |
| content-engine           | OpenClaw    | Content         |
| x-twitter-browser        | OpenClaw    | Social          |
| youtube-factory          | OpenClaw    | YouTube         |
| thumbnail-optimizer      | OpenClaw    | Visual          |
| youtube-studio-uploader  | OpenClaw    | YouTube-Upload  |
| meta-ads                 | OpenClaw    | Ads             |
| seo-ranker               | OpenClaw    | SEO             |
| trading-monitor          | OpenClaw    | Trading-Watch   |
| server-optimizer         | OpenClaw    | Ops             |
| toggle-context           | OpenClaw    | Context-Mgmt    |
| agent-team-orchestration | OpenClaw    | Meta            |
| self-improving-agent     | OpenClaw    | Evolution       |
| laser-focus              | OpenClaw    | Discipline      |
| agent-memory-ultimate    | OpenClaw    | Memory (own)    |
| bookkeeper               | OpenClaw    | Revenue-Log     |
| agent-earner             | OpenClaw    | Template-Sales  |
| legal-opponent           | Harvey      | Legal           |
| legal-settlement         | Harvey      | Legal           |
| legal-claims             | Harvey      | Legal           |
| legal-evidence           | Harvey      | Legal           |
| legal-warroom            | Harvey      | Legal           |
| legal-consistency        | Harvey      | Legal           |
| risk-monitor             | Harvey      | Trading-Risk    |
| sales-leadgen            | Harvey      | Sales           |
| revenue-audit            | Harvey      | Business        |
| customer-communication   | Harvey      | Sales/Support   |

---

## Skill-Discovery (für Hermes)

Beim Start scant Hermes:
1. `/.openclaw/openclaw.json` → `skills.entries` (deklariert)
2. `/openclaw/workspace/skills/*/SKILL.md` (vorhanden)
3. `/control-plane/openclaw/skills_index.md` (kanonische Liste)

Bei Mismatch: Warning in Hermes-Log + Maurice-Alert.
