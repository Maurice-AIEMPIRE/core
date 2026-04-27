#!/usr/bin/env bash
# Find vault notes that no other note links to. Prints a list to stdout and
# (optionally) writes it to vault/ORPHANS.md so the AI can review weekly.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib/common.sh"
load_env

require VAULT

OUT="${1:-$VAULT/vault/ORPHANS.md}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# All markdown files, relative to the vault, minus archive/.
( cd "$VAULT" && find . -type f -name '*.md' \
        -not -path './archive/*' \
        -not -path './.obsidian/*' ) | sort > "$TMP/all"

# Pull every [[wikilink]] target from every note. Strip alias and heading.
( cd "$VAULT" && find . -type f -name '*.md' -not -path './archive/*' -print0 |
    xargs -0 grep -hoE '\[\[[^]]+\]\]' 2>/dev/null || true ) |
    sed -E 's/\[\[([^|#]+)([|#].*)?\]\]/\1/' |
    sort -u > "$TMP/linked"

{
    printf '# Orphans — %s\n\n' "$(today_iso)"
    printf 'Notes with no inbound `[[wikilinks]]`. Review and either link, '
    printf 'archive, or delete.\n\n'

    while IFS= read -r path; do
        # basename without .md
        base="${path##*/}"; base="${base%.md}"
        # Skip the special always-loaded files.
        case "$base" in
            MEMORY|USER|README|INDEX|ORPHANS) continue ;;
        esac
        if ! grep -qx "$base" "$TMP/linked"; then
            printf -- '- `%s`\n' "$path"
        fi
    done < "$TMP/all"
} > "$OUT"

echo "wrote $OUT"
