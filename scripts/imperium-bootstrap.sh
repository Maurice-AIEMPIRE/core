#!/usr/bin/env bash
# imperium-bootstrap.sh — sets up the GitHub import quarantine zone:
#   /opt/imperium/imports/github   — quarantine for cloned repos
#   /opt/imperium/audit/github     — analysis reports
#   /opt/imperium/build            — isolated test sandbox
#   /opt/imperium/apps             — vetted production modules
#   /opt/imperium/systemd          — vetted systemd units
#
# Writes three scripts:
#   /root/safe-harvest-github.sh
#   /opt/imperium/audit/github/inventory.sh
#   /opt/imperium/audit/github/risk_scan.sh
#
# Idempotent: safe to re-run.

set -Eeuo pipefail

mkdir -p /opt/imperium/imports/github
mkdir -p /opt/imperium/audit/github
mkdir -p /opt/imperium/build
mkdir -p /opt/imperium/apps
mkdir -p /opt/imperium/systemd

# 1) safe-harvest-github.sh — uses gh CLI + jq, no eval, no token in env
cat > /root/safe-harvest-github.sh <<'HARVEST_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_DIR="${TARGET_DIR:-/opt/imperium/imports/github}"
INCLUDE_FORKS="${INCLUDE_FORKS:-no}"
INCLUDE_ARCHIVED="${INCLUDE_ARCHIVED:-yes}"

mkdir -p "$TARGET_DIR"

for cmd in gh jq git; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: $cmd missing — apt-get install -y $cmd" >&2
        exit 1
    fi
done

if ! gh auth status >/dev/null 2>&1; then
    echo "ERROR: gh CLI not authenticated. Run: gh auth login" >&2
    exit 1
fi

if [[ "$#" -lt 1 ]]; then
    echo "Usage: INCLUDE_FORKS=yes TARGET_DIR=/path $0 owner1 [owner2 ...]" >&2
    exit 1
fi

for owner in "$@"; do
    echo "==> harvesting ${owner}"
    gh repo list "$owner" \
        --limit 1000 \
        --json nameWithOwner,isFork,isArchived,sshUrl,url \
    | jq -c '.[]' \
    | while read -r repo; do
        nameWithOwner=$(echo "$repo" | jq -r '.nameWithOwner')
        isFork=$(echo "$repo" | jq -r '.isFork')
        isArchived=$(echo "$repo" | jq -r '.isArchived')
        sshUrl=$(echo "$repo" | jq -r '.sshUrl')

        if [[ "$INCLUDE_FORKS" != "yes" && "$isFork" == "true" ]]; then
            echo "  skip (fork):     $nameWithOwner"
            continue
        fi
        if [[ "$INCLUDE_ARCHIVED" != "yes" && "$isArchived" == "true" ]]; then
            echo "  skip (archived): $nameWithOwner"
            continue
        fi

        safe_dir="${nameWithOwner//\//__}"
        dest="$TARGET_DIR/$safe_dir"
        echo "  repo: $nameWithOwner"
        if [[ -d "$dest/.git" ]]; then
            git -C "$dest" fetch --all --prune --quiet 2>/dev/null \
                || echo "    fetch failed: $nameWithOwner" >&2
            git -C "$dest" pull --ff-only --quiet 2>/dev/null || true
        else
            git clone --quiet "$sshUrl" "$dest" \
                || echo "    clone failed: $nameWithOwner" >&2
        fi
    done
done

echo
echo "DONE. Target: $TARGET_DIR"
HARVEST_EOF
chmod +x /root/safe-harvest-github.sh

# 2) inventory.sh — TSV + aligned text report of every cloned repo
cat > /opt/imperium/audit/github/inventory.sh <<'INV_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/opt/imperium/imports/github"
OUT_TSV="/opt/imperium/audit/github/repo_inventory.tsv"
OUT_TXT="/opt/imperium/audit/github/repo_inventory.txt"

printf 'repo\tbranch\tlast_commit\tfiles\tlanguages_hint\n' > "$OUT_TSV"

find "$ROOT" -mindepth 1 -maxdepth 1 -type d | sort | while read -r repo; do
    [[ -d "$repo/.git" ]] || continue
    name=$(basename "$repo")
    branch=$(git -C "$repo" branch --show-current 2>/dev/null || true)
    last_commit=$(git -C "$repo" log -1 --format='%ci %h %s' 2>/dev/null \
        | tr '\t' ' ' | head -c 100 || true)
    files=$(find "$repo" -type f -not -path '*/\.git/*' | wc -l | tr -d ' ')
    langs=$(find "$repo" -maxdepth 3 -type f -not -path '*/\.git/*' \
        | awk -F. 'NF>1 {print $NF}' \
        | sort | uniq -c | sort -nr | head -6 \
        | awk '{printf "%s(%s) ",$2,$1}')
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$branch" "$last_commit" "$files" "$langs" \
        >> "$OUT_TSV"
done

column -t -s $'\t' "$OUT_TSV" | tee "$OUT_TXT"
echo
echo "TSV: $OUT_TSV"
echo "TXT: $OUT_TXT"
INV_EOF
chmod +x /opt/imperium/audit/github/inventory.sh

# 3) risk_scan.sh — secrets, dangerous install patterns, port exposure, services
cat > /opt/imperium/audit/github/risk_scan.sh <<'RISK_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/opt/imperium/imports/github"
OUT="/opt/imperium/audit/github/risk_scan_$(date +%Y-%m-%d_%H-%M-%S).txt"

if ! command -v rg >/dev/null 2>&1; then
    echo "ERROR: ripgrep missing — apt-get install -y ripgrep" >&2
    exit 1
fi

{
    echo "# GitHub Import Risk Scan"
    echo "Date: $(date -Is)"
    echo "Root: $ROOT"
    echo

    echo "## Potential secrets"
    rg -n --hidden --glob '!**/.git/**' \
        'ghp_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY|xoxb-[0-9A-Za-z-]+|AIza[0-9A-Za-z_-]{35}' \
        "$ROOT" || echo "  (none)"
    echo

    echo "## Dangerous install / runtime patterns"
    rg -n --hidden --glob '!**/.git/**' \
        'curl .*\| *bash|curl .*\| *sh|wget .*\| *bash|wget .*\| *sh|chmod 777|rm -rf /|eval +"\$\(' \
        "$ROOT" || echo "  (none)"
    echo

    echo "## Port exposure hints"
    rg -n --hidden --glob '!**/.git/**' \
        '0\.0\.0\.0|hostNetwork|EXPOSE [0-9]+|--publish|-p [0-9]+:[0-9]+' \
        "$ROOT" || echo "  (none)"
    echo

    echo "## Systemd / docker compose units"
    find "$ROOT" -type f \( \
        -name "*.service" -o \
        -name "docker-compose.yml" -o \
        -name "docker-compose.yaml" -o \
        -name "compose.yml" -o \
        -name "compose.yaml" \
    \) -print 2>/dev/null || true
    echo

    echo "## Install / bootstrap / Dockerfile scripts"
    find "$ROOT" -type f \( \
        -name "setup.sh" -o \
        -name "install.sh" -o \
        -name "bootstrap.sh" -o \
        -name "start.sh" -o \
        -name "deploy.sh" -o \
        -name "Dockerfile" \
    \) -print 2>/dev/null || true
} | tee "$OUT"

echo
echo "Report: $OUT"
RISK_EOF
chmod +x /opt/imperium/audit/github/risk_scan.sh

echo "==> Bootstrap complete."
echo
echo "Quarantine layout:"
echo "  /opt/imperium/imports/github  (code, do NOT execute)"
echo "  /opt/imperium/audit/github    (reports)"
echo "  /opt/imperium/build           (sandbox)"
echo "  /opt/imperium/apps            (vetted)"
echo "  /opt/imperium/systemd         (vetted units)"
echo
echo "Scripts written:"
echo "  /root/safe-harvest-github.sh"
echo "  /opt/imperium/audit/github/inventory.sh"
echo "  /opt/imperium/audit/github/risk_scan.sh"
echo
echo "Next:"
echo "  1) gh auth login   (if not already authed)"
echo "  2) INCLUDE_FORKS=yes /root/safe-harvest-github.sh mauricepfeiferai-jpg mauricepfeifer-ctrl Maurice-AIEMPIRE"
echo "  3) /opt/imperium/audit/github/inventory.sh"
echo "  4) /opt/imperium/audit/github/risk_scan.sh"
