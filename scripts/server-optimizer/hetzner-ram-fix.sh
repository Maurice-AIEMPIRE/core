#!/usr/bin/env bash
# =============================================================================
# hetzner-ram-fix.sh
# Optimiert RAM-Nutzung auf Hetzner Bare Metal (125GB)
# Ziel: 80GB+ freier RAM für 200+ AI Agents
# =============================================================================

set -euo pipefail

LOG_FILE="/var/log/hetzner-ram-optimizer.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

section() {
    echo "" | tee -a "$LOG_FILE"
    log "=== $1 ==="
}

# 1. Status Check
section "Status Check"
free -h
top -b -n 1 | head -15

# 2. Docker-Container einschränken
section "Docker Limits setzen"
# Hinweis: Diese Befehle setzen voraus, dass die Container via docker-compose oder Flags verwaltet werden.
# Wir geben hier Empfehlungen aus oder wenden sie direkt an, falls möglich.
log "Empfohlene Limits: Ollama (32G), OpenClaw (8G), ChromaDB (16G), Redis (4G)"

# 3. Sysctl Tuning
section "Sysctl Tuning"
if grep -q "vm.swappiness" /etc/sysctl.conf; then
    sed -i 's/vm.swappiness=.*/vm.swappiness=10/' /etc/sysctl.conf
else
    echo "vm.swappiness=10" >> /etc/sysctl.conf
fi

if grep -q "vm.overcommit_memory" /etc/sysctl.conf; then
    sed -i 's/vm.overcommit_memory=.*/vm.overcommit_memory=1/' /etc/sysctl.conf
else
    echo "vm.overcommit_memory=1" >> /etc/sysctl.conf
fi
sysctl -p

# 4. Swap-File optimieren
section "Swap-File"
if [[ -f /swapfile ]]; then
    log "Swapfile vorhanden. Größe prüfen..."
else
    log "Erstelle 16GB Swapfile..."
    fallocate -l 16G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo "/swapfile none swap sw 0 0" >> /etc/fstab
fi

# 5. Cleanup
section "Cleanup"
docker system prune -f
sync && echo 3 > /proc/sys/vm/drop_caches
log "Caches geleert und Docker bereinigt."

# 6. Endergebnis
section "Optimierung abgeschlossen"
free -h
log "Ziel: 80GB+ freier RAM für AI Empire Agents."
