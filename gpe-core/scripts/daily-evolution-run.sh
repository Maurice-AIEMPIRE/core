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

# ── Allowed tools (WebFetch for GitHub API — no MCP needed) ──────────────────
ALLOWED_TOOLS="Read,Write,Edit,Glob,Grep,WebFetch,Bash(git add *),Bash(git commit *),Bash(git status),Bash(git log *),Bash(git diff *)"

# ── Prompt ────────────────────────────────────────────────────────────────────
PROMPT="You are running the GPE Daily Evolution Loop. Today is $DATE.
Working directory: $REPO_ROOT

Your job: execute these steps in order. Use WebFetch to access GitHub.

STEP 1 — Pre-Loop Check:
Read these files:
- $REPO_ROOT/gpe-core/evolution/EVOLUTION_LOG.yaml
- $REPO_ROOT/gpe-core/failures/FAILURE_REGISTRY.yaml
- $REPO_ROOT/gpe-core/evolution/LEARNING_QUEUE.yaml
Report: system version, open failures count, pending queue count, last run date.

STEP 2 — Pick Target Repos:
Read $REPO_ROOT/gpe-core/evolution/REPO_WATCHLIST.yaml.
Select the 2 CRITICAL-priority repos not already in EVOLUTION_LOG daily_runs.
These are the targets for today.

STEP 3 — Fetch and Analyze Each Repo:
For each target repo (format: owner/repo), fetch via WebFetch:
a) README: https://raw.githubusercontent.com/{owner}/{repo}/main/README.md
   (fallback: https://raw.githubusercontent.com/{owner}/{repo}/master/README.md)
b) If README mentions key files, fetch up to 2 more raw file URLs.

Then apply the repo-analyzer SKILL logic from:
$REPO_ROOT/gpe-core/skills/evolution/repo-analyzer/SKILL.md

Extract ONLY implementable improvements for GPE. No summaries. Be specific:
- What exactly to change (file path + what to add/modify)
- Effort: LOW / MEDIUM / HIGH
- Impact: HIGH / MEDIUM / LOW

STEP 4 — Write to LEARNING_QUEUE:
For each insight (minimum 2, maximum 5 per repo), append to:
$REPO_ROOT/gpe-core/evolution/LEARNING_QUEUE.yaml

Use this exact format for each entry:
  - id: LEARN-${DATE}-001
    source_repo: owner/repo
    discovered_at: $DATE
    domain: [domain from REPO_WATCHLIST]
    insight_type: [pattern|implementation|architecture|template|tool]
    title: [short title]
    description: >
      [2-3 sentences: what was found, why it matters, how it improves GPE]
    target_skill: [which GPE skill or file]
    implementation_effort: [LOW|MEDIUM|HIGH]
    expected_impact: [HIGH|MEDIUM|LOW]
    review_gate_passed: false
    status: discovered
    implemented_in_commit: null

STEP 5 — Update EVOLUTION_LOG:
Append under the 'daily_runs' key in $REPO_ROOT/gpe-core/evolution/EVOLUTION_LOG.yaml:
  - date: $DATE
    triggered_by: cron-daily
    repos_analyzed: [list of repos]
    insights_discovered: [count]
    open_failures: [count]
    pending_learning_queue: [count]
    notes: [brief summary]

STEP 6 — Git Commit:
Run: git -C $REPO_ROOT add gpe-core/evolution/
Run: git -C $REPO_ROOT commit -m 'chore(gpe-evolution): daily run $DATE — [N] insights queued from [repos]'

HARD CONSTRAINTS:
- Do NOT run self-patcher or apply any patches. Status stays 'discovered'.
- Do NOT push to remote. Local commit only.
- Do NOT touch RESOLVER.yaml, SKILL_INDEX.md, or any SKILL.md files.
- If a repo returns 404 or is rate-limited, skip it, log the skip, continue.
- Increment LEARN IDs sequentially: LEARN-${DATE}-001, LEARN-${DATE}-002, etc."

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
