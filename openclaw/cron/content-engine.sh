#!/usr/bin/env bash
# ================================================================
# CRON: Content Engine — Kelly + Ross
# ================================================================
# Automatische Content-Generierung und Scheduling
# X/Twitter Daily Routine + YouTube Trending Scan
# ================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BROWSER_DIR="$(dirname "$SCRIPT_DIR")/browser"
LOG_FILE="$(dirname "$SCRIPT_DIR")/memory/content-cron.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

log "=== Content Engine Cron Start ==="

# 1. Kelly: Generate scheduled tweets
log "Generating scheduled tweets..."
bash "$BROWSER_DIR/x-content-engine.sh" schedule crypto 3 >> "$LOG_FILE" 2>&1 || log "Tweet schedule failed"
bash "$BROWSER_DIR/x-content-engine.sh" schedule ai 2 >> "$LOG_FILE" 2>&1 || log "AI tweet schedule failed"

# 2. Kelly: Growth scan
log "Running growth scan..."
bash "$BROWSER_DIR/x-content-engine.sh" growth-scan >> "$LOG_FILE" 2>&1 || log "Growth scan failed"

# 3. Ross: YouTube trending scan
log "Scanning YouTube trends..."
bash "$BROWSER_DIR/youtube-faceless.sh" trending finance >> "$LOG_FILE" 2>&1 || log "YouTube trending failed"

# 4. Kelly: Hashtag research
log "Researching hashtags..."
bash "$BROWSER_DIR/x-content-engine.sh" hashtags crypto >> "$LOG_FILE" 2>&1 || log "Hashtag research failed"

log "=== Content Engine Cron Complete ==="
