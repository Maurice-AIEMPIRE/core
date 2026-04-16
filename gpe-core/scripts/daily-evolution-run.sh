#!/usr/bin/env bash
# GPE Core — Daily Evolution Run
# Runs every day via cron. Scouts repos, queues insights, logs results.
# Does NOT auto-apply patches — human approval required before self-patcher runs.

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLAUDE_BIN="${CLAUDE_BIN:-/opt/node22/bin/claude}"
LOG_DIR="$REPO_ROOT/gpe-core/evolution/logs"
DATE="$(date +%Y-%m-%d)"
LOG_FILE="$LOG_DIR/$DATE.log"
MAX_BUDGET_USD="${MAX_BUDGET_USD:-3.00}"

# ── Allowed tools (read + write only — no destructive ops) ────────────────────
ALLOWED_TOOLS="Read,Write,Edit,Glob,Grep,Bash(git add *),Bash(git commit *),Bash(git status),Bash(git log *),Bash(git diff *),mcp__github__search_repositories,mcp__github__get_file_contents,mcp__github__search_code"

# ── Prompt ────────────────────────────────────────────────────────────────────
PROMPT="You are running the GPE Daily Evolution Loop. Today is $DATE.

Your job: follow the evolution-loop SKILL strictly.

STEP 1 — Pre-Loop Check:
Read these files and report current state:
- $REPO_ROOT/gpe-core/evolution/EVOLUTION_LOG.yaml
- $REPO_ROOT/gpe-core/failures/FAILURE_REGISTRY.yaml
- $REPO_ROOT/gpe-core/evolution/LEARNING_QUEUE.yaml

STEP 2 — Repo Scout:
Read $REPO_ROOT/gpe-core/evolution/REPO_WATCHLIST.yaml.
Pick the 2 highest-priority repos NOT analyzed in the last 7 days (check EVOLUTION_LOG).
For each: use mcp__github__get_file_contents to read their README.md and core files.
Apply the repo-analyzer SKILL from $REPO_ROOT/gpe-core/skills/evolution/repo-analyzer/SKILL.md.
Extract only IMPLEMENTABLE improvements for GPE.

STEP 3 — Update LEARNING_QUEUE:
For each insight found, append a properly formatted entry to:
$REPO_ROOT/gpe-core/evolution/LEARNING_QUEUE.yaml
Set status: 'discovered'. Do NOT set status to 'approved' — that requires human review.

STEP 4 — Log Results:
Append a new entry to $REPO_ROOT/gpe-core/evolution/EVOLUTION_LOG.yaml with:
- date: $DATE
- triggered_by: cron-daily
- repos_analyzed: [list]
- insights_discovered: [count]
- open_failures: [count from FAILURE_REGISTRY]
- pending_learning_queue: [count]

STEP 5 — Git Commit:
Stage and commit all changed files in $REPO_ROOT/gpe-core/evolution/ with message:
'chore(gpe-evolution): daily run $DATE — auto-scout and queue update'

HARD CONSTRAINTS:
- Do NOT run self-patcher. Do NOT apply any patches. Human approval required.
- Do NOT push to remote. Commit only.
- Do NOT modify RESOLVER.yaml, SKILL_INDEX.md, or any SKILL.md files.
- If a repo is rate-limited or unavailable, skip it and log the skip.
- Maximum 2 repos per run to stay within budget."

# ── Run ───────────────────────────────────────────────────────────────────────
mkdir -p "$LOG_DIR"

{
  echo "=========================================="
  echo "GPE DAILY EVOLUTION RUN — $DATE"
  echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "Repo root: $REPO_ROOT"
  echo "Max budget: \$$MAX_BUDGET_USD"
  echo "=========================================="

  "$CLAUDE_BIN" \
    --print \
    --allowedTools "$ALLOWED_TOOLS" \
    --max-budget-usd "$MAX_BUDGET_USD" \
    --output-format text \
    -p "$PROMPT" \
    2>&1

  echo ""
  echo "=========================================="
  echo "Finished: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "=========================================="

} | tee "$LOG_FILE"

# ── Cleanup: keep only last 30 days of logs ────────────────────────────────
find "$LOG_DIR" -name "*.log" -mtime +30 -delete 2>/dev/null || true

echo "Log written to: $LOG_FILE"
