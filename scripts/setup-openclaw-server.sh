#!/bin/bash
set -e

echo "🦞 OpenClaw Gateway Server Setup (2026.3.7)"
echo "=============================================="

# Check if running as root or with sudo
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root or with sudo"
   exit 1
fi

# Check OpenClaw is installed
if ! command -v openclaw &> /dev/null; then
    echo "❌ OpenClaw not found. Install with: curl -fsSL https://openclaw.ai/install.sh | bash"
    exit 1
fi

# Check Tailscale is installed
if ! command -v tailscale &> /dev/null; then
    echo "⚠️  Tailscale not found. Install with: curl -fsSL https://tailscale.com/install.sh | sh"
    exit 1
fi

echo ""
echo "📝 Step 1: Generating secure authentication token..."
TOKEN=$(openssl rand -hex 32)
echo "$TOKEN" > /root/.openclaw_gateway_token
chmod 600 /root/.openclaw_gateway_token
echo "✓ Token generated and stored securely"

echo ""
echo "⚙️  Step 2: Configuring OpenClaw Gateway..."

# Set gateway authentication
openclaw config set gateway.auth.mode "token" || true
openclaw config set gateway.auth.token "$TOKEN" || true

# Set primary model
openclaw config set agents.defaults.model.primary "ollama/qwen2.5-coder:14b-q5_K_M" || true

# Set fallback models (optional)
openclaw config set agents.defaults.model.fallbacks '["ollama/phi4:14b-q5_K_M","ollama/mistral:7b"]' || true

echo "✓ Gateway configuration updated"

echo ""
echo "🚀 Step 3: Starting OpenClaw Gateway..."
openclaw gateway restart || {
    echo "⚠️  Gateway restart had issues, attempting manual start..."
    pkill -f "openclaw gateway" || true
    sleep 2
    nohup openclaw gateway --port 18789 --token "$TOKEN" >/var/log/openclaw-gateway.log 2>&1 &
    sleep 3
}
echo "✓ Gateway started on port 18789"

echo ""
echo "🔗 Step 4: Configuring Tailscale Serve..."
tailscale serve 443 http://127.0.0.1:18789 || {
    echo "⚠️  Tailscale serve failed. Ensure Tailscale is authenticated:"
    echo "   tailscale up"
    exit 1
}
echo "✓ Tailscale serving gateway on HTTPS 443"

echo ""
echo "✅ Server Setup Complete!"
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                   COPY THIS TOKEN EXACTLY                   ║"
echo "╠════════════════════════════════════════════════════════════╣"
cat /root/.openclaw_gateway_token
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Get your Tailscale IP:"
tailscale ip -4
echo ""
echo "Next: Run setup-openclaw-mac.sh on your Mac client with:"
echo "  --token <the-token-above>"
echo "  --server <your-tailscale-ip>"
echo ""
