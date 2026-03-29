# Galaxia Brain — Claude Code Instructions

This repository is the **Maurice AI Empire** — a fully automated AI system with
persistent memory across all subsystems. Claude Code is the primary development brain.

## Memory First — Always

At the start of every session, query CORE memory for relevant context:

```
Search core memory for context about [current task or file being worked on]
```

Before making architectural decisions:
```
Search core memory for past decisions about [topic]
```

## MCP Configuration

CORE memory is connected via MCP. The server runs on Hetzner.

If not yet connected, run in terminal:
```bash
claude mcp add --transport http --scope user core-memory http://HETZNER_IP:3033/api/v1/mcp
```

Then authenticate: `/mcp` → core-memory → Browser-Login

## Brain Sources

Each subsystem tags its memories with a source. Use these to filter searches:

| Source | What it contains |
|--------|-----------------|
| `claude-code` | Code decisions, architecture choices, bug fixes |
| `openclaw` | Agent states, Monica/Dwight/Kelly/... actions, revenue data |
| `galaxia` | Planet results, research discoveries, vector knowledge |
| `mac` | Local Mac files, iCloud documents |
| `telegram` | Telegram bot interactions, user feedback |

## Always Store Important Discoveries

When you find something important, store it in CORE:
- Architectural decisions: `remember this decision: [what and why]`
- Bug patterns: `remember this bug pattern: [description]`
- User preferences: `remember Maurice prefers: [preference]`

## Galaxia Brain Architecture

```
CORE Memory (Hetzner :3033)     ← Single source of truth
    ↑ REST API / MCP
    ├── Claude Code Brain        (you — via MCP)
    ├── OpenClaw Brain Sync      (openclaw/brain/sync-to-core.ts, every 15min)
    ├── Galaxia Vector Bridge    (galaxia/brain/galaxia-bridge.ts, every 30min)
    └── Mac Brain / iCloud       (integrations/mac-brain/, Port 9001)
                                         ↓ SSH
                               ~/iCloud Drive/GalaxiaBrain/
```

## Key Commands

```bash
# Start all brain services
bash server/scripts/start-all.sh

# Manual OpenClaw sync to CORE
cd /path/to/repo && node openclaw/brain/sync-to-core.js

# Manual Galaxia sync to CORE
node galaxia/brain/galaxia-bridge.js

# Write document to iCloud
bash integrations/mac-brain/icloud-writer.sh "Title" "Content" "GalaxiaBrain"

# Setup everything from scratch
bash scripts/setup-galaxia-brain.sh
```

## Inner Circle Agents

The system runs 7 AI agents on Hetzner:
- **Monica** — CEO & Orchestrator
- **Dwight** — Research Lead
- **Kelly** — X/Content Creator
- **Pam** — Newsletter & Products
- **Ryan** — Code & Templates
- **Chandler** — Sales & Freelance
- **Ross** — YouTube

Agent states sync automatically to CORE memory every 15 minutes.

## iCloud Document Output

Final documents land in:
`~/iCloud Drive/GalaxiaBrain/[YYYY-MM-DD]-[title].md`

To trigger document creation from code, use the GalaxiaBrain client:
```typescript
import { brain } from "@core/galaxia-brain";
await brain.generateDocument("My Document Title", content);
```
