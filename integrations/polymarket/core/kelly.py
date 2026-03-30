import numpy as np

def full_kelly(p_true: float, p_market: float) -> float:
    if p_market >= 1.0 or p_market <= 0.0 or p_true <= p_market:
        return 0.0
    return (p_true - p_market) / (1.0 - p_market)

def fractional_kelly(p_true: float, p_market: float, fraction: float = 0.25) -> float:
    return fraction * full_kelly(p_true, p_market)

def calculate_position_size(capital: float, p_true: float, p_market: float, fraction: float = 0.25) -> float:
    f = fractional_kelly(p_true, p_market, fraction)
    return capital * f

def expected_value(p_true: float, p_market: float, stake: float, fee: float = 0.02) -> float:
    payout = stake / p_market
    ev = p_true * (payout - stake) - (1 - p_true) * stake - fee * stake
    return ev
