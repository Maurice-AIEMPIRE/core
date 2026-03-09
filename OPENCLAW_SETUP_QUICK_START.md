# OpenClaw + Tailscale Quick Start

**Two-minute setup for remote CORE gateway with client connection.**

## Server Setup (Ubuntu 24.04+)

```bash
# 1. Run setup script
sudo bash scripts/setup-openclaw-server.sh

# 2. Copy the token displayed at the end
# 3. Get your Tailscale IP: tailscale ip -4
```

## Mac Client Setup

```bash
# Replace values with your server details
bash scripts/setup-openclaw-mac.sh \
  --token YOUR_TOKEN_FROM_ABOVE \
  --server YOUR_TAILSCALE_IP
```

## Manual Setup (If Scripts Fail)

### Server
```bash
TOKEN=$(openssl rand -hex 32)
echo "$TOKEN" > /root/.openclaw_gateway_token
chmod 600 /root/.openclaw_gateway_token

openclaw config set gateway.auth.mode "token"
openclaw config set gateway.auth.token "$TOKEN"
openclaw config set agents.defaults.model.primary "ollama/qwen2.5-coder:14b-q5_K_M"

openclaw gateway restart
tailscale serve 443 http://127.0.0.1:18789

echo "=== COPY THIS TOKEN ==="
cat /root/.openclaw_gateway_token
```

### Mac
```bash
openclaw gateway stop
pkill -f "ssh -N -L 18789" || true

# Replace DEIN_TOKEN and SERVER_IP
openclaw gateway connect --url wss://SERVER_IP:443 --token DEIN_TOKEN
```

## Verification

```bash
# Mac client
openclaw gateway status
openclaw models list

# Test inference
openclaw query "Hello, test this connection"
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Connection failed | Verify Tailscale: `tailscale status` |
| Token error | Regenerate token on server, reconnect on Mac |
| Models not found | Check server: `ollama ps` |
| Port 443 blocked | Tailscale handles this automatically |

## Architecture

```
Server (100.124.239.46)
├─ OpenClaw Gateway :18789
├─ Ollama Models
└─ Tailscale Serve :443

    ↓ (WSS over Tailscale)

Mac Client
└─ OpenClaw Client
```

## Documentation

- Full guide: [`docs/guides/openclaw-tailscale-setup.mdx`](docs/guides/openclaw-tailscale-setup.mdx)
- Server script: [`scripts/setup-openclaw-server.sh`](scripts/setup-openclaw-server.sh)
- Mac script: [`scripts/setup-openclaw-mac.sh`](scripts/setup-openclaw-mac.sh)
