import numpy as np
from typing import Tuple, List

def kl_divergence(p: np.ndarray, q: np.ndarray) -> float:
    epsilon = 1e-10
    p = np.clip(p, epsilon, 1)
    q = np.clip(q, epsilon, 1)
    return float(np.sum(p * np.log(p / q)))

def detect_mispricing(p_true: np.ndarray, p_market: np.ndarray, threshold: float = 0.02) -> Tuple[bool, float, int]:
    divergence = kl_divergence(p_true, p_market)
    if divergence > threshold:
        best_idx = int(np.argmax(p_true - p_market))
        return True, divergence, best_idx
    return False, divergence, -1

def find_correlated_arbitrage(markets: List[dict]) -> List[dict]:
    opportunities = []
    for m in markets:
        if "complement_price" in m:
            total = m["yes_price"] + m["no_price"]
            if abs(total - 1.0) > 0.03:
                opportunities.append({
                    "market_id": m["id"],
                    "type": "complement_arb",
                    "deviation": total - 1.0
                })
    return opportunities
