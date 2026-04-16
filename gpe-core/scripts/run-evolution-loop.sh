#!/usr/bin/env bash
# GPE Core — Evolution Loop Runner
# Simpler wrapper: reads LEARNING_QUEUE for approved items, calls self-patcher.
# Called manually or by evolution-loop skill after human approval step.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QUEUE="$REPO_ROOT/gpe-core/evolution/LEARNING_QUEUE.yaml"
LOG_DIR="$REPO_ROOT/gpe-core/evolution/logs"
DATE="$(date +%Y-%m-%d)"
LOG_FILE="$LOG_DIR/$DATE-patcher.log"

mkdir -p "$LOG_DIR"

echo "GPE Evolution Loop — $DATE" | tee "$LOG_FILE"
echo "Checking LEARNING_QUEUE for approved items..." | tee -a "$LOG_FILE"

# Count approved items
APPROVED=$(grep -c "status: approved" "$QUEUE" 2>/dev/null || echo 0)

if [[ "$APPROVED" -eq 0 ]]; then
  echo "No approved items in LEARNING_QUEUE. Nothing to patch." | tee -a "$LOG_FILE"
  echo "To approve items: edit LEARNING_QUEUE.yaml and set status: approved" | tee -a "$LOG_FILE"
  exit 0
fi

echo "Found $APPROVED approved item(s). Running self-patcher..." | tee -a "$LOG_FILE"

# Trigger daily-evolution-run with self-patcher mode
CLAUDE_BIN="${CLAUDE_BIN:-$(which claude 2>/dev/null)}"

"$CLAUDE_BIN" \
  --print \
  --allowedTools "Read,Write,Edit,Glob,Grep,Bash(git add *),Bash(git commit *),Bash(git status)" \
  --max-budget-usd "${MAX_BUDGET_USD:-2.00}" \
  -p "Run the GPE self-patcher skill: $REPO_ROOT/gpe-core/skills/evolution/self-patcher/SKILL.md

Read $QUEUE and apply ALL items with status: approved.
For each: implement the change, update status to 'implemented', log to EVOLUTION_LOG.yaml.
Do NOT touch items with status: discovered or validated.
Commit all changes when done." \
  2>&1 | tee -a "$LOG_FILE"

echo "Self-patcher complete. Check $LOG_FILE for results." | tee -a "$LOG_FILE"
