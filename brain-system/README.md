# 🧠 Brain System — Setup & Bedienung

Dein persönliches KI-Gehirn, steuerbar per Telegram.
Einmal einrichten, dann läuft alles automatisch.

---

## Schnellstart (3 Schritte)

### 1. Tokens eintragen

Öffne die Datei:
```
brain-system/config.env
```

Fülle diese 3 Zeilen aus:

```env
TELEGRAM_BOT_TOKEN=  # von @BotFather in Telegram
TELEGRAM_CHAT_ID=    # schreib @userinfobot → gibt dir deine ID
TELEGRAM_ADMIN_IDS=  # gleiche Zahl wie CHAT_ID (bei Privat-Chat)
```

> **Tipp:** Öffne Telegram, schreib `@userinfobot` — er antwortet sofort mit deiner ID.

---

### 2. Starten

```bash
bash brain-system/start.sh
```

Das Script prüft automatisch ob alle Felder ausgefüllt sind und zeigt dir was noch fehlt.

---

### 3. Fertig

Schreib deinem Bot in Telegram. Alle Funktionen sind sofort aktiv.

---

## Telegram-Befehle

| Befehl | Was er macht |
|---|---|
| `/health` | System-Check — läuft alles? |
| `/morning` | Morgen-Briefing |
| `/cycle` | Kompletter Tages-Durchlauf |
| `/xp 50 Notiz` | XP hinzufügen |
| `/streak name` | Streak aktualisieren |
| `/status` | Offene Aufgaben + Fehlerrate |
| `/log 20` | Letzte 20 Zeilen des Logs |
| `/cleanup` | Alte Daten aufräumen |
| `/amygdala` | Risiko-Scan jetzt starten |
| `/models` | Welches KI-Modell macht was |
| `/seclog 10` | Letzte 10 Security-Events |

> **Freitext:** Einfach schreiben ohne `/` — der Bot erkennt Fehler und löst sie automatisch.

---

## Sicherheit (läuft automatisch)

Das System schützt sich selbst — du musst nichts tun:

| Schutz | Was passiert |
|---|---|
| **Sender-Auth** | Nur du kannst Befehle senden |
| **Rate-Limit** | Max. 20 Nachrichten/Minute |
| **Injection-Guard** | Angriffe werden blockiert & geloggt |
| **Security-Log** | Alle Ereignisse werden gespeichert |

Bei einem Angriff bekommst du sofort eine Warnung in Telegram.
Logs anschauen: `/seclog 20`

---

## Konfiguration

Alle Einstellungen in `brain-system/config.env`:

```env
## Pflichtfelder
TELEGRAM_BOT_TOKEN=    # Bot-Token von @BotFather
TELEGRAM_CHAT_ID=      # Deine Chat-ID
TELEGRAM_ADMIN_IDS=    # Deine User-ID(s), kommagetrennt

## KI-Modelle
ANTHROPIC_API_KEY=     # Claude / Anthropic
OPENAI_API_KEY=        # OpenAI (optional)
OLLAMA_URL=            # Lokale Modelle (optional)

## Feintuning
TELEGRAM_POLL_SLEEP=10     # Prüfintervall in Sekunden
TELEGRAM_RATE_LIMIT=20     # Max. Nachrichten pro Minute
```

---

## Dateien

```
brain-system/
├── config.env          ← Deine Tokens (hier eintragen)
├── start.sh            ← Starter-Script
├── telegram_bridge.py  ← Telegram-Bot + Security
└── README.md           ← Diese Datei
```

---

## Troubleshooting

**Bot antwortet nicht**
- Prüfe ob `TELEGRAM_BOT_TOKEN` korrekt ist
- Schreib zuerst `/start` an deinen Bot

**"Unauthorized" Fehler**
- Deine `TELEGRAM_ADMIN_IDS` stimmt nicht — prüfe sie mit `@userinfobot`

**Bot startet nicht**
- Das Script sagt dir genau was fehlt — einfach lesen und eintragen
