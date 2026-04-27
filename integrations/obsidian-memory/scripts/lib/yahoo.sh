#!/usr/bin/env bash
# Yahoo Finance scrapers. Source me.
#
# Uses Yahoo's public quote endpoint for price + change, and the news RSS
# feed for headlines. No auth required.

# Echo: "TICKER price change_pct" for each ticker.
yahoo_quote() {
    local symbols="$1"  # comma separated
    curl -fsS \
        -H 'User-Agent: Mozilla/5.0 (obsidian-memory)' \
        "https://query1.finance.yahoo.com/v7/finance/quote?symbols=${symbols}" |
    python3 -c '
import json, sys
for q in json.load(sys.stdin).get("quoteResponse", {}).get("result", []):
    sym  = q.get("symbol", "?")
    px   = q.get("regularMarketPrice")
    chg  = q.get("regularMarketChangePercent")
    if px is None or chg is None:
        print(f"{sym} ? ?")
    else:
        print(f"{sym} {px:.2f} {chg:+.2f}%")
'
}

# Echo up to 3 recent headlines for one ticker, classified as bullish /
# neutral / bearish via a small keyword heuristic.
yahoo_headlines() {
    local sym="$1"
    curl -fsS \
        -H 'User-Agent: Mozilla/5.0 (obsidian-memory)' \
        "https://feeds.finance.yahoo.com/rss/2.0/headline?s=${sym}&region=US&lang=en-US" |
    python3 -c '
import sys, re, html
raw = sys.stdin.read()
items = re.findall(r"<item>(.*?)</item>", raw, flags=re.S)[:3]
BULL = {"surge","jump","beat","beats","rally","upgrade","upgraded","record","soar","gain","gains","rise","rises"}
BEAR = {"drop","drops","plunge","miss","misses","downgrade","downgraded","cut","cuts","fall","falls","slump","loss","losses","sink"}
def classify(t):
    w = set(re.findall(r"[A-Za-z]+", t.lower()))
    if w & BULL and not w & BEAR: return "bullish"
    if w & BEAR and not w & BULL: return "bearish"
    return "neutral"
for it in items:
    m = re.search(r"<title>(.*?)</title>", it, flags=re.S)
    if not m: continue
    title = html.unescape(m.group(1)).strip()
    title = re.sub(r"^<!\[CDATA\[|\]\]>$", "", title)
    print(f"  [{classify(title)}] {title}")
'
}
