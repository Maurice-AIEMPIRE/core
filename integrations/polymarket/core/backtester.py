import numpy as np
import pandas as pd
from typing import List, Dict, Tuple
from datetime import datetime

def run_backtest(trades: List[Dict], initial_capital: float = 600.0) -> Dict:
    capital = initial_capital
    equity_curve = [capital]
    wins = 0
    losses = 0

    for trade in trades:
        pnl = trade.get("pnl", 0)
        capital += pnl
        equity_curve.append(capital)
        if pnl > 0:
            wins += 1
        elif pnl < 0:
            losses += 1

    equity = np.array(equity_curve)
    returns = np.diff(equity) / equity[:-1]

    max_dd = 0.0
    peak = equity[0]
    for v in equity:
        if v > peak:
            peak = v
        dd = (peak - v) / peak
        if dd > max_dd:
            max_dd = dd

    sharpe = float(np.mean(returns) / (np.std(returns) + 1e-10)) * np.sqrt(365 * 24 * 4)  # 15-min cycles
    total_trades = wins + losses
    win_rate = wins / total_trades if total_trades > 0 else 0

    return {
        "initial_capital": initial_capital,
        "final_capital": float(capital),
        "total_return_pct": float((capital - initial_capital) / initial_capital * 100),
        "sharpe_ratio": sharpe,
        "max_drawdown_pct": float(max_dd * 100),
        "win_rate": win_rate,
        "total_trades": total_trades,
        "equity_curve": equity_curve,
    }

def monte_carlo_simulation(win_rate: float, avg_win: float, avg_loss: float,
                            capital: float, n_trades: int = 100, n_simulations: int = 1000) -> Dict:
    results = []
    for _ in range(n_simulations):
        cap = capital
        for _ in range(n_trades):
            if np.random.random() < win_rate:
                cap += avg_win
            else:
                cap -= avg_loss
        results.append(cap)

    results = np.array(results)
    return {
        "median_capital": float(np.median(results)),
        "p10_capital": float(np.percentile(results, 10)),
        "p90_capital": float(np.percentile(results, 90)),
        "ruin_probability": float(np.mean(results <= 0)),
    }
