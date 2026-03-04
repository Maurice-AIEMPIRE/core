#!/usr/bin/env bash
# ================================================================
# CHANDLER — Polymarket Prediction Bot via Browser
# ================================================================
# Browser-basierter Polymarket Monitor + Trading Bot
# Scannt Maerkte, analysiert Wahrscheinlichkeiten, tradet Events
#
# Befehle:
#   ./polymarket.sh login              — Polymarket Login pruefen
#   ./polymarket.sh trending           — Trending Markets anzeigen
#   ./polymarket.sh search <query>     — Maerkte suchen
#   ./polymarket.sh market <url>       — Market-Details analysieren
#   ./polymarket.sh portfolio          — Eigene Positionen anzeigen
#   ./polymarket.sh signals            — AI Signal Generator
#   ./polymarket.sh news               — Relevante News scannen
#   ./polymarket.sh arbitrage          — Arbitrage Chancen finden
#   ./polymarket.sh watchlist          — Watchlist verwalten
#   ./polymarket.sh report             — Taeglicher Report
# ================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/browser-helper.sh"

PROFILE="openclaw"
POLYMARKET="https://polymarket.com"
MEMORY_FILE="$MEMORY_DIR/polymarket.json"

# --- State Management ---
init_state() {
    if [[ ! -f "$MEMORY_FILE" ]]; then
        cat > "$MEMORY_FILE" << 'INIT'
{
  "watchlist": [],
  "positions": [],
  "signals_history": [],
  "daily_pnl": [],
  "last_scan": null,
  "total_invested": 0,
  "total_pnl": 0
}
INIT
    fi
}

save_state() {
    local key="$1"
    local value="$2"
    python3 -c "
import json
with open('$MEMORY_FILE', 'r') as f:
    data = json.load(f)
data['$key'] = $value
with open('$MEMORY_FILE', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || warn "State save failed"
}

load_state() {
    local key="$1"
    python3 -c "
import json
with open('$MEMORY_FILE', 'r') as f:
    data = json.load(f)
print(json.dumps(data.get('$key', '')))
" 2>/dev/null
}

# =================================================================
# LOGIN — Polymarket Login pruefen
# =================================================================
cmd_login() {
    step "Pruefe Polymarket Login..."
    browser_open "$POLYMARKET" "$PROFILE"
    wait_seconds 4

    local snapshot
    snapshot=$(browser_snapshot "$PROFILE" 2>/dev/null || echo "")

    if echo "$snapshot" | grep -qi "portfolio\|positions\|balance\|deposit"; then
        log "✓ Polymarket: Eingeloggt"
        save_to_memory "polymarket_login" "active"
        notify_telegram "🟢 *Polymarket* Login aktiv" ""
    else
        warn "Polymarket: Nicht eingeloggt"
        echo ""
        echo "  Bitte manuell einloggen:"
        echo "  1. Gehe zu $POLYMARKET"
        echo "  2. Klicke 'Log In' → Wallet verbinden"
        echo "  3. Fuehre diesen Befehl erneut aus"
        echo ""
        browser_screenshot "polymarket-login" "$PROFILE"
    fi
}

# =================================================================
# TRENDING — Top Trending Markets
# =================================================================
cmd_trending() {
    step "Lade Trending Markets von Polymarket..."
    browser_open "$POLYMARKET" "$PROFILE"
    wait_seconds 4

    local snapshot
    snapshot=$(browser_snapshot "$PROFILE" 2>/dev/null || echo "")

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  📊 POLYMARKET — TRENDING MARKETS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Parse trending markets from snapshot
    echo "$snapshot" | python3 -c "
import sys
content = sys.stdin.read()
lines = content.split('\n')
market_count = 0
for line in lines:
    line = line.strip()
    if not line:
        continue
    # Look for market-like patterns (question marks, percentages)
    if '?' in line and len(line) > 20:
        market_count += 1
        if market_count <= 15:
            print(f'  {market_count}. {line[:120]}')
    elif '%' in line and any(c.isdigit() for c in line):
        if market_count > 0 and market_count <= 15:
            print(f'     → {line[:80]}')
if market_count == 0:
    print('  Keine Markets gefunden - bitte Login pruefen')
" 2>/dev/null || echo "  Snapshot-Parsing fehlgeschlagen"

    echo ""
    browser_screenshot "polymarket-trending" "$PROFILE"
    save_state "last_scan" "\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
}

# =================================================================
# SEARCH — Markets suchen
# =================================================================
cmd_search() {
    local query="${1:-}"
    if [[ -z "$query" ]]; then
        error "Bitte Suchbegriff angeben: ./polymarket.sh search <query>"
        exit 1
    fi

    step "Suche Markets: '$query'"
    browser_open "$POLYMARKET/search?query=$(echo "$query" | sed 's/ /+/g')" "$PROFILE"
    wait_seconds 4

    local snapshot
    snapshot=$(browser_snapshot "$PROFILE" 2>/dev/null || echo "")

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  🔍 SUCHE: $query"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    echo "$snapshot" | python3 -c "
import sys
content = sys.stdin.read()
lines = content.split('\n')
count = 0
for line in lines:
    line = line.strip()
    if '?' in line and len(line) > 15:
        count += 1
        if count <= 20:
            print(f'  {count}. {line[:120]}')
if count == 0:
    print('  Keine Ergebnisse gefunden')
" 2>/dev/null || echo "  Parsing fehlgeschlagen"
    echo ""
}

# =================================================================
# MARKET — Einzelnen Market analysieren
# =================================================================
cmd_market() {
    local url="${1:-}"
    if [[ -z "$url" ]]; then
        error "Bitte Market-URL angeben: ./polymarket.sh market <url>"
        exit 1
    fi

    step "Analysiere Market: $url"
    browser_open "$url" "$PROFILE"
    wait_seconds 4

    local snapshot
    snapshot=$(browser_snapshot "$PROFILE" 2>/dev/null || echo "")

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  📈 MARKET ANALYSE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    echo "$snapshot" | python3 -c "
import sys
content = sys.stdin.read()
lines = content.split('\n')
for line in lines:
    line = line.strip()
    if not line:
        continue
    # Title (usually first meaningful line)
    if '?' in line and len(line) > 20:
        print(f'\n  Frage: {line}')
    # Probabilities
    elif '%' in line:
        print(f'  Wahrscheinlichkeit: {line[:80]}')
    # Volume
    elif 'vol' in line.lower() or 'volume' in line.lower():
        print(f'  Volumen: {line[:80]}')
    # Liquidity
    elif 'liquid' in line.lower():
        print(f'  Liquiditaet: {line[:80]}')
    # End date
    elif 'end' in line.lower() or 'expir' in line.lower() or 'resolv' in line.lower():
        print(f'  Enddatum: {line[:80]}')
" 2>/dev/null || echo "  Analyse fehlgeschlagen"

    echo ""

    # AI Analysis via Ollama
    step "AI-Analyse laeuft..."
    local ai_input
    ai_input=$(echo "$snapshot" | head -100)

    local ai_response
    ai_response=$(curl -s "http://localhost:11434/api/generate" \
        -d "{
            \"model\": \"glm4:9b-chat\",
            \"prompt\": \"Analysiere diesen Polymarket prediction market. Gib eine kurze Einschaetzung (3-4 Saetze) ob YES oder NO wahrscheinlicher ist und warum. Daten: $ai_input\",
            \"stream\": false
        }" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('response','Analyse fehlgeschlagen'))" 2>/dev/null || echo "AI nicht verfuegbar")

    echo "  🤖 AI-Einschaetzung:"
    echo "$ai_response" | fold -s -w 70 | sed 's/^/     /'
    echo ""

    browser_screenshot "polymarket-market" "$PROFILE"
}

# =================================================================
# PORTFOLIO — Eigene Positionen
# =================================================================
cmd_portfolio() {
    step "Lade Portfolio..."
    browser_open "$POLYMARKET/portfolio" "$PROFILE"
    wait_seconds 4

    local snapshot
    snapshot=$(browser_snapshot "$PROFILE" 2>/dev/null || echo "")

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  💼 POLYMARKET PORTFOLIO"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    echo "$snapshot" | python3 -c "
import sys
content = sys.stdin.read()
lines = content.split('\n')
for line in lines:
    line = line.strip()
    if not line:
        continue
    if any(kw in line.lower() for kw in ['balance', 'position', 'profit', 'loss', 'pnl', 'invested', '\$']):
        print(f'  {line[:100]}')
" 2>/dev/null || echo "  Portfolio-Daten nicht verfuegbar"
    echo ""

    browser_screenshot "polymarket-portfolio" "$PROFILE"
    notify_telegram "📊 *Polymarket Portfolio* abgerufen" ""
}

# =================================================================
# SIGNALS — AI-basierte Trading Signals
# =================================================================
cmd_signals() {
    step "Generiere Polymarket Trading Signals..."

    # Scan multiple categories
    local categories=("politics" "crypto" "sports" "science" "economy")
    local all_data=""

    for cat in "${categories[@]}"; do
        browser_open "$POLYMARKET/browse?topic=$cat" "$PROFILE"
        wait_seconds 3
        local snap
        snap=$(browser_snapshot "$PROFILE" 2>/dev/null || echo "")
        all_data+="
=== $cat ===
$snap
"
    done

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  🎯 POLYMARKET TRADING SIGNALS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # AI Signal Generation
    local ai_prompt="Du bist ein Prediction Market Analyst. Analysiere diese Polymarket-Daten und finde die 5 besten Trading-Moeglichkeiten. Fuer jede Chance: Market-Name, aktuelle Quote, deine Einschaetzung (YES/NO), Konfidenz (1-10), Begruendung (1 Satz). Format: Nummerierte Liste. Daten: $(echo "$all_data" | head -200)"

    local signals
    signals=$(curl -s "http://localhost:11434/api/generate" \
        -d "{
            \"model\": \"glm4:9b-chat\",
            \"prompt\": \"$ai_prompt\",
            \"stream\": false
        }" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('response','Keine Signals'))" 2>/dev/null || echo "AI nicht verfuegbar")

    echo "$signals" | fold -s -w 70 | sed 's/^/  /'
    echo ""

    # Save signal history
    python3 -c "
import json
from datetime import datetime
with open('$MEMORY_FILE', 'r') as f:
    data = json.load(f)
history = data.get('signals_history', [])
history.append({
    'timestamp': datetime.utcnow().isoformat(),
    'signals': '''$(echo "$signals" | head -20)'''
})
# Keep last 30 entries
data['signals_history'] = history[-30:]
with open('$MEMORY_FILE', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true

    notify_telegram "🎯 *Polymarket Signals* generiert — $(date +%H:%M)" ""
}

# =================================================================
# NEWS — Relevante News fuer offene Markets
# =================================================================
cmd_news() {
    step "Scanne relevante News..."

    # Google News for prediction market topics
    browser_open "https://news.google.com/search?q=prediction+market+polymarket" "$PROFILE"
    wait_seconds 4

    local snapshot
    snapshot=$(browser_snapshot "$PROFILE" 2>/dev/null || echo "")

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  📰 NEWS — Prediction Markets"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    echo "$snapshot" | python3 -c "
import sys
content = sys.stdin.read()
lines = content.split('\n')
count = 0
for line in lines:
    line = line.strip()
    if len(line) > 30 and not line.startswith(('http', 'www', '<')):
        count += 1
        if count <= 15:
            print(f'  {count}. {line[:120]}')
if count == 0:
    print('  Keine News gefunden')
" 2>/dev/null || echo "  News-Parsing fehlgeschlagen"
    echo ""
}

# =================================================================
# ARBITRAGE — Arbitrage Chancen finden
# =================================================================
cmd_arbitrage() {
    step "Suche Arbitrage-Moeglichkeiten..."

    browser_open "$POLYMARKET" "$PROFILE"
    wait_seconds 4
    local snapshot
    snapshot=$(browser_snapshot "$PROFILE" 2>/dev/null || echo "")

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ⚡ ARBITRAGE SCANNER"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # AI Arbitrage analysis
    local ai_prompt="Du bist ein Arbitrage-Experte fuer Prediction Markets. Analysiere diese Polymarket-Daten und finde: 1) Markets wo YES+NO Preise nicht 100% ergeben (Overround/Underround), 2) Korrelierte Markets mit inkonsistenten Preisen, 3) Markets nahe Ablauf mit klarem Ergebnis aber noch nicht bei 95%+. Daten: $(echo "$snapshot" | head -200)"

    local analysis
    analysis=$(curl -s "http://localhost:11434/api/generate" \
        -d "{
            \"model\": \"glm4:9b-chat\",
            \"prompt\": \"$ai_prompt\",
            \"stream\": false
        }" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('response','Analyse fehlgeschlagen'))" 2>/dev/null || echo "AI nicht verfuegbar")

    echo "$analysis" | fold -s -w 70 | sed 's/^/  /'
    echo ""
}

# =================================================================
# WATCHLIST — Markets zur Beobachtung
# =================================================================
cmd_watchlist() {
    local action="${1:-show}"
    local url="${2:-}"

    init_state

    case "$action" in
        add)
            if [[ -z "$url" ]]; then
                error "URL fehlt: ./polymarket.sh watchlist add <url>"
                exit 1
            fi
            python3 -c "
import json
with open('$MEMORY_FILE', 'r') as f:
    data = json.load(f)
wl = data.get('watchlist', [])
if '$url' not in wl:
    wl.append('$url')
    data['watchlist'] = wl
    with open('$MEMORY_FILE', 'w') as f:
        json.dump(data, f, indent=2)
    print('  ✓ Zur Watchlist hinzugefuegt: $url')
else:
    print('  Bereits auf Watchlist')
" 2>/dev/null
            ;;
        remove)
            if [[ -z "$url" ]]; then
                error "URL fehlt: ./polymarket.sh watchlist remove <url>"
                exit 1
            fi
            python3 -c "
import json
with open('$MEMORY_FILE', 'r') as f:
    data = json.load(f)
wl = data.get('watchlist', [])
if '$url' in wl:
    wl.remove('$url')
    data['watchlist'] = wl
    with open('$MEMORY_FILE', 'w') as f:
        json.dump(data, f, indent=2)
    print('  ✓ Von Watchlist entfernt')
else:
    print('  Nicht auf Watchlist')
" 2>/dev/null
            ;;
        show|*)
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "  👁️ WATCHLIST"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            python3 -c "
import json
with open('$MEMORY_FILE', 'r') as f:
    data = json.load(f)
wl = data.get('watchlist', [])
if not wl:
    print('  Watchlist ist leer')
    print('  Hinzufuegen: ./polymarket.sh watchlist add <url>')
else:
    for i, url in enumerate(wl, 1):
        print(f'  {i}. {url}')
" 2>/dev/null || echo "  Watchlist nicht verfuegbar"
            echo ""
            ;;
    esac
}

# =================================================================
# REPORT — Taeglicher Report
# =================================================================
cmd_report() {
    step "Erstelle taeglichen Polymarket Report..."

    # Gather all data
    local trending_snap=""
    browser_open "$POLYMARKET" "$PROFILE"
    wait_seconds 4
    trending_snap=$(browser_snapshot "$PROFILE" 2>/dev/null || echo "")

    local portfolio_snap=""
    browser_open "$POLYMARKET/portfolio" "$PROFILE"
    wait_seconds 3
    portfolio_snap=$(browser_snapshot "$PROFILE" 2>/dev/null || echo "")

    # Load state
    local state_data
    state_data=$(cat "$MEMORY_FILE" 2>/dev/null || echo "{}")

    # AI Report
    local ai_prompt="Erstelle einen kurzen taeglichen Polymarket Report (auf Deutsch). Enthalte: 1) Top 3 Trending Markets, 2) Portfolio-Status, 3) Beste Chancen heute, 4) Risiko-Warnung falls noetig. Halte es unter 200 Woertern. Daten Trending: $(echo "$trending_snap" | head -100). Portfolio: $(echo "$portfolio_snap" | head -50). State: $(echo "$state_data" | head -30)"

    local report
    report=$(curl -s "http://localhost:11434/api/generate" \
        -d "{
            \"model\": \"glm4:9b-chat\",
            \"prompt\": \"$ai_prompt\",
            \"stream\": false
        }" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('response','Report fehlgeschlagen'))" 2>/dev/null || echo "AI nicht verfuegbar")

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  📋 TAEGLICHER POLYMARKET REPORT"
    echo "  $(date '+%d.%m.%Y %H:%M')"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "$report" | fold -s -w 70 | sed 's/^/  /'
    echo ""

    notify_telegram "📋 *Polymarket Daily Report*
$(echo "$report" | head -20)" ""
}

# =================================================================
# MAIN
# =================================================================
init_state

case "${1:-help}" in
    login)      cmd_login ;;
    trending)   cmd_trending ;;
    search)     cmd_search "${2:-}" ;;
    market)     cmd_market "${2:-}" ;;
    portfolio)  cmd_portfolio ;;
    signals)    cmd_signals ;;
    news)       cmd_news ;;
    arbitrage)  cmd_arbitrage ;;
    watchlist)  cmd_watchlist "${2:-show}" "${3:-}" ;;
    report)     cmd_report ;;
    help|*)
        echo ""
        echo "  🎯 Polymarket Prediction Bot — Chandler"
        echo ""
        echo "  Befehle:"
        echo "    login              Polymarket Login pruefen"
        echo "    trending           Trending Markets"
        echo "    search <query>     Markets suchen"
        echo "    market <url>       Market analysieren"
        echo "    portfolio          Eigene Positionen"
        echo "    signals            AI Trading Signals"
        echo "    news               Relevante News"
        echo "    arbitrage          Arbitrage Chancen"
        echo "    watchlist [add|remove|show] [url]"
        echo "    report             Taeglicher Report"
        echo ""
        ;;
esac
