# Harvey — QPTS Trading Agent

Quantitative Polymarket Trading System integrated into the openclaw monorepo.

## Architecture
- LangGraph State Machine: Research → Analyze → Risk → Execute → Log
- Kelly Criterion sizing (Quarter-Kelly = 0.25x)
- KL-Divergence arbitrage detection
- Probability calibration (LLM + market prior blend)

## Quick Start
```bash
# Paper mode (safe, always start here)
/harvey-paper

# Run backtest
/harvey-backtest

# Check logs
/harvey-logs
```

## Safety Rules
1. Paper mode until 50+ cycles with Sharpe > 1.5
2. Max 5% capital per trade
3. Max 20% total exposure
4. Quarter-Kelly only
5. system_audit.sh before any live start

## Files
- `integrations/polymarket/main.py` — Main entry point
- `integrations/polymarket/core/` — Math modules (Kelly, Arbitrage, Calibration, Backtest)
- `integrations/polymarket/agents/` — Research, Analyst, Risk Manager
- `integrations/polymarket/tools/` — Polymarket client, News fetcher
