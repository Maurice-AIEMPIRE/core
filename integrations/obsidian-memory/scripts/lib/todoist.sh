#!/usr/bin/env bash
# Todoist helpers. Source me.

# Echo today's tasks as markdown checkboxes, one per line.
# Format: "- [ ] {content} {tags} (p{priority})"
todoist_today() {
    require TODOIST_TOKEN
    curl -fsS -H "Authorization: Bearer $TODOIST_TOKEN" \
        'https://api.todoist.com/rest/v2/tasks?filter=today%20%7C%20overdue' |
    python3 -c '
import json, sys
tasks = json.load(sys.stdin)
prio_map = {4: "p1", 3: "p2", 2: "p3", 1: "p4"}
for t in tasks:
    labels = " ".join("#" + l for l in t.get("labels", []))
    due = (t.get("due") or {}).get("date") or ""
    overdue = " (overdue)" if due and due < __import__("datetime").date.today().isoformat() else ""
    print(f"- [ ] {t[\"content\"]} {labels} ({prio_map.get(t[\"priority\"], \"p4\")}){overdue}".rstrip())
'
}

# Echo only overdue tasks.
todoist_overdue() {
    require TODOIST_TOKEN
    curl -fsS -H "Authorization: Bearer $TODOIST_TOKEN" \
        'https://api.todoist.com/rest/v2/tasks?filter=overdue' |
    python3 -c '
import json, sys
for t in json.load(sys.stdin):
    due = (t.get("due") or {}).get("date") or "?"
    print(f"- [ ] {t[\"content\"]} (was due {due})")
'
}
