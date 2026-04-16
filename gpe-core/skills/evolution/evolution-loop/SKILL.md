# SKILL: evolution-loop
# GPE Domain: Evolution
# Purpose: The master orchestrator for the full self-improvement cycle.
# Trigger: "run evolution loop", "system verbessern", "selbst verbessern", "improve system", "evolution loop"

## Mission

This is the highest-level skill in GPE Core.
It orchestrates the entire self-improvement pipeline:
Scout → Analyze → Queue → Patch → Log → Evolve.

Run this weekly (or on-demand) to keep GPE ahead of the curve.

## The Full Evolution Loop

```
┌─────────────────────────────────────────────────────────────┐
│                    GPE EVOLUTION LOOP                        │
│                                                             │
│  1. SCOUT      repo-scout skill                             │
│     └─ Find new top repos per domain                        │
│     └─ Update REPO_WATCHLIST.yaml                           │
│                           │                                 │
│  2. ANALYZE    repo-analyzer skill (per new repo)           │
│     └─ Extract implementable insights                       │
│     └─ Write to LEARNING_QUEUE.yaml (status: discovered)   │
│                           │                                 │
│  3. VALIDATE   Human review checkpoint                      │
│     └─ Review LEARNING_QUEUE entries                        │
│     └─ Approve high-impact items (status: approved)         │
│     └─ Archive low-value items (status: archived)           │
│                           │                                 │
│  4. PATCH      self-patcher skill                           │
│     └─ Apply approved LEARNING_QUEUE items                  │
│     └─ Fix open FAILURE_REGISTRY entries                    │
│     └─ Update RESOLVER, SKILL_INDEX, brief templates        │
│                           │                                 │
│  5. LOG        evolution-loop (this skill)                  │
│     └─ Write EVOLUTION_LOG entry                            │
│     └─ Bump system version if major change                  │
│     └─ Commit all changes to git                            │
└─────────────────────────────────────────────────────────────┘
```

## Execution Steps

1. **Pre-Loop Check**
   - Read EVOLUTION_LOG.yaml → When was last loop? What version are we on?
   - Read FAILURE_REGISTRY.yaml → How many open failures?
   - Read LEARNING_QUEUE.yaml → How many items pending?
   - Decision: Full loop (weekly) or Quick loop (patch-only)?

2. **Full Loop (Weekly)**
   - Trigger `repo-scout` for each domain in REPO_WATCHLIST.yaml
   - For each NEW repo found: trigger `repo-analyzer`
   - Present LEARNING_QUEUE additions to user for validation
   - Trigger `self-patcher` on all approved items + open failures
   - Write EVOLUTION_LOG entry
   - Git commit all changes

3. **Quick Loop (On-demand / after failure)**
   - Skip Scout and Analyze
   - Go directly to `self-patcher`
   - Only process: open FAILURE_REGISTRY + approved LEARNING_QUEUE items
   - Write EVOLUTION_LOG entry

4. **Post-Loop Report**
   Format:
   ```
   GPE EVOLUTION LOOP — [DATE]
   ============================
   System Version: [old] → [new]
   New Repos Scouted: X
   Repos Analyzed: X
   Insights Discovered: X
   Improvements Applied: X
   Failures Resolved: X
   Failures Still Open: X (list)
   Next Scheduled Loop: [DATE]
   ```

## Loop Governance Rules

- **Human Checkpoint at Step 3 is MANDATORY** — the system never auto-applies without approval
- If 0 insights found in a domain: log `[DOMAIN_STAGNANT]` and widen search criteria
- If a patch breaks an existing skill: immediate rollback + log as CRITICAL failure
- Version bump rules: 10+ improvements = minor version bump (1.1 → 1.2), major rework = major bump (1.x → 2.0)

## Review Gate

- [ ] All 5 loop steps completed (or explicitly skipped with reason)
- [ ] Human approval obtained before self-patcher ran
- [ ] EVOLUTION_LOG updated with full loop summary
- [ ] Git commit created with descriptive message
- [ ] No existing GPE functionality broken
