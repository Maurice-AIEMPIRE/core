#!/usr/bin/env bash
# 07:00 cron: read today's daily note, send a clean briefing to Telegram.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib/common.sh"
# shellcheck disable=SC1091
. "$HERE/lib/telegram.sh"
load_env

require VAULT
DATE="$(today_iso)"
NOTE="$VAULT/daily/$DATE.md"

if [[ ! -f "$NOTE" ]]; then
    "$HERE/generate-daily-note.sh"
fi

# Pull each section out of the note. Sections are `## Title` blocks.
section() {
    awk -v sec="$1" '
        $0 ~ "^## " sec "$" { in_sec = 1; next }
        /^## /                { in_sec = 0 }
        in_sec                { print }
    ' "$NOTE" | sed '/^[[:space:]]*$/d'
}

CONTEXT="${BRIEFING_CONTEXT:-personal}"
WEEKDAY="$(today_weekday)"

{
    printf '*Morning briefing — %s (%s)*\n' "$DATE" "$WEEKDAY"
    printf '_context: %s_\n\n' "$CONTEXT"

    printf '*Schedule*\n'
    section Schedule || echo '- (none)'
    printf '\n'

    printf '*Top priority*\n'
    section Priority || echo '- (none)'
    printf '\n'

    OVR="$(section Overdue || true)"
    if [[ -n "$OVR" && "$OVR" != '- (none)' ]]; then
        printf '*Overdue*\n%s\n\n' "$OVR"
    fi

    TASKS="$(section Tasks || true)"
    if [[ -n "$TASKS" ]]; then
        N=$(printf '%s\n' "$TASKS" | wc -l | tr -d ' ')
        printf '*Tasks today:* %s\n' "$N"
    fi
} | telegram_send

log_line "$VAULT" "morning briefing sent (context=$CONTEXT)"
