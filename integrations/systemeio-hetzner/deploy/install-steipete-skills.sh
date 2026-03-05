#!/bin/bash
# =============================================================
# STEIPETE COMPLETE SKILLS INSTALLER
# Installiert ALLE 50 @steipete ClawHub Skills + Top Community Skills
# Direkt auf dem Hetzner Server ausfuehren:
#   curl -sL https://raw.githubusercontent.com/Maurice-AIEMPIRE/core/claude/fix-systeme-io-login-VStsj/integrations/systemeio-hetzner/deploy/install-steipete-skills.sh | bash
# =============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗"
echo -e "║  STEIPETE COMPLETE SKILLS INSTALLER                      ║"
echo -e "║  50 @steipete Skills + 4 Community Skills = 54 total     ║"
echo -e "╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Pruefen ob OpenClaw Container laeuft
if ! docker inspect --format='{{.State.Running}}' openclaw 2>/dev/null | grep -q true; then
    echo -e "${RED}FEHLER: OpenClaw Container laeuft nicht!${NC}"
    echo "  Starte mit: cd /opt/ki-power && docker compose up -d"
    exit 1
fi

OK=0
FAIL=0

install_skill() {
    local AUTHOR="$1"
    local SLUG="$2"
    local DESC="$3"
    local FULL_SLUG
    if [ -n "$AUTHOR" ]; then
        FULL_SLUG="@${AUTHOR}/${SLUG}"
    else
        FULL_SLUG="${SLUG}"
    fi
    if docker exec openclaw npx clawhub@latest install "${FULL_SLUG}" 2>/dev/null; then
        echo -e "${GREEN}  OK   ${SLUG} - ${DESC}${NC}"
        OK=$((OK + 1))
    else
        echo -e "${YELLOW}  SKIP ${SLUG} - ${DESC}${NC}"
        FAIL=$((FAIL + 1))
    fi
}

# ====================================================================
echo -e "${BOLD}=== PRODUKTIVITAET & WORKSPACE ===${NC}"
echo ""
install_skill steipete gog "Google Workspace - Gmail, Calendar, Drive, Sheets, Docs (83.6K DL)"
install_skill steipete summarize "URLs/PDFs/Audio/YouTube zusammenfassen (77.1K DL)"
install_skill steipete github "GitHub Issues, PRs, Repos, Actions (69K DL)"
install_skill steipete weather "Wetter aktuell + Vorhersage, kein API Key (58.8K DL)"
install_skill steipete sonoscli "Sonos Lautsprecher steuern (47.1K DL)"
install_skill steipete notion "Notion Pages, Databases, Blocks API (39.9K DL)"
install_skill steipete nano-pdf "PDF bearbeiten mit natuerlicher Sprache (37.1K DL)"
install_skill steipete obsidian "Obsidian Vault Markdown Notes (34.7K DL)"
install_skill steipete nano-banana-pro "Bilder generieren/bearbeiten Gemini 3 Pro (34.3K DL)"
install_skill steipete openai-whisper "Lokale Sprache-zu-Text ohne API Key (31.4K DL)"
install_skill steipete mcporter "MCP Server verwalten + Tools aufrufen (28.3K DL)"
install_skill steipete brave-search "Web-Suche ohne Browser via Brave API (28.1K DL)"
install_skill steipete frontend-design "Production-grade Web-UI erstellen (22K DL)"
install_skill steipete slack "Slack Nachrichten, Channels, Reactions, Pins (21.5K DL)"

echo ""
echo -e "${BOLD}=== MEDIEN & KREATIV ===${NC}"
echo ""
install_skill steipete model-usage "Per-Model Kosten/Usage Tracker via codexbar (19.9K DL)"
install_skill steipete video-frames "Video-Frames/Clips extrahieren mit ffmpeg (19.6K DL)"
install_skill steipete trello "Trello Boards, Listen, Karten verwalten (19.1K DL)"
install_skill steipete gemini "Gemini CLI fuer Q&A, Summaries, Generierung (17.9K DL)"
install_skill steipete discord "Discord Messages, Reactions, Polls, Threads (16K DL)"
install_skill steipete qmd "Lokale Suche BM25 + Vektoren + Rerank (15.9K DL)"
install_skill steipete clawdhub "ClawHub CLI - Skills suchen/installieren/updaten (14.4K DL)"
install_skill steipete markdown-converter "PDF/Word/Excel/HTML/CSV zu Markdown (14.3K DL)"
install_skill steipete sag "ElevenLabs Text-to-Speech (14.1K DL)"
install_skill steipete peekaboo "macOS UI Capture + Automation (13.8K DL)"
install_skill steipete spotify-player "Spotify Playback/Search im Terminal (13.2K DL)"
install_skill steipete tmux "Terminal Sessions fernsteuern (13K DL)"
install_skill steipete 1password "1Password CLI - Secrets lesen/injizieren (12.9K DL)"
install_skill steipete openai-image-gen "Bilder generieren via OpenAI API (12.8K DL)"
install_skill steipete openai-whisper-api "Sprache-zu-Text via OpenAI Whisper API (12.3K DL)"
install_skill steipete goplaces "Google Places API - Orte suchen + Details (12.3K DL)"

echo ""
echo -e "${BOLD}=== SMART HOME & IoT ===${NC}"
echo ""
install_skill steipete camsnap "RTSP/ONVIF Kamera Frames/Clips aufnehmen (8.1K DL)"
install_skill steipete oracle "Second-Model Review fuer Debugging/Refactors (8.1K DL)"
install_skill steipete imsg "iMessage/SMS CLI - Chats, History, Senden (8.2K DL)"
install_skill steipete things-mac "Things 3 Aufgaben verwalten via CLI (7.7K DL)"
install_skill steipete openhue "Philips Hue Licht + Szenen steuern (6.6K DL)"
install_skill steipete local-places "Lokale Orte suchen via Google Places (6.2K DL)"
install_skill steipete songsee "Audio Spektrogramme + Visualisierung (6K DL)"
install_skill steipete eightctl "Eight Sleep Pod steuern (5.2K DL)"
install_skill steipete video-transcript-downloader "YouTube/Video Transkripte + Untertitel (5.3K DL)"
install_skill steipete blucli "BluOS Lautsprecher Discovery + Playback (5.1K DL)"
install_skill steipete ordercli "Foodora Bestellungen + Status (4.7K DL)"

echo ""
echo -e "${BOLD}=== DEVELOPMENT & SWIFT ===${NC}"
echo ""
install_skill steipete coding-agent "Code schreiben + refactoren"
install_skill steipete swiftui-liquid-glass "SwiftUI iOS 26+ Liquid Glass API (2.5K DL)"
install_skill steipete swift-concurrency-expert "Swift 6.2+ Concurrency Review (2.3K DL)"
install_skill steipete domain-dns-ops "Domain/DNS Cloudflare/DNSimple/Namecheap (2.3K DL)"
install_skill steipete create-cli "CLI Design - Args, Flags, UX (2.2K DL)"
install_skill steipete swiftui-performance-audit "SwiftUI Performance Audit (2.2K DL)"
install_skill steipete swiftui-view-refactor "SwiftUI View Refactoring (2.1K DL)"
install_skill steipete food-order "Foodora Nachbestellen + ETA (2.5K DL)"
install_skill steipete instruments-profiling "Instruments/xctrace Profiling (1.8K DL)"
install_skill steipete native-app-performance "macOS/iOS App Performance Profiling (1.7K DL)"

# ====================================================================
echo ""
echo -e "${BOLD}=== GOG BINARY (Google Workspace braucht Binary) ===${NC}"
echo ""

GOG_URL=$(curl -fsSL https://api.github.com/repos/steipete/gogcli/releases/latest 2>/dev/null | jq -r '.assets[] | select(.name | contains("linux_amd64")) | .browser_download_url' 2>/dev/null || echo "")
if [ -n "$GOG_URL" ]; then
    cd /tmp
    curl -fsSL -o gogcli.tgz "$GOG_URL" && tar -xzf gogcli.tgz && install -m 0755 gog /usr/local/bin/gog 2>/dev/null && {
        docker cp /usr/local/bin/gog openclaw:/usr/local/bin/gog 2>/dev/null || true
        echo -e "${GREEN}  OK   gog Binary -> /usr/local/bin/gog${NC}"
        OK=$((OK + 1))
    } || {
        echo -e "${YELLOW}  SKIP gog Binary${NC}"
        FAIL=$((FAIL + 1))
    }
    rm -f /tmp/gogcli.tgz /tmp/gog 2>/dev/null
else
    echo -e "${YELLOW}  SKIP gog Binary - manuell: github.com/steipete/gogcli${NC}"
    FAIL=$((FAIL + 1))
fi

# ====================================================================
echo ""
echo -e "${BOLD}=== TOP COMMUNITY SKILLS ===${NC}"
echo ""

install_skill "" capability-evolver "KI verbessert sich selbst (35K DL)"
install_skill "" self-improving-agent "Lernt aus Interaktionen (15K DL)"
install_skill "" byterover "Code-Analyse + Optimierung (16K DL)"
install_skill "" agent-browser "Web Scraping + Automatisierung (11K DL)"

# ====================================================================
TOTAL=$((OK + FAIL))

echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}  FERTIG: ${OK}/${TOTAL} Skills installiert${NC}"
if [ $FAIL -gt 0 ]; then
    echo -e "${YELLOW}  Uebersprungen: ${FAIL} (ggf. manuell nachinstallieren)${NC}"
fi
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}Pruefen:${NC}"
echo "  docker exec openclaw ls ~/.openclaw/skills/"
echo ""
echo -e "${BOLD}Weitere Skills:${NC}"
echo "  docker exec openclaw npx clawhub@latest search \"keyword\""
echo ""
echo -e "${BOLD}Google Workspace einrichten:${NC}"
echo "  gog auth credentials /pfad/zu/client_secret.json"
echo "  gog auth add deine@gmail.com --services gmail,calendar,drive,sheets,docs"
echo ""
echo -e "${BOLD}Skills nutzen:${NC}"
echo "  Die Skills sind jetzt in OpenClaw aktiv. Schreib deinem Bot z.B.:"
echo "    'Fasse diese URL zusammen: https://...'  (summarize)"
echo "    'Wie ist das Wetter in Berlin?'          (weather)"
echo "    'Suche im Web nach ...'                  (brave-search)"
echo "    'Erstelle ein PDF aus ...'               (nano-pdf)"
echo ""
