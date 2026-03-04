#!/usr/bin/env bash
# ================================================================
# ROSS — Faceless YouTube Automation Pipeline
# ================================================================
# Vollautomatische Faceless YouTube Video Produktion
# Script → TTS → Video Assembly → Thumbnail → Upload
#
# Befehle:
#   ./youtube-faceless.sh generate <niche> <topic>  — Komplettes Video generieren
#   ./youtube-faceless.sh script <niche> <topic>    — Nur Script erstellen
#   ./youtube-faceless.sh tts <script-file>         — Text-to-Speech
#   ./youtube-faceless.sh assemble <audio> <images-dir> — Video zusammenbauen
#   ./youtube-faceless.sh thumbnail <title>         — Thumbnail generieren
#   ./youtube-faceless.sh upload <video> <meta.json>— Upload via youtube-studio
#   ./youtube-faceless.sh pipeline <niche>          — Volle Pipeline (1 Klick)
#   ./youtube-faceless.sh niches                    — Profitable Nischen anzeigen
#   ./youtube-faceless.sh trending                  — Trending Topics finden
#   ./youtube-faceless.sh analytics                 — Performance Report
# ================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/browser-helper.sh"

PROFILE="openclaw"
WORKSPACE="/tmp/openclaw/youtube-factory"
SCRIPTS_DIR="$WORKSPACE/scripts"
AUDIO_DIR="$WORKSPACE/audio"
IMAGES_DIR="$WORKSPACE/images"
VIDEOS_DIR="$WORKSPACE/videos"
THUMBS_DIR="$WORKSPACE/thumbnails"
MEMORY_FILE="$MEMORY_DIR/youtube-faceless.json"

mkdir -p "$SCRIPTS_DIR" "$AUDIO_DIR" "$IMAGES_DIR" "$VIDEOS_DIR" "$THUMBS_DIR"

# --- State ---
init_state() {
    if [[ ! -f "$MEMORY_FILE" ]]; then
        cat > "$MEMORY_FILE" << 'INIT'
{
  "videos_created": 0,
  "videos_uploaded": 0,
  "total_views": 0,
  "niches": [],
  "history": [],
  "last_upload": null
}
INIT
    fi
}

# --- Profitable Niches ---
NICHES=(
    "finance:Personal Finance Tips|Passive Income|Crypto Explained|Stock Market|Side Hustles"
    "tech:AI News|Tech Reviews|Programming Tutorials|Gadgets|Apps"
    "health:Weight Loss|Meditation|Workout Routines|Nutrition|Mental Health"
    "motivation:Success Stories|Productivity|Self Improvement|Stoicism|Mindset"
    "facts:Amazing Facts|History|Science|Geography|Psychology"
    "horror:Scary Stories|True Crime|Unsolved Mysteries|Creepy|Urban Legends"
    "gaming:Game Reviews|Top 10|Gaming News|Tips & Tricks|Speedruns"
    "money:Make Money Online|Investing|Real Estate|Dropshipping|Freelancing"
)

# =================================================================
# NICHES — Profitable Nischen anzeigen
# =================================================================
cmd_niches() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  💰 PROFITABLE FACELESS YOUTUBE NISCHEN"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    for entry in "${NICHES[@]}"; do
        local niche="${entry%%:*}"
        local topics="${entry#*:}"
        echo "  📂 ${niche^^}"
        IFS='|' read -ra TOPICS <<< "$topics"
        for t in "${TOPICS[@]}"; do
            echo "     → $t"
        done
        echo ""
    done
}

# =================================================================
# TRENDING — Trending Topics via Browser
# =================================================================
cmd_trending() {
    local niche="${1:-}"
    step "Suche Trending Topics${niche:+ in Nische: $niche}..."

    local search_query="trending youtube topics 2026${niche:+ $niche}"
    browser_open "https://www.google.com/search?q=$(echo "$search_query" | sed 's/ /+/g')" "$PROFILE"
    wait_seconds 3
    local snap1
    snap1=$(browser_snapshot "$PROFILE" 2>/dev/null || echo "")

    # Also check YouTube trending
    browser_open "https://www.youtube.com/feed/trending" "$PROFILE"
    wait_seconds 3
    local snap2
    snap2=$(browser_snapshot "$PROFILE" 2>/dev/null || echo "")

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  🔥 TRENDING TOPICS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # AI analysis of trends
    local ai_prompt="Basierend auf diesen Daten, gib mir die 10 besten Faceless YouTube Video Ideen${niche:+ in der Nische $niche}. Format: Nummerierte Liste mit Titel und geschaetztem View-Potential (Low/Medium/High). Google: $(echo "$snap1" | head -80). YouTube Trending: $(echo "$snap2" | head -80)"

    local ideas
    ideas=$(curl -s "http://localhost:11434/api/generate" \
        -d "{
            \"model\": \"qwen3:14b\",
            \"prompt\": \"$ai_prompt\",
            \"stream\": false
        }" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('response','Keine Ideen'))" 2>/dev/null || echo "AI nicht verfuegbar")

    echo "$ideas" | fold -s -w 70 | sed 's/^/  /'
    echo ""
}

# =================================================================
# SCRIPT — AI Video Script generieren
# =================================================================
cmd_script() {
    local niche="${1:-finance}"
    local topic="${2:-}"

    if [[ -z "$topic" ]]; then
        # Auto-generate topic
        step "Generiere Topic fuer Nische: $niche"
        topic=$(curl -s "http://localhost:11434/api/generate" \
            -d "{
                \"model\": \"qwen3:14b\",
                \"prompt\": \"Generate ONE viral YouTube video topic for the '$niche' niche. Just the topic title, nothing else. Make it click-worthy.\",
                \"stream\": false
            }" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('response','Top 10 Amazing Facts').strip())" 2>/dev/null || echo "Top 10 Amazing Facts")
    fi

    step "Erstelle Script: '$topic'"

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local script_file="$SCRIPTS_DIR/${timestamp}_script.txt"
    local meta_file="$SCRIPTS_DIR/${timestamp}_meta.json"

    # Generate full script
    local script_prompt="Du bist ein erfolgreicher YouTube Scriptwriter. Erstelle ein komplettes Faceless YouTube Video Script (8-12 Minuten) zum Thema: '$topic' in der Nische '$niche'.

Format:
HOOK: (Erster Satz, der Aufmerksamkeit erregt — 15 Sekunden)
INTRO: (Kurze Einfuehrung — 30 Sekunden)
MAIN: (Hauptteil mit 5-8 Abschnitten, jeder 60-90 Sekunden)
CTA: (Call to Action — Like, Sub, Comment)
OUTRO: (Abschluss — 15 Sekunden)

Regeln:
- Einfache, klare Sprache (Deutsch oder Englisch je nach Zielgruppe)
- Jeder Abschnitt mit [VISUAL: Beschreibung] fuer Stock Footage
- Emotional, engaging, storytelling
- SEO-optimiert"

    local script_content
    script_content=$(curl -s "http://localhost:11434/api/generate" \
        -d "{
            \"model\": \"qwen3:14b\",
            \"prompt\": \"$script_prompt\",
            \"stream\": false
        }" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('response','Script generation failed'))" 2>/dev/null || echo "AI nicht verfuegbar")

    echo "$script_content" > "$script_file"

    # Generate metadata
    local meta_prompt="Erstelle YouTube SEO Metadaten fuer dieses Video als JSON. Felder: title (max 70 chars, click-worthy), description (2000 chars mit Keywords), tags (15 relevante Tags als Array), category (YouTube Kategorie). Topic: $topic. Nische: $niche. Nur JSON ausgeben, kein anderer Text."

    local meta_content
    meta_content=$(curl -s "http://localhost:11434/api/generate" \
        -d "{
            \"model\": \"qwen3:14b\",
            \"prompt\": \"$meta_prompt\",
            \"stream\": false
        }" 2>/dev/null | python3 -c "
import json, sys, re
response = json.load(sys.stdin).get('response', '{}')
# Extract JSON from response
match = re.search(r'\{.*\}', response, re.DOTALL)
if match:
    try:
        data = json.loads(match.group())
        print(json.dumps(data, indent=2))
    except:
        print(json.dumps({'title': '$topic', 'description': 'Video about $topic', 'tags': ['$niche', '$topic'], 'category': 'Education'}))
else:
    print(json.dumps({'title': '$topic', 'description': 'Video about $topic', 'tags': ['$niche', '$topic'], 'category': 'Education'}))
" 2>/dev/null || echo '{"title": "'"$topic"'", "tags": ["'"$niche"'"]}')

    echo "$meta_content" > "$meta_file"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  📝 SCRIPT ERSTELLT"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Script: $script_file"
    echo "  Meta:   $meta_file"
    echo "  Topic:  $topic"
    echo "  Nische: $niche"
    echo ""
    echo "  Vorschau (erste 10 Zeilen):"
    head -10 "$script_file" | sed 's/^/    /'
    echo ""
    echo "  Naechster Schritt: ./youtube-faceless.sh tts $script_file"
    echo ""
}

# =================================================================
# TTS — Text-to-Speech Audio generieren
# =================================================================
cmd_tts() {
    local script_file="${1:-}"
    if [[ -z "$script_file" || ! -f "$script_file" ]]; then
        error "Script-Datei nicht gefunden: $script_file"
        echo "  Usage: ./youtube-faceless.sh tts <script-file>"
        exit 1
    fi

    step "Generiere Audio via TTS..."

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local audio_file="$AUDIO_DIR/${timestamp}_voice.wav"

    # Clean script for TTS (remove [VISUAL:...] tags)
    local clean_text
    clean_text=$(sed 's/\[VISUAL:[^]]*\]//g; s/HOOK://; s/INTRO://; s/MAIN://; s/CTA://; s/OUTRO://' "$script_file" | tr '\n' ' ' | sed 's/  */ /g')

    # Try multiple TTS options
    # Option 1: edge-tts (Microsoft, free, high quality)
    if command -v edge-tts &>/dev/null; then
        log "Verwende edge-tts..."
        edge-tts --text "$clean_text" --voice "de-DE-ConradNeural" --write-media "$audio_file" 2>/dev/null && {
            log "Audio erstellt: $audio_file"
            echo "  ✓ Audio: $audio_file"
            echo "  Naechster Schritt: ./youtube-faceless.sh assemble $audio_file"
            return 0
        }
    fi

    # Option 2: piper-tts (local, offline)
    if command -v piper &>/dev/null; then
        log "Verwende piper-tts..."
        echo "$clean_text" | piper --output_file "$audio_file" 2>/dev/null && {
            log "Audio erstellt: $audio_file"
            echo "  ✓ Audio: $audio_file"
            return 0
        }
    fi

    # Option 3: gtts (Google TTS, free)
    if python3 -c "import gtts" 2>/dev/null; then
        log "Verwende gTTS..."
        python3 -c "
from gtts import gTTS
text = '''$clean_text'''
tts = gTTS(text=text[:5000], lang='de')
tts.save('$audio_file')
print('Audio saved')
" 2>/dev/null && {
            log "Audio erstellt: $audio_file"
            echo "  ✓ Audio: $audio_file"
            return 0
        }
    fi

    # Option 4: Browser-based TTS via ElevenLabs/PlayHT
    warn "Kein lokales TTS verfuegbar. Verwende Browser-TTS..."
    echo "$clean_text" > "$AUDIO_DIR/${timestamp}_text_for_tts.txt"
    echo ""
    echo "  ⚠ Kein lokales TTS installiert."
    echo "  Optionen:"
    echo "    1. pip install edge-tts   (empfohlen, kostenlos)"
    echo "    2. pip install gtts       (Google TTS)"
    echo "    3. Manuell: Text in $AUDIO_DIR/${timestamp}_text_for_tts.txt"
    echo ""
    echo "  Text gespeichert fuer manuelles TTS."
}

# =================================================================
# ASSEMBLE — Video aus Audio + Stock Images zusammenbauen
# =================================================================
cmd_assemble() {
    local audio_file="${1:-}"
    local img_dir="${2:-$IMAGES_DIR}"

    if [[ -z "$audio_file" || ! -f "$audio_file" ]]; then
        error "Audio-Datei nicht gefunden: $audio_file"
        exit 1
    fi

    step "Baue Video zusammen..."

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local output_video="$VIDEOS_DIR/${timestamp}_faceless.mp4"

    # Check for ffmpeg
    if ! command -v ffmpeg &>/dev/null; then
        error "ffmpeg nicht installiert!"
        echo "  brew install ffmpeg  (Mac)"
        echo "  apt install ffmpeg   (Linux)"
        exit 1
    fi

    # Get audio duration
    local duration
    duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$audio_file" 2>/dev/null | cut -d. -f1)
    duration=${duration:-600}

    # Check for images
    local image_count
    image_count=$(find "$img_dir" -name "*.jpg" -o -name "*.png" -o -name "*.jpeg" 2>/dev/null | wc -l)

    if [[ "$image_count" -gt 0 ]]; then
        # Slideshow with images
        log "Erstelle Slideshow mit $image_count Bildern..."
        local seconds_per_image=$(( duration / image_count + 1 ))

        # Create image list for ffmpeg
        local concat_file="$WORKSPACE/images_concat.txt"
        > "$concat_file"
        find "$img_dir" -name "*.jpg" -o -name "*.png" -o -name "*.jpeg" 2>/dev/null | sort | while read -r img; do
            echo "file '$img'" >> "$concat_file"
            echo "duration $seconds_per_image" >> "$concat_file"
        done

        ffmpeg -y -f concat -safe 0 -i "$concat_file" \
            -i "$audio_file" \
            -c:v libx264 -pix_fmt yuv420p \
            -c:a aac -b:a 192k \
            -shortest -movflags +faststart \
            -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:black" \
            "$output_video" 2>/dev/null
    else
        # Just audio with black background (user adds images later)
        warn "Keine Bilder gefunden in $img_dir"
        log "Erstelle Video mit schwarzem Hintergrund..."
        ffmpeg -y -f lavfi -i "color=c=black:s=1920x1080:d=$duration" \
            -i "$audio_file" \
            -c:v libx264 -pix_fmt yuv420p \
            -c:a aac -b:a 192k \
            -shortest -movflags +faststart \
            "$output_video" 2>/dev/null
    fi

    if [[ -f "$output_video" ]]; then
        local filesize
        filesize=$(du -h "$output_video" | cut -f1)
        echo ""
        echo "  ✓ Video erstellt: $output_video"
        echo "  Groesse: $filesize"
        echo "  Dauer:   ~${duration}s"
        echo ""
        echo "  Naechster Schritt: ./youtube-faceless.sh upload $output_video"
    else
        error "Video-Erstellung fehlgeschlagen"
    fi
}

# =================================================================
# THUMBNAIL — Thumbnail generieren
# =================================================================
cmd_thumbnail() {
    local title="${1:-Amazing Video}"

    step "Generiere Thumbnail..."

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local thumb_file="$THUMBS_DIR/${timestamp}_thumb.png"

    # Check for ImageMagick
    if command -v convert &>/dev/null; then
        # Create eye-catching thumbnail with ImageMagick
        log "Erstelle Thumbnail mit ImageMagick..."

        # Simple but effective: Bold text on gradient background
        convert -size 1280x720 \
            -define gradient:angle=135 \
            gradient:'#FF6B35-#004E89' \
            -gravity center \
            -font "Helvetica-Bold" \
            -pointsize 72 \
            -fill white \
            -stroke black \
            -strokewidth 3 \
            -annotate 0 "$(echo "$title" | fold -s -w 25)" \
            "$thumb_file" 2>/dev/null && {
            echo "  ✓ Thumbnail: $thumb_file"
            return 0
        }
    fi

    # Fallback: Python PIL
    if python3 -c "from PIL import Image" 2>/dev/null; then
        python3 -c "
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (1280, 720), color=(255, 107, 53))
draw = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 60)
except:
    font = ImageFont.load_default()
text = '''$title'''
# Center text
bbox = draw.textbbox((0, 0), text, font=font)
w = bbox[2] - bbox[0]
h = bbox[3] - bbox[1]
draw.text(((1280-w)/2, (720-h)/2), text, fill='white', font=font)
img.save('$thumb_file')
" 2>/dev/null && {
        echo "  ✓ Thumbnail: $thumb_file"
        return 0
    }
    fi

    warn "Kein Bildbearbeitungstool verfuegbar"
    echo "  Installiere: brew install imagemagick oder pip install Pillow"
}

# =================================================================
# UPLOAD — Video hochladen via youtube-studio.sh
# =================================================================
cmd_upload() {
    local video="${1:-}"
    local meta="${2:-}"

    if [[ -z "$video" || ! -f "$video" ]]; then
        error "Video-Datei nicht gefunden: $video"
        exit 1
    fi

    # Find meta file if not provided
    if [[ -z "$meta" ]]; then
        meta=$(ls -t "$SCRIPTS_DIR"/*_meta.json 2>/dev/null | head -1)
    fi

    if [[ -z "$meta" || ! -f "$meta" ]]; then
        error "Meta-Datei nicht gefunden. Erstelle mit: ./youtube-faceless.sh script"
        exit 1
    fi

    step "Starte Upload via YouTube Studio..."
    echo ""
    echo "  Video: $video"
    echo "  Meta:  $meta"
    echo ""

    # Human-in-the-loop confirmation
    read -rp "  Video wirklich hochladen? (j/n): " confirm
    if [[ "$confirm" != "j" && "$confirm" != "J" && "$confirm" != "y" && "$confirm" != "Y" ]]; then
        warn "Upload abgebrochen"
        return 0
    fi

    # Use existing youtube-studio.sh for upload
    bash "$SCRIPT_DIR/youtube-studio.sh" upload "$video" "$meta"

    # Update state
    python3 -c "
import json
from datetime import datetime
with open('$MEMORY_FILE', 'r') as f:
    data = json.load(f)
data['videos_uploaded'] = data.get('videos_uploaded', 0) + 1
data['last_upload'] = datetime.utcnow().isoformat()
data['history'] = data.get('history', [])
data['history'].append({
    'timestamp': datetime.utcnow().isoformat(),
    'video': '$video',
    'meta': '$meta',
    'status': 'uploaded'
})
with open('$MEMORY_FILE', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true

    notify_telegram "🎬 *YouTube Upload* gestartet — $(date +%H:%M)" ""
}

# =================================================================
# PIPELINE — Volle automatische Pipeline
# =================================================================
cmd_pipeline() {
    local niche="${1:-finance}"
    local topic="${2:-}"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  🏭 FACELESS YOUTUBE PIPELINE"
    echo "  Nische: $niche"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Step 1: Generate Script
    step "[1/5] Script generieren..."
    cmd_script "$niche" "$topic"
    local script_file
    script_file=$(ls -t "$SCRIPTS_DIR"/*_script.txt 2>/dev/null | head -1)
    local meta_file
    meta_file=$(ls -t "$SCRIPTS_DIR"/*_meta.json 2>/dev/null | head -1)

    if [[ -z "$script_file" ]]; then
        error "Script-Generierung fehlgeschlagen"
        return 1
    fi

    # Step 2: TTS
    step "[2/5] Text-to-Speech..."
    cmd_tts "$script_file"
    local audio_file
    audio_file=$(ls -t "$AUDIO_DIR"/*_voice.wav 2>/dev/null | head -1)

    if [[ -z "$audio_file" || ! -f "$audio_file" ]]; then
        warn "TTS fehlgeschlagen — Pipeline pausiert"
        echo "  Bitte TTS manuell ausfuehren und dann fortfahren mit:"
        echo "  ./youtube-faceless.sh assemble <audio-file>"
        return 1
    fi

    # Step 3: Get stock images (via browser)
    step "[3/5] Stock-Bilder laden..."
    local title
    title=$(python3 -c "import json; print(json.load(open('$meta_file')).get('title','Video'))" 2>/dev/null || echo "Video")
    browser_open "https://www.pexels.com/search/$( echo "$title" | sed 's/ /+/g' | head -c 50)/" "$PROFILE"
    wait_seconds 3
    echo "  Bilder-Suche geoeffnet. Lade manuell relevante Bilder nach: $IMAGES_DIR"
    echo "  Oder ueberspringe fuer Video mit schwarzem Hintergrund."

    # Step 4: Assemble
    step "[4/5] Video zusammenbauen..."
    cmd_assemble "$audio_file" "$IMAGES_DIR"
    local video_file
    video_file=$(ls -t "$VIDEOS_DIR"/*_faceless.mp4 2>/dev/null | head -1)

    # Step 5: Thumbnail
    step "[5/5] Thumbnail erstellen..."
    cmd_thumbnail "$title"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ✅ PIPELINE ABGESCHLOSSEN"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Script:    $script_file"
    echo "  Audio:     ${audio_file:-FEHLT}"
    echo "  Video:     ${video_file:-FEHLT}"
    echo "  Meta:      $meta_file"
    echo ""
    echo "  Upload: ./youtube-faceless.sh upload $video_file $meta_file"
    echo ""

    # Update state
    python3 -c "
import json
from datetime import datetime
with open('$MEMORY_FILE', 'r') as f:
    data = json.load(f)
data['videos_created'] = data.get('videos_created', 0) + 1
with open('$MEMORY_FILE', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true

    notify_telegram "🏭 *Faceless Pipeline* abgeschlossen — $title" ""
}

# =================================================================
# ANALYTICS — Performance Report
# =================================================================
cmd_analytics() {
    step "Lade YouTube Analytics..."
    bash "$SCRIPT_DIR/youtube-studio.sh" analytics

    # Local stats
    init_state
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  📊 FACELESS FACTORY STATS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    python3 -c "
import json
with open('$MEMORY_FILE', 'r') as f:
    data = json.load(f)
print(f\"  Videos erstellt:  {data.get('videos_created', 0)}\")
print(f\"  Videos uploaded:  {data.get('videos_uploaded', 0)}\")
print(f\"  Letzter Upload:   {data.get('last_upload', 'Noch keiner')}\")
history = data.get('history', [])
if history:
    print(f\"  Letzte {min(5, len(history))} Videos:\")
    for h in history[-5:]:
        print(f\"    → {h.get('timestamp','')} | {h.get('status','')}\")
" 2>/dev/null || echo "  Keine lokalen Stats"
    echo ""
}

# =================================================================
# MAIN
# =================================================================
init_state

case "${1:-help}" in
    generate|script)  cmd_script "${2:-finance}" "${3:-}" ;;
    tts)              cmd_tts "${2:-}" ;;
    assemble)         cmd_assemble "${2:-}" "${3:-}" ;;
    thumbnail)        cmd_thumbnail "${2:-Amazing Video}" ;;
    upload)           cmd_upload "${2:-}" "${3:-}" ;;
    pipeline)         cmd_pipeline "${2:-finance}" "${3:-}" ;;
    niches)           cmd_niches ;;
    trending)         cmd_trending "${2:-}" ;;
    analytics)        cmd_analytics ;;
    help|*)
        echo ""
        echo "  🎬 Faceless YouTube Factory — Ross"
        echo ""
        echo "  Befehle:"
        echo "    generate <niche> [topic]  Komplettes Video generieren"
        echo "    script <niche> [topic]    Nur Script erstellen"
        echo "    tts <script-file>         Text-to-Speech"
        echo "    assemble <audio> [imgs]   Video zusammenbauen"
        echo "    thumbnail <title>         Thumbnail generieren"
        echo "    upload <video> <meta>     Video hochladen"
        echo "    pipeline <niche> [topic]  Volle 1-Klick Pipeline"
        echo "    niches                    Profitable Nischen"
        echo "    trending [niche]          Trending Topics"
        echo "    analytics                 Performance Report"
        echo ""
        echo "  Quick Start:"
        echo "    ./youtube-faceless.sh pipeline finance"
        echo ""
        ;;
esac
