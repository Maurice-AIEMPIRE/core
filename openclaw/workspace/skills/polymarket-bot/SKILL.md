---
name: polymarket-bot
description: Polymarket Prediction Market Bot mit AI Signals und Arbitrage
version: 1.0.0
metadata:
  openclaw:
    requires:
      config:
        - browser
---

# Polymarket Prediction Bot Skill

Browser-basierter Polymarket Monitor und Trading Signal Generator.
Agent: Chandler (Sales & Trading)

## SAFETY RULES
1. **PAPER-MODUS DEFAULT** — Nur Signale, kein automatischer Trade
2. **Human-in-the-Loop** — Manuelle Freigabe vor jeder Aktion
3. **Wallet-Verbindung** muss manuell erfolgen

## Browser Script
`openclaw/browser/polymarket.sh`

## Befehle
- `/chandler-poly-login` — Polymarket Login pruefen
- `/chandler-poly-trending` — Trending Markets anzeigen
- `/chandler-poly-signals` — AI Trading Signals generieren
- `/chandler-poly-portfolio` — Eigene Positionen
- `/chandler-poly-arbitrage` — Arbitrage Chancen finden
- `/chandler-poly-report` — Taeglicher Report
- `./polymarket.sh search <query>` — Markets suchen
- `./polymarket.sh market <url>` — Market-Details analysieren
- `./polymarket.sh watchlist [add|remove|show] [url]` — Watchlist

## Features
- Trending Market Scanner (5 Kategorien: Politics, Crypto, Sports, Science, Economy)
- AI Signal Generator mit Konfidenz-Scoring
- Arbitrage Scanner (Overround/Underround, korrelierte Markets)
- Watchlist Management
- Taeglicher Report mit Telegram-Benachrichtigung
