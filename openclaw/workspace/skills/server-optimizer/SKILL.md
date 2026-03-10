# 🛰️ Server Optimizer Skill

## Purpose
Manages RAM and resource allocation on the Hetzner Bare Metal server (125GB). Ensures 80GB+ of free RAM is available to support the orchestration of 200+ parallel AI agents.

## Capabilities
- **RAM Throttling**: Automatically adjusts sysctl parameters and swap files to prevent memory exhaustion.
- **Docker Cleanup**: Prunes unused Docker volumes and images to reclaim storage and memory.
- **Agent Acceleration**: Configures OpenClaw to prioritize high-performance agents when memory headroom is available.
- **Security Watchdog**: Monitors SSH access and firewall status post-optimization.

## Commands
- `optimize-server`: Run full RAM tuning on the Hetzner server.
- `check-server-ram`: View real-time memory usage and agent overhead.
- `scale-agents`: Adjust parallel agent instances based on free RAM.

## Integration
- **Hetzner SSH**: Requires root access to the Hetzner server (100.124.239.46).
- **OpenClaw Gateway**: Direct integration with the gateway-monitor.py to trigger alerts via Telegram.

---
*Powered by Lobster-Empire*
