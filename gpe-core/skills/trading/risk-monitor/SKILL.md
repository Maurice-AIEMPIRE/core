# SKILL: risk-monitor
# GPE Domain: Trading
# Purpose: Real-time audit of all active bots — 1% mandate, LIVE vs PAPER, drawdown.
# Trigger: "risk check", "bot status", "1% check", "trading audit", "risiko prüfen"

## Mission

The #1 risk in trading is not a bad trade — it's a silent failure.
Thinking a bot is PAPER when it's LIVE. Risk creeping above 1%. Drawdown ignored.
risk-monitor is the early warning system that catches these before they cost money.

## Execution Steps

1. **Load Context**
   - Read: `/root/TRADING_BRAIN.md`
   - Read: All bot configuration files
   - Read: Latest trade logs (last 30 days)
   - Build: Bot inventory table (Name | Mode | Market | Risk% | Last Trade)

2. **1% Risk Mandate Audit**
   For each bot:
   - Extract: position size calculation method
   - Calculate: risk per trade as % of account
   - Flag: Any bot where risk > 1% as [VIOLATION — CRITICAL]
   - Flag: Any bot where risk calculation is unclear as [STATUS UNKNOWN]

3. **LIVE vs PAPER Classification**
   - Confirm LIVE status by checking: API keys active, real exchange connection
   - Confirm PAPER status by checking: paper trading flag, simulated exchange
   - Any bot where status cannot be confirmed: [STATUS UNKNOWN — DO NOT RUN]

4. **Drawdown Analysis**
   - Calculate: Max drawdown per bot (last 30 days)
   - Calculate: Current open position drawdown
   - Flag: Any drawdown > 10% as [DRAWDOWN WARNING]
   - Flag: Any drawdown > 20% as [DRAWDOWN CRITICAL — PAUSE BOT]

5. **Generate Risk Dashboard**
   ```
   RISK DASHBOARD — [DATE]
   ========================
   LIVE Bots: X  |  PAPER Bots: Y  |  STATUS UNKNOWN: Z
   1% Mandate: X PASS / Y FAIL / Z UNKNOWN
   Max Drawdown: X% (Bot: [name])
   CRITICAL Violations: [list]
   ```

## Review Gate

- [ ] Every bot has confirmed LIVE or PAPER status (none UNKNOWN unless flagged)
- [ ] Every 1% violation has severity level
- [ ] All PnL figures cite source log and date range
- [ ] Recommended actions are specific (not "review the bot")
