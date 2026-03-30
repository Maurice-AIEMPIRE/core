import os
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from typing import Dict, Any
from core.kelly import full_kelly, calculate_position_size, expected_value
from core.arbitrage_detector import detect_mispricing
from core.probability_calibrator import calibrate_llm_probability
import numpy as np

def analyze_markets(state: Dict[str, Any]) -> Dict[str, Any]:
    """Analyst: calculates edge, Kelly sizing, EV for each market."""
    markets = state.get("researched_markets", [])
    capital = state["capital"]
    kelly_fraction = state.get("kelly_fraction", 0.25)

    trade_candidates = []

    for m in markets:
        yes_price = m["yes_price"]

        # Probability estimation (simplified - in production use LLM + calibration)
        # Use news sentiment + market price as proxy
        news = m.get("news_summary", "")

        # Probability estimation: use market structure as signal
        # Markets far from 0.5 have higher mean-reversion tendency
        # Edge heuristic: markets with extreme prices (< 0.15 or > 0.85)
        # are often mispriced vs true probability
        edge_score = m.get("edge_score", 0)

        if news and ("likely" in news.lower() or "confirm" in news.lower()):
            adjustment = 0.06
        elif news and ("unlikely" in news.lower() or "fail" in news.lower()):
            adjustment = -0.06
        elif yes_price < 0.15:
            # Cheap YES — slight upward bias (underdog effect)
            adjustment = 0.03
        elif yes_price > 0.85:
            # Expensive YES — slight downward bias (overpricing effect)
            adjustment = -0.03
        elif 0.45 <= yes_price <= 0.55:
            # Near 50/50 — slight positive signal for YES (volume attractor)
            adjustment = 0.04
        else:
            adjustment = 0.02  # Small positive default

        p_true = calibrate_llm_probability(
            llm_confidence=yes_price + adjustment,
            market_price=yes_price,
            weight_llm=0.5
        )

        # Kelly + EV calculation
        kelly_f = full_kelly(p_true, yes_price)
        size = calculate_position_size(capital, p_true, yes_price, kelly_fraction)
        ev = expected_value(p_true, yes_price, size)

        # Only proceed if EV > 0 and Kelly > 0.005 (min edge, lowered for paper mode)
        if ev > 0 and kelly_f > 0.005 and size > 1.0:
            # Arbitrage check
            p_vec = np.array([p_true, 1 - p_true])
            q_vec = np.array([yes_price, 1 - yes_price])
            has_arb, divergence, _ = detect_mispricing(p_vec, q_vec, threshold=0.02)

            trade_candidates.append({
                **m,
                "p_true": p_true,
                "kelly_fraction": kelly_f,
                "position_size": round(size, 2),
                "expected_value": round(ev, 4),
                "kl_divergence": round(divergence, 4),
                "has_arb": has_arb,
                "side": "YES" if p_true > yes_price else "NO",
                "token_price": yes_price if p_true > yes_price else m["no_price"],
            })

    # Sort by EV
    trade_candidates.sort(key=lambda x: x["expected_value"], reverse=True)

    state["trade_candidates"] = trade_candidates
    state["cycle_log"].append(f"[Analyst] {len(trade_candidates)} trade candidates found")
    return state
