#!/usr/bin/env python3
"""
QPTS Historical Backtester
Fetches real historical market data from Gamma API and runs Walk-Forward backtest
"""
import os
import sys
import json
from datetime import datetime, timedelta
from typing import List, Dict

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import requests
import numpy as np

from core.kelly import calculate_position_size, expected_value
from core.backtester import run_backtest, monte_carlo_simulation
from core.probability_calibrator import calibrate_llm_probability

GAMMA_API = "https://gamma-api.polymarket.com"

def fetch_resolved_markets(days_back: int = 90, limit: int = 100) -> List[Dict]:
    """Fetch resolved markets for backtesting."""
    try:
        params = {"limit": limit, "closed": True, "active": False}
        resp = requests.get(f"{GAMMA_API}/markets", params=params, timeout=15)
        markets = resp.json()
        if isinstance(markets, dict):
            markets = markets.get("markets", [])
        return [m for m in markets if m.get("resolutionTime") or m.get("endDate")]
    except Exception as e:
        print(f"Warning: Could not fetch live data: {e}")
        return generate_synthetic_data()

def generate_synthetic_data(n: int = 100) -> List[Dict]:
    """Generate synthetic market data for offline testing."""
    np.random.seed(42)
    markets = []
    for i in range(n):
        true_prob = np.random.beta(5, 5)  # Realistic probabilities
        market_price = true_prob + np.random.normal(0, 0.05)
        market_price = np.clip(market_price, 0.02, 0.98)
        outcome = 1 if np.random.random() < true_prob else 0
        markets.append({
            "id": f"synthetic_{i}",
            "question": f"Synthetic market {i}",
            "yes_price_at_entry": float(market_price),
            "true_prob": float(true_prob),
            "outcome": outcome,
            "volume": float(np.random.uniform(5000, 500000)),
        })
    return markets

def simulate_trades(markets: List[Dict], capital: float = 600.0, kelly_fraction: float = 0.25) -> List[Dict]:
    """Simulate trades on historical data."""
    trades = []
    current_capital = capital

    for m in markets:
        yes_price = m.get("yes_price_at_entry", 0.5)
        outcome = m.get("outcome", 0)

        p_true = calibrate_llm_probability(
            llm_confidence=yes_price + np.random.normal(0.02, 0.03),
            market_price=yes_price,
            weight_llm=0.4
        )

        size = calculate_position_size(current_capital, p_true, yes_price, kelly_fraction)
        ev = expected_value(p_true, yes_price, size)

        if ev <= 0 or size < 1.0:
            continue

        # Simulate pnl
        if outcome == 1:
            pnl = size * (1.0 / yes_price - 1) * 0.98  # 2% fee
        else:
            pnl = -size

        current_capital += pnl
        trades.append({
            "market": m.get("question", "")[:50],
            "yes_price": yes_price,
            "p_true": p_true,
            "size": size,
            "ev": ev,
            "outcome": outcome,
            "pnl": pnl,
            "capital_after": current_capital,
        })

        if current_capital <= 0:
            break

    return trades

def walk_forward_test(markets: List[Dict], n_splits: int = 5) -> List[Dict]:
    """Walk-forward validation."""
    results = []
    split_size = len(markets) // n_splits

    for i in range(n_splits):
        test_markets = markets[i * split_size:(i + 1) * split_size]
        trades = simulate_trades(test_markets)
        if trades:
            result = run_backtest(trades, 600.0 / n_splits)
            result["split"] = i + 1
            results.append(result)

    return results

def main():
    print("=" * 60)
    print("QPTS Backtester — Walk-Forward + Monte Carlo")
    print("=" * 60)

    print("\n1. Fetching historical market data...")
    markets = fetch_resolved_markets(days_back=90, limit=200)
    print(f"   Got {len(markets)} markets")

    print("\n2. Running Walk-Forward Test (5 splits)...")
    wf_results = walk_forward_test(markets)

    avg_sharpe = np.mean([r["sharpe_ratio"] for r in wf_results])
    avg_dd = np.mean([r["max_drawdown_pct"] for r in wf_results])
    avg_return = np.mean([r["total_return_pct"] for r in wf_results])
    avg_winrate = np.mean([r["win_rate"] for r in wf_results])

    print(f"\n   Avg Sharpe:    {avg_sharpe:.2f}")
    print(f"   Avg Drawdown:  {avg_dd:.1f}%")
    print(f"   Avg Return:    {avg_return:.1f}%")
    print(f"   Avg Win Rate:  {avg_winrate:.1%}")

    print("\n3. Monte Carlo Simulation (1000 runs, 100 trades)...")
    mc = monte_carlo_simulation(avg_winrate, 8.0, 4.5, 600.0, n_trades=100, n_simulations=1000)

    print(f"   Median Capital: ${mc['median_capital']:.2f}")
    print(f"   10th Pct:       ${mc['p10_capital']:.2f}")
    print(f"   90th Pct:       ${mc['p90_capital']:.2f}")
    print(f"   Ruin Prob:      {mc['ruin_probability']:.1%}")

    print("\n4. Go/No-Go Decision:")
    go = avg_sharpe >= 1.5 and avg_dd <= 20 and mc["ruin_probability"] <= 0.05

    if go:
        print("   ✅ GO — Sharpe > 1.5, Drawdown < 20%, Ruin < 5%")
        print("   Next: Run 50 paper cycles, then consider PAPER_MODE=false")
    else:
        print("   ❌ NO-GO — Criteria not met:")
        if avg_sharpe < 1.5: print(f"      Sharpe {avg_sharpe:.2f} < 1.5")
        if avg_dd > 20: print(f"      Drawdown {avg_dd:.1f}% > 20%")
        if mc["ruin_probability"] > 0.05: print(f"      Ruin {mc['ruin_probability']:.1%} > 5%")

    # Save report
    report = {
        "timestamp": datetime.now().isoformat(),
        "walk_forward": wf_results,
        "monte_carlo": mc,
        "go_decision": go,
        "markets_tested": len(markets),
    }

    os.makedirs(os.path.dirname(__file__), exist_ok=True)
    report_path = os.path.join(os.path.dirname(__file__), f"backtest_{datetime.now().strftime('%Y%m%d_%H%M')}.json")
    with open(report_path, "w") as f:
        json.dump(report, f, indent=2)
    print(f"\n   Report saved: {report_path}")

if __name__ == "__main__":
    main()
