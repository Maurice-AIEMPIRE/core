#!/bin/bash
set -e

echo "🦞 OpenClaw Mac Client Setup (2026.3.7)"
echo "========================================"

# Parse arguments
TOKEN=""
SERVER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --token)
            TOKEN="$2"
            shift 2
            ;;
        --server)
            SERVER="$2"
            shift 2
            ;;
        *)
            echo "Usage: $0 --token TOKEN --server SERVER_IP"
            echo "Example: $0 --token a8191cc6... --server 100.124.239.46"
            exit 1
            ;;
    esac
done

# Validate inputs
if [ -z "$TOKEN" ]; then
    echo "❌ Error: --token is required"
    echo "Usage: $0 --token TOKEN --server SERVER_IP"
    exit 1
fi

if [ -z "$SERVER" ]; then
    echo "❌ Error: --server is required"
    echo "Usage: $0 --token TOKEN --server SERVER_IP"
    exit 1
fi

# Check if OpenClaw is installed
if ! command -v openclaw &> /dev/null; then
    echo "❌ OpenClaw not found. Install with:"
    echo "   curl -fsSL https://openclaw.ai/install.sh | bash"
    exit 1
fi

# Check if Tailscale is installed
if ! command -v tailscale &> /dev/null; then
    echo "⚠️  Tailscale not found. Install with:"
    echo "   brew install --cask tailscale"
    echo "   # Then run: open -a Tailscale"
    exit 1
fi

echo ""
echo "📝 Step 1: Preparing local environment..."

# Stop any existing gateway
openclaw gateway stop || true
pkill -f "ssh -N -L 18789" || true
sleep 2

echo "✓ Local gateway stopped"

echo ""
echo "🔗 Step 2: Connecting to remote gateway..."
echo "   Server: $SERVER"
echo "   URL: wss://$SERVER:443"

# Connect to remote gateway
if openclaw gateway connect --url "wss://$SERVER:443" --token "$TOKEN"; then
    echo "✓ Connected to remote gateway"
else
    echo "❌ Connection failed. Check:"
    echo "   1. Server token is correct"
    echo "   2. Server IP is reachable via Tailscale"
    echo "   3. Server gateway is running: openclaw gateway status"
    exit 1
fi

sleep 2

echo ""
echo "✅ Mac Client Setup Complete!"
echo ""
echo "🔍 Verifying connection..."
if openclaw gateway status 2>/dev/null | grep -q "connected\|active"; then
    echo "✓ Gateway connection verified"
else
    echo "⚠️  Gateway status unclear. Run: openclaw gateway status"
fi

echo ""
echo "📊 Available Models:"
openclaw models list 2>/dev/null || echo "   (Models listed on server)"

echo ""
echo "🚀 Next Steps:"
echo "   1. Test query: openclaw query 'test prompt'"
echo "   2. Check status: openclaw gateway status"
echo "   3. View logs: tail -f ~/.openclaw/gateway.log"
echo ""
