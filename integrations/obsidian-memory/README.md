# Obsidian AI Memory System

A 3-tier long-term memory system for an AI assistant, built on a plain Obsidian
vault. The vault is just markdown — if your AI provider goes down or you
switch, the notes still work as a normal Obsidian vault. Zero vendor lockin.

## The 3 tiers

**Tier 1 — Hot memory** (`MEMORY.md`, `USER.md`)
Small (~9k chars), injected into every conversation. Preferences, active
projects, recent corrections, procedural quirks. The AI's working memory.

**Tier 2 — Vault living files** (`vault/*.md`)
When hot memory hits 67% capacity, stable entries get promoted here.
Environment configs, operational context, known failure patterns. Read
on demand by the AI.

**Tier 3 — Daily notes** (`daily/YYYY-MM-DD.md`)
One dated markdown file per day with tasks, schedule, log section. A
searchable timeline of every decision and action.

## Routing rules

| Where it goes | What goes there |
|---|---|
| Daily log | Meetings, calls, decisions |
| `vault/TROUBLESHOOTING.md` | System issues, technical fixes |
| `MEMORY.md` (hot) | Learned corrections — promote to vault when stable |
| `vault/SKILLS/*.md` | Recurring workflows as reusable skill files |
| `inbox/` | Unknown incoming, until classified |

## Quick start

```bash
# 1. Scaffold the vault
./setup-vault.sh ~/ObsidianVault

# 2. Copy your secrets
cp .env.example ~/ObsidianVault/.env
$EDITOR ~/ObsidianVault/.env

# 3. Generate today's daily note manually to test
VAULT=~/ObsidianVault ./scripts/generate-daily-note.sh

# 4. Send a test briefing
VAULT=~/ObsidianVault ./scripts/morning-briefing.sh

# 5. Wire up cron
crontab crontab.example
```

## File layout in the vault

```
ObsidianVault/
├── MEMORY.md                 # tier 1 hot memory
├── USER.md                   # tier 1 user profile
├── vault/                    # tier 2 living files
│   ├── ENVIRONMENT.md
│   ├── PROJECTS.md
│   ├── TROUBLESHOOTING.md
│   └── SKILLS/
├── daily/                    # tier 3 daily notes
│   └── 2026-04-27.md
├── inbox/                    # unclassified incoming
├── people/                   # one file per person, backlinked
├── work/                     # work context (separated)
├── personal/                 # personal context (separated)
└── .env                      # secrets, gitignored
```

## Cron schedule

| Time  | Job |
|-------|-----|
| 06:50 | `generate-daily-note.sh` — pull todoist + gcal, scaffold today's note |
| 07:00 | `morning-briefing.sh` — read daily note, send clean summary to Telegram |
| 09:00 | `finance-briefing.sh` — scrape Yahoo Finance for tracked tickers, send report |
| 22:00 | `wrap-up.sh` — append wins/losses prompt to daily note (optional) |

See `crontab.example` for the exact lines.

## System prompt

The AI is given `system-prompt.md` plus the contents of `MEMORY.md` and
`USER.md` injected on every turn. See that file for routing logic the AI
must follow when reading or writing the vault.

## Maintenance

See `MAINTENANCE.md` for the weekly + monthly checklist (orphan sweep,
hot-memory compaction, vault graph review).

## Work / personal separation

Briefings respect context. Set `BRIEFING_CONTEXT=work` or
`BRIEFING_CONTEXT=personal` in the cron environment — only matching folders
are read for that briefing's content.
