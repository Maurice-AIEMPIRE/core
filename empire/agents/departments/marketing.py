"""
Marketing & Growth Agent
=========================
Content creation, growth strategies, brand management.
"""

import json
from datetime import datetime

from base_agent import BaseAgent


class MarketingAgent(BaseAgent):
    def __init__(self, redis_url: str = "redis://redis:6379/0"):
        super().__init__(
            name="Marketing",
            mission="Wachstum treiben durch Content, Social Media, SEO und kreative Kampagnen. Brand aufbauen und Reichweite maximieren.",
            kpis=[
                "Content-Output: 5 Stück/Woche",
                "Engagement-Rate tracken",
                "Neue Kanäle identifizieren",
            ],
            redis_url=redis_url,
        )

    async def observe(self) -> dict:
        """Check for marketing tasks and content requests."""
        observations = {"tasks": [], "content_requests": []}

        if self.redis:
            tasks_raw = await self.redis.lrange("empire:tasks:marketing", 0, 4)
            observations["tasks"] = [json.loads(t) for t in tasks_raw]

        return observations

    async def propose(self, observations: dict) -> list[dict]:
        proposals = []
        for task in observations.get("tasks", []):
            proposals.append({"action": "create_content", "task": task})
        return proposals

    async def execute(self, proposal: dict) -> dict:
        action = proposal.get("action")

        if action == "create_content":
            task = proposal["task"]
            topic = task.get("title", "allgemein")

            content = await self.think(
                f"Erstelle Marketing-Content zum Thema: {topic}\n\n"
                "Liefere:\n"
                "1. Social Media Post (Twitter/X Format)\n"
                "2. Längerer Blog-Absatz\n"
                "3. Call-to-Action\n"
                "4. Hashtag-Vorschläge"
            )

            filename = f"content_{datetime.now().strftime('%Y%m%d_%H%M')}.md"
            await self.save_result(filename, f"# Marketing: {topic}\n\n{content}", subdir="marketing")
            await self.report(f"📢 Content erstellt: {topic}")

            if self.redis:
                await self.redis.lpop("empire:tasks:marketing")

            return {"status": "created", "topic": topic}

        return {"status": "unknown_action"}
