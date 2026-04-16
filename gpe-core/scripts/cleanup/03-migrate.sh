#!/usr/bin/env bash
# Phase 3: Migration
# Reads TRIAGE.md and physically moves files to the new architecture.
# MOVE → target path, ARCHIVE → /root/_archive/, TRASH → /root/_trash/
# Nothing is permanently deleted. _trash/ is reviewed manually.

set -euo pipefail
ROOT="${SCAN_ROOT:-/root}"
TRIAGE="$ROOT/gpe-core/evolution/TRIAGE.md"
LOG="$ROOT/gpe-core/evolution/MIGRATION_LOG.md"
DRY_RUN="${DRY_RUN:-true}"   # Set DRY_RUN=false to actually move files

[[ ! -f "$TRIAGE" ]] && { echo "Run 02-classify.sh first."; exit 1; }

# Safety check
if [[ "$DRY_RUN" == "true" ]]; then
  echo "DRY RUN MODE — no files will be moved."
  echo "Set DRY_RUN=false to execute."
  echo ""
fi

mkdir -p "$ROOT/_archive" "$ROOT/_trash" "$ROOT/brain/legal" \
         "$ROOT/brain/trading" "$ROOT/brain/empire" \
         "$ROOT/ops/bots" "$ROOT/ops/scripts" "$ROOT/ops/docker" \
         "$ROOT/projects"

echo "# MIGRATION LOG" > "$LOG"
echo "Date: $(date '+%Y-%m-%d %H:%M')" >> "$LOG"
echo "DRY_RUN: $DRY_RUN" >> "$LOG"
echo "" >> "$LOG"

moved=0; archived=0; trashed=0; skipped=0

# Parse TRIAGE.md table rows
while IFS='|' read -r _ status path _ _ notes _; do
  status=$(echo "$status" | xargs)
  path=$(echo "$path" | xargs)
  [[ -z "$path" || "$path" == "PATH" || ! -e "$path" ]] && continue

  case "$status" in
    MOVE)
      # Determine target from path pattern
      target=""
      [[ "$path" =~ (legal|court|klage|gericht) ]] && target="$ROOT/brain/legal/"
      [[ "$path" =~ (trading|bot|xrp|crypto) ]]    && target="$ROOT/ops/bots/"
      [[ "$path" =~ (empire|revenue|affiliate) ]]   && target="$ROOT/brain/empire/"
      [[ "$path" =~ (script|\.sh) ]]                && target="$ROOT/ops/scripts/"
      [[ "$path" =~ (docker|compose) ]]             && target="$ROOT/ops/docker/"
      if [[ -n "$target" ]]; then
        echo "MOVE: $path → $target" | tee -a "$LOG"
        [[ "$DRY_RUN" == "false" ]] && mv "$path" "$target" && ((moved++))
      else
        echo "MOVE (no target pattern): $path — manual review needed" | tee -a "$LOG"
        ((skipped++))
      fi
      ;;
    ARCHIVE)
      echo "ARCHIVE: $path → $ROOT/_archive/" | tee -a "$LOG"
      [[ "$DRY_RUN" == "false" ]] && mv "$path" "$ROOT/_archive/" && ((archived++))
      ;;
    TRASH)
      echo "TRASH: $path → $ROOT/_trash/" | tee -a "$LOG"
      [[ "$DRY_RUN" == "false" ]] && mv "$path" "$ROOT/_trash/" && ((trashed++))
      ;;
    KEEP)
      ((skipped++))
      ;;
  esac
done < <(grep "^|" "$TRIAGE")

echo "" | tee -a "$LOG"
echo "Summary: moved=$moved archived=$archived trashed=$trashed skipped=$skipped" | tee -a "$LOG"
echo ""
echo "When satisfied, run Phase 4:"
echo "  bash gpe-core/scripts/cleanup/04-harden.sh"
echo ""
echo "To permanently delete _trash (IRREVERSIBLE):"
echo "  rm -rf $ROOT/_trash/*"
