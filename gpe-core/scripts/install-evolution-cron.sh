#!/usr/bin/env bash
# GPE Core — Evolution Cron Only
# Assumes: repo already cloned, cron already running.
# Run once: bash gpe-core/scripts/install-evolution-cron.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/gpe-core/scripts/daily-evolution-run.sh"
CRON_FILE="/etc/cron.d/gpe-evolution"
CRON_HOUR="${CRON_HOUR:-3}"
LOG="$REPO_ROOT/gpe-core/evolution/logs/cron-scheduler.log"

# Detect claude binary
CLAUDE_BIN="${CLAUDE_BIN:-$(which claude 2>/dev/null || echo '')}"
[[ -z "$CLAUDE_BIN" ]] && { echo "ERROR: claude not found. Set CLAUDE_BIN=/path/to/claude"; exit 1; }

chmod +x "$SCRIPT"
mkdir -p "$REPO_ROOT/gpe-core/evolution/logs"

cat > "$CRON_FILE" << EOF
# GPE Core — Daily Evolution Loop
SHELL=/bin/bash
PATH=$(dirname "$CLAUDE_BIN"):/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
CLAUDE_BIN=$CLAUDE_BIN
MAX_BUDGET_USD=3.00

0 ${CRON_HOUR} * * * root source /root/.env 2>/dev/null; ${SCRIPT} >> ${LOG} 2>&1
EOF

chmod 644 "$CRON_FILE"

echo "Done. Evolution loop runs daily at ${CRON_HOUR}:00 AM."
echo "Test now: bash $SCRIPT"
