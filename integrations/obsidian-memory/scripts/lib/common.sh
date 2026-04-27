#!/usr/bin/env bash
# Shared helpers. Source me, don't run me.

set -euo pipefail

require() {
    local name="$1"
    if [[ -z "${!name:-}" ]]; then
        echo "missing required env var: $name" >&2
        exit 1
    fi
}

load_env() {
    local vault="${VAULT:-}"
    if [[ -n "$vault" && -f "$vault/.env" ]]; then
        set -a
        # shellcheck disable=SC1091
        . "$vault/.env"
        set +a
    fi
}

today_iso() { date +%Y-%m-%d; }

today_weekday() { date +%A; }

# Escape a string for safe insertion into Markdown line content.
md_escape() { sed 's/[][\\]/\\&/g'; }

# Append a timestamped log line to today's daily note.
log_line() {
    local vault="$1" line="$2"
    local note="$vault/daily/$(today_iso).md"
    if [[ ! -f "$note" ]]; then
        echo "daily note missing: $note" >&2
        return 1
    fi
    printf -- '- %s %s\n' "$(date +%H:%M)" "$line" >> "$note"
}
