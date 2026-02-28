"""
Product Engineering Agent
==========================
Builds, maintains and improves technical products and infrastructure.
"""

import json
from datetime import datetime

from base_agent import BaseAgent


class EngineeringAgent(BaseAgent):
    def __init__(self, redis_url: str = "redis://redis:6379/0"):
        super().__init__(
            name="Engineering",
            mission="Technische Produkte und Services bauen, warten und verbessern. Code-Qualität sicherstellen. Infrastruktur optimieren.",
            kpis=[
                "System-Uptime > 99.5%",
                "Bug-Fix-Zeit < 2h",
                "Feature-Delivery on time",
            ],
            redis_url=redis_url,
        )

    async def observe(self) -> dict:
        """Check for engineering tasks and system health."""
        observations = {"tasks": [], "health_issues": []}

        if self.redis:
            tasks_raw = await self.redis.lrange("empire:tasks:engineering", 0, 4)
            observations["tasks"] = [json.loads(t) for t in tasks_raw]

        return observations

    async def propose(self, observations: dict) -> list[dict]:
        """Propose engineering actions."""
        proposals = []

        for task in observations.get("tasks", []):
            proposals.append({
                "action": "implement",
                "task": task,
            })

        return proposals

    async def execute(self, proposal: dict) -> dict:
        """Execute engineering tasks."""
        action = proposal.get("action")

        if action == "implement":
            task = proposal["task"]
            title = task.get("title", "unbekannt")

            plan = await self.think(
                f"Erstelle einen technischen Implementierungsplan für: {title}\n\n"
                "Gib:\n"
                "1. Technologie-Stack\n"
                "2. Architektur-Übersicht\n"
                "3. Schritte zur Umsetzung\n"
                "4. Geschätzter Aufwand\n"
                "5. Risiken"
            )

            filename = f"eng_plan_{datetime.now().strftime('%Y%m%d_%H%M')}.md"
            await self.save_result(filename, f"# Engineering Plan: {title}\n\n{plan}", subdir="engineering")
            await self.report(f"🔧 Engineering Plan erstellt: {title}")

            if self.redis:
                await self.redis.lpop("empire:tasks:engineering")

            return {"status": "planned", "task": title}

        return {"status": "unknown_action"}
