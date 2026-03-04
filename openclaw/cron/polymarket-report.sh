#!/usr/bin/env bash
# ================================================================
# CRON: Polymarket Daily Report — Chandler
# ================================================================
# Taeglicher Polymarket Report (abends um 20:00)
# ================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BROWSER_DIR="$(dirname "$SCRIPT_DIR")/browser"
LOG_FILE="$(dirname "$SCRIPT_DIR")/memory/polymarket-cron.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

log "=== Polymarket Report Cron Start ==="

# Full daily report
bash "$BROWSER_DIR/polymarket.sh" report >> "$LOG_FILE" 2>&1 || log "Report failed"

# Signals refresh
bash "$BROWSER_DIR/polymarket.sh" signals >> "$LOG_FILE" 2>&1 || log "Signals failed"

log "=== Polymarket Report Cron Complete ==="
