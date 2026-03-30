import os
from typing import List, Dict, Optional
from dotenv import load_dotenv

load_dotenv()

class PolymarketClient:
    def __init__(self, paper_mode: bool = True):
        self.host = os.getenv("POLYMARKET_HOST", "https://clob.polymarket.com")
        self.gamma_host = "https://gamma-api.polymarket.com"
        self.chain_id = int(os.getenv("CHAIN_ID", "137"))
        self.paper_mode = paper_mode
        self._client = None

        if not paper_mode:
            self._init_live_client()

    def _init_live_client(self):
        try:
            from py_clob_client.client import ClobClient
            from py_clob_client.clob_types import ApiCreds
            private_key = os.getenv("POLYGON_PRIVATE_KEY")
            if not private_key:
                raise ValueError("POLYGON_PRIVATE_KEY not set")
            self._client = ClobClient(self.host, self.chain_id, private_key)
        except ImportError:
            raise ImportError("py-clob-client not installed: pip install py-clob-client")

    def get_markets(self, limit: int = 20, active_only: bool = True) -> List[Dict]:
        import requests
        params = {"limit": limit, "active": active_only, "closed": False}
        resp = requests.get(f"{self.gamma_host}/markets", params=params, timeout=10)
        resp.raise_for_status()
        return resp.json().get("markets", resp.json() if isinstance(resp.json(), list) else [])

    def get_market(self, condition_id: str) -> Dict:
        import requests
        resp = requests.get(f"{self.gamma_host}/markets/{condition_id}", timeout=10)
        resp.raise_for_status()
        return resp.json()

    def get_orderbook(self, token_id: str) -> Dict:
        import requests
        resp = requests.get(f"{self.host}/book?token_id={token_id}", timeout=10)
        resp.raise_for_status()
        return resp.json()

    def place_order(self, token_id: str, side: str, price: float, size: float) -> Dict:
        if self.paper_mode:
            return {
                "status": "paper",
                "token_id": token_id,
                "side": side,
                "price": price,
                "size": size,
                "estimated_pnl": size * (1 / price - 1) if side == "BUY" else 0,
            }
        # Live order via CLOB
        from py_clob_client.clob_types import MarketOrderArgs, OrderType
        order_args = MarketOrderArgs(token_id=token_id, amount=size)
        signed_order = self._client.create_market_order(order_args)
        return self._client.post_order(signed_order, OrderType.GTC)

    def get_market_prices(self, condition_id: str) -> Dict:
        import requests
        resp = requests.get(f"{self.gamma_host}/markets/{condition_id}", timeout=10)
        data = resp.json()
        tokens = data.get("tokens", data.get("outcomePrices", []))
        if isinstance(tokens, list) and len(tokens) >= 2:
            yes_price = float(tokens[0].get("price", 0.5) if isinstance(tokens[0], dict) else tokens[0])
            no_price = float(tokens[1].get("price", 0.5) if isinstance(tokens[1], dict) else tokens[1])
            return {"yes": yes_price, "no": no_price, "condition_id": condition_id}
        return {"yes": 0.5, "no": 0.5, "condition_id": condition_id}
