"""n8n Integration - Trigger and manage n8n workflows from Galaxia agents.

Connects to the existing n8n instance on the server to execute
real-world automations (email, webhooks, API calls, etc.).
"""

from __future__ import annotations

import logging
from typing import Any

import aiohttp

logger = logging.getLogger("galaxia.n8n")


class N8nClient:
    """Client for n8n REST API."""

    def __init__(
        self,
        base_url: str = "http://localhost:5678",
        api_key: str = "",
    ):
        self._base_url = base_url.rstrip("/")
        self._api_key = api_key
        self._headers = {
            "Accept": "application/json",
            "Content-Type": "application/json",
        }
        if api_key:
            self._headers["X-N8N-API-KEY"] = api_key

    async def _request(self, method: str, path: str, data: dict | None = None) -> dict:
        url = f"{self._base_url}/api/v1{path}"
        async with aiohttp.ClientSession(headers=self._headers) as session:
            async with session.request(method, url, json=data, timeout=aiohttp.ClientTimeout(total=30)) as resp:
                if resp.status >= 400:
                    text = await resp.text()
                    logger.error("n8n API error %d: %s", resp.status, text[:200])
                    return {"error": text, "status": resp.status}
                return await resp.json()

    # === Workflows ===

    async def list_workflows(self) -> list[dict]:
        """List all n8n workflows."""
        result = await self._request("GET", "/workflows")
        return result.get("data", [])

    async def get_workflow(self, workflow_id: str) -> dict:
        return await self._request("GET", f"/workflows/{workflow_id}")

    async def activate_workflow(self, workflow_id: str) -> dict:
        return await self._request("PATCH", f"/workflows/{workflow_id}", {"active": True})

    async def deactivate_workflow(self, workflow_id: str) -> dict:
        return await self._request("PATCH", f"/workflows/{workflow_id}", {"active": False})

    # === Executions ===

    async def trigger_webhook(self, webhook_path: str, data: dict | None = None) -> dict:
        """Trigger a webhook-based workflow."""
        url = f"{self._base_url}/webhook/{webhook_path}"
        async with aiohttp.ClientSession() as session:
            async with session.post(url, json=data or {}, timeout=aiohttp.ClientTimeout(total=60)) as resp:
                try:
                    return await resp.json()
                except Exception:
                    text = await resp.text()
                    return {"response": text, "status": resp.status}

    async def list_executions(self, limit: int = 10) -> list[dict]:
        result = await self._request("GET", f"/executions?limit={limit}")
        return result.get("data", [])

    # === Helper ===

    async def health_check(self) -> bool:
        """Check if n8n is reachable."""
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(f"{self._base_url}/healthz", timeout=aiohttp.ClientTimeout(total=5)) as resp:
                    return resp.status == 200
        except Exception:
            return False

    async def get_summary(self) -> str:
        """Get a summary of n8n status for the brain."""
        workflows = await self.list_workflows()
        active = [w for w in workflows if w.get("active")]
        return (
            f"n8n: {len(workflows)} Workflows total, {len(active)} aktiv. "
            f"Aktive: {', '.join(w.get('name', '?') for w in active[:5])}"
        )
