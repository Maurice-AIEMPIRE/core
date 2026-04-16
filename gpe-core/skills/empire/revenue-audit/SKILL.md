# SKILL: revenue-audit
# GPE Domain: Empire
# Purpose: Track revenue streams, identify dead automations, surface top opportunities.
# Trigger: "revenue audit", "empire status", "was verdienen wir", "income check", "affiliate audit"

## Mission

Revenue without visibility is gambling.
revenue-audit turns the Empire into a dashboard:
What's generating money? What's dead? What's the next highest-leverage move?

## Execution Steps

1. **Load Context**
   - Read: `/root/aiempire/` directory structure
   - Read: Any revenue tracking files, affiliate dashboards, automation configs
   - Build: Revenue stream inventory (Stream | Type | Status | Monthly Revenue | Last Active)

2. **Stream Classification**
   For each revenue stream:
   | Type | Examples | Status Check |
   |------|----------|--------------|
   | Active | Affiliate commissions, bot revenue | Last transaction date |
   | Dormant | Set up but 0 revenue last 30 days | Last activity timestamp |
   | Dead | No activity last 90 days | Confirm and flag for removal/reactivation |
   | Pipeline | In progress, not yet live | Completion % and next action |

3. **Automation Health Check**
   - Which automations are running? (confirmed via logs/crons)
   - Which automations are broken? (error logs, no output)
   - Which automations have never run? (configured but untriggered)

4. **Opportunity Ranking**
   Rank ALL identified opportunities by:
   - Revenue potential (estimated monthly €/$ range)
   - Implementation effort (LOW/MEDIUM/HIGH)
   - Time to first revenue (days)
   Priority Score = (Revenue Potential × 0.5) + (Low Effort × 0.3) + (Speed × 0.2)

5. **Generate Empire Dashboard**
   ```
   EMPIRE STATUS — [DATE]
   ======================
   Active Streams: X | Monthly Revenue: €X
   Dormant Streams: X | Revenue at Risk: €X
   Dead Automations: X | Recovery Potential: €X
   Top Opportunity: [name] | Est. Revenue: €X/mo | Effort: LOW
   Next Action: [specific task]
   ```

## Review Gate

- [ ] Every revenue figure cites its source
- [ ] Every automation has confirmed status (running/broken/dormant)
- [ ] Top 3 opportunities are ranked with justification
- [ ] Next action is specific and immediately executable
