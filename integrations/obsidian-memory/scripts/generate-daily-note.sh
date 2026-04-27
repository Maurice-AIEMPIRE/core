#!/usr/bin/env bash
# 06:50 cron: scaffold today's daily note from Todoist + Google Calendar.
# Idempotent — re-running on the same day will not clobber log/wins/losses.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib/common.sh"
load_env

require VAULT
mkdir -p "$VAULT/daily"

DATE="$(today_iso)"
WEEKDAY="$(today_weekday)"
NOTE="$VAULT/daily/$DATE.md"
TPL="$HERE/../templates/daily-note.md"

if [[ -f "$NOTE" ]]; then
    echo "daily note already exists, skipping scaffold: $NOTE" >&2
    exit 0
fi

# shellcheck disable=SC1091
. "$HERE/lib/todoist.sh"
# shellcheck disable=SC1091
. "$HERE/lib/gcal.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

gcal_today          > "$TMP/schedule" 2>/dev/null || echo '- (no events)'   > "$TMP/schedule"
[[ -s "$TMP/schedule" ]] || echo '- (no events)' > "$TMP/schedule"

todoist_today       > "$TMP/tasks_all" 2>/dev/null || true
grep -v '(overdue)' "$TMP/tasks_all" > "$TMP/tasks" || true
[[ -s "$TMP/tasks" ]] || echo '- (no tasks)' > "$TMP/tasks"

todoist_overdue     > "$TMP/overdue" 2>/dev/null || true
[[ -s "$TMP/overdue" ]] || echo '- (none)' > "$TMP/overdue"

grep -E '\((p1|p2)\)' "$TMP/tasks" | head -3 > "$TMP/priority" || true
[[ -s "$TMP/priority" ]] || echo '- (set top-3 in the morning)' > "$TMP/priority"

CONTEXT="${BRIEFING_CONTEXT:-personal}"

DATE="$DATE" WEEKDAY="$WEEKDAY" CONTEXT="$CONTEXT" \
TPL="$TPL" NOTE="$NOTE" TMP="$TMP" \
python3 <<'PY'
import os, pathlib
tpl  = pathlib.Path(os.environ["TPL"]).read_text()
read = lambda n: pathlib.Path(os.environ["TMP"], n).read_text().rstrip()
out  = (tpl
    .replace("{{DATE}}",     os.environ["DATE"])
    .replace("{{WEEKDAY}}",  os.environ["WEEKDAY"])
    .replace("{{CONTEXT}}",  os.environ["CONTEXT"])
    .replace("{{SCHEDULE}}", read("schedule"))
    .replace("{{TASKS}}",    read("tasks"))
    .replace("{{OVERDUE}}",  read("overdue"))
    .replace("{{PRIORITY}}", read("priority"))
)
pathlib.Path(os.environ["NOTE"]).write_text(out)
PY

echo "wrote $NOTE"
