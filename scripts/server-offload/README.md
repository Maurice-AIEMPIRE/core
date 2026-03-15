# Mac → Diplo Offload

**Mac = leichte Steuerzentrale | Diplo (Hetzner) = Rechenmaschine**

## Schnellstart (auf dem Mac ausführen)

```bash
# 1. Diplo-Server einrichten (einmalig, per SSH)
ssh root@65.21.203.174 bash -s < scripts/server-offload/diplo-server-setup.sh

# 2. Mac auf Diplo verbinden (SSH-Tunnel + permanenter LaunchAgent)
bash scripts/server-offload/mac-offload-to-diplo.sh
```

## Was läuft wo?

| Service | Diplo (Server) | Mac |
|---------|---------------|-----|
| Ollama LLM | ✅ läuft auf Server | Tunnel → localhost:11434 |
| Redis Cache | ✅ läuft auf Server | Tunnel → localhost:6379 |
| API Gateway | ✅ läuft auf Server | Tunnel → localhost:8080 |
| Claude Code | – | ✅ Steuerzentrale |
| Browser | – | ✅ UI/Control |

## Tunnel-Status prüfen

```bash
launchctl list com.core.diplo-tunnel
curl http://localhost:11434/api/tags
```

## Tunnel Log

```bash
tail -f ~/Library/Logs/mac-optimizer/diplo-tunnel.log
```
