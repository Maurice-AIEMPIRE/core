#!/usr/bin/env bash
# Telegram helpers. Source me.

# Send a message to the configured chat. Reads stdin if no $1.
telegram_send() {
    require TELEGRAM_BOT_TOKEN
    require TELEGRAM_CHAT_ID
    local text
    if [[ $# -gt 0 ]]; then
        text="$*"
    else
        text="$(cat)"
    fi
    # Telegram caps a single message at ~4096 chars; truncate gracefully.
    if (( ${#text} > 3900 )); then
        text="${text:0:3900}"$'\n\n…(truncated)'
    fi
    curl -fsS -X POST \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${text}" \
        --data-urlencode "parse_mode=Markdown" \
        --data-urlencode "disable_web_page_preview=true" \
        >/dev/null
}
