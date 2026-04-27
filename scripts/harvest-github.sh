#!/usr/bin/env bash
# harvest-github.sh — clone every repo from one or more GitHub accounts
# and produce an inventory report, so you can decide what to keep, archive,
# or delete.
#
# usage:
#   GITHUB_TOKEN=ghp_xxx ./harvest-github.sh <account1> [account2 ...]
#
# env:
#   GITHUB_TOKEN     required — personal access token with `repo` scope
#   TARGET_DIR       default: ./harvest  (where repos get cloned)
#   INCLUDE_FORKS    default: no   (set yes to also clone forks)
#   INCLUDE_ARCHIVED default: yes  (set no to skip archived repos)
#   PROTOCOL         default: https (or `ssh` if you have keys configured)
#
# output:
#   $TARGET_DIR/<account>/<repo>/   — a working clone of every repo
#   $TARGET_DIR/INVENTORY.md         — markdown report you can read top-to-bottom

set -euo pipefail

if [[ $# -lt 1 ]]; then
    cat >&2 <<'EOF'
usage: GITHUB_TOKEN=ghp_xxx ./harvest-github.sh <account1> [account2 ...]

example:
  GITHUB_TOKEN=ghp_xxx ./harvest-github.sh mauricepfeifer-ctrl Maurice-AIEMPIRE
EOF
    exit 1
fi

: "${GITHUB_TOKEN:?GITHUB_TOKEN env var is required (https://github.com/settings/tokens)}"

TARGET_DIR="${TARGET_DIR:-./harvest}"
INCLUDE_FORKS="${INCLUDE_FORKS:-no}"
INCLUDE_ARCHIVED="${INCLUDE_ARCHIVED:-yes}"
PROTOCOL="${PROTOCOL:-https}"

mkdir -p "$TARGET_DIR"
INVENTORY="$TARGET_DIR/INVENTORY.md"

{
    echo "# GitHub repo inventory"
    echo
    echo "_generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)_"
    echo
} > "$INVENTORY"

api() {
    curl -fsS \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H 'Accept: application/vnd.github+json' \
        -H 'X-GitHub-Api-Version: 2022-11-28' \
        "$@"
}

# Decide if account is a user or an org (try /user first, fall back to /org).
account_type() {
    local acc="$1"
    if api "https://api.github.com/users/$acc" | grep -q '"type": *"Organization"'; then
        echo org
    else
        echo user
    fi
}

# List repos for an account, paginated, output one JSON per line.
list_repos() {
    local acc="$1" type="$2"
    local endpoint
    if [[ "$type" == "org" ]]; then
        endpoint="https://api.github.com/orgs/$acc/repos"
    else
        # /user/repos returns YOUR repos when token belongs to that user;
        # falls back to /users/$acc/repos for public-only listing.
        endpoint="https://api.github.com/user/repos?affiliation=owner,collaborator,organization_member"
        # If the token doesn't belong to $acc, this returns empty; in that case use public listing.
        local probe
        probe="$(api "https://api.github.com/user" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("login",""))')"
        if [[ "$probe" != "$acc" ]]; then
            endpoint="https://api.github.com/users/$acc/repos"
        fi
    fi
    local page=1
    while :; do
        local body
        body="$(api "${endpoint}$( [[ "$endpoint" == *\?* ]] && echo "&" || echo "?" )per_page=100&page=$page")"
        # Stop on empty array.
        local count
        count="$(printf '%s' "$body" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
        [[ "$count" -eq 0 ]] && break
        printf '%s' "$body" | python3 -c '
import json, sys
for r in json.load(sys.stdin):
    print(json.dumps({
        "name":        r["name"],
        "full_name":   r["full_name"],
        "ssh_url":     r["ssh_url"],
        "clone_url":   r["clone_url"],
        "fork":        r.get("fork", False),
        "archived":    r.get("archived", False),
        "private":     r.get("private", False),
        "language":    r.get("language") or "",
        "size_kb":     r.get("size", 0),
        "description": r.get("description") or "",
        "pushed_at":   r.get("pushed_at") or "",
        "default_branch": r.get("default_branch") or "main",
    }))
'
        ((page++))
        [[ "$count" -lt 100 ]] && break
    done
}

clone_or_update() {
    local url="$1" dest="$2"
    if [[ -d "$dest/.git" ]]; then
        git -C "$dest" fetch --all --prune --quiet || echo "  fetch failed: $dest" >&2
    else
        git clone --quiet "$url" "$dest" || echo "  clone failed: $url" >&2
    fi
}

inspect_repo() {
    local dir="$1"
    local has_readme=no has_tests=no has_ci=no last_commit="" loc=0
    [[ -f "$dir/README.md" || -f "$dir/README" || -f "$dir/readme.md" ]] && has_readme=yes
    [[ -d "$dir/test" || -d "$dir/tests" || -d "$dir/__tests__" || -d "$dir/spec" ]] && has_tests=yes
    [[ -d "$dir/.github/workflows" || -f "$dir/.gitlab-ci.yml" || -f "$dir/.circleci/config.yml" ]] && has_ci=yes
    last_commit="$(git -C "$dir" log -1 --format='%cs %s' 2>/dev/null | head -c 120 || true)"
    loc="$(git -C "$dir" ls-files 2>/dev/null | wc -l | tr -d ' ')"
    echo "readme=$has_readme tests=$has_tests ci=$has_ci files=$loc last=\"$last_commit\""
}

for ACCOUNT in "$@"; do
    echo "==> harvesting $ACCOUNT"
    TYPE="$(account_type "$ACCOUNT")"
    DEST_ROOT="$TARGET_DIR/$ACCOUNT"
    mkdir -p "$DEST_ROOT"

    {
        echo "## $ACCOUNT ($TYPE)"
        echo
        echo "| repo | language | size | last push | files | readme | tests | ci | description |"
        echo "|------|----------|------|-----------|-------|--------|-------|----|-------------|"
    } >> "$INVENTORY"

    list_repos "$ACCOUNT" "$TYPE" | while IFS= read -r json; do
        name=$(printf '%s' "$json" | python3 -c 'import json,sys;print(json.load(sys.stdin)["name"])')
        is_fork=$(printf '%s' "$json" | python3 -c 'import json,sys;print(json.load(sys.stdin)["fork"])')
        is_archived=$(printf '%s' "$json" | python3 -c 'import json,sys;print(json.load(sys.stdin)["archived"])')

        if [[ "$is_fork" == "True" && "$INCLUDE_FORKS" != "yes" ]]; then
            echo "  skip (fork): $name"
            continue
        fi
        if [[ "$is_archived" == "True" && "$INCLUDE_ARCHIVED" != "yes" ]]; then
            echo "  skip (archived): $name"
            continue
        fi

        if [[ "$PROTOCOL" == "ssh" ]]; then
            url=$(printf '%s' "$json" | python3 -c 'import json,sys;print(json.load(sys.stdin)["ssh_url"])')
        else
            base=$(printf '%s' "$json" | python3 -c 'import json,sys;print(json.load(sys.stdin)["clone_url"])')
            # inject token for private repos
            url="${base/https:\/\//https://x-access-token:$GITHUB_TOKEN@}"
        fi

        dest="$DEST_ROOT/$name"
        echo "  $name"
        clone_or_update "$url" "$dest"

        # Inventory row
        if [[ -d "$dest/.git" ]]; then
            eval "$(inspect_repo "$dest")"
            lang=$(printf '%s' "$json" | python3 -c 'import json,sys;print(json.load(sys.stdin)["language"])')
            size_kb=$(printf '%s' "$json" | python3 -c 'import json,sys;print(json.load(sys.stdin)["size_kb"])')
            pushed=$(printf '%s' "$json" | python3 -c 'import json,sys;print(json.load(sys.stdin)["pushed_at"][:10])')
            desc=$(printf '%s' "$json" | python3 -c 'import json,sys;d=json.load(sys.stdin)["description"];print(d.replace("|"," ")[:80])')
            printf '| [%s](./%s/%s) | %s | %sKB | %s | %s | %s | %s | %s | %s |\n' \
                "$name" "$ACCOUNT" "$name" "$lang" "$size_kb" "$pushed" "$files" "$readme" "$tests" "$ci" "$desc" \
                >> "$INVENTORY"
        fi
    done
    echo >> "$INVENTORY"
done

echo
echo "done."
echo "  repos:     $TARGET_DIR/<account>/<repo>"
echo "  inventory: $INVENTORY"
