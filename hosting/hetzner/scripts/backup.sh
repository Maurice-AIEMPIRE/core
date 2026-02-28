#!/usr/bin/env bash
# =============================================================================
# CORE - Automated Backup Script for Hetzner
# =============================================================================
# Creates timestamped backups of PostgreSQL, Neo4j, and Redis data.
# Retains backups for RETENTION_DAYS (default: 14).
#
# Usage:
#   ./scripts/backup.sh                    # Run backup
#   BACKUP_DIR=/custom/path ./scripts/backup.sh  # Custom backup directory
#
# Crontab (daily at 3:00 AM):
#   0 3 * * * cd /opt/core && ./scripts/backup.sh >> /var/log/core-backup.log 2>&1
# =============================================================================

set -euo pipefail

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/mnt/data/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"

# Load environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env.production"
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

# Defaults from environment
PG_USER="${POSTGRES_USER:-docker}"
PG_DB="${POSTGRES_DB:-core}"
PG_PASSWORD="${POSTGRES_PASSWORD:-docker}"
NEO4J_USER="${NEO4J_USERNAME:-neo4j}"
NEO4J_PASS="${NEO4J_PASSWORD:-}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error_exit() {
    log "ERROR: $*"
    exit 1
}

# Create backup directory
mkdir -p "${BACKUP_PATH}"
log "Starting backup to ${BACKUP_PATH}"

# ─── PostgreSQL Backup ───────────────────────────────────────────────────────
log "Backing up PostgreSQL..."
if docker exec core-postgres pg_dump \
    -U "${PG_USER}" \
    -d "${PG_DB}" \
    --format=custom \
    --compress=9 \
    > "${BACKUP_PATH}/postgres_${PG_DB}.dump" 2>/dev/null; then
    PG_SIZE=$(du -sh "${BACKUP_PATH}/postgres_${PG_DB}.dump" | cut -f1)
    log "PostgreSQL backup complete (${PG_SIZE})"
else
    log "WARNING: PostgreSQL backup failed"
fi

# ─── Neo4j Backup ────────────────────────────────────────────────────────────
log "Backing up Neo4j..."
if docker exec core-neo4j cypher-shell \
    -u "${NEO4J_USER}" \
    -p "${NEO4J_PASS}" \
    "CALL apoc.export.json.all(null, {stream:true}) YIELD data RETURN data" \
    > "${BACKUP_PATH}/neo4j_export.json" 2>/dev/null; then
    # Compress the export
    gzip "${BACKUP_PATH}/neo4j_export.json"
    NEO4J_SIZE=$(du -sh "${BACKUP_PATH}/neo4j_export.json.gz" | cut -f1)
    log "Neo4j backup complete (${NEO4J_SIZE})"
else
    log "WARNING: Neo4j backup failed (attempting volume copy)"
    # Fallback: copy Neo4j data directory
    if docker exec core-neo4j sh -c "tar czf - /data" > "${BACKUP_PATH}/neo4j_data.tar.gz" 2>/dev/null; then
        log "Neo4j volume backup complete"
    else
        log "WARNING: Neo4j volume backup also failed"
    fi
fi

# ─── Redis Backup ────────────────────────────────────────────────────────────
log "Backing up Redis..."
if docker exec core-redis redis-cli \
    -a "${REDIS_PASSWORD:-}" \
    BGSAVE 2>/dev/null && sleep 2; then
    if docker cp core-redis:/data/dump.rdb "${BACKUP_PATH}/redis_dump.rdb" 2>/dev/null; then
        gzip "${BACKUP_PATH}/redis_dump.rdb"
        log "Redis backup complete"
    fi
else
    log "WARNING: Redis backup failed"
fi

# ─── Compress full backup ────────────────────────────────────────────────────
log "Creating compressed archive..."
cd "${BACKUP_DIR}"
tar czf "${TIMESTAMP}.tar.gz" "${TIMESTAMP}/"
rm -rf "${BACKUP_PATH}"
TOTAL_SIZE=$(du -sh "${BACKUP_DIR}/${TIMESTAMP}.tar.gz" | cut -f1)
log "Backup archive created: ${TIMESTAMP}.tar.gz (${TOTAL_SIZE})"

# ─── Cleanup old backups ─────────────────────────────────────────────────────
log "Cleaning up backups older than ${RETENTION_DAYS} days..."
DELETED=$(find "${BACKUP_DIR}" -name "*.tar.gz" -mtime +${RETENTION_DAYS} -print -delete | wc -l)
log "Deleted ${DELETED} old backup(s)"

# ─── Summary ─────────────────────────────────────────────────────────────────
BACKUP_COUNT=$(find "${BACKUP_DIR}" -name "*.tar.gz" | wc -l)
TOTAL_USAGE=$(du -sh "${BACKUP_DIR}" | cut -f1)
log "Backup complete. ${BACKUP_COUNT} backup(s) stored, total usage: ${TOTAL_USAGE}"
