# REVIEW_GATE_RULES.md
# GPE CORE - QUALITY REVIEW GATES
# No high-stakes output is delivered without passing these gates.

## 1. General Gate (All Domains)

- [ ] **Decision-Ready:** Does the output recommend a specific action, or does it just "describe" the problem?
- [ ] **Evidence-Backed:** Are all claims backed by provided context (not AI training data)?
- [ ] **No Hallucinations:** Are there zero fabricated names, dates, figures, or citations?
- [ ] **Gaps Flagged:** Are all evidence gaps explicitly marked as `[EVIDENCE GAP]` or `[UNVERIFIED]`?
- [ ] **Format Correct:** Does the output match the format specified in the Brief?

**Pass Threshold:** ALL 5 checks must be YES. Any NO = return to execution for revision.

---

## 2. Legal Gate (Legal Domain Only)

- [ ] **Citation Standard:** Every factual claim has `[Source: FILE.md, Section X]`
- [ ] **Timeline Cross-Check:** All dates verified against the master timeline
- [ ] **Contradiction Audit:** All inter-document contradictions explicitly flagged
- [ ] **Cold Logic:** Zero emotional or advocacy language
- [ ] **Actionable:** A qualified attorney could act on this output without further research

**Pass Threshold:** ALL 5 checks must be YES.

---

## 3. Trading Gate (Trading Domain Only)

- [ ] **1% Mandate:** Every active bot's risk-per-trade is confirmed ≤ 1%
- [ ] **LIVE vs PAPER:** Status is unambiguous for every bot
- [ ] **PnL Citation:** Every performance figure cites a source log and date range
- [ ] **Violation Flags:** All risk mandate violations marked with severity (HIGH/MEDIUM/LOW)
- [ ] **No Rounding:** All risk figures are precise, not estimated

**Pass Threshold:** ALL 5 checks must be YES.

---

## 4. Gate Failure Protocol

If any gate check fails:
1. Log the failure in `FAILURE_REGISTRY.yaml` with type `review_gate_failure`
2. Return the output to the executing skill with specific failed checks noted
3. Re-execute with the failed checks as explicit constraints
4. Do NOT deliver the output to the user until all gates pass
