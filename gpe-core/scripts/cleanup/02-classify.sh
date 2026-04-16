#!/usr/bin/env bash
# Phase 2: Classification
# Reads the inventory, writes TRIAGE.md with GREEN/YELLOW/RED/BLUE tags.
# Edit TRIAGE.md before running Phase 3 — nothing is moved yet.

set -euo pipefail
ROOT="${SCAN_ROOT:-/root}"
TRIAGE="$ROOT/gpe-core/evolution/TRIAGE.md"

cat > "$TRIAGE" << 'TRIAGE_TEMPLATE'
# TRIAGE.md
# Review this file BEFORE running 03-migrate.sh
# Change status tags as needed. Nothing is touched until you run migrate.
#
# Status tags:
#   KEEP    = stays where it is, no change
#   MOVE    = relocate to new GPE architecture path
#   ARCHIVE = move to /root/_archive/ (inactive but keep)
#   TRASH   = move to /root/_trash/ (delete after 48h review)

## Target Architecture

```
/root/
├── gpe-core/          ← GPE OS (routing, briefs, registry, evolution)
├── brain/             ← Knowledge center (docs, context, research)
│   ├── legal/
│   ├── trading/
│   └── empire/
├── ops/               ← Active tools, bots, scripts, Docker
│   ├── bots/
│   ├── scripts/
│   └── docker/
├── projects/          ← Active projects with their own structure
├── _archive/          ← Museum (inactive but historically relevant)
└── _trash/            ← Holding zone before deletion (48h)
```

## Classification Table
# Edit the STATUS column. Leave PATH unchanged.
# Add notes in the NOTES column.

| STATUS | PATH | SIZE | LAST MODIFIED | NOTES |
|--------|------|------|---------------|-------|
TRIAGE_TEMPLATE

# Auto-populate from actual directories
echo "" >> "$TRIAGE"
find "$ROOT" -maxdepth 2 -not -path "*/.git/*" -not -path "*/node_modules/*" \
  2>/dev/null | sort | while read -r path; do
  size=$(du -sh "$path" 2>/dev/null | cut -f1 || echo "?")
  mtime=$(stat -c '%y' "$path" 2>/dev/null | cut -d' ' -f1 || echo "?")
  name=$(basename "$path")
  # Auto-suggest status based on name patterns
  status="KEEP"
  [[ "$name" =~ ^(backup|bak|old|tmp|temp|test|\.DS_Store) ]] && status="TRASH"
  [[ "$name" =~ ^(_archive|archive) ]] && status="ARCHIVE"
  [[ "$name" =~ ^(gpe-core) ]] && status="KEEP"
  echo "| $status | $path | $size | $mtime | |" >> "$TRIAGE"
done

echo ""
echo "TRIAGE written to: $TRIAGE"
echo ""
echo "IMPORTANT: Review and edit $TRIAGE before proceeding."
echo "When ready: bash gpe-core/scripts/cleanup/03-migrate.sh"
