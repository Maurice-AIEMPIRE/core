import os
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from typing import Dict, Any, List

def risk_check(state: Dict[str, Any]) -> Dict[str, Any]:
    """Risk manager: validates trades against risk rules."""
    candidates = state.get("trade_candidates", [])
    capital = state["capital"]
    max_drawdown = state.get("max_drawdown", 0.20)

    approved_trades = []
    rejected = []
    total_exposure = 0

    for trade in candidates:
        size = trade["position_size"]
        reasons = []

        # Rule 1: Max 5% capital per trade
        if size / capital > 0.05:
            trade["position_size"] = round(capital * 0.05, 2)
            size = trade["position_size"]
            reasons.append("capped at 5% max")

        # Rule 2: Min size $1
        if size < 1.0:
            rejected.append({**trade, "reason": "size < $1 min"})
            continue

        # Rule 3: Total exposure max 20% capital
        if total_exposure + size > capital * 0.20:
            rejected.append({**trade, "reason": "max portfolio exposure reached"})
            continue

        # Rule 4: Only high EV trades
        if trade["expected_value"] <= 0:
            rejected.append({**trade, "reason": "EV <= 0"})
            continue

        total_exposure += size
        trade["risk_notes"] = reasons
        approved_trades.append(trade)

    state["approved_trades"] = approved_trades[:2]  # Max 2 trades per cycle
    state["rejected_trades"] = rejected
    state["total_exposure"] = total_exposure
    state["cycle_log"].append(
        f"[Risk] {len(approved_trades)} approved, {len(rejected)} rejected, "
        f"total exposure: ${total_exposure:.2f}"
    )
    return state
