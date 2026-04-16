# SKILL: repo-scout
# GPE Domain: Evolution
# Purpose: Discover and rank GitHub repos for each GPE domain.
# Trigger: "scout repos", "find best repos", "github scout", "neue repos finden"

## Mission

Search GitHub for the highest-value repositories in a given domain.
Rank them by: Stars + Recent Activity + Relevance to GPE target skill.
Output a ranked watchlist update for REPO_WATCHLIST.yaml.

## Execution Steps

1. **Load Context**
   - Read: `gpe-core/evolution/REPO_WATCHLIST.yaml` (existing watchlist)
   - Read: `gpe-core/SKILL_INDEX.md` (what skills exist and need improvement)
   - Identify: Which domain is being scouted? Which skill is the target?

2. **Search Strategy**
   - Use GitHub search with these query patterns per domain:
     - `ai_agents`: `topic:ai-agent stars:>500 pushed:>2025-01-01`
     - `legal_tech`: `topic:legal-tech OR legal-nlp stars:>200`
     - `trading`: `topic:algorithmic-trading stars:>500 pushed:>2025-01-01`
     - `automation`: `topic:workflow-automation stars:>1000`
     - `self_improvement`: `topic:self-improving-agent OR reflexion stars:>100`
   - Filter: Must have README, active commits in last 6 months, open license

3. **Ranking Criteria**
   - Stars (weight: 30%)
   - Commits in last 90 days (weight: 25%)
   - Relevance to GPE target skill (weight: 35%)
   - License permissiveness (weight: 10%)

4. **Deduplication**
   - Cross-check against existing REPO_WATCHLIST.yaml
   - Flag repos already in watchlist as [ALREADY TRACKED]
   - Only surface NEW repos not yet in the list

5. **Output**
   - Ranked list of top 5 NEW repos per domain
   - Pre-formatted REPO_WATCHLIST.yaml entries (ready to paste)
   - Recommendation: Which repo to analyze FIRST and why

## Review Gate

Before delivering output:
- [ ] At least 3 new repos found per domain
- [ ] Every repo has stars > threshold for its domain
- [ ] No duplicates with existing REPO_WATCHLIST.yaml
- [ ] Relevance score justified (not just "it's about AI")
