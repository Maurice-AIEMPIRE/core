# Mac Performance Fix - Anleitung

## Schnellstart (3 Schritte)

### 1. Dateien auf den Mac kopieren
Lade diesen Ordner `scripts/mac-performance/` auf deinen Mac herunter.

### 2. Ausfuehrbar machen
```bash
cd ~/Downloads/mac-performance   # oder wo du den Ordner gespeichert hast
chmod +x *.sh
```

### 3. Ausfuehren (in dieser Reihenfolge)

```bash
# Schritt 1: Diagnose - Was ist los?
./01-diagnose.sh

# Schritt 2: Sofortmassnahmen - Sofort schneller
./02-sofortmassnahmen.sh

# Schritt 3: Dauerhafte Optimierung
./03-dauerhafte-optimierung.sh

# Schritt 4: Guardian installieren (automatischer Waechter)
./install-guardian.sh
```

---

## Was macht jedes Skript?

### `01-diagnose.sh` - Systemanalyse
- Analysiert CPU, RAM, Festplatte, Netzwerk
- Zeigt die groessten Ressourcen-Fresser
- Prueft Browser-Tab-Anzahl
- Erkennt Probleme mit Spotlight, Thermal Throttling
- Speichert einen Report auf dem Desktop

### `02-sofortmassnahmen.sh` - Sofort-Fix
- Gibt RAM frei (purge)
- Beendet CPU-Fresser (mit Rueckfrage)
- Beendet haengende Apps
- Bereinigt Caches
- Leert DNS-Cache
- Leert Papierkorb
- Behebt Spotlight-Probleme

### `03-dauerhafte-optimierung.sh` - Permanente Fixes
- Reduziert Animationen (schnelleres Gefuehl)
- Reduziert Transparenz-Effekte
- Optimiert Spotlight-Indexierung
- Bereinigt Autostart-Programme
- Optimiert Energieeinstellungen
- Installiert den Guardian Daemon

### `mac-guardian-daemon.sh` - Automatischer Waechter
Der Guardian ist ein intelligenter Hintergrundprozess der:
- Alle 10 Sekunden CPU, RAM und Swap prueft
- Haengende Apps automatisch erkennt und beendet
- Bei hohem RAM-Verbrauch automatisch Speicher freigibt
- Bei CPU-Ueberlastung niedrig-priorisierte Apps beendet
- Geschuetzte Apps (Finder, Terminal, etc.) NIEMALS beendet
- Maximal 5 Apps pro Stunde automatisch beendet (Sicherheitsgrenze)
- macOS-Benachrichtigungen bei Eingriffen anzeigt

### `install-guardian.sh` - Guardian-Installation
- Installiert den Guardian nach `~/.mac-guardian/`
- Richtet automatischen Start beim Login ein
- Erstellt anpassbare Konfiguration

---

## Guardian konfigurieren

Bearbeite `~/.mac-guardian/config.sh`:

```bash
nano ~/.mac-guardian/config.sh
```

Wichtige Einstellungen:
- `CPU_CRITICAL_THRESHOLD`: Ab welcher CPU% eingegriffen wird (Standard: 95%)
- `RAM_CRITICAL_THRESHOLD`: Ab welcher RAM% eingegriffen wird (Standard: 93%)
- `PROTECTED_APPS`: Apps die NIE beendet werden
- `LOW_PRIORITY_APPS`: Apps die ZUERST beendet werden
- `MAX_KILLS_PER_HOUR`: Sicherheitsgrenze (Standard: 5)

---

## Guardian-Befehle

```bash
# Status anzeigen
~/.mac-guardian/mac-guardian-daemon.sh status

# Stoppen
~/.mac-guardian/mac-guardian-daemon.sh stop

# Starten
~/.mac-guardian/mac-guardian-daemon.sh start

# Log ansehen (live)
tail -f ~/.mac-guardian/guardian.log

# Komplett deinstallieren
launchctl unload ~/Library/LaunchAgents/com.mac-guardian.daemon.plist
rm ~/Library/LaunchAgents/com.mac-guardian.daemon.plist
rm -rf ~/.mac-guardian
```
