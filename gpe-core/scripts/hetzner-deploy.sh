#!/usr/bin/env bash
# GPE Core — Hetzner Server Deployment
# Run this ONCE on your Hetzner server as root:
#   curl -fsSL https://raw.githubusercontent.com/Maurice-AIEMPIRE/core/claude/gpe-core-implementation-rRqRn/gpe-core/scripts/hetzner-deploy.sh | bash
# Or after cloning:
#   bash /root/core/gpe-core/scripts/hetzner-deploy.sh

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
REPO_URL="https://github.com/Maurice-AIEMPIRE/core"
BRANCH="claude/gpe-core-implementation-rRqRn"
INSTALL_DIR="/root/core"
NODE_VERSION="22"
CRON_HOUR=3   # 03:00 AM daily

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[GPE]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
die()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║     GPE Core — Hetzner Server Deployment     ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── Root check ────────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && die "Run as root: sudo bash hetzner-deploy.sh"

# ── 1. System packages ────────────────────────────────────────────────────────
log "Step 1/6: Installing system packages..."
apt-get update -qq
apt-get install -y -qq git curl wget cron 2>/dev/null || true
log "  System packages: OK"

# ── 2. Node.js ────────────────────────────────────────────────────────────────
log "Step 2/6: Checking Node.js..."
if ! command -v node &>/dev/null || [[ $(node -v | cut -d. -f1 | tr -d 'v') -lt $NODE_VERSION ]]; then
  log "  Installing Node.js $NODE_VERSION..."
  curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - 2>/dev/null
  apt-get install -y -qq nodejs
fi
log "  Node.js: $(node -v)"

# ── 3. Claude Code CLI ────────────────────────────────────────────────────────
log "Step 3/6: Installing Claude Code CLI..."
npm install -g @anthropic-ai/claude-code --quiet 2>/dev/null || \
  npm install -g @anthropic-ai/claude-code 2>&1 | tail -3
CLAUDE_BIN=$(which claude)
log "  Claude Code: $($CLAUDE_BIN --version 2>/dev/null || echo 'installed')"

# ── 4. Anthropic API Key ──────────────────────────────────────────────────────
log "Step 4/6: Checking API key..."
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  if [[ -f /root/.env ]]; then
    source /root/.env
  fi
fi

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  warn "ANTHROPIC_API_KEY not set."
  echo ""
  echo "  Set it now and re-run, or add to /root/.env:"
  echo "  export ANTHROPIC_API_KEY='sk-ant-...'"
  echo "  echo 'export ANTHROPIC_API_KEY=sk-ant-...' >> /root/.env"
  echo ""
  read -rp "  Enter your API key now (or press Enter to skip): " KEY
  if [[ -n "$KEY" ]]; then
    echo "export ANTHROPIC_API_KEY='$KEY'" >> /root/.env
    export ANTHROPIC_API_KEY="$KEY"
    log "  API key saved to /root/.env"
  else
    warn "  Skipped. The daily evolution run will fail until key is set."
  fi
else
  log "  API key: found"
fi

# ── 5. Clone / update repo ────────────────────────────────────────────────────
log "Step 5/6: Syncing repository..."
if [[ -d "$INSTALL_DIR/.git" ]]; then
  log "  Repo exists — pulling latest..."
  git -C "$INSTALL_DIR" fetch origin
  git -C "$INSTALL_DIR" checkout "$BRANCH" 2>/dev/null || \
    git -C "$INSTALL_DIR" checkout -b "$BRANCH" "origin/$BRANCH"
  git -C "$INSTALL_DIR" pull origin "$BRANCH"
else
  log "  Cloning repo to $INSTALL_DIR..."
  git clone --branch "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
fi
log "  Repo: OK (branch: $BRANCH)"

# ── 6. Cron job ───────────────────────────────────────────────────────────────
log "Step 6/6: Installing daily cron job..."
SCRIPT="$INSTALL_DIR/gpe-core/scripts/daily-evolution-run.sh"
LOG="$INSTALL_DIR/gpe-core/evolution/logs/cron-scheduler.log"
CRON_FILE="/etc/cron.d/gpe-evolution"

chmod +x "$SCRIPT"
mkdir -p "$INSTALL_DIR/gpe-core/evolution/logs"

# Write the cron file with the CORRECT claude binary and API key path
cat > "$CRON_FILE" << EOF
# GPE Core — Daily Evolution Loop
# Runs every day at ${CRON_HOUR}:00 AM
SHELL=/bin/bash
PATH=$(dirname $CLAUDE_BIN):/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
CLAUDE_BIN=$CLAUDE_BIN
MAX_BUDGET_USD=3.00
ANTHROPIC_API_KEY_FILE=/root/.env

0 ${CRON_HOUR} * * * root source /root/.env 2>/dev/null; ${SCRIPT} >> ${LOG} 2>&1
EOF

chmod 644 "$CRON_FILE"

# Ensure cron daemon is running
service cron start 2>/dev/null || systemctl start cron 2>/dev/null || true

log "  Cron: every day at ${CRON_HOUR}:00 AM"
log "  Log: $LOG"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║             DEPLOYMENT COMPLETE              ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "  Repo:      $INSTALL_DIR"
echo "  Branch:    $BRANCH"
echo "  Claude:    $CLAUDE_BIN"
echo "  Cron:      daily at ${CRON_HOUR}:00 AM"
echo "  Cron log:  $LOG"
echo ""
echo "  Run NOW manually to test:"
echo "  bash $SCRIPT"
echo ""
echo "  Check tomorrow's result:"
echo "  cat $INSTALL_DIR/gpe-core/evolution/logs/$(date +%Y-%m-%d).log"
echo ""
echo "  View what was queued:"
echo "  cat $INSTALL_DIR/gpe-core/evolution/LEARNING_QUEUE.yaml"
echo ""
