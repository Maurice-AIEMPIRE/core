#!/usr/bin/env bash
# ================================================================
# CHANDLER — XRP Trading Bot via Browser
# ================================================================
# Browser-basierter XRP Trading Monitor + Signal Generator
# Nutzt CoinGecko, TradingView und DEX-Daten
#
# Befehle:
#   ./trading-xrp.sh price            — Aktueller XRP Preis
#   ./trading-xrp.sh monitor          — Live Price Monitor (Loop)
#   ./trading-xrp.sh signals          — Trading Signals generieren
#   ./trading-xrp.sh fear-greed       — Crypto Fear & Greed Index
#   ./trading-xrp.sh whale-alert      — Whale Bewegungen pruefen
#   ./trading-xrp.sh portfolio <amount> — Portfolio Tracker
#   ./trading-xrp.sh news             — Aktuelle XRP News
#   ./trading-xrp.sh analysis         — AI-basierte Analyse via Ollama
#   ./trading-xrp.sh dca-plan <budget> — DCA Strategie berechnen
#   ./trading-xrp.sh alerts           — Preis-Alerts konfigurieren
# ================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/browser-helper.sh"

PROFILE="openclaw"
COINGECKO="https://www.coingecko.com/en/coins/xrp"
TRADINGVIEW="https://www.tradingview.com/chart/?symbol=BINANCE:XRPUSDT"
FEAR_GREED="https://alternative.me/crypto/fear-and-greed-index"

TRADING_MEMORY="$MEMORY_DIR/trading-xrp.json"
SIGNALS_LOG="$MEMORY_DIR/trading-signals.json"

# Initialize trading memory
init_trading_memory() {
    if [[ ! -f "$TRADING_MEMORY" ]]; then
        cat > "$TRADING_MEMORY" << 'ENDJSON'
{
  "price_history": [],
  "signals": [],
  "alerts": {"upper": 3.00, "lower": 1.50},
  "portfolio": {"xrp_amount": 0, "avg_buy_price": 0},
  "last_analysis": "",
  "dca_plan": {"budget": 0, "frequency": "weekly", "next_buy": ""}
}
ENDJSON
    fi
}

# ================================================================
# XRP PREIS ABRUFEN
# ================================================================
cmd_price() {
    step "XRP Preis abrufen..."

    # Methode 1: CoinGecko API (kein Browser noetig)
    local price_data
    price_data=$(curl -s "https://api.coingecko.com/api/v3/simple/price?ids=ripple&vs_currencies=usd,eur&include_24hr_change=true&include_24hr_vol=true&include_market_cap=true" 2>/dev/null || echo "{}")

    if echo "$price_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['ripple']['usd'])" 2>/dev/null; then
        local usd eur change vol mcap
        usd=$(echo "$price_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f\"{d['ripple']['usd']:.4f}\")")
        eur=$(echo "$price_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f\"{d['ripple']['eur']:.4f}\")")
        change=$(echo "$price_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f\"{d['ripple']['usd_24h_change']:.2f}\")")
        vol=$(echo "$price_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f\"{d['ripple']['usd_24h_vol']/1e6:.1f}M\")")
        mcap=$(echo "$price_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f\"{d['ripple']['usd_market_cap']/1e9:.2f}B\")")

        local trend_icon="📊"
        if python3 -c "exit(0 if float('$change') > 0 else 1)" 2>/dev/null; then
            trend_icon="📈"
        else
            trend_icon="📉"
        fi

        echo ""
        echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║         XRP LIVE PRICE               ║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC} $trend_icon USD:    \$$usd"
        echo -e "${CYAN}║${NC} $trend_icon EUR:    ${eur}EUR"
        echo -e "${CYAN}║${NC} 24h:     ${change}%"
        echo -e "${CYAN}║${NC} Volume:  \$$vol"
        echo -e "${CYAN}║${NC} MCap:    \$$mcap"
        echo -e "${CYAN}║${NC} Zeit:    $(date '+%H:%M:%S %d.%m.%Y')"
        echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"

        # Preis in History speichern
        python3 -c "
import json
from datetime import datetime
try:
    with open('$TRADING_MEMORY', 'r') as f:
        data = json.load(f)
except:
    data = {'price_history': [], 'signals': [], 'alerts': {'upper': 3.0, 'lower': 1.5}}

data['price_history'].append({
    'timestamp': datetime.utcnow().isoformat(),
    'usd': float('$usd'),
    'eur': float('$eur'),
    'change_24h': float('$change')
})
# Nur letzte 1000 Eintraege behalten
data['price_history'] = data['price_history'][-1000:]

with open('$TRADING_MEMORY', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true

        # Alert Check
        check_price_alerts "$usd" "$change"

    else
        # Fallback: Browser
        warn "API nicht erreichbar — Browser Fallback"
        browser_open "$COINGECKO" "$PROFILE"
        wait_seconds 4
        browser_screenshot "xrp-price" "$PROFILE"

        local browser_price
        browser_price=$(browser_eval "
            const price = document.querySelector('[data-converter-target=\"price\"], .no-wrap');
            price ? price.textContent.trim() : 'N/A';
        " "$PROFILE" 2>/dev/null || echo "Preis nicht extrahierbar")
        log "XRP Preis (Browser): $browser_price"
    fi
}

# ================================================================
# PREIS ALERTS PRUEFEN
# ================================================================
check_price_alerts() {
    local current_price="$1"
    local change="$2"

    local upper lower
    upper=$(python3 -c "
import json
with open('$TRADING_MEMORY', 'r') as f:
    d = json.load(f)
print(d.get('alerts', {}).get('upper', 3.0))
" 2>/dev/null || echo "3.0")

    lower=$(python3 -c "
import json
with open('$TRADING_MEMORY', 'r') as f:
    d = json.load(f)
print(d.get('alerts', {}).get('lower', 1.5))
" 2>/dev/null || echo "1.5")

    if python3 -c "exit(0 if float('$current_price') >= float('$upper') else 1)" 2>/dev/null; then
        notify_telegram "🚨 *XRP ALERT: UPPER TARGET*
💰 Preis: \$$current_price
🎯 Target: \$$upper
📈 24h: ${change}%
⚡ Aktion: TAKE PROFIT erwägen"
        log "ALERT: XRP hat Upper Target erreicht!"
    fi

    if python3 -c "exit(0 if float('$current_price') <= float('$lower') else 1)" 2>/dev/null; then
        notify_telegram "🚨 *XRP ALERT: LOWER TARGET*
💰 Preis: \$$current_price
🎯 Target: \$$lower
📉 24h: ${change}%
⚡ Aktion: BUY ZONE — DCA Einstieg erwägen"
        log "ALERT: XRP hat Lower Target erreicht!"
    fi

    # Starke Bewegung (>5%)
    if python3 -c "exit(0 if abs(float('$change')) > 5 else 1)" 2>/dev/null; then
        notify_telegram "⚡ *XRP STARKE BEWEGUNG*
💰 Preis: \$$current_price
📊 24h: ${change}%
🔍 Markt analysieren!"
    fi
}

# ================================================================
# LIVE MONITOR (Loop)
# ================================================================
cmd_monitor() {
    local interval="${1:-60}"
    log "XRP Live Monitor gestartet (Interval: ${interval}s)"
    log "Strg+C zum Beenden"

    while true; do
        cmd_price
        sleep "$interval"
    done
}

# ================================================================
# TRADING SIGNALS GENERIEREN
# ================================================================
cmd_signals() {
    step "XRP Trading Signals generieren..."

    # Preis-Daten holen
    local price_data
    price_data=$(curl -s "https://api.coingecko.com/api/v3/coins/ripple?localization=false&tickers=false&community_data=false&developer_data=false" 2>/dev/null || echo "{}")

    local current_price change_24h change_7d change_14d change_30d ath ath_change
    current_price=$(echo "$price_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['market_data']['current_price']['usd'])" 2>/dev/null || echo "0")
    change_24h=$(echo "$price_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['market_data']['price_change_percentage_24h'])" 2>/dev/null || echo "0")
    change_7d=$(echo "$price_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['market_data']['price_change_percentage_7d'])" 2>/dev/null || echo "0")
    change_14d=$(echo "$price_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['market_data']['price_change_percentage_14d'])" 2>/dev/null || echo "0")
    change_30d=$(echo "$price_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['market_data']['price_change_percentage_30d'])" 2>/dev/null || echo "0")
    ath=$(echo "$price_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['market_data']['ath']['usd'])" 2>/dev/null || echo "0")
    ath_change=$(echo "$price_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['market_data']['ath_change_percentage']['usd'])" 2>/dev/null || echo "0")

    # Signal-Logik
    local signal signal_reason strength
    signal=$(python3 << PYEOF
import json

price = float("$current_price")
d24 = float("$change_24h")
d7 = float("$change_7d")
d14 = float("$change_14d")
d30 = float("$change_30d")

score = 0
reasons = []

# Momentum Signals
if d24 > 3:
    score += 2; reasons.append("Strong 24h pump (+{:.1f}%)".format(d24))
elif d24 > 0:
    score += 1; reasons.append("Positive 24h ({:.1f}%)".format(d24))
elif d24 < -5:
    score -= 2; reasons.append("Heavy 24h dump ({:.1f}%)".format(d24))
elif d24 < 0:
    score -= 1; reasons.append("Negative 24h ({:.1f}%)".format(d24))

# Trend Signals
if d7 > 5 and d30 > 10:
    score += 2; reasons.append("Strong uptrend (7d: {:.1f}%, 30d: {:.1f}%)".format(d7, d30))
elif d7 < -5 and d30 < -10:
    score -= 2; reasons.append("Strong downtrend (7d: {:.1f}%, 30d: {:.1f}%)".format(d7, d30))

# Mean Reversion
if d7 < -10 and d24 > 0:
    score += 1; reasons.append("Bounce after dip — potential reversal")
if d7 > 15:
    score -= 1; reasons.append("Overextended — pullback likely")

# Consolidation
if abs(d7) < 2 and abs(d14) < 3:
    reasons.append("Consolidation phase — breakout pending")

if score >= 3:
    signal = "STRONG BUY"
elif score >= 1:
    signal = "BUY"
elif score <= -3:
    signal = "STRONG SELL"
elif score <= -1:
    signal = "SELL"
else:
    signal = "HOLD"

print(f"{signal}|{score}|{'; '.join(reasons)}")
PYEOF
)

    local signal_type signal_score signal_reasons
    signal_type=$(echo "$signal" | cut -d'|' -f1)
    signal_score=$(echo "$signal" | cut -d'|' -f2)
    signal_reasons=$(echo "$signal" | cut -d'|' -f3)

    local signal_icon="⚪"
    case "$signal_type" in
        "STRONG BUY")  signal_icon="🟢🟢" ;;
        "BUY")         signal_icon="🟢" ;;
        "HOLD")        signal_icon="🟡" ;;
        "SELL")        signal_icon="🔴" ;;
        "STRONG SELL") signal_icon="🔴🔴" ;;
    esac

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║       XRP TRADING SIGNAL             ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} $signal_icon Signal:  $signal_type"
    echo -e "${CYAN}║${NC} Score:    $signal_score"
    echo -e "${CYAN}║${NC} Preis:    \$$current_price"
    echo -e "${CYAN}║${NC} ATH:      \$$ath ($ath_change%)"
    echo -e "${CYAN}╠══════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} 24h: ${change_24h}%"
    echo -e "${CYAN}║${NC}  7d: ${change_7d}%"
    echo -e "${CYAN}║${NC} 14d: ${change_14d}%"
    echo -e "${CYAN}║${NC} 30d: ${change_30d}%"
    echo -e "${CYAN}╠══════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} Reasons:"
    echo "$signal_reasons" | tr ';' '\n' | while read -r reason; do
        echo -e "${CYAN}║${NC}   - $reason"
    done
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"

    # Signal speichern
    python3 -c "
import json
from datetime import datetime
try:
    with open('$TRADING_MEMORY', 'r') as f:
        data = json.load(f)
except:
    data = {'signals': []}

if 'signals' not in data:
    data['signals'] = []

data['signals'].append({
    'timestamp': datetime.utcnow().isoformat(),
    'signal': '$signal_type',
    'score': int('$signal_score'),
    'price': float('$current_price'),
    'reasons': '$signal_reasons'
})
data['signals'] = data['signals'][-200:]

with open('$TRADING_MEMORY', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true

    notify_telegram "$signal_icon *XRP Signal: $signal_type*
💰 \$$current_price
📊 Score: $signal_score
📈 24h: ${change_24h}% | 7d: ${change_7d}%
🔍 $signal_reasons"
}

# ================================================================
# FEAR & GREED INDEX
# ================================================================
cmd_fear_greed() {
    step "Crypto Fear & Greed Index..."

    local fg_data
    fg_data=$(curl -s "https://api.alternative.me/fng/?limit=1" 2>/dev/null || echo "{}")

    local value classification
    value=$(echo "$fg_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['data'][0]['value'])" 2>/dev/null || echo "?")
    classification=$(echo "$fg_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['data'][0]['value_classification'])" 2>/dev/null || echo "?")

    local fg_icon="⚪"
    if [[ "$value" != "?" ]]; then
        if (( value <= 25 )); then fg_icon="😱 Extreme Fear"
        elif (( value <= 45 )); then fg_icon="😨 Fear"
        elif (( value <= 55 )); then fg_icon="😐 Neutral"
        elif (( value <= 75 )); then fg_icon="😏 Greed"
        else fg_icon="🤑 Extreme Greed"
        fi
    fi

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║    CRYPTO FEAR & GREED INDEX         ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} Index:    $value / 100"
    echo -e "${CYAN}║${NC} Status:   $fg_icon"
    echo -e "${CYAN}║${NC} Class:    $classification"
    echo -e "${CYAN}╠══════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} Strategie:"
    if [[ "$value" != "?" ]] && (( value <= 25 )); then
        echo -e "${CYAN}║${NC}   BUY ZONE — Angst = Gelegenheit"
    elif [[ "$value" != "?" ]] && (( value >= 75 )); then
        echo -e "${CYAN}║${NC}   VORSICHT — Gier = Risiko, Profits sichern"
    else
        echo -e "${CYAN}║${NC}   NEUTRAL — Plan folgen, DCA weitermachen"
    fi
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"

    notify_telegram "📊 *Fear & Greed: $value/100*
$fg_icon
$classification"
}

# ================================================================
# WHALE ALERT (Browser-basiert)
# ================================================================
cmd_whale_alert() {
    step "XRP Whale Bewegungen pruefen..."
    browser_open "https://whale-alert.io/transactions/xrp" "$PROFILE"
    wait_seconds 5

    browser_screenshot "whale-alert-xrp" "$PROFILE"

    local whales
    whales=$(browser_eval "
        const rows = document.querySelectorAll('tr, .transaction, [class*=\"transaction\"]');
        let result = [];
        rows.forEach((r, i) => {
            if (i < 10 && i > 0) {
                result.push(r.textContent.trim().replace(/\\s+/g, ' ').substring(0, 150));
            }
        });
        result.join('\\n');
    " "$PROFILE" 2>/dev/null || echo "Whale Daten nicht extrahierbar — siehe Screenshot")

    log "=== XRP WHALE ALERT ==="
    echo "$whales"

    notify_telegram "🐋 *XRP Whale Alert*
$whales"
}

# ================================================================
# PORTFOLIO TRACKER
# ================================================================
cmd_portfolio() {
    local xrp_amount="${1:-}"

    if [[ -n "$xrp_amount" ]]; then
        # Portfolio Amount speichern
        python3 -c "
import json
with open('$TRADING_MEMORY', 'r') as f:
    data = json.load(f)
data['portfolio'] = data.get('portfolio', {})
data['portfolio']['xrp_amount'] = float('$xrp_amount')
with open('$TRADING_MEMORY', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true
    fi

    local amount
    amount=$(python3 -c "
import json
with open('$TRADING_MEMORY', 'r') as f:
    d = json.load(f)
print(d.get('portfolio', {}).get('xrp_amount', 0))
" 2>/dev/null || echo "0")

    # Aktuellen Preis holen
    local price_data
    price_data=$(curl -s "https://api.coingecko.com/api/v3/simple/price?ids=ripple&vs_currencies=usd,eur" 2>/dev/null || echo "{}")
    local usd eur
    usd=$(echo "$price_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['ripple']['usd'])" 2>/dev/null || echo "0")
    eur=$(echo "$price_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['ripple']['eur'])" 2>/dev/null || echo "0")

    local value_usd value_eur
    value_usd=$(python3 -c "print(f'{float(\"$amount\") * float(\"$usd\"):.2f}')" 2>/dev/null || echo "0")
    value_eur=$(python3 -c "print(f'{float(\"$amount\") * float(\"$eur\"):.2f}')" 2>/dev/null || echo "0")

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║       XRP PORTFOLIO                  ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC} XRP:     $amount XRP"
    echo -e "${GREEN}║${NC} Preis:   \$$usd / ${eur}EUR"
    echo -e "${GREEN}║${NC} Wert:    \$$value_usd"
    echo -e "${GREEN}║${NC} Wert:    ${value_eur}EUR"
    echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"

    notify_telegram "💼 *XRP Portfolio*
$amount XRP
💰 \$$value_usd / ${value_eur}EUR"
}

# ================================================================
# XRP NEWS (Browser)
# ================================================================
cmd_news() {
    step "XRP News laden..."
    browser_open "https://www.coingecko.com/en/coins/xrp/news" "$PROFILE"
    wait_seconds 4

    browser_screenshot "xrp-news" "$PROFILE"

    local news
    news=$(browser_eval "
        const articles = document.querySelectorAll('article, [class*=\"news\"], .post-title, h3 a');
        let result = [];
        articles.forEach((a, i) => {
            if (i < 10) result.push((i+1) + '. ' + a.textContent.trim().substring(0, 120));
        });
        result.join('\\n');
    " "$PROFILE" 2>/dev/null || echo "News nicht extrahierbar — siehe Screenshot")

    log "=== XRP NEWS ==="
    echo "$news"

    notify_telegram "📰 *XRP News*
$news"
}

# ================================================================
# AI ANALYSE via Ollama
# ================================================================
cmd_analysis() {
    step "XRP AI-Analyse starten..."

    # Alle Daten sammeln
    local price_data
    price_data=$(curl -s "https://api.coingecko.com/api/v3/coins/ripple?localization=false&tickers=false&community_data=false&developer_data=false" 2>/dev/null || echo "{}")

    local fg_data
    fg_data=$(curl -s "https://api.alternative.me/fng/?limit=1" 2>/dev/null || echo "{}")

    local market_context
    market_context=$(python3 << 'PYEOF'
import json, sys

try:
    with open(sys.argv[1] if len(sys.argv) > 1 else '/dev/null') as f:
        price = json.load(f) if f.name != '/dev/null' else {}
except:
    price = {}

md = price.get('market_data', {})
result = {
    'price_usd': md.get('current_price', {}).get('usd', 'N/A'),
    'change_24h': md.get('price_change_percentage_24h', 'N/A'),
    'change_7d': md.get('price_change_percentage_7d', 'N/A'),
    'change_30d': md.get('price_change_percentage_30d', 'N/A'),
    'ath': md.get('ath', {}).get('usd', 'N/A'),
    'ath_change': md.get('ath_change_percentage', {}).get('usd', 'N/A'),
    'volume_24h': md.get('total_volume', {}).get('usd', 'N/A'),
    'market_cap': md.get('market_cap', {}).get('usd', 'N/A'),
}
print(json.dumps(result))
PYEOF
)

    local analysis_prompt="Du bist ein erfahrener Crypto-Analyst. Analysiere XRP basierend auf diesen Daten:

$market_context

Gib eine klare, actionable Analyse:
1. Aktuelle Marktlage (bullish/bearish/neutral)
2. Key Support/Resistance Levels
3. Kurzfrist-Empfehlung (24h-7d)
4. Mittelfrist-Empfehlung (1-3 Monate)
5. Risiko-Level (1-10)
6. Konkrete Aktion: KAUFEN / HALTEN / VERKAUFEN + Begruendung

Antworte auf Deutsch, kurz und praezise. Max 200 Woerter."

    local analysis
    analysis=$(curl -s "http://localhost:11434/api/generate" \
        -d "{\"model\": \"qwen3:8b\", \"prompt\": \"$analysis_prompt\", \"stream\": false}" 2>/dev/null | \
        python3 -c "import json,sys; print(json.load(sys.stdin).get('response','Analyse fehlgeschlagen'))" 2>/dev/null || \
        echo "Ollama nicht erreichbar — Analyse nicht moeglich")

    log "=== XRP AI ANALYSE ==="
    echo "$analysis"

    save_to_memory "xrp_last_analysis" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    notify_telegram "🤖 *XRP AI Analyse*
$analysis"
}

# ================================================================
# DCA PLAN
# ================================================================
cmd_dca_plan() {
    local monthly_budget="${1:-100}"

    local price
    price=$(curl -s "https://api.coingecko.com/api/v3/simple/price?ids=ripple&vs_currencies=usd" 2>/dev/null | \
        python3 -c "import json,sys; print(json.load(sys.stdin)['ripple']['usd'])" 2>/dev/null || echo "2.0")

    local weekly=$((monthly_budget / 4))
    local daily=$((monthly_budget / 30))
    local xrp_weekly xrp_monthly
    xrp_weekly=$(python3 -c "print(f'{$weekly / float(\"$price\"):.1f}')")
    xrp_monthly=$(python3 -c "print(f'{$monthly_budget / float(\"$price\"):.1f}')")

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║       XRP DCA STRATEGIE              ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC} Budget:     \$$monthly_budget/Monat"
    echo -e "${GREEN}║${NC} XRP Preis:  \$$price"
    echo -e "${GREEN}╠══════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC} Taeglich:   \$$daily → ~$(python3 -c "print(f'{$daily/float(\"$price\"):.1f}')") XRP"
    echo -e "${GREEN}║${NC} Woechentl.: \$$weekly → ~$xrp_weekly XRP"
    echo -e "${GREEN}║${NC} Monatlich:  \$$monthly_budget → ~$xrp_monthly XRP"
    echo -e "${GREEN}╠══════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC} 6 Monate:   ~$(python3 -c "print(f'{6*$monthly_budget/float(\"$price\"):.0f}')") XRP"
    echo -e "${GREEN}║${NC} 12 Monate:  ~$(python3 -c "print(f'{12*$monthly_budget/float(\"$price\"):.0f}')") XRP"
    echo -e "${GREEN}╠══════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC} Empfehlung: Woechentlich kaufen"
    echo -e "${GREEN}║${NC}             Montag morgens (niedrigste Vola)"
    echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"

    # Plan speichern
    python3 -c "
import json
with open('$TRADING_MEMORY', 'r') as f:
    data = json.load(f)
data['dca_plan'] = {
    'budget': $monthly_budget,
    'frequency': 'weekly',
    'xrp_per_week': float('$xrp_weekly'),
    'current_price': float('$price')
}
with open('$TRADING_MEMORY', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true
}

# ================================================================
# PREIS ALERTS SETZEN
# ================================================================
cmd_alerts() {
    local upper="${1:-}"
    local lower="${2:-}"

    if [[ -n "$upper" ]] && [[ -n "$lower" ]]; then
        python3 -c "
import json
with open('$TRADING_MEMORY', 'r') as f:
    data = json.load(f)
data['alerts'] = {'upper': float('$upper'), 'lower': float('$lower')}
with open('$TRADING_MEMORY', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null
        log "Alerts gesetzt: Upper \$$upper / Lower \$$lower"
    else
        local current_upper current_lower
        current_upper=$(python3 -c "
import json
with open('$TRADING_MEMORY', 'r') as f:
    d = json.load(f)
print(d.get('alerts', {}).get('upper', 3.0))
" 2>/dev/null || echo "3.0")
        current_lower=$(python3 -c "
import json
with open('$TRADING_MEMORY', 'r') as f:
    d = json.load(f)
print(d.get('alerts', {}).get('lower', 1.5))
" 2>/dev/null || echo "1.5")

        echo "Aktuelle Alerts:"
        echo "  Upper (Take Profit): \$$current_upper"
        echo "  Lower (Buy Zone):    \$$current_lower"
        echo ""
        echo "Setzen: ./trading-xrp.sh alerts <upper> <lower>"
    fi
}

# ================================================================
# MAIN ROUTER
# ================================================================
init_trading_memory

case "${1:-help}" in
    price)       cmd_price ;;
    monitor)     cmd_monitor "${2:-60}" ;;
    signals)     cmd_signals ;;
    fear-greed)  cmd_fear_greed ;;
    whale-alert) cmd_whale_alert ;;
    portfolio)   cmd_portfolio "${2:-}" ;;
    news)        cmd_news ;;
    analysis)    cmd_analysis ;;
    dca-plan)    cmd_dca_plan "${2:-100}" ;;
    alerts)      cmd_alerts "${2:-}" "${3:-}" ;;
    help|*)
        echo ""
        echo "  CHANDLER — XRP Trading Bot"
        echo ""
        echo "  Usage: ./trading-xrp.sh <command> [args]"
        echo ""
        echo "  Commands:"
        echo "    price                    — Aktueller XRP Preis"
        echo "    monitor [interval]       — Live Monitor (default: 60s)"
        echo "    signals                  — Trading Signals generieren"
        echo "    fear-greed               — Crypto Fear & Greed Index"
        echo "    whale-alert              — Whale Bewegungen"
        echo "    portfolio [amount]       — Portfolio Tracker"
        echo "    news                     — Aktuelle XRP News"
        echo "    analysis                 — AI-basierte Analyse (Ollama)"
        echo "    dca-plan [budget]        — DCA Strategie (default: 100\$/Mo)"
        echo "    alerts [upper] [lower]   — Preis-Alerts setzen"
        echo ""
        ;;
esac
