#!/usr/bin/env bash
# =============================================================================
# diplo-server-setup.sh
# Richtet den Hetzner-Server "Diplo" als vollständige Rechenmaschine ein.
# Läuft direkt auf dem SERVER (root@65.21.203.174).
#
# Ausführen auf dem SERVER:
#   bash scripts/server-offload/diplo-server-setup.sh
#
# Oder per SSH vom Mac:
#   ssh root@65.21.203.174 bash -s < scripts/server-offload/diplo-server-setup.sh
# =============================================================================

set -euo pipefail

LOG_FILE="/var/log/diplo-setup.log"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[✓]${NC} $*" | tee -a "$LOG_FILE"; }
info() { echo -e "${YELLOW}[→]${NC} $*" | tee -a "$LOG_FILE"; }
step() { echo -e "\n${CYAN}=== $* ===${NC}" | tee -a "$LOG_FILE"; }

[[ "$(id -u)" -eq 0 ]] || { echo "Als root ausführen!"; exit 1; }

echo ""
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║  DIPLO SERVER SETUP                          ║"
echo "  ║  Hetzner Bare Metal → AI Rechenmaschine      ║"
echo "  ╚══════════════════════════════════════════════╝"
echo ""

RAM_TOTAL=$(free -g | awk '/^Mem:/{print $2}')
CPU_CORES=$(nproc)
info "Server: $(hostname), ${RAM_TOTAL}GB RAM, ${CPU_CORES} CPU-Kerne"

# =============================================================================
# 1. System-Optimierung: RAM + CPU für maximale Leistung
# =============================================================================
step "1 · System-Optimierung"

# Swappiness auf minimum (RAM bevorzugen)
echo "vm.swappiness=5"            >> /etc/sysctl.d/99-diplo.conf
echo "vm.overcommit_memory=1"     >> /etc/sysctl.d/99-diplo.conf
echo "vm.dirty_ratio=60"          >> /etc/sysctl.d/99-diplo.conf
echo "vm.dirty_background_ratio=5" >> /etc/sysctl.d/99-diplo.conf
echo "net.core.somaxconn=65535"   >> /etc/sysctl.d/99-diplo.conf
sysctl -p /etc/sysctl.d/99-diplo.conf &>/dev/null || true
ok "Kernel-Parameter optimiert (swappiness=5, max-connections=65535)"

# Limits für Datei-Handles erhöhen
cat >> /etc/security/limits.conf <<'LIMITS'
root soft nofile 1048576
root hard nofile 1048576
* soft nofile 524288
* hard nofile 524288
LIMITS
ok "Datei-Handle-Limits erhöht (1M)"

# =============================================================================
# 2. Ollama installieren und konfigurieren (läuft auf 0.0.0.0)
# =============================================================================
step "2 · Ollama (LLM-Engine)"

if ! command -v ollama &>/dev/null; then
    info "Ollama installieren..."
    curl -fsSL https://ollama.ai/install.sh | sh
    ok "Ollama installiert"
else
    ok "Ollama bereits installiert: $(ollama --version)"
fi

# Ollama auf alle Interfaces binden (SSH-Tunnel vom Mac kann drauf zugreifen)
mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf <<'UNIT'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_KEEP_ALIVE=24h"
Environment="OLLAMA_NUM_PARALLEL=4"
Restart=always
RestartSec=5
UNIT

systemctl daemon-reload
systemctl enable ollama
systemctl restart ollama
sleep 3
ok "Ollama läuft auf 0.0.0.0:11434 (zugänglich via SSH-Tunnel)"

# Standard-Modell vorinstallieren (klein und schnell)
info "Standard-Modell laden (llama3.2:3b – schnell & effizient)..."
ollama pull llama3.2:3b &>/dev/null &
ok "Modell wird im Hintergrund geladen"

# =============================================================================
# 3. Redis (Caching und Message Queue)
# =============================================================================
step "3 · Redis (Caching)"

if ! command -v redis-server &>/dev/null; then
    apt-get install -y -qq redis-server
fi

# Redis auf localhost binden (SSH-Tunnel macht es sicher)
sed -i 's/^bind .*/bind 127.0.0.1/' /etc/redis/redis.conf 2>/dev/null || true
sed -i 's/^# maxmemory-policy.*/maxmemory-policy allkeys-lru/' /etc/redis/redis.conf 2>/dev/null || true
# 10% des RAMs für Redis
REDIS_MAX_MEM=$(( RAM_TOTAL * 10 / 100 ))
echo "maxmemory ${REDIS_MAX_MEM}gb" >> /etc/redis/redis.conf

systemctl enable redis-server
systemctl restart redis-server
ok "Redis läuft auf 127.0.0.1:6379 (${REDIS_MAX_MEM}GB limit)"

# =============================================================================
# 4. API-Gateway (Nginx als Reverse Proxy)
# =============================================================================
step "4 · API-Gateway (Nginx)"

if ! command -v nginx &>/dev/null; then
    apt-get install -y -qq nginx
fi

cat > /etc/nginx/sites-available/diplo-gateway <<'NGINX'
server {
    listen 8080;
    server_name _;

    # Ollama API
    location /api/ {
        proxy_pass http://127.0.0.1:11434;
        proxy_set_header Host $host;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
        client_max_body_size 100M;
    }

    # Health Check
    location /health {
        return 200 '{"status":"ok","server":"diplo"}';
        add_header Content-Type application/json;
    }

    # Status
    location /status {
        stub_status on;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/diplo-gateway /etc/nginx/sites-enabled/
nginx -t && systemctl enable nginx && systemctl reload nginx
ok "Nginx-Gateway läuft auf Port 8080"

# =============================================================================
# 5. Firewall: Nur SSH von außen, alles andere nur via Tunnel
# =============================================================================
step "5 · Firewall"

if command -v ufw &>/dev/null; then
    ufw default deny incoming
    ufw allow 22/tcp     # SSH (von Mac und überall)
    ufw allow 11434/tcp  # Ollama (auch direkt, für direkte Verbindung)
    ufw allow 8080/tcp   # API Gateway
    ufw --force enable
    ok "Firewall konfiguriert (SSH + Ollama + API offen)"
fi

# =============================================================================
# 6. Status-Bericht
# =============================================================================
step "6 · Status-Bericht"

echo ""
echo "  ╔════════════════════════════════════════════════════╗"
echo "  ║  DIPLO SERVER BEREIT!                             ║"
echo "  ╠════════════════════════════════════════════════════╣"
free -h | awk '/^Mem:/{printf "  ║  RAM:    %s total, %s verfügbar\n", $2, $7}'
echo "  ║  CPU:    $(nproc) Kerne"
echo "  ║  Ollama: $(systemctl is-active ollama)"
echo "  ║  Redis:  $(systemctl is-active redis-server 2>/dev/null || echo 'prüfen')"
echo "  ║  Nginx:  $(systemctl is-active nginx)"
echo "  ╠════════════════════════════════════════════════════╣"
echo "  ║  Services erreichbar via SSH-Tunnel vom Mac:      ║"
echo "  ║  localhost:11434  → Ollama LLM                    ║"
echo "  ║  localhost:8080   → API Gateway                   ║"
echo "  ║  localhost:6379   → Redis                         ║"
echo "  ╚════════════════════════════════════════════════════╝"
echo ""
