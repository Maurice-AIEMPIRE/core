#!/usr/bin/env bash
# Check MEMORY.md occupancy. If over 67% of budget, print a promotion plan
# to stdout. Does NOT mutate the vault — the AI does the actual moves so it
# can apply judgement on what to promote vs archive vs drop.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib/common.sh"
load_env

require VAULT
BUDGET=${MEMORY_BUDGET:-9000}
THRESHOLD=$(( BUDGET * 67 / 100 ))

MEM="$VAULT/MEMORY.md"
[[ -f "$MEM" ]] || { echo "no MEMORY.md found at $MEM" >&2; exit 1; }

SIZE=$(wc -c < "$MEM" | tr -d ' ')

printf 'MEMORY.md: %s / %s chars (threshold %s)\n' "$SIZE" "$BUDGET" "$THRESHOLD"

if (( SIZE < THRESHOLD )); then
    echo 'under threshold — no compaction needed.'
    exit 0
fi

echo
echo 'OVER THRESHOLD. Suggested promotion targets:'
echo
echo '- Active projects → vault/PROJECTS.md'
echo '- Procedural quirks → vault/ENVIRONMENT.md (or USER.md if profile-level)'
echo '- Recurring workflows seen 3+ times → vault/SKILLS/<name>.md'
echo '- Recent corrections older than 14d → review for promotion or archive'
echo
echo 'Hand this output to the AI; it should follow the compaction protocol'
echo 'in system-prompt.md (promote, archive, or drop — never silently lose).'
