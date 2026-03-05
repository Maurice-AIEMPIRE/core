#!/bin/bash
# =============================================================
# FIX: OpenClaw Auth-Profile konfigurieren
# Behebt: "No API key found for provider" Fehler
#
# Auf dem Hetzner Server ausfuehren:
#   bash fix-openclaw-auth.sh
# =============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${CYAN}${BOLD}=== OPENCLAW AUTH FIX ===${NC}"
echo -e "Behebt: 'No API key found for provider' Fehler"
echo ""

# Container pruefen
if ! docker inspect --format='{{.State.Running}}' openclaw 2>/dev/null | grep -q true; then
    echo -e "${RED}FEHLER: OpenClaw Container laeuft nicht!${NC}"
    echo "  Starte mit: cd /opt/ki-power && docker compose up -d"
    exit 1
fi

# Auth-Profiles Pfad im Container
AUTH_PATH="/root/.openclaw/agents/main/agent"

echo -e "${BOLD}Welchen KI-Provider willst du nutzen?${NC}"
echo ""
echo "  1) Ollama (kostenlos, lokal auf Server)"
echo "  2) OpenAI (braucht API Key, am schnellsten)"
echo "  3) Beide (Ollama als Standard, OpenAI als Fallback)"
echo ""
read -p "Auswahl [1/2/3]: " CHOICE

case "$CHOICE" in
    1)
        # Pruefen ob Ollama erreichbar ist
        if ! curl -sf http://localhost:11434/api/tags > /dev/null 2>&1; then
            echo -e "${YELLOW}Ollama laeuft nicht auf localhost:11434${NC}"
            echo "Installiere Ollama mit: curl -fsSL https://ollama.com/install.sh | sh"
            read -p "Trotzdem konfigurieren? (j/N): " FORCE
            [ "$FORCE" != "j" ] && exit 1
        fi

        # Auth-Profile fuer Ollama
        docker exec openclaw mkdir -p "$AUTH_PATH"
        docker exec openclaw sh -c "cat > $AUTH_PATH/auth-profiles.json << 'AUTHEOF'
{
  \"profiles\": {
    \"ollama\": {
      \"provider\": \"ollama\",
      \"baseUrl\": \"http://ollama:11434\",
      \"apiKey\": \"ollama-local\"
    }
  },
  \"default\": \"ollama\"
}
AUTHEOF"
        echo -e "${GREEN}OK - Ollama konfiguriert${NC}"

        # Modell pruefen/pullen
        echo "Pruefe Ollama Modelle..."
        if ! curl -sf http://localhost:11434/api/tags | grep -q "qwen3"; then
            echo "Lade qwen3:14b (kann etwas dauern)..."
            ollama pull qwen3:14b
        fi
        echo -e "${GREEN}OK - qwen3:14b bereit${NC}"
        ;;

    2)
        read -p "OpenAI API Key (sk-...): " OPENAI_KEY
        if [ -z "$OPENAI_KEY" ]; then
            echo -e "${RED}Kein Key eingegeben!${NC}"
            exit 1
        fi

        docker exec openclaw mkdir -p "$AUTH_PATH"
        docker exec openclaw sh -c "cat > $AUTH_PATH/auth-profiles.json << AUTHEOF
{
  \"profiles\": {
    \"openai\": {
      \"provider\": \"openai\",
      \"apiKey\": \"${OPENAI_KEY}\"
    }
  },
  \"default\": \"openai\"
}
AUTHEOF"
        echo -e "${GREEN}OK - OpenAI konfiguriert${NC}"

        # Auch in .env speichern
        if [ -f /opt/ki-power/.env ]; then
            sed -i "s|^OPENAI_API_KEY=.*|OPENAI_API_KEY=${OPENAI_KEY}|" /opt/ki-power/.env
            echo -e "${GREEN}OK - .env aktualisiert${NC}"
        fi
        ;;

    3)
        read -p "OpenAI API Key (sk-...): " OPENAI_KEY
        if [ -z "$OPENAI_KEY" ]; then
            echo -e "${RED}Kein OpenAI Key eingegeben!${NC}"
            exit 1
        fi

        docker exec openclaw mkdir -p "$AUTH_PATH"
        docker exec openclaw sh -c "cat > $AUTH_PATH/auth-profiles.json << AUTHEOF
{
  \"profiles\": {
    \"ollama\": {
      \"provider\": \"ollama\",
      \"baseUrl\": \"http://ollama:11434\",
      \"apiKey\": \"ollama-local\"
    },
    \"openai\": {
      \"provider\": \"openai\",
      \"apiKey\": \"${OPENAI_KEY}\"
    }
  },
  \"default\": \"ollama\"
}
AUTHEOF"
        echo -e "${GREEN}OK - Ollama + OpenAI konfiguriert${NC}"

        if [ -f /opt/ki-power/.env ]; then
            sed -i "s|^OPENAI_API_KEY=.*|OPENAI_API_KEY=${OPENAI_KEY}|" /opt/ki-power/.env
        fi
        ;;

    *)
        echo -e "${RED}Ungueltige Auswahl${NC}"
        exit 1
        ;;
esac

# Container neustarten
echo ""
echo "Container wird neugestartet..."
docker restart openclaw
sleep 3

# Pruefen
if docker inspect --format='{{.State.Running}}' openclaw 2>/dev/null | grep -q true; then
    echo -e "${GREEN}${BOLD}FERTIG! OpenClaw laeuft wieder.${NC}"
    echo ""
    echo "Teste jetzt deinen Telegram Bot - schreib ihm eine Nachricht!"
    echo ""
    echo "Logs anschauen: docker logs -f openclaw"
    echo "Status pruefen: adler telegram"
else
    echo -e "${RED}Container startet nicht - Logs pruefen:${NC}"
    echo "  docker logs openclaw --tail 20"
fi
echo ""
