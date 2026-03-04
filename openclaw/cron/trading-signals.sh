#!/usr/bin/env bash
# ================================================================
# CRON: Trading Signals — Chandler
# ================================================================
# Automatische Trading-Signal-Generierung (3x taeglich)
# XRP Signals + Polymarket Scan + Report via Telegram
# ================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BROWSER_DIR="$(dirname "$SCRIPT_DIR")/browser"
LOG_FILE="$(dirname "$SCRIPT_DIR")/memory/trading-cron.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

log "=== Trading Signals Cron Start ==="

# 1. XRP Price + Signals
log "Running XRP price check..."
bash "$BROWSER_DIR/trading-xrp.sh" price >> "$LOG_FILE" 2>&1 || log "XRP price failed"

log "Running XRP signals..."
bash "$BROWSER_DIR/trading-xrp.sh" signals >> "$LOG_FILE" 2>&1 || log "XRP signals failed"

# 2. Fear & Greed Index
log "Running Fear & Greed check..."
bash "$BROWSER_DIR/trading-xrp.sh" fear-greed >> "$LOG_FILE" 2>&1 || log "Fear & Greed failed"

# 3. Polymarket Trending
log "Running Polymarket scan..."
bash "$BROWSER_DIR/polymarket.sh" trending >> "$LOG_FILE" 2>&1 || log "Polymarket scan failed"

# 4. XRP Alerts check
log "Running XRP alerts..."
bash "$BROWSER_DIR/trading-xrp.sh" alerts >> "$LOG_FILE" 2>&1 || log "Alerts failed"

log "=== Trading Signals Cron Complete ==="
