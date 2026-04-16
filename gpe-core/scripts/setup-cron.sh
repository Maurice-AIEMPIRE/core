#!/usr/bin/env bash
# GPE Core — Cron Setup
# Installs the daily evolution run via /etc/cron.d/ (requires root).
# Run once: bash gpe-core/scripts/setup-cron.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/gpe-core/scripts/daily-evolution-run.sh"
CRON_FILE="/etc/cron.d/gpe-evolution"
CRON_HOUR="${CRON_HOUR:-3}"   # Default: 3 AM
LOG="$REPO_ROOT/gpe-core/evolution/logs/cron-scheduler.log"

# Make the run script executable
chmod +x "$SCRIPT"

cat > "$CRON_FILE" << EOF
# GPE Core — Daily Evolution Loop
# Runs every day at 0${CRON_HOUR}:00 AM
SHELL=/bin/bash
PATH=/opt/node22/bin:/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
CLAUDE_BIN=/opt/node22/bin/claude
MAX_BUDGET_USD=3.00

0 ${CRON_HOUR} * * * root ${SCRIPT} >> ${LOG} 2>&1
EOF

chmod 644 "$CRON_FILE"

echo "Cron job installed: $CRON_FILE"
echo "Schedule: 0${CRON_HOUR}:00 AM daily"
echo "Log: $LOG"
echo ""
echo "To change time: CRON_HOUR=6 bash gpe-core/scripts/setup-cron.sh"
echo "To remove:      rm $CRON_FILE"
