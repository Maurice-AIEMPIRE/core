#!/bin/bash
set -e

echo "🦞 OpenClaw Mac Client Setup (2026.3.7)"
echo "========================================"

# Parse arguments
TOKEN=""
SERVER=""
SSH_USER="root"
SSH_HOST=""

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
        --ssh-user)
            SSH_USER="$2"
            shift 2
            ;;
        --ssh-host)
            SSH_HOST="$2"
            shift 2
            ;;
        *)
            echo "Usage: $0 --token TOKEN --server SERVER_IP [--ssh-user USER] [--ssh-host HOSTNAME]"
            echo ""
            echo "Examples:"
            echo "  With SSH tunnel:"
            echo "    $0 --token a8191cc6... --server 100.124.239.46 --ssh-user ubuntu --ssh-host example.com"
            echo ""
            echo "  Or if gateway binds to Tailscale IP (requires server config):"
            echo "    openclaw gateway --bind tailnet  # Run this on the server first"
            exit 1
            ;;
    esac
done

# Validate inputs
if [ -z "$TOKEN" ]; then
    echo "❌ Error: --token is required"
    exit 1
fi

if [ -z "$SERVER" ]; then
    echo "❌ Error: --server is required"
    exit 1
fi

# Check if OpenClaw is installed
if ! command -v openclaw &> /dev/null; then
    echo "❌ OpenClaw not found. Install with:"
    echo "   curl -fsSL https://openclaw.ai/install.sh | bash"
    exit 1
fi

echo ""
echo "📝 Step 1: Preparing local environment..."

# Kill any existing SSH tunnel
pkill -f "ssh -N -L 18789" || true
sleep 1

echo "✓ Ready to connect"

echo ""
echo "🔗 Step 2: Connecting to remote gateway..."
echo "   Server: $SERVER (Tailscale)"
echo ""

# Method 1: Try direct connection via Tailscale (if gateway binds to Tailscale IP)
echo "   Trying direct connection to Tailscale gateway..."
if openclaw gateway health --url "ws://$SERVER:18789" --token "$TOKEN" >/dev/null 2>&1; then
    echo "✓ Direct connection successful!"
    echo ""
    echo "📊 Gateway Configuration:"
    echo "   Type: Direct (Tailscale)"
    echo "   Address: ws://$SERVER:18789"
    echo "   Token: ${TOKEN:0:8}..."
elif [ -n "$SSH_HOST" ]; then
    # Method 2: Set up SSH tunnel
    echo "✓ Starting SSH tunnel to $SSH_USER@$SSH_HOST..."
    ssh -N -L 18789:127.0.0.1:18789 "$SSH_USER@$SSH_HOST" &
    SSH_PID=$!
    sleep 2

    # Test tunnel connection
    if openclaw gateway health --url "ws://127.0.0.1:18789" --token "$TOKEN" >/dev/null 2>&1; then
        echo "✓ SSH tunnel connection successful!"
        echo ""
        echo "📊 Gateway Configuration:"
        echo "   Type: SSH Tunnel"
        echo "   Address: ws://127.0.0.1:18789"
        echo "   Tunnel: $SSH_USER@$SSH_HOST -> $SERVER"
        echo "   Tunnel PID: $SSH_PID"
        echo ""
        echo "   To kill tunnel later: kill $SSH_PID"
    else
        kill $SSH_PID 2>/dev/null || true
        echo "❌ SSH tunnel connection failed. Check:"
        echo "   1. SSH credentials: $SSH_USER@$SSH_HOST"
        echo "   2. Gateway running on server: openclaw gateway status"
        exit 1
    fi
else
    # Neither method works
    echo "❌ Cannot reach gateway at ws://$SERVER:18789"
    echo ""
    echo "Fix this by either:"
    echo ""
    echo "1️⃣  Configure server to bind to Tailscale:"
    echo "    ssh root@$SERVER"
    echo "    openclaw gateway --bind tailnet"
    echo "    # Then retry this script"
    echo ""
    echo "2️⃣  Use SSH tunnel method:"
    echo "    $0 --token $TOKEN --server $SERVER --ssh-user ubuntu --ssh-host HOSTNAME"
    echo ""
    exit 1
fi

echo ""
echo "✅ Setup Complete!"
echo ""
echo "🚀 Test your connection:"
echo "   openclaw query 'What is 2+2?'"
echo ""
echo "   Or check gateway status:"
echo "   openclaw gateway status"
echo ""
