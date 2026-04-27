#!/usr/bin/env bash
# 09:00 cron: scrape Yahoo Finance for tracked tickers, classify headlines,
# send a mini market report to Telegram. Also append a copy to today's
# daily note under a `## Finance` block.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib/common.sh"
# shellcheck disable=SC1091
. "$HERE/lib/yahoo.sh"
# shellcheck disable=SC1091
. "$HERE/lib/telegram.sh"
load_env

require VAULT
require TICKERS

DATE="$(today_iso)"
NOTE="$VAULT/daily/$DATE.md"

REPORT="$(mktemp)"
trap 'rm -f "$REPORT"' EXIT

{
    printf '*Finance — %s*\n\n' "$DATE"

    # Quote table
    yahoo_quote "$TICKERS" | while read -r sym px chg; do
        printf '`%-6s` %s (%s)\n' "$sym" "$px" "$chg"
    done

    printf '\n*Headlines*\n'
    IFS=',' read -ra SYMS <<< "$TICKERS"
    for s in "${SYMS[@]}"; do
        H="$(yahoo_headlines "$s" || true)"
        if [[ -n "$H" ]]; then
            printf '\n*%s*\n%s\n' "$s" "$H"
        fi
    done
} > "$REPORT"

telegram_send < "$REPORT"

# Append to today's daily note, scaffolding it first if missing.
if [[ ! -f "$NOTE" ]]; then
    "$HERE/generate-daily-note.sh"
fi

if ! grep -q '^## Finance$' "$NOTE"; then
    {
        printf '\n## Finance\n'
        cat "$REPORT"
    } >> "$NOTE"
fi

log_line "$VAULT" "finance briefing sent ($TICKERS)"
