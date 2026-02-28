"""
Research & Innovation Lab Agent
================================
Scans for trends, evaluates technologies, proposes innovations.
"""

import json
from datetime import datetime

from base_agent import BaseAgent


class ResearchAgent(BaseAgent):
    def __init__(self, redis_url: str = "redis://redis:6379/0"):
        super().__init__(
            name="Research",
            mission="Neue Technologien, Trends und Geschäftsmöglichkeiten identifizieren. Marktforschung betreiben und dem Empire einen Wissensvorsprung verschaffen.",
            kpis=[
                "Min. 3 neue Insights pro Woche",
                "Trend-Reports pünktlich",
                "Technologie-Bewertungen < 24h",
            ],
            redis_url=redis_url,
        )

    async def observe(self) -> dict:
        """Check for research requests and pending evaluations."""
        observations = {"research_requests": [], "pending_evaluations": []}

        if self.redis:
            # Check for specific research requests
            req_count = await self.redis.llen("empire:research:requests")
            if req_count > 0:
                raw = await self.redis.lrange("empire:research:requests", 0, 4)
                observations["research_requests"] = [json.loads(r) for r in raw]

        return observations

    async def propose(self, observations: dict) -> list[dict]:
        """Propose research actions."""
        proposals = []

        for req in observations.get("research_requests", []):
            proposals.append({
                "action": "research",
                "request": req,
            })

        return proposals

    async def execute(self, proposal: dict) -> dict:
        """Execute research tasks."""
        action = proposal.get("action")

        if action == "research":
            req = proposal["request"]
            topic = req.get("topic", "unbekannt")

            analysis = await self.think(
                f"Recherchiere gründlich zum Thema: {topic}\n\n"
                "Gib eine strukturierte Analyse mit:\n"
                "1. Zusammenfassung\n"
                "2. Wichtigste Erkenntnisse\n"
                "3. Chancen für unser AI Empire\n"
                "4. Risiken\n"
                "5. Empfehlung"
            )

            filename = f"research_{datetime.now().strftime('%Y%m%d_%H%M')}_{topic[:30]}.md"
            await self.save_result(filename, f"# Research: {topic}\n\n{analysis}", subdir="research")
            await self.report(f"🔬 Research abgeschlossen: {topic}\n\nDatei: {filename}")

            # Remove processed request
            if self.redis:
                await self.redis.lpop("empire:research:requests")

            return {"status": "completed", "topic": topic}

        return {"status": "unknown_action"}
