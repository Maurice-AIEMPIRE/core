"""Agent Orchestrator - CEO Brain of the Empire.

Receives tasks from Telegram Bot, routes to departments,
monitors progress, and reports back.
Each department has a personality and mission.
"""

import asyncio
import json
import logging
import os
import time

import anthropic
import redis.asyncio as redis
from dotenv import load_dotenv

load_dotenv()
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("orchestrator")

DEPARTMENT_PROMPTS = {
    "research": {
        "name": "Research & Innovation Lab",
        "mission": "Neue Technologien, Markttrends und Geschaeftschancen finden.",
        "personality": "Neugierig, analytisch, immer auf der Suche nach dem naechsten grossen Ding.",
    },
    "product": {
        "name": "Product Engineering",
        "mission": "Software, Tools und Produkte bauen die Wert schaffen.",
        "personality": "Hands-on, perfektionistisch, shipping-oriented.",
    },
    "marketing": {
        "name": "Marketing & Growth",
        "mission": "Reichweite aufbauen, Content erstellen, Audience wachsen.",
        "personality": "Kreativ, datengetrieben, viral-denkend.",
    },
    "sales": {
        "name": "Sales & CRM",
        "mission": "Leads generieren, Deals abschliessen, Revenue steigern.",
        "personality": "Ueberzeugend, hartnäckig, beziehungsorientiert.",
    },
    "finance": {
        "name": "Finance & Ops",
        "mission": "Budget verwalten, Kosten optimieren, ROI maximieren.",
        "personality": "Praezise, konservativ, zahlenorientiert.",
    },
    "legal": {
        "name": "Legal & Compliance",
        "mission": "Rechtliche Risiken minimieren, Compliance sicherstellen.",
        "personality": "Vorsichtig, gruendlich, regelkonform.",
    },
    "hr": {
        "name": "HR & Culture",
        "mission": "Team-Effizienz steigern, Workflows optimieren.",
        "personality": "Empathisch, organisiert, team-fokussiert.",
    },
    "customer": {
        "name": "Customer Success",
        "mission": "User-Zufriedenheit maximieren, Feedback verarbeiten.",
        "personality": "Serviceorientiert, loesungsfokussiert, proaktiv.",
    },
    "ceo": {
        "name": "CEO / Strategic Command",
        "mission": "Strategie definieren, Prioritaeten setzen, Empire ausbauen.",
        "personality": "Visionaer, entscheidungsfreudig, ambitioniert.",
    },
    "meta": {
        "name": "Meta-Skill-Agent",
        "mission": "System verbessern, neue Skills entwickeln, Self-Improvement.",
        "personality": "Selbstreflektiv, experimentierfreudig, meta-denkend.",
    },
}


class Orchestrator:
    def __init__(self):
        self.redis = redis.from_url(
            os.environ.get("REDIS_URL", "redis://redis:6379"),
            decode_responses=True,
        )
        api_key = os.environ.get("CLAUDE_API_KEY", "")
        self.claude = anthropic.Anthropic(api_key=api_key) if api_key else None

    async def run_department_agent(self, department: str, task_description: str) -> str:
        dept = DEPARTMENT_PROMPTS.get(department, DEPARTMENT_PROMPTS["ceo"])

        if not self.claude:
            return f"[{dept['name']}] Claude API nicht verfuegbar. Task gespeichert."

        system = (
            f"Du bist der Agent der Abteilung '{dept['name']}' im UserAI Empire.\n"
            f"Mission: {dept['mission']}\n"
            f"Persoenlichkeit: {dept['personality']}\n\n"
            f"Regeln:\n"
            f"- Sei konkret und liefere Ergebnisse, keine Theorie\n"
            f"- Wenn du etwas nicht umsetzen kannst, sag was genau fehlt\n"
            f"- Antworte auf Deutsch\n"
            f"- Gib am Ende eine klare Zusammenfassung + naechste Schritte"
        )

        try:
            response = self.claude.messages.create(
                model="claude-sonnet-4-20250514",
                max_tokens=3000,
                system=system,
                messages=[{"role": "user", "content": task_description}],
            )
            return response.content[0].text
        except Exception as e:
            return f"[{dept['name']}] Error: {e}"

    async def process_tasks(self):
        logger.info("Orchestrator listening for tasks...")
        while True:
            try:
                result = await self.redis.blpop("orchestrator:tasks", timeout=5)
                if not result:
                    continue

                _, raw = result
                task = json.loads(raw)
                task_id = task["task_id"]
                department = task["department"]
                description = task["description"]

                logger.info(f"Processing task {task_id[:8]} for {department}")

                # Update status
                await self.redis.set(
                    f"task:{task_id}:status",
                    json.dumps({"status": "in_progress", "department": department}),
                )

                # Run department agent
                result_text = await self.run_department_agent(department, description)

                # Save result
                result_path = f"/empire/results/{department}/{task_id[:8]}.md"
                os.makedirs(os.path.dirname(result_path), exist_ok=True)
                with open(result_path, "w") as f:
                    f.write(f"# Task: {description[:80]}\n\n")
                    f.write(f"Department: {department}\n")
                    f.write(f"Date: {time.strftime('%Y-%m-%d %H:%M')}\n\n")
                    f.write(result_text)

                # Send result back to Telegram
                await self.redis.rpush(
                    "telegram:results",
                    json.dumps({
                        "task_id": task_id,
                        "department": department,
                        "success": True,
                        "message": result_text[:1500],
                        "file_path": result_path,
                    }),
                )

                logger.info(f"Task {task_id[:8]} completed")

            except Exception as e:
                logger.error(f"Orchestrator error: {e}")
                await asyncio.sleep(5)

    async def proactive_loop(self):
        """Proactive entrepreneurial thinking loop - runs every 6 hours."""
        while True:
            await asyncio.sleep(21600)  # 6 hours
            try:
                if not self.claude:
                    continue

                result = await self.run_department_agent(
                    "ceo",
                    "Analysiere den aktuellen Stand des Empires. "
                    "Was sollten wir als naechstes tun? "
                    "Gibt es neue Geschaeftschancen? "
                    "Welche Abteilung braucht Aufmerksamkeit? "
                    "Schlage 3 konkrete Aktionen vor.",
                )

                await self.redis.rpush(
                    "telegram:results",
                    json.dumps({
                        "task_id": "proactive",
                        "department": "ceo",
                        "success": True,
                        "message": f"[Proaktiver Report]\n\n{result[:1500]}",
                    }),
                )
            except Exception as e:
                logger.error(f"Proactive loop error: {e}")

    async def run(self):
        await asyncio.gather(
            self.process_tasks(),
            self.proactive_loop(),
        )


async def main():
    orchestrator = Orchestrator()
    await orchestrator.run()


if __name__ == "__main__":
    asyncio.run(main())
