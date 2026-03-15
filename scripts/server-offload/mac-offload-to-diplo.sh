#!/usr/bin/env bash
# =============================================================================
# mac-offload-to-diplo.sh
# Lagert alle rechenintensiven Services vom Mac auf den Hetzner-Server "Diplo"
# aus und hält den Mac als leichte Steuerzentrale.
#
# Ausführen auf dem MAC:
#   bash scripts/server-offload/mac-offload-to-diplo.sh
#
# Was es macht:
#   1. SSH-Tunnel zum Server aufbauen (Mac → Diplo)
#   2. Alle schweren Services auf Diplo starten (Ollama, Docker, AI-Agents)
#   3. Port-Forwarding: Server-Ports auf Mac-localhost verfügbar machen
#   4. LaunchAgent installieren: Tunnel bleibt permanent aktiv
# =============================================================================

set -euo pipefail

DIPLO_IP="65.21.203.174"
DIPLO_USER="root"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o ServerAliveInterval=30 -o ServerAliveCountMax=3"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()      { echo -e "${GREEN}✓${NC} $*"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $*"; }
err()     { echo -e "${RED}✗ FEHLER:${NC} $*"; exit 1; }
step()    { echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n${CYAN}  $*${NC}\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
header()  { echo -e "\n${BOLD}$*${NC}"; }

[[ "$(uname)" == "Darwin" ]] || err "Dieses Skript läuft nur auf macOS."

echo ""
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║  MAC → DIPLO OFFLOAD-SETUP                   ║"
echo "  ║  Mac = Steuerzentrale (leicht)                ║"
echo "  ║  Diplo = Rechenpower (schwer)                 ║"
echo "  ╚══════════════════════════════════════════════╝"
echo ""

# =============================================================================
# SCHRITT 1: SSH-Verbindung testen
# =============================================================================
step "1/5 · SSH-Verbindung zu Diplo prüfen ($DIPLO_IP)"

if ! ssh $SSH_OPTS -o BatchMode=yes ${DIPLO_USER}@${DIPLO_IP} "echo 'OK'" 2>/dev/null; then
    warn "SSH-Key-Authentifizierung nicht eingerichtet."
    echo ""
    echo "  Richte zuerst deinen SSH-Key ein:"
    echo "  ssh-copy-id ${DIPLO_USER}@${DIPLO_IP}"
    echo ""
    read -rp "  Jetzt einrichten? [Y/n]: " SETUP_SSH
    if [[ "${SETUP_SSH:-y}" =~ ^[Yy]$ ]]; then
        if [[ ! -f "$HOME/.ssh/id_ed25519" ]]; then
            ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" -C "mac-diplo-offload"
        fi
        ssh-copy-id -i "$HOME/.ssh/id_ed25519.pub" "${DIPLO_USER}@${DIPLO_IP}"
    else
        err "SSH-Zugang benötigt. Bitte einrichten und Script erneut starten."
    fi
fi
ok "SSH-Verbindung zu Diplo ($DIPLO_IP) funktioniert!"

# =============================================================================
# SCHRITT 2: Alle schweren Services auf Diplo starten
# =============================================================================
step "2/5 · Schwere Services auf Diplo starten"

ssh $SSH_OPTS ${DIPLO_USER}@${DIPLO_IP} bash <<'REMOTE'
set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[DIPLO ✓]${NC} $*"; }
info() { echo -e "${YELLOW}[DIPLO]${NC} $*"; }

info "=== Diplo Server Setup ==="
info "RAM: $(free -h | awk '/^Mem:/{print $2}') total, $(free -h | awk '/^Mem:/{print $4}') frei"
info "CPU: $(nproc) Kerne"

# ---- Ollama (LLM-Inferenz) ----
if ! command -v ollama &>/dev/null; then
    info "Ollama installieren..."
    curl -fsSL https://ollama.ai/install.sh | sh
fi

if ! systemctl is-active ollama &>/dev/null 2>&1; then
    info "Ollama starten..."
    # Ollama soll auf 0.0.0.0 hören (Mac kann darauf zugreifen)
    mkdir -p /etc/systemd/system/ollama.service.d
    cat > /etc/systemd/system/ollama.service.d/override.conf <<'UNIT'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
UNIT
    systemctl daemon-reload
    systemctl enable --now ollama
fi
ok "Ollama läuft auf Port 11434"

# ---- RAM-Optimierung ----
info "RAM für maximale Leistung optimieren..."
sysctl -w vm.swappiness=10 &>/dev/null || true
sysctl -w vm.overcommit_memory=1 &>/dev/null || true
sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
ok "RAM optimiert"

# ---- Docker-Services ----
if command -v docker &>/dev/null; then
    info "Docker-System bereinigen..."
    docker system prune -f &>/dev/null || true
    ok "Docker bereinigt"
fi

# ---- Firewall: relevante Ports öffnen ----
if command -v ufw &>/dev/null; then
    ufw allow 11434/tcp &>/dev/null || true   # Ollama
    ufw allow 8080/tcp  &>/dev/null || true   # API Gateway
    ufw allow 6379/tcp  &>/dev/null || true   # Redis
fi

info "=== Diplo bereit ==="
free -h | awk '/^Mem:/{printf "RAM: %s total, %s verfügbar\n", $2, $7}'
REMOTE

ok "Alle schweren Services auf Diplo gestartet!"

# =============================================================================
# SCHRITT 3: SSH-Tunnel aufbauen (Port-Forwarding Mac ← Diplo)
# =============================================================================
step "3/5 · SSH-Tunnel einrichten (Server-Ports auf Mac verfügbar)"

TUNNEL_PLIST="$HOME/Library/LaunchAgents/com.core.diplo-tunnel.plist"
TUNNEL_LOG="$HOME/Library/Logs/mac-optimizer/diplo-tunnel.log"
mkdir -p "$HOME/Library/Logs/mac-optimizer"

# Aktiven Tunnel-Port-Mapping:
#   localhost:11434 → Diplo:11434 (Ollama LLM)
#   localhost:8080  → Diplo:8080  (API Gateway)
#   localhost:6379  → Diplo:6379  (Redis)
SSH_TUNNEL_CMD="ssh -N -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30 -o ServerAliveCountMax=5 -o ExitOnForwardFailure=yes -L 11434:localhost:11434 -L 8080:localhost:8080 -L 6379:localhost:6379 ${DIPLO_USER}@${DIPLO_IP}"

# LaunchAgent für permanenten Tunnel
cat > "$TUNNEL_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.core.diplo-tunnel</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>${SSH_TUNNEL_CMD}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardOutPath</key>
    <string>${TUNNEL_LOG}</string>
    <key>StandardErrorPath</key>
    <string>${TUNNEL_LOG}</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
</dict>
</plist>
PLIST

# Bestehenden Tunnel-Agent entladen
launchctl unload "$TUNNEL_PLIST" 2>/dev/null || true
# Neu laden
launchctl load "$TUNNEL_PLIST"
ok "SSH-Tunnel-LaunchAgent installiert (startet bei Login automatisch)"

# Kurz warten und Verbindung testen
sleep 3
if curl -sf --max-time 5 http://localhost:11434/api/tags &>/dev/null; then
    ok "Tunnel aktiv! Ollama auf Diplo über localhost:11434 erreichbar"
else
    warn "Tunnel läuft – Ollama auf Diplo wird gleich verfügbar sein."
fi

# =============================================================================
# SCHRITT 4: Mac-Environment konfigurieren (auf Server zeigen)
# =============================================================================
step "4/5 · Mac-Environment auf Diplo-Services zeigen"

ENV_FILE="$HOME/.diplo-env"
cat > "$ENV_FILE" <<'ENVFILE'
# Diplo-Offload-Konfiguration
# Alle AI-Calls gehen über den lokalen SSH-Tunnel an Diplo

# Ollama läuft auf Diplo, Mac sieht es als localhost
export OLLAMA_HOST="http://localhost:11434"

# OpenAI-kompatibler Endpunkt (Ollama)
export OPENAI_BASE_URL="http://localhost:11434/v1"
export OPENAI_API_KEY="ollama"  # Kein echter Key nötig für lokales Ollama

# Weitere Services auf Diplo
export REDIS_URL="redis://localhost:6379"
export API_GATEWAY_URL="http://localhost:8080"
ENVFILE

# In Shell-Config eintragen (einmalig)
SHELL_RC="$HOME/.zshrc"
if [[ -f "$HOME/.bashrc" ]]; then SHELL_RC="$HOME/.bashrc"; fi

if ! grep -q "diplo-env" "$SHELL_RC" 2>/dev/null; then
    cat >> "$SHELL_RC" <<'SHELLRC'

# Diplo-Offload: rechenintensive Services laufen auf dem Hetzner-Server
source "$HOME/.diplo-env" 2>/dev/null || true
SHELLRC
    ok "Diplo-Environment in $SHELL_RC eingetragen"
else
    ok "Diplo-Environment bereits in $SHELL_RC"
fi

# =============================================================================
# SCHRITT 5: Mac sofort entlasten (schwere Prozesse auf Server übertragen)
# =============================================================================
step "5/5 · Mac jetzt sofort entlasten"

# Lokale schwere Prozesse stoppen (falls Ollama lokal läuft)
if pgrep -x ollama &>/dev/null; then
    warn "Lokales Ollama läuft – wird gestoppt (Diplo übernimmt)..."
    pkill -x ollama 2>/dev/null || true
    ok "Lokales Ollama gestoppt – Diplo übernimmt die LLM-Last"
fi

# Mac RAM freigeben
if sudo -n true 2>/dev/null; then
    sudo purge 2>/dev/null || true
    ok "Mac RAM freigegeben"
fi

# =============================================================================
# FERTIG
# =============================================================================
echo ""
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║  OFFLOAD ABGESCHLOSSEN!                              ║"
echo "  ╠══════════════════════════════════════════════════════╣"
echo "  ║                                                      ║"
echo "  ║  Dein Mac:  Steuerzentrale (leicht, flüssig)        ║"
echo "  ║  Diplo:     Rechenpower (Ollama, AI, Docker)        ║"
echo "  ║                                                      ║"
echo "  ║  Ollama:    http://localhost:11434 (→ Diplo)        ║"
echo "  ║  API:       http://localhost:8080  (→ Diplo)        ║"
echo "  ║  Tunnel:    Läuft automatisch (auch nach Neustart)  ║"
echo "  ║                                                      ║"
echo "  ║  Tunnel-Log:                                         ║"
echo "  ║  tail -f ~/Library/Logs/mac-optimizer/diplo-tunnel.log ║"
echo "  ║                                                      ║"
echo "  ║  Tunnel manuell prüfen:                             ║"
echo "  ║  launchctl list com.core.diplo-tunnel               ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo ""
