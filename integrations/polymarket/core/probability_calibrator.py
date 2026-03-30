import numpy as np
from typing import List

def platt_scaling(raw_score: float, a: float = 1.0, b: float = 0.0) -> float:
    return 1.0 / (1.0 + np.exp(a * raw_score + b))

def temperature_scaling(logit: float, temperature: float = 1.5) -> float:
    return 1.0 / (1.0 + np.exp(-logit / temperature))

def calibrate_llm_probability(llm_confidence: float, market_price: float, weight_llm: float = 0.6) -> float:
    # Blend LLM confidence with market price (market as prior)
    calibrated = weight_llm * llm_confidence + (1 - weight_llm) * market_price
    return max(0.01, min(0.99, calibrated))

def ensemble_probability(probabilities: List[float], weights: List[float] = None) -> float:
    if weights is None:
        weights = [1.0 / len(probabilities)] * len(probabilities)
    total = sum(w * p for w, p in zip(weights, probabilities))
    return max(0.01, min(0.99, total))
