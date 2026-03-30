import os
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from typing import Dict, List, Any
from tools.polymarket_client import PolymarketClient
from tools.news_fetcher import fetch_news_tavily, summarize_news_for_market
from core.probability_calibrator import calibrate_llm_probability, ensemble_probability

def research_markets(state: Dict[str, Any]) -> Dict[str, Any]:
    """Research agent: fetches markets and scores them."""
    client = state["client"]

    markets = client.get_markets(limit=30)

    scored = []
    for m in markets[:10]:  # Process top 10
        question = m.get("question", m.get("title", ""))
        if not question:
            continue

        # Get current prices
        condition_id = m.get("conditionId", m.get("id", ""))
        try:
            prices = client.get_market_prices(condition_id)
            yes_price = prices["yes"]
        except Exception:
            yes_price = 0.5

        # Fetch news
        news = fetch_news_tavily(question, max_results=3)

        # Simple heuristic scoring (replace with LLM in production)
        # Edge = distance from 0.5 (more polarized = more research opportunity)
        edge_score = abs(yes_price - 0.5)

        scored.append({
            "question": question,
            "condition_id": condition_id,
            "yes_price": yes_price,
            "no_price": 1 - yes_price,
            "edge_score": edge_score,
            "news_summary": summarize_news_for_market(question, news),
            "volume": m.get("volume", 0),
        })

    # Sort by edge score + volume
    scored.sort(key=lambda x: (x["edge_score"] * 0.7 + min(float(x["volume"] or 0) / 100000, 1) * 0.3), reverse=True)

    state["researched_markets"] = scored[:3]  # Top 3
    state["cycle_log"].append(f"[Research] Found {len(scored)} markets, top 3 selected")
    return state
