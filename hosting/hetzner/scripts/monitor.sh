#!/usr/bin/env bash
# =============================================================================
# CORE - Health Monitor & Alerting Script
# =============================================================================
# Monitors all CORE services and sends alerts on failures.
#
# Usage:
#   ./scripts/monitor.sh              # Run health check
#   WEBHOOK_URL=... ./scripts/monitor.sh  # With Slack/Discord alerts
#
# Crontab (every 5 minutes):
#   */5 * * * * cd /opt/core && ./scripts/monitor.sh >> /var/log/core-monitor.log 2>&1
# =============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env.production"
ALERT_FILE="/tmp/core-alert-state"

if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

DOMAIN="${DOMAIN:-localhost}"
WEBHOOK_URL="${WEBHOOK_URL:-}"
EMAIL_ALERT="${EMAIL_ALERT:-}"
ALERT_COOLDOWN="${ALERT_COOLDOWN:-300}"  # 5 minutes between repeated alerts

ERRORS=()
WARNINGS=()

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

check_container() {
    local name="$1"
    local status
    status=$(docker inspect --format='{{.State.Status}}' "$name" 2>/dev/null || echo "not_found")

    if [ "$status" = "running" ]; then
        local health
        health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no_healthcheck{{end}}' "$name" 2>/dev/null)
        if [ "$health" = "unhealthy" ]; then
            ERRORS+=("Container $name is unhealthy")
            return 1
        fi
        return 0
    else
        ERRORS+=("Container $name is $status")
        return 1
    fi
}

check_http() {
    local url="$1"
    local name="$2"
    local timeout="${3:-10}"

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$timeout" "$url" 2>/dev/null || echo "000")

    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 400 ]; then
        return 0
    else
        ERRORS+=("HTTP check failed for $name: status=$http_code (url=$url)")
        return 1
    fi
}

check_disk() {
    local path="$1"
    local threshold="${2:-85}"

    if [ -d "$path" ]; then
        local usage
        usage=$(df "$path" | tail -1 | awk '{print $5}' | tr -d '%')
        if [ "$usage" -ge "$threshold" ]; then
            WARNINGS+=("Disk usage at ${usage}% on $path (threshold: ${threshold}%)")
        fi
    fi
}

check_memory() {
    local usage
    usage=$(free | awk '/Mem:/ {printf "%.0f", $3/$2 * 100}')
    if [ "$usage" -ge 90 ]; then
        ERRORS+=("Memory usage critical: ${usage}%")
    elif [ "$usage" -ge 80 ]; then
        WARNINGS+=("Memory usage high: ${usage}%")
    fi
}

send_alert() {
    local message="$1"
    local level="$2"  # error or warning

    # Cooldown check
    if [ -f "$ALERT_FILE" ]; then
        local last_alert
        last_alert=$(cat "$ALERT_FILE")
        local now
        now=$(date +%s)
        if [ $((now - last_alert)) -lt "$ALERT_COOLDOWN" ]; then
            log "Alert suppressed (cooldown active)"
            return 0
        fi
    fi
    date +%s > "$ALERT_FILE"

    # Slack/Discord webhook
    if [ -n "$WEBHOOK_URL" ]; then
        local color="danger"
        [ "$level" = "warning" ] && color="warning"

        local payload
        payload=$(cat <<PAYLOAD
{
  "text": "CORE Monitor Alert",
  "attachments": [{
    "color": "${color}",
    "title": "CORE Health Check - $(hostname)",
    "text": "${message}",
    "footer": "$(date '+%Y-%m-%d %H:%M:%S UTC')"
  }]
}
PAYLOAD
)
        curl -s -X POST -H 'Content-Type: application/json' \
            -d "$payload" "$WEBHOOK_URL" > /dev/null 2>&1 || true
        log "Alert sent to webhook"
    fi
}

# ─── Run Checks ──────────────────────────────────────────────────────────────

log "Starting health checks..."

# Container checks
check_container "core-app"
check_container "core-postgres"
check_container "core-redis"
check_container "core-neo4j"
check_container "core-nginx"

# HTTP checks
check_http "http://localhost/health" "Nginx Health"
check_http "http://localhost:3000" "Core App" 15

# System checks
check_disk "/" 85
check_disk "/mnt/data" 85
check_memory

# Docker disk usage
DOCKER_SIZE=$(docker system df --format '{{.Size}}' 2>/dev/null | head -1)
log "Docker disk usage: ${DOCKER_SIZE:-unknown}"

# ─── Report ──────────────────────────────────────────────────────────────────

if [ ${#ERRORS[@]} -gt 0 ]; then
    log "ERRORS DETECTED:"
    ERROR_MSG=""
    for err in "${ERRORS[@]}"; do
        log "  - $err"
        ERROR_MSG="${ERROR_MSG}\n- ${err}"
    done
    send_alert "$ERROR_MSG" "error"
    exit 1
fi

if [ ${#WARNINGS[@]} -gt 0 ]; then
    log "WARNINGS:"
    WARN_MSG=""
    for warn in "${WARNINGS[@]}"; do
        log "  - $warn"
        WARN_MSG="${WARN_MSG}\n- ${warn}"
    done
    send_alert "$WARN_MSG" "warning"
    exit 0
fi

log "All checks passed"
