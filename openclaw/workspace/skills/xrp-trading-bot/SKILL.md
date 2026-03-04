---
name: xrp-trading-bot
description: XRP Trading Bot mit Signalen, Whale Alerts und AI-Analyse
version: 1.0.0
metadata:
  openclaw:
    requires:
      config:
        - browser
---

# XRP Trading Bot Skill

Browser-basierter XRP Trading Monitor und Signal Generator.
Agent: Chandler (Sales & Trading)

## SAFETY RULES
1. **PAPER-MODUS DEFAULT** — Nur Signale und Empfehlungen, kein Auto-Trading
2. **Human-in-the-Loop** — Jede Trade-Empfehlung braucht manuelle Freigabe
3. **Kein echtes Geld** ohne explizite Freigabe

## Browser Script
`openclaw/browser/trading-xrp.sh`

## Befehle
- `/chandler-xrp-price` — Aktueller XRP Preis (CoinGecko)
- `/chandler-xrp-signals` — Trading Signals generieren (Momentum-basiert)
- `/chandler-xrp-monitor` — Live Price Monitor (Loop)
- `/chandler-xrp-analysis` — AI-basierte Analyse via Ollama
- `/chandler-xrp-fear` — Crypto Fear & Greed Index
- `/chandler-xrp-whale` — Whale Bewegungen pruefen
- `/chandler-xrp-news` — Aktuelle XRP News
- `/chandler-xrp-dca` — DCA Strategie berechnen
- `/chandler-xrp-alerts` — Preis-Alerts konfigurieren

## Signal-Scoring
- Score -3 bis +3 basierend auf 24h/7d/14d/30d Preisaenderungen
- STRONG BUY / BUY / HOLD / SELL / STRONG SELL
- Alerts via Telegram bei Zielpreisen oder >5% Bewegungen

## Datenquellen
- CoinGecko API (kostenlos, kein API Key noetig)
- Alternative.me Fear & Greed Index
- Whale Alert (Browser Scraping)
- Google News (Browser)
- Ollama AI fuer Zusammenfassungen
