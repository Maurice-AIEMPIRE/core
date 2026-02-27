# Mac Guardian AI - Der Prompt zum Kopieren

## Für X / Social Media Posts

---

### POST 1: Der Hook (Kurz, viral)

```
Mein Mac friert nie mehr ein. 🛡

Ich hab ein AI-System gebaut das meinen Mac 24/7 überwacht:
- Erkennt Probleme BEVOR sie auftreten
- Killt hängende Apps automatisch
- Verhindert Überhitzung
- Räumt Speicher frei
- Lernt aus eigenen Aktionen

Open Source. Ein Befehl. Fertig:

bash <(curl -sL https://raw.githubusercontent.com/Maurice-AIEMPIRE/core/claude/fix-pc-performance-epsd4/scripts/mac-performance/mac-guardian-quickstart.sh)

Thread 🧵👇
```

---

### POST 2: Technische Details

```
Was Mac Guardian AI unter der Haube macht:

🧠 AI Brain
→ Z-Score Anomalie-Erkennung
→ Lineare Regression für Vorhersagen
→ Pattern Learning (merkt sich was funktioniert hat)

🌡 Thermal Guardian
→ Erkennt Überhitzung bevor macOS drosselt
→ 3 Stufen: light → medium → heavy
→ Pausiert Prozesse temporär mit Auto-Resume

🧹 Memory Guardian
→ Erkennt Speicherlecks durch Trend-Analyse
→ 4 Stufen Freigabe bis Notfall
→ Beendet Low-Priority Apps wenn nötig

⚡ Process Manager
→ Gibt deiner aktiven App CPU-Priorität
→ Erkennt hängende Apps und beendet sie
→ Räumt Zombie-Prozesse auf

4.654 Zeilen. 8 Module. 0 Config nötig.

Gebaut mit Claude Code in einer Session.
```

---

### POST 3: Der Claude Code Prompt

```
Willst du das SELBST bauen? Hier der Prompt für Claude Code:

Paste das in Claude Code (oder jede andere coding AI) 👇
```

---

## DER PROMPT (Zum Kopieren in Claude Code / ChatGPT / Cursor etc.)

```
Baue mir ein vollständiges Mac Performance Guardian System mit folgenden Anforderungen:

ARCHITEKTUR:
- Modulares System mit gemeinsamer Library (Logging, Metriken, Trends)
- Jedes Modul läuft unabhängig, ein Master-Orchestrator koordiniert alles
- LaunchAgent für automatischen Start beim Login
- CLI-Tool "guardian" für einfache Steuerung

MODULE:

1. AUDIT ENGINE
- 50+ System-Checks: CPU, RAM, Disk, Thermal, Network, Battery, Security, Browser, Spotlight, Autostart
- Generiert detaillierten Report auf dem Desktop
- JSON-Export aller Issues mit Severity

2. AI BRAIN (Entscheidungs-Engine)
- Pattern Learning: Speichert welche Aktion bei welchem Problem geholfen hat
- Adaptive Schwellwerte basierend auf statistischer Baseline (Mean + 1.5*StdDev)
- Vorhersage: Lineare Regression um Threshold-Breach X Minuten vorher zu erkennen
- Anomalie-Erkennung: Z-Score basiert (>2.5 = Anomalie)
- Korrelation: Erkennt zusammenhängende Probleme (CPU+RAM=App-Overload, CPU+Temp=Throttling)
- Feedback-Loop: Evaluiert ob Aktionen erfolgreich waren und lernt daraus

3. THERMAL GUARDIAN
- CPU-Temperatur lesen (powermetrics, IOKit, kernel_task als Fallback)
- 3 Stufen Last-Reduzierung:
  * Light: Spotlight-Indexierung pausieren, Time Machine drosseln
  * Medium: + CPU-intensive Hintergrundprozesse renicen
  * Heavy: + Prozesse temporär pausieren (SIGSTOP) mit automatischem Resume nach 30s
- Geschützte Prozesse: WindowServer, kernel_task, loginwindow, Finder, Dock

4. MEMORY GUARDIAN
- RAM-Metriken via vm_stat (free, active, wired, compressed, swap)
- Memory Leak Detection: Snapshots alle 100s, Vergleich über 5min, Alarm bei >20% Wachstum UND >100MB
- 4 Stufen Freigabe:
  * Soft: purge + Browser-Cache
  * Medium: + Erweiterte Caches + memory_pressure warn
  * Aggressive: + Low-Priority Apps beenden (Slack, Discord, Spotify etc.)
  * Emergency: + Top 3 RAM-Verbraucher killen

5. DISK GUARDIAN
- Auto-Cleanup: Browser-Caches, System-Logs, Crash-Reports, Temp, Xcode DerivedData, npm/yarn/pip cache, Homebrew
- Papierkorb auto-leeren bei >1GB
- Downloads >30 Tage in Unterordner verschieben
- SSD SMART-Status prüfen (stündlich)
- Bereinigung startet automatisch bei >85% Belegung

6. NETWORK OPTIMIZER
- DNS-Speed-Test: Cloudflare (1.1.1.1), Google (8.8.8.8), Quad9 (9.9.9.9), OpenDNS
- Automatischer Wechsel zum schnellsten DNS bei >150ms
- Wi-Fi Signal-Monitoring (RSSI, Noise, SNR)
- Konnektivitäts-Watchdog mit auto DNS-Cache-Flush
- TCP-Tuning (Window Scaling, Buffer Size, Delayed ACK)

7. PROCESS MANAGER
- Vordergrund-App Erkennung → höchste Priorität (renice -5)
- App-Kategorisierung: System(0), Arbeit(1), Kommunikation(3), Media(4), Gaming(5)
- Hängende Apps erkennen (3s Timeout-Test) und force-quit
- Runaway-Prozesse erkennen (>100% CPU) und drosseln (renice 20)
- Zombie-Prozesse bereinigen
- Max 5 automatische Kills pro Stunde

8. ORCHESTRATOR
- Hauptschleife alle 10 Sekunden
- Sammelt Metriken von allen Modulen
- Fragt AI Brain nach Entscheidung
- Führt empfohlene Aktion aus
- Evaluiert Ergebnis (Feedback-Loop)
- Tagesbericht um 22 Uhr
- Selbstheilung: Log-Rotation, alte Daten bereinigen

INSTALLER:
- Ein-Klick-Installation
- LaunchAgent mit KeepAlive und Auto-Restart
- "guardian" CLI-Befehl (start/stop/status/audit/report/log/config/uninstall)
- Konfigurierbares .conf File mit allen Schwellwerten

TECH REQUIREMENTS:
- Nur bash, keine externen Dependencies
- macOS native Tools (vm_stat, ps, top, sysctl, pmset, diskutil, osascript etc.)
- Niedriger Eigenverbrauch (Nice 10, LowPriorityIO)
- Alle Metriken als CSV mit Timestamps
- Log-Rotation bei >50MB
```

---

## ALTERNATIVE: Kürzerer Prompt (für ChatGPT/GPT-4)

```
Baue ein macOS Performance-Daemon in Bash:

1. Überwacht alle 10s: CPU, RAM, Temp, Disk, Network
2. AI-Entscheidungs-Engine: Adaptive Schwellwerte (Mean+1.5*StdDev), Trend-Vorhersage, Z-Score Anomalie-Erkennung, Pattern Learning
3. Automatische Reaktion auf Probleme:
   - CPU zu hoch → Prozesse drosseln/pausieren
   - RAM voll → 4-stufige Freigabe (Cache→Apps killen)
   - Überhitzung → Last reduzieren bevor Throttling
   - Disk voll → Auto-Cleanup Caches/Logs/Temp
   - DNS langsam → Auto-Switch zum schnellsten Server
   - App hängt → Auto Force-Quit
4. LaunchAgent für Autostart
5. CLI: guardian {start|stop|status|audit}
6. Nur bash + native macOS Tools, keine Dependencies

Generiere alle Dateien komplett.
```

---

## INSTALLATION (für README)

### One-Liner (empfohlen):
```bash
bash <(curl -sL https://raw.githubusercontent.com/Maurice-AIEMPIRE/core/claude/fix-pc-performance-epsd4/scripts/mac-performance/mac-guardian-quickstart.sh)
```

### Manuell:
```bash
git clone https://github.com/Maurice-AIEMPIRE/core.git
cd core
git checkout claude/fix-pc-performance-epsd4
cd scripts/mac-performance
./guardian-install.sh
```

### Danach:
```bash
guardian status     # Status prüfen
guardian audit      # Vollständiges System-Audit
guardian log        # Live-Log ansehen
guardian config     # Einstellungen anpassen
guardian stop       # Stoppen
guardian uninstall  # Komplett entfernen
```
