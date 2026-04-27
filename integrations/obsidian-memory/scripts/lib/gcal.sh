#!/usr/bin/env bash
# Google Calendar helpers. Source me.
#
# Reads via the @core/google-calendar CLI if installed (preferred), else
# falls back to the REST API with GCAL_ACCESS_TOKEN if exported.

# Echo today's events as: "- HH:MM–HH:MM title"
gcal_today() {
    if command -v google-calendar >/dev/null 2>&1; then
        google-calendar list --today --format=line 2>/dev/null && return
    fi

    if [[ -n "${GCAL_ACCESS_TOKEN:-}" ]]; then
        local cal="${GCAL_CALENDAR_ID:-primary}"
        local start end
        start="$(date -u +%Y-%m-%dT00:00:00Z)"
        end="$(date -u -d 'tomorrow' +%Y-%m-%dT00:00:00Z 2>/dev/null || date -u -v+1d +%Y-%m-%dT00:00:00Z)"
        curl -fsS -H "Authorization: Bearer $GCAL_ACCESS_TOKEN" \
            "https://www.googleapis.com/calendar/v3/calendars/${cal}/events?timeMin=${start}&timeMax=${end}&singleEvents=true&orderBy=startTime" |
        python3 -c '
import json, sys
from datetime import datetime
def fmt(t):
    s = (t.get("dateTime") or t.get("date") or "")
    if "T" in s:
        try: return datetime.fromisoformat(s.replace("Z","+00:00")).astimezone().strftime("%H:%M")
        except: return s[11:16]
    return "all-day"
for e in json.load(sys.stdin).get("items", []):
    print(f"- {fmt(e[\"start\"])}–{fmt(e[\"end\"])} {e.get(\"summary\",\"(no title)\")}")
'
        return
    fi

    echo "- (gcal not configured — set GCAL_ACCESS_TOKEN or install @core/google-calendar)"
}
