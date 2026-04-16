# SKILL_INDEX.md
# GPE CORE - MASTER SKILL INVENTORY

**System Version:** GPE Core v1.1
**Last Updated:** 2026-04-16
**Total Active Skills:** 18

---

## Domain: Legal

| Skill Name | Path | Status | Resolver Trigger |
| :--- | :--- | :--- | :--- |
| **legal-opponent** | `fort-knox/.../legal-opponent/SKILL.md` | active | "analyze opponent", "gegnerverhalten" |
| **legal-settlement** | `fort-knox/.../legal-settlement/SKILL.md` | active | "settlement strategy", "vergleich bewerten" |
| **legal-claims** | `fort-knox/.../legal-claims/SKILL.md` | active | "claims matrix", "forderungsliste" |
| **legal-evidence** | `fort-knox/.../legal-evidence/SKILL.md` | active | "evidence map", "exhibit index" |
| **legal-warroom** | `fort-knox/.../legal-warroom/SKILL.md` | active | "coordinate legal", "legal pipeline" |
| **legal-consistency** | `fort-knox/.../legal-consistency/SKILL.md` | active | "check contradictions", "konsistenzprüfung" |

---

## Domain: Trading

| Skill Name | Path | Status | Resolver Trigger |
| :--- | :--- | :--- | :--- |
| **risk-monitor** | `gpe-core/skills/trading/risk-monitor/SKILL.md` | active | "risk check", "bot status", "1% check" |

---

## Domain: Empire / Revenue

| Skill Name | Path | Status | Resolver Trigger |
| :--- | :--- | :--- | :--- |
| **revenue-audit** | `gpe-core/skills/empire/revenue-audit/SKILL.md` | active | "revenue audit", "empire status", "was verdienen wir" |
| **sales-leadgen** | `fort-knox/.../sales-leadgen/SKILL.md` | active | "lead generation", "sales pipeline" |

---

## Domain: Evolution (Self-Improvement)

| Skill Name | Path | Status | Resolver Trigger |
| :--- | :--- | :--- | :--- |
| **evolution-loop** | `gpe-core/skills/evolution/evolution-loop/SKILL.md` | active | "run evolution loop", "system verbessern" |
| **repo-scout** | `gpe-core/skills/evolution/repo-scout/SKILL.md` | active | "scout repos", "neue repos finden" |
| **repo-analyzer** | `gpe-core/skills/evolution/repo-analyzer/SKILL.md` | active | "analyze repo", "repo analysieren" |
| **self-patcher** | `gpe-core/skills/evolution/self-patcher/SKILL.md` | active | "self patch", "fehler beheben" |

---

## Domain: System

| Skill Name | Path | Status | Resolver Trigger |
| :--- | :--- | :--- | :--- |
| **nucleus** | `fort-knox/.../nucleus/SKILL.md` | active | "system orchestration", "nucleus" |
| **data-ops** | `fort-knox/.../data-ops/SKILL.md` | active | "normalize data", "ingest raw files" |
| **system-audit** | `/root/.claude/skills/system-audit/SKILL.md` | active | "reachability audit", "audit skills" |

---

## Dark Skills (Unreachable — Needs Mapping)

| Skill Name | Known Path | Domain | Priority |
| :--- | :--- | :--- | :--- |
| *(Populated via repo-scout and system-audit results)* | — | — | — |

---

## Skill Status Legend

| Status | Meaning |
| :--- | :--- |
| **active** | Explicit resolver trigger, fully reachable |
| **dark** | Exists but no resolver trigger (unreachable by default) |
| **deprecated** | No longer in use |
| **planned** | Defined but not yet implemented |
