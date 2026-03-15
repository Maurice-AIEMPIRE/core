# SSH Remote Access Setup – @maurice__92

## Status
- ✅ Deine Termius-Phone-Keys wurden in `~/.ssh/authorized_keys` eingetragen
- ✅ Keys haben korrekte Permissions (600)
- ⚙️ Remote-Zugang (außerhalb Local Network) erfordert folgende Schritte

---

## Deine SSH Keys (bereits eingetragen)
```
Key 1: ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAABB...BIdpr6BF...
Key 2: ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAABB...BH0khw1e...
```
Beide Termius-Keys von `ssh.id / @maurice__92` sind gesetzt.

---

## Remote-Zugang einrichten (außerhalb Local Network)

### Option A: Router Port-Forwarding (einfachste Lösung)
1. Router-Admin öffnen (meist `192.168.1.1` oder `192.168.0.1`)
2. Port-Forwarding / NAT-Regel erstellen:
   - **Externer Port**: `2222` (nicht 22 – weniger Bot-Traffic)
   - **Interner Port**: `22`
   - **Ziel-IP**: Deine Server-LAN-IP (z.B. `192.168.1.X`)
3. Deine externe IP herausfinden: `curl ifconfig.me`
4. In Termius verbinden: `[externe-ip]:2222`

> **Tipp**: Fritzbox → Heimnetz → Netzwerk → Port-Sharing

### Option B: Tailscale (empfohlen – kein Port-Forwarding nötig)
Tailscale erstellt ein privates VPN-Mesh. Kein offener Port nötig.
```bash
# Auf dem Server installieren:
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# Auf dem iPhone:
# Tailscale App installieren + einloggen
# Dann per SSH auf die Tailscale-IP verbinden
```
→ Funktioniert überall, selbst hinter CGNAT.

### Option C: Cloudflare Tunnel (für erfahrene Nutzer)
```bash
# Cloudflared installieren und SSH-Tunnel einrichten
# Kein offener Port, kein öffentliche IP nötig
```

---

## Termius-Konfiguration (iPhone)

### Verbindungs-Settings:
```
Host: [Server-IP oder Tailscale-IP]
Port: 22 (lokal) / 2222 (Port-Forwarding) / Tailscale: 22
Username: root (oder dein User)
Auth: SSH Key
Key: Wähle deinen gespeicherten ECDSA-Key aus
```

### Troubleshooting – Verbindung schlägt fehl:
1. **Permission denied**: Key in Termius korrekt ausgewählt?
2. **Connection refused**: SSH-Dienst läuft? → `systemctl status sshd`
3. **Timeout**: Firewall/Router blockiert? → Port-Forwarding prüfen
4. **Host key changed**: Termius meldet sich – alten Key löschen + neu verbinden

---

## SSH-Härtung (empfohlen nach Einrichtung)

Füge in `/etc/ssh/sshd_config` hinzu:
```
PasswordAuthentication no
PermitRootLogin prohibit-password
MaxAuthTries 3
ClientAliveInterval 300
```
Dann: `systemctl reload sshd`

---

## Quick-Connect Befehl (von anderem Gerät)
```bash
ssh -i ~/.ssh/[dein-key] root@[server-ip] -p 22
```
