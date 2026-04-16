# SKILL: self-patcher
# GPE Domain: Evolution
# Purpose: Read FAILURE_REGISTRY + LEARNING_QUEUE and auto-generate patches.
# Trigger: "self patch", "fix failures", "selbst reparieren", "auto fix", "patch system"

## Mission

The GPE system cannot improve if failures are just logged and forgotten.
self-patcher closes the loop: read failures → diagnose root cause → generate fix → apply.
This is the "immune system" of GPE Core.

## Execution Steps

1. **Load Context**
   - Read: `gpe-core/failures/FAILURE_REGISTRY.yaml` (all open failures)
   - Read: `gpe-core/evolution/LEARNING_QUEUE.yaml` (approved improvements pending impl)
   - Read: `gpe-core/resolver/RESOLVER.yaml` (current routing state)
   - Read: `gpe-core/SKILL_INDEX.md` (active skills)

2. **Triage Open Failures**
   For each entry in FAILURE_REGISTRY with `status: open`:

   | Failure Type | Root Cause Pattern | Auto-Fix Action |
   |---|---|---|
   | `routing_error` | Trigger phrase missing in RESOLVER | Add trigger phrase to RESOLVER.yaml |
   | `skill_missing` | Skill in SKILL_INDEX but no SKILL.md | Create SKILL.md stub + add to LEARNING_QUEUE |
   | `hallucination` | Brief constraint too weak | Add specific constraint to relevant brief template |
   | `evidence_gap` | Context Pack incomplete | Update skill's Step 1 to load missing file |
   | `brief_incomplete` | Required field missing | Update brief template with required field |
   | `review_gate_failure` | Gate check not met | Strengthen the relevant gate rule |

3. **Process LEARNING_QUEUE (status: approved)**
   For each approved item in LEARNING_QUEUE:
   - Determine target file
   - Generate the specific change (new YAML entry, new SKILL.md section, etc.)
   - Apply change
   - Update item status to `implemented`
   - Log to EVOLUTION_LOG.yaml

4. **Generate Patch Report**
   - List: X failures patched, Y improvements applied
   - List: Files changed with before/after for each
   - Flag: Any failure that CANNOT be auto-patched (needs human decision)
   - Update FAILURE_REGISTRY: closed entries get `status: resolved`

5. **Post-Patch Validation**
   - Re-check: Does the RESOLVER now have triggers for previously failed intents?
   - Re-check: Do patched brief templates pass their own review gates?
   - Log result to EVOLUTION_LOG.yaml

## Hard Rules

- Never delete from FAILURE_REGISTRY — only update status
- Never apply a patch to a HIGH-priority skill without human approval flag
- If a patch touches RESOLVER.yaml, always validate that no existing routes break
- Every patch generates an EVOLUTION_LOG entry

## Review Gate

- [ ] Every open failure has either a patch applied or a [NEEDS HUMAN] flag
- [ ] No existing RESOLVER routes were broken by the patch
- [ ] EVOLUTION_LOG updated with all changes
- [ ] FAILURE_REGISTRY statuses updated (open → resolved)
