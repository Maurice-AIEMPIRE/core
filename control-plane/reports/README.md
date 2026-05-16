# Reports — Status-Outputs des Kerns

> **Wer schreibt hier:** Primär Hermes (Goal-Done-Reports, Daily Summary)
> Sekundär: Jarvis (Memory-Snapshots), Harvey (Sales/Legal-Reports)
> OpenClaw schreibt eigene Skill-Logs unter `/openclaw/workspace/`.

---

## Verzeichnis-Layout (Phase 2+)

```
reports/
├── README.md                              ← hier
├── daily/
│   └── {YYYY-MM-DD}_summary.md            ← täglich 22:00 (Hermes)
├── monthly/
│   └── {YYYY-MM}_empire.md                ← Revenue-Audit (Harvey)
├── sales/
│   └── {YYYY-W##}_weekly.md               ← Weekly Sales (Harvey, Montag)
├── verifier/
│   └── {goal_id}/{vrun_id}.yaml           ← Verifier-Runs (Hermes)
├── monitor/
│   └── {monitor_id}.json                  ← Periodische Monitore (OpenClaw)
├── legal/
│   └── {case_id}/{ts}_review.md           ← Legal-Reviews (Harvey)
├── research/
│   └── {goal_id}_research.md              ← Research-Goals (OpenClaw via Jarvis)
└── audit/
    └── CORE_CONSOLIDATION_*.md            ← Audit-Snapshots (manuell)
```

---

## Report-Format-Standard

Jeder Report hat oben:

```yaml
---
type: <daily|monthly|sales|verifier|monitor|legal|research|audit>
generated_at: <ISO 8601>
owner_agent: <jarvis|hermes|openclaw|harvey>
goal_id: <ulid>     # optional
period:
  from: <ISO>
  to: <ISO>
---
```

Body in Markdown.

---

## Aktuelle Reports

Status: **leer** — Phase 1 ist nur Setup.

In Phase 2 wird Hermes anfangen, automatisch Daily Summary zu schreiben (22:00 lokale Zeit).

---

## Wer darf was lesen

| Report-Typ      | Maurice | Jarvis | Hermes | OpenClaw | Harvey |
|-----------------|:-------:|:------:|:------:|:--------:|:------:|
| daily/          |   ✅    |   ✅   |   ✅   |    ❌    |   ❌   |
| monthly/        |   ✅    |   ✅   |   ✅   |    ❌    |   ✅   |
| sales/          |   ✅    |   ✅   |   ✅   |    ❌    |   ✅   |
| verifier/       |   ✅    |   ✅   |   ✅   |    ✅    |   ✅   |
| monitor/        |   ✅    |   ✅   |   ✅   |    ✅    |   ❌   |
| legal/          |   ✅    |   ✅   |   ✅   |    ❌    |   ✅   |
| research/       |   ✅    |   ✅   |   ✅   |    ✅    |   ❌   |
| audit/          |   ✅    |   ✅   |   ✅   |    ❌    |   ❌   |
