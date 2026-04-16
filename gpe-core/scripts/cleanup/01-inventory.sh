#!/usr/bin/env bash
# Phase 1: Grand Inventory
# Run on your Hetzner server as root.
# Scans /root, reports sizes, ages, structure — no changes made.

set -euo pipefail
ROOT="${SCAN_ROOT:-/root}"
OUT="$ROOT/gpe-core/evolution/SYSTEM_INVENTORY.md"
mkdir -p "$(dirname "$OUT")"

echo "# SYSTEM INVENTORY" > "$OUT"
echo "Generated: $(date '+%Y-%m-%d %H:%M')" >> "$OUT"
echo "" >> "$OUT"

# ── Top-level structure ───────────────────────────────────────────────────────
echo "## Top-Level Directories" >> "$OUT"
echo '```' >> "$OUT"
du -sh "$ROOT"/*/  2>/dev/null | sort -rh >> "$OUT" || true
echo '```' >> "$OUT"
echo "" >> "$OUT"

# ── File counts per dir ───────────────────────────────────────────────────────
echo "## File Counts" >> "$OUT"
echo '```' >> "$OUT"
find "$ROOT" -maxdepth 2 -type d 2>/dev/null | while read -r dir; do
  count=$(find "$dir" -maxdepth 1 -type f 2>/dev/null | wc -l)
  [[ $count -gt 0 ]] && printf "%-6s %s\n" "$count" "$dir"
done | sort -rn >> "$OUT"
echo '```' >> "$OUT"
echo "" >> "$OUT"

# ── Large files (> 10MB) ──────────────────────────────────────────────────────
echo "## Large Files (> 10MB)" >> "$OUT"
echo '```' >> "$OUT"
find "$ROOT" -type f -size +10M 2>/dev/null \
  -not -path "*/\.*" \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  | xargs du -sh 2>/dev/null | sort -rh | head -30 >> "$OUT" || true
echo '```' >> "$OUT"
echo "" >> "$OUT"

# ── Old files (not touched in 90+ days) ──────────────────────────────────────
echo "## Stale Files (not modified in 90+ days)" >> "$OUT"
echo '```' >> "$OUT"
find "$ROOT" -maxdepth 4 -type f -mtime +90 2>/dev/null \
  -not -path "*/.git/*" \
  -not -path "*/node_modules/*" \
  | head -50 >> "$OUT" || true
echo '```' >> "$OUT"
echo "" >> "$OUT"

# ── Duplicate directory names (shadow copies) ─────────────────────────────────
echo "## Potential Duplicate Directories" >> "$OUT"
echo '```' >> "$OUT"
find "$ROOT" -maxdepth 5 -type d 2>/dev/null \
  -not -path "*/.git/*" \
  -not -path "*/node_modules/*" \
  | sed 's|.*/||' | sort | uniq -d >> "$OUT" || true
echo '```' >> "$OUT"
echo "" >> "$OUT"

# ── Active cron jobs ──────────────────────────────────────────────────────────
echo "## Active Cron Jobs" >> "$OUT"
echo '```' >> "$OUT"
cat /etc/cron.d/* 2>/dev/null | grep -v "^#" | grep -v "^$" >> "$OUT" || true
crontab -l 2>/dev/null >> "$OUT" || true
echo '```' >> "$OUT"
echo "" >> "$OUT"

# ── Running processes (relevant) ─────────────────────────────────────────────
echo "## Running Processes (non-system)" >> "$OUT"
echo '```' >> "$OUT"
ps aux 2>/dev/null | grep -vE "^(root\s+[0-9]+\s.*\[|USER)" \
  | awk '$3>0.1 || $4>0.1 {print}' | head -20 >> "$OUT" || true
echo '```' >> "$OUT"

echo ""
echo "Inventory written to: $OUT"
echo "Review it, then run: bash gpe-core/scripts/cleanup/02-classify.sh"
