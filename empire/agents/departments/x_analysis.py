"""
X Analysis & Prompt Factory Department
========================================
Specialized agent that processes X/Twitter analysis requests.
Works with the x-analyzer service to process posts.
"""

import json
from datetime import datetime

from base_agent import BaseAgent


class XAnalysisDepartment(BaseAgent):
    def __init__(self, redis_url: str = "redis://redis:6379/0"):
        super().__init__(
            name="XAnalysis",
            mission="X/Twitter Posts analysieren, Prompts daraus generieren, prüfen ob sie zum Empire passen, und verwertbare Insights liefern.",
            kpis=[
                "Analyse-Zeit < 2 Minuten pro Post",
                "Prompt-Qualität: nutzbar > 70%",
                "10k-Queue: 500+ Posts/Tag",
            ],
            redis_url=redis_url,
        )

    async def observe(self) -> dict:
        """Check for completed analyses that need evaluation."""
        observations = {"completed_analyses": [], "queue_stats": {}}

        if self.redis:
            # Check for completed analyses from x-analyzer
            count = await self.redis.llen("empire:x:completed")
            if count > 0:
                raw = await self.redis.lrange("empire:x:completed", 0, 9)
                observations["completed_analyses"] = [json.loads(r) for r in raw]

            # Queue stats
            observations["queue_stats"] = {
                "pending": await self.redis.llen("empire:x:analysis_queue"),
                "bulk_pending": await self.redis.llen("empire:queue:bulk"),
            }

        return observations

    async def propose(self, observations: dict) -> list[dict]:
        proposals = []

        for analysis in observations.get("completed_analyses", []):
            proposals.append({
                "action": "evaluate_and_generate_prompts",
                "analysis": analysis,
            })

        return proposals

    async def execute(self, proposal: dict) -> dict:
        action = proposal.get("action")

        if action == "evaluate_and_generate_prompts":
            analysis = proposal["analysis"]
            url = analysis.get("url", "unknown")
            content = analysis.get("content", "")
            transcript = analysis.get("transcript", "")

            combined = f"Post-Content: {content}\n"
            if transcript:
                combined += f"Video-Transkript: {transcript}\n"

            # Generate prompts from the content
            prompt_result = await self.think(
                f"Analysiere diesen X/Twitter Post und generiere daraus verwertbare Prompts:\n\n"
                f"URL: {url}\n"
                f"{combined}\n\n"
                "Schritte:\n"
                "1. Was ist der Kerninhalt / die Kernidee?\n"
                "2. Generiere 1-3 konkrete Prompts die wir für unser AI Empire nutzen können\n"
                "3. Bewerte: Passt das zu unseren Zielen? (AI, Automatisierung, Geschäftsaufbau)\n"
                "4. Empfehlung: UMSETZEN (mit konkretem Plan) oder ABLEHNEN (mit Begründung)\n\n"
                "Format: Strukturierter Report"
            )

            # Save result
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"x_analysis_{timestamp}.md"
            report_content = (
                f"# X-Analyse Report\n\n"
                f"**URL:** {url}\n"
                f"**Datum:** {datetime.now().strftime('%Y-%m-%d %H:%M')}\n\n"
                f"## Content\n{combined}\n\n"
                f"## Analyse & Prompts\n{prompt_result}\n"
            )

            filepath = await self.save_result(filename, report_content, subdir="x-analyses")

            await self.report(
                f"🐦 X-Analyse abgeschlossen!\n\n"
                f"URL: {url}\n"
                f"Datei: {filepath}\n\n"
                f"{prompt_result[:500]}",
                priority="normal",
            )

            # Remove from completed queue
            if self.redis:
                await self.redis.lpop("empire:x:completed")

            return {"status": "evaluated", "url": url, "filepath": filepath}

        return {"status": "unknown_action"}
