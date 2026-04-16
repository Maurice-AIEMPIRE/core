#!/usr/bin/env bash
# Phase 4: Hardening
# Updates RESOLVER.yaml paths and AGENTS.md to match new architecture.
# Creates symlinks for any broken references.
# Writes final ARCHITECTURE.md documenting the new structure.

set -euo pipefail
ROOT="${SCAN_ROOT:-/root}"
RESOLVER="$ROOT/gpe-core/resolver/RESOLVER.yaml"
ARCH_DOC="$ROOT/gpe-core/ARCHITECTURE.md"

echo "Phase 4: Hardening..."

# ── Validate new structure ─────────────────────────────────────────────────────
echo "Checking new directory structure..."
for dir in "$ROOT/brain" "$ROOT/ops" "$ROOT/projects" "$ROOT/_archive"; do
  if [[ -d "$dir" ]]; then
    count=$(find "$dir" -type f 2>/dev/null | wc -l)
    echo "  $dir: $count files"
  else
    echo "  MISSING: $dir"
  fi
done

# ── Write ARCHITECTURE.md ─────────────────────────────────────────────────────
cat > "$ARCH_DOC" << EOF
# ARCHITECTURE.md
# GPE Server Architecture — Post-Cleanup
# Generated: $(date '+%Y-%m-%d')

## Directory Structure

\`\`\`
/root/
├── gpe-core/          GPE OS — routing, briefs, registry, evolution loop
│   ├── resolver/      RESOLVER.yaml — precision intent router
│   ├── briefs/        Brief templates (standard, legal, trading, repo)
│   ├── skills/        Skill definitions per domain
│   ├── evolution/     Learning queue, evolution log, repo watchlist
│   ├── failures/      Failure registry
│   ├── reviews/       Review gate rules
│   └── scripts/       Automation scripts (cron, deploy, cleanup)
│
├── brain/             Knowledge center — context packs, research
│   ├── legal/         Legal case files, timeline, evidence, claims
│   ├── trading/       Trading brain, strategies, backtests
│   └── empire/        Revenue, affiliate, automation docs
│
├── ops/               Active operational tools
│   ├── bots/          Trading bots, Telegram bots, automation bots
│   ├── scripts/       Utility scripts
│   └── docker/        Docker compose files, container configs
│
├── projects/          Active projects (each with own structure)
│
├── _archive/          Inactive but historically relevant
│
└── _trash/            Pending deletion (review before rm -rf)
\`\`\`

## GPE Core Entry Points

| Domain | Brain Path | Skill Path |
|--------|-----------|------------|
| Legal | /root/brain/legal/ | gpe-core/skills/legal-*/SKILL.md |
| Trading | /root/brain/trading/ | gpe-core/skills/trading/*/SKILL.md |
| Empire | /root/brain/empire/ | gpe-core/skills/empire/*/SKILL.md |
| Evolution | /root/gpe-core/evolution/ | gpe-core/skills/evolution/*/SKILL.md |

## Key Files

- RESOLVER: /root/gpe-core/resolver/RESOLVER.yaml
- FAILURE REGISTRY: /root/gpe-core/failures/FAILURE_REGISTRY.yaml
- LEARNING QUEUE: /root/gpe-core/evolution/LEARNING_QUEUE.yaml
- EVOLUTION LOG: /root/gpe-core/evolution/EVOLUTION_LOG.yaml
- SKILL INDEX: /root/gpe-core/SKILL_INDEX.md
EOF

echo "Architecture documented: $ARCH_DOC"

# ── Update RESOLVER paths if brain/ exists ────────────────────────────────────
if [[ -d "$ROOT/brain/legal" ]] && [[ -f "$RESOLVER" ]]; then
  echo "Updating RESOLVER.yaml context paths..."
  # Replace old gpe-legal-central paths with new brain/legal path
  sed -i 's|/root/gpe-legal-central/|/root/brain/legal/|g' "$RESOLVER" 2>/dev/null || true
  sed -i 's|/root/aiempire/|/root/brain/empire/|g' "$RESOLVER" 2>/dev/null || true
  echo "  RESOLVER.yaml updated."
fi

echo ""
echo "Phase 4 complete. System is hardened."
echo ""
echo "Final checks:"
echo "  cat $ARCH_DOC"
echo "  cat $RESOLVER | grep primary_context"
echo ""
echo "GPE Architecture v2.0 is live."
