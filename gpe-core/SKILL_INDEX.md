# SKILL_INDEX.md
# GPE CORE - MASTER SKILL INVENTORY

**System Version:** GPE Core v1.0
**Last Updated:** 2026-04-16

## Active Skill Inventory

| Skill Name | Primary Path | Domain | Status | Resolver Trigger |
| :--- | :--- | :--- | :--- | :--- |
| **legal-opponent** | `fort-knox/icloud-sync/.claude/skills/legal-opponent/SKILL.md` | Legal | active | "analyze opponent", "gegnerverhalten" |
| **legal-settlement** | `fort-knox/icloud-sync/.claude/skills/legal-settlement/SKILL.md` | Legal | active | "settlement strategy", "vergleich bewerten" |
| **legal-claims** | `fort-knox/icloud-sync/.claude/skills/legal-claims/SKILL.md` | Legal | active | "claims matrix", "forderungsliste" |
| **legal-evidence** | `fort-knox/icloud-sync/.claude/skills/legal-evidence/SKILL.md` | Legal | active | "evidence map", "exhibit index" |
| **legal-warroom** | `fort-knox/icloud-sync/.claude/skills/legal-warroom/SKILL.md` | Legal | active | "coordinate legal", "legal pipeline" |
| **legal-consistency** | `fort-knox/icloud-sync/.claude/skills/legal-consistency/SKILL.md` | Legal | active | "check contradictions", "konsistenzprüfung" |
| **nucleus** | `fort-knox/icloud-sync/.claude/skills/nucleus/SKILL.md` | System | active | "system orchestration", "nucleus" |
| **data-ops** | `fort-knox/icloud-sync/.claude/skills/data-ops/SKILL.md` | Data | active | "normalize data", "ingest raw files" |
| **sales-leadgen** | `fort-knox/icloud-sync/.claude/skills/sales-leadgen/SKILL.md` | Empire | active | "lead generation", "sales pipeline" |
| **system-audit** | `/root/.claude/skills/system-audit/SKILL.md` | System | active | "reachability audit", "audit skills" |

## Dark Skills (No Resolver Trigger — Needs Mapping)

Skills that exist but have no explicit trigger in RESOLVER.yaml yet.
These must be mapped in the next patch cycle.

| Skill Name | Known Path | Domain | Priority to Map |
| :--- | :--- | :--- | :--- |
| *(To be populated via skill discovery audit)* | — | — | — |

## Skill Status Legend

- **active** — Has explicit resolver trigger, fully reachable
- **dark** — Exists but has no resolver trigger (unreachable by default)
- **deprecated** — No longer in use, pending removal
- **planned** — Defined but not yet implemented
