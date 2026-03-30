import os
from typing import List, Dict
from dotenv import load_dotenv

load_dotenv()

def fetch_news_tavily(query: str, max_results: int = 5) -> List[Dict]:
    try:
        from tavily import TavilyClient
        client = TavilyClient(api_key=os.getenv("TAVILY_API_KEY", ""))
        result = client.search(query, max_results=max_results, search_depth="advanced")
        return result.get("results", [])
    except Exception as e:
        return [{"title": "Tavily unavailable", "content": str(e), "url": ""}]

def summarize_news_for_market(market_question: str, news_items: List[Dict]) -> str:
    summaries = []
    for item in news_items[:3]:
        title = item.get("title", "")
        content = item.get("content", "")[:300]
        summaries.append(f"- {title}: {content}")
    return f"Market: {market_question}\nNews:\n" + "\n".join(summaries)
