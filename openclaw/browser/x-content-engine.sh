#!/usr/bin/env bash
# ================================================================
# KELLY — X/Twitter Content Engine
# ================================================================
# Automatische Content-Generierung + Posting fuer X/Twitter
# AI-generierte Tweets, Threads, Engagement, Growth Hacking
#
# Befehle:
#   ./x-content-engine.sh generate <niche>       — Tweet generieren
#   ./x-content-engine.sh thread <topic>         — Thread generieren
#   ./x-content-engine.sh viral-hooks            — Virale Hook-Ideen
#   ./x-content-engine.sh schedule <niche> <n>   — n Tweets vorplanen
#   ./x-content-engine.sh auto-engage            — Auto-Engagement (Like/Reply)
#   ./x-content-engine.sh growth-scan            — Growth Opportunities
#   ./x-content-engine.sh hashtags <topic>       — Trending Hashtags
#   ./x-content-engine.sh analytics              — Content Analytics
#   ./x-content-engine.sh repurpose <url>        — Content Repurposing
#   ./x-content-engine.sh daily                  — Taegliche Content-Routine
# ================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/browser-helper.sh"

PROFILE="openclaw"
MEMORY_FILE="$MEMORY_DIR/x-content-engine.json"
CONTENT_DIR="/tmp/openclaw/x-content"
mkdir -p "$CONTENT_DIR"

# --- State ---
init_state() {
    if [[ ! -f "$MEMORY_FILE" ]]; then
        cat > "$MEMORY_FILE" << 'INIT'
{
  "tweets_generated": 0,
  "tweets_posted": 0,
  "threads_created": 0,
  "engagement_actions": 0,
  "scheduled_queue": [],
  "posted_history": [],
  "best_performing": [],
  "niches": ["crypto", "ai", "tech", "money", "motivation"]
}
INIT
    fi
}

# Content Templates
HOOK_TEMPLATES=(
    "Most people don't know this about {topic}:"
    "I spent 100 hours studying {topic}. Here's what I learned:"
    "{topic} is about to change everything. Here's why:"
    "Stop scrolling. This {topic} insight will save you thousands:"
    "The truth about {topic} that nobody talks about:"
    "I made \$10K from {topic} in 30 days. Here's my exact strategy:"
    "99% of people get {topic} wrong. Here's the 1% secret:"
    "Hot take: {topic} is overrated. Here's what actually works:"
    "The {topic} cheat code that changed my life:"
    "Unpopular opinion about {topic}:"
)

# =================================================================
# GENERATE — AI Tweet generieren
# =================================================================
cmd_generate() {
    local niche="${1:-crypto}"

    step "Generiere Tweet fuer Nische: $niche"

    # Pick random hook template
    local hook_idx=$(( RANDOM % ${#HOOK_TEMPLATES[@]} ))
    local hook="${HOOK_TEMPLATES[$hook_idx]}"
    hook="${hook//\{topic\}/$niche}"

    local ai_prompt="Du bist ein viraler X/Twitter Content Creator. Erstelle einen Tweet (max 280 Zeichen) in der Nische '$niche'. Nutze diesen Hook als Inspiration: '$hook'. Regeln: 1) Emotionaler Hook, 2) Wertvoller Inhalt, 3) Call-to-Action (Like/RT/Follow), 4) Max 2 Hashtags. Gib NUR den Tweet-Text aus, nichts anderes."

    local tweet
    tweet=$(curl -s "http://localhost:11434/api/generate" \
        -d "{
            \"model\": \"qwen3:14b\",
            \"prompt\": \"$ai_prompt\",
            \"stream\": false
        }" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('response','').strip())" 2>/dev/null || echo "")

    if [[ -z "$tweet" ]]; then
        error "Tweet-Generierung fehlgeschlagen"
        return 1
    fi

    # Truncate to 280 chars
    tweet="${tweet:0:280}"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  🐦 GENERIERTER TWEET"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  $tweet"
    echo ""
    echo "  Zeichen: ${#tweet}/280"
    echo ""

    # Ask to post
    read -rp "  Jetzt posten? (j/n/e=edit): " action
    case "$action" in
        j|J|y|Y)
            step "Poste Tweet..."
            bash "$SCRIPT_DIR/x-twitter.sh" tweet "$tweet"
            update_stats "tweet_posted"
            notify_telegram "🐦 *Tweet gepostet*: $(echo "$tweet" | head -c 100)..." ""
            ;;
        e|E)
            echo "  Bearbeite den Tweet und poste manuell mit:"
            echo "  ./x-twitter.sh tweet \"<dein text>\""
            ;;
        *)
            # Save to queue
            save_to_queue "$tweet" "$niche"
            echo "  Tweet zur Queue hinzugefuegt."
            ;;
    esac
}

# =================================================================
# THREAD — AI Thread generieren
# =================================================================
cmd_thread() {
    local topic="${1:-}"
    if [[ -z "$topic" ]]; then
        error "Topic fehlt: ./x-content-engine.sh thread <topic>"
        exit 1
    fi

    step "Generiere Thread: '$topic'"

    local ai_prompt="Erstelle einen viralen X/Twitter Thread (8-12 Tweets) zum Thema: '$topic'. Format: Jeder Tweet auf einer eigenen Zeile, nummeriert (1/, 2/, etc). Regeln: 1) Tweet 1 = starker Hook mit Versprechen, 2) Tweets 2-10 = wertvoller Content mit konkreten Tipps, 3) Letzter Tweet = CTA (Follow + RT). Jeder Tweet max 270 Zeichen. Nur die Tweets ausgeben, kein anderer Text."

    local thread
    thread=$(curl -s "http://localhost:11434/api/generate" \
        -d "{
            \"model\": \"qwen3:14b\",
            \"prompt\": \"$ai_prompt\",
            \"stream\": false
        }" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('response','').strip())" 2>/dev/null || echo "")

    if [[ -z "$thread" ]]; then
        error "Thread-Generierung fehlgeschlagen"
        return 1
    fi

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local thread_file="$CONTENT_DIR/${timestamp}_thread.txt"
    echo "$thread" > "$thread_file"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  🧵 GENERIERTER THREAD"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "$thread" | sed 's/^/  /'
    echo ""
    echo "  Gespeichert: $thread_file"
    echo ""

    read -rp "  Thread jetzt posten? (j/n): " confirm
    if [[ "$confirm" == "j" || "$confirm" == "J" || "$confirm" == "y" || "$confirm" == "Y" ]]; then
        step "Poste Thread via x-twitter..."
        bash "$SCRIPT_DIR/x-twitter.sh" thread "$thread_file"
        update_stats "thread_posted"
        notify_telegram "🧵 *Thread gepostet*: $topic" ""
    fi
}

# =================================================================
# VIRAL-HOOKS — Virale Hook-Ideen generieren
# =================================================================
cmd_viral_hooks() {
    local niche="${1:-}"

    step "Generiere virale Hooks..."

    local ai_prompt="Generiere 20 virale X/Twitter Hook-Saetze${niche:+ fuer die Nische $niche}. Format: Nummerierte Liste. Jeder Hook soll Neugier wecken und zum Klicken/Lesen animieren. Mix aus: Kontroverse, Storytelling, Zahlen, Geheimnis, FOMO. Nur die Hooks, kein anderer Text."

    local hooks
    hooks=$(curl -s "http://localhost:11434/api/generate" \
        -d "{
            \"model\": \"qwen3:14b\",
            \"prompt\": \"$ai_prompt\",
            \"stream\": false
        }" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('response','').strip())" 2>/dev/null || echo "Keine Hooks generiert")

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  🎣 VIRALE HOOKS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "$hooks" | fold -s -w 70 | sed 's/^/  /'
    echo ""
}

# =================================================================
# SCHEDULE — Tweets vorplanen
# =================================================================
cmd_schedule() {
    local niche="${1:-crypto}"
    local count="${2:-5}"

    step "Generiere $count Tweets fuer Nische: $niche"

    local ai_prompt="Erstelle $count verschiedene Tweets fuer die Nische '$niche'. Jeder Tweet auf einer eigenen Zeile, getrennt durch ---. Mix aus: Tipps, Hot Takes, Fragen, Motivation, Fakten. Max 280 Zeichen pro Tweet. 1-2 Hashtags pro Tweet. Nur die Tweets, kein anderer Text."

    local tweets
    tweets=$(curl -s "http://localhost:11434/api/generate" \
        -d "{
            \"model\": \"qwen3:14b\",
            \"prompt\": \"$ai_prompt\",
            \"stream\": false
        }" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('response','').strip())" 2>/dev/null || echo "")

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  📅 SCHEDULED TWEETS ($count)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "$tweets" | sed 's/^/  /'
    echo ""

    # Save to queue
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    echo "$tweets" > "$CONTENT_DIR/${timestamp}_scheduled.txt"

    python3 -c "
import json
from datetime import datetime
with open('$MEMORY_FILE', 'r') as f:
    data = json.load(f)
queue = data.get('scheduled_queue', [])
tweets = '''$tweets'''.split('---')
for t in tweets:
    t = t.strip()
    if t and len(t) > 10:
        queue.append({
            'text': t[:280],
            'niche': '$niche',
            'created': datetime.utcnow().isoformat(),
            'status': 'scheduled'
        })
data['scheduled_queue'] = queue
with open('$MEMORY_FILE', 'w') as f:
    json.dump(data, f, indent=2)
print(f'  ✓ {len(tweets)} Tweets zur Queue hinzugefuegt')
" 2>/dev/null || echo "  Queue-Update fehlgeschlagen"
    echo ""
}

# =================================================================
# AUTO-ENGAGE — Automatisches Engagement
# =================================================================
cmd_auto_engage() {
    local niche="${1:-crypto}"

    step "Starte Auto-Engagement in Nische: $niche"

    # Search for relevant tweets
    browser_open "https://x.com/search?q=$niche&src=typed_query&f=live" "$PROFILE"
    wait_seconds 4

    local snapshot
    snapshot=$(browser_snapshot "$PROFILE" 2>/dev/null || echo "")

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  🤝 AUTO-ENGAGEMENT: $niche"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # AI generates smart replies
    local ai_prompt="Basierend auf diesen Tweets, generiere 5 smarte, hilfreiche Reply-Vorschlaege. Jede Reply soll: 1) Wert bieten, 2) Nicht spammy sein, 3) Max 200 Zeichen, 4) Zur Interaktion einladen. Format: Nummerierte Liste mit je 'Tweet: [Zusammenfassung]' und 'Reply: [deine Antwort]'. Daten: $(echo "$snapshot" | head -100)"

    local replies
    replies=$(curl -s "http://localhost:11434/api/generate" \
        -d "{
            \"model\": \"qwen3:14b\",
            \"prompt\": \"$ai_prompt\",
            \"stream\": false
        }" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('response','').strip())" 2>/dev/null || echo "Keine Replies generiert")

    echo "$replies" | fold -s -w 70 | sed 's/^/  /'
    echo ""
    echo "  Replies manuell posten via: ./x-twitter.sh reply"
    echo ""

    browser_screenshot "x-engage-$niche" "$PROFILE"
    update_stats "engagement"
}

# =================================================================
# GROWTH-SCAN — Growth Opportunities finden
# =================================================================
cmd_growth_scan() {
    step "Scanne Growth Opportunities..."

    # Check trending topics
    browser_open "https://x.com/explore/tabs/trending" "$PROFILE"
    wait_seconds 4
    local trending
    trending=$(browser_snapshot "$PROFILE" 2>/dev/null || echo "")

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  📈 GROWTH OPPORTUNITIES"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    local ai_prompt="Du bist ein X/Twitter Growth Hacker. Analysiere diese Trending Topics und gib 5 konkrete Aktionen fuer maximales Follower-Wachstum. Fuer jede Aktion: 1) Trending Topic nutzen, 2) Konkreter Tweet/Thread-Vorschlag, 3) Bester Zeitpunkt. Daten: $(echo "$trending" | head -100)"

    local analysis
    analysis=$(curl -s "http://localhost:11434/api/generate" \
        -d "{
            \"model\": \"qwen3:14b\",
            \"prompt\": \"$ai_prompt\",
            \"stream\": false
        }" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('response','').strip())" 2>/dev/null || echo "Analyse nicht verfuegbar")

    echo "$analysis" | fold -s -w 70 | sed 's/^/  /'
    echo ""
}

# =================================================================
# HASHTAGS — Trending Hashtags finden
# =================================================================
cmd_hashtags() {
    local topic="${1:-crypto}"

    step "Suche Trending Hashtags: $topic"

    browser_open "https://x.com/search?q=%23$topic&src=typed_query" "$PROFILE"
    wait_seconds 3
    local snapshot
    snapshot=$(browser_snapshot "$PROFILE" 2>/dev/null || echo "")

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  #️ TRENDING HASHTAGS: $topic"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Extract hashtags
    echo "$snapshot" | python3 -c "
import sys, re
content = sys.stdin.read()
hashtags = re.findall(r'#\w+', content)
seen = set()
count = 0
for tag in hashtags:
    tag_lower = tag.lower()
    if tag_lower not in seen:
        seen.add(tag_lower)
        count += 1
        if count <= 20:
            print(f'  {count}. {tag}')
if count == 0:
    print('  Keine Hashtags gefunden')
" 2>/dev/null || echo "  Parsing fehlgeschlagen"
    echo ""
}

# =================================================================
# REPURPOSE — Content Repurposing
# =================================================================
cmd_repurpose() {
    local url="${1:-}"
    if [[ -z "$url" ]]; then
        error "URL fehlt: ./x-content-engine.sh repurpose <url>"
        exit 1
    fi

    step "Repurpose Content von: $url"
    browser_open "$url" "$PROFILE"
    wait_seconds 4
    local snapshot
    snapshot=$(browser_snapshot "$PROFILE" 2>/dev/null || echo "")

    local ai_prompt="Basierend auf diesem Content, erstelle 3 verschiedene Formate fuer X/Twitter: 1) Ein einzelner Tweet (max 280 Zeichen), 2) Ein Thread (5 Tweets), 3) Ein Poll-Vorschlag. Content: $(echo "$snapshot" | head -150)"

    local repurposed
    repurposed=$(curl -s "http://localhost:11434/api/generate" \
        -d "{
            \"model\": \"qwen3:14b\",
            \"prompt\": \"$ai_prompt\",
            \"stream\": false
        }" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('response','').strip())" 2>/dev/null || echo "Repurposing fehlgeschlagen")

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ♻️ CONTENT REPURPOSED"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "$repurposed" | fold -s -w 70 | sed 's/^/  /'
    echo ""
}

# =================================================================
# DAILY — Taegliche Content-Routine
# =================================================================
cmd_daily() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  📆 TAEGLICHE X CONTENT ROUTINE"
    echo "  $(date '+%d.%m.%Y %H:%M')"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # 1. Check queue and post scheduled tweets
    step "[1/5] Geplante Tweets pruefen..."
    python3 -c "
import json
with open('$MEMORY_FILE', 'r') as f:
    data = json.load(f)
queue = data.get('scheduled_queue', [])
pending = [t for t in queue if t.get('status') == 'scheduled']
print(f'  Tweets in Queue: {len(pending)}')
if pending:
    print(f'  Naechster Tweet: {pending[0].get(\"text\", \"\")[:80]}...')
" 2>/dev/null || echo "  Queue nicht verfuegbar"

    # 2. Generate fresh content
    step "[2/5] Frischen Content generieren..."
    local niches
    niches=$(python3 -c "
import json
with open('$MEMORY_FILE', 'r') as f:
    data = json.load(f)
print(' '.join(data.get('niches', ['crypto', 'ai'])))
" 2>/dev/null || echo "crypto ai")

    for niche in $niches; do
        echo "  Generiere Tweet: $niche"
        local tweet
        tweet=$(curl -s "http://localhost:11434/api/generate" \
            -d "{
                \"model\": \"qwen3:14b\",
                \"prompt\": \"Create one viral tweet about $niche. Max 280 chars. Include 1 hashtag. Just the tweet text.\",
                \"stream\": false
            }" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('response','').strip()[:280])" 2>/dev/null || echo "")
        if [[ -n "$tweet" ]]; then
            save_to_queue "$tweet" "$niche"
        fi
    done

    # 3. Engagement check
    step "[3/5] Engagement-Check..."
    bash "$SCRIPT_DIR/x-twitter.sh" analytics 2>/dev/null || echo "  Analytics nicht verfuegbar"

    # 4. Trending scan
    step "[4/5] Trending Topics..."
    browser_open "https://x.com/explore/tabs/trending" "$PROFILE"
    wait_seconds 3
    browser_snapshot "$PROFILE" 2>/dev/null | head -20 | sed 's/^/  /'

    # 5. Report
    step "[5/5] Daily Report..."
    cmd_analytics_local

    notify_telegram "📆 *X Daily Routine* abgeschlossen — $(date +%H:%M)" ""
}

# =================================================================
# ANALYTICS — Content Performance
# =================================================================
cmd_analytics() {
    bash "$SCRIPT_DIR/x-twitter.sh" analytics 2>/dev/null || true
    cmd_analytics_local
}

cmd_analytics_local() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  📊 CONTENT ENGINE STATS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    python3 -c "
import json
with open('$MEMORY_FILE', 'r') as f:
    data = json.load(f)
print(f\"  Tweets generiert:   {data.get('tweets_generated', 0)}\")
print(f\"  Tweets gepostet:    {data.get('tweets_posted', 0)}\")
print(f\"  Threads erstellt:   {data.get('threads_created', 0)}\")
print(f\"  Engagement-Aktionen:{data.get('engagement_actions', 0)}\")
queue = data.get('scheduled_queue', [])
pending = [t for t in queue if t.get('status') == 'scheduled']
print(f\"  Tweets in Queue:    {len(pending)}\")
" 2>/dev/null || echo "  Keine Stats"
    echo ""
}

# --- Helper Functions ---
save_to_queue() {
    local text="$1"
    local niche="${2:-general}"
    python3 -c "
import json
from datetime import datetime
with open('$MEMORY_FILE', 'r') as f:
    data = json.load(f)
queue = data.get('scheduled_queue', [])
queue.append({
    'text': '''$text'''[:280],
    'niche': '$niche',
    'created': datetime.utcnow().isoformat(),
    'status': 'scheduled'
})
data['scheduled_queue'] = queue
data['tweets_generated'] = data.get('tweets_generated', 0) + 1
with open('$MEMORY_FILE', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true
}

update_stats() {
    local action="$1"
    python3 -c "
import json
with open('$MEMORY_FILE', 'r') as f:
    data = json.load(f)
if '$action' == 'tweet_posted':
    data['tweets_posted'] = data.get('tweets_posted', 0) + 1
elif '$action' == 'thread_posted':
    data['threads_created'] = data.get('threads_created', 0) + 1
elif '$action' == 'engagement':
    data['engagement_actions'] = data.get('engagement_actions', 0) + 1
with open('$MEMORY_FILE', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true
}

# =================================================================
# MAIN
# =================================================================
init_state

case "${1:-help}" in
    generate)     cmd_generate "${2:-crypto}" ;;
    thread)       cmd_thread "${2:-}" ;;
    viral-hooks)  cmd_viral_hooks "${2:-}" ;;
    schedule)     cmd_schedule "${2:-crypto}" "${3:-5}" ;;
    auto-engage)  cmd_auto_engage "${2:-crypto}" ;;
    growth-scan)  cmd_growth_scan ;;
    hashtags)     cmd_hashtags "${2:-crypto}" ;;
    analytics)    cmd_analytics ;;
    repurpose)    cmd_repurpose "${2:-}" ;;
    daily)        cmd_daily ;;
    help|*)
        echo ""
        echo "  🐦 X Content Engine — Kelly"
        echo ""
        echo "  Befehle:"
        echo "    generate <niche>        Tweet generieren"
        echo "    thread <topic>          Thread generieren"
        echo "    viral-hooks [niche]     Virale Hook-Ideen"
        echo "    schedule <niche> <n>    Tweets vorplanen"
        echo "    auto-engage [niche]     Auto-Engagement"
        echo "    growth-scan             Growth Opportunities"
        echo "    hashtags <topic>        Trending Hashtags"
        echo "    analytics               Performance Stats"
        echo "    repurpose <url>         Content Repurposing"
        echo "    daily                   Taegliche Routine"
        echo ""
        ;;
esac
