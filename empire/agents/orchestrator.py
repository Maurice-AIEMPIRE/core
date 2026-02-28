"""
CEO / Strategic Command Orchestrator
=====================================
The main orchestrator agent that:
- Coordinates all department agents
- Sends daily standups via Telegram
- Evaluates new ideas and assigns tasks
- Monitors overall empire health
"""

import asyncio
import json
import logging
import os
from datetime import datetime

import redis.asyncio as redis

from base_agent import BaseAgent
from departments.research import ResearchAgent
from departments.engineering import EngineeringAgent
from departments.marketing import MarketingAgent
from departments.x_analysis import XAnalysisDepartment

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
)
logger = logging.getLogger("orchestrator")

REDIS_URL = os.environ.get("REDIS_URL", "redis://redis:6379/0")


class CEOAgent(BaseAgent):
    """The CEO orchestrator that manages all departments."""

    def __init__(self):
        super().__init__(
            name="CEO",
            mission="Das gesamte AI Empire strategisch steuern, alle Abteilungen koordinieren, neue Ideen evaluieren und tägliche Reports generieren.",
            kpis=[
                "Agenten-Uptime > 99%",
                "Ideen-Evaluierung < 5 Minuten",
                "Täglicher Report pünktlich um 08:00",
                "Task-Completion-Rate > 80%",
            ],
        )
        self.departments: list[BaseAgent] = []

    async def setup(self):
        await super().setup()

        # Initialize department agents
        self.departments = [
            ResearchAgent(redis_url=self.redis_url),
            EngineeringAgent(redis_url=self.redis_url),
            MarketingAgent(redis_url=self.redis_url),
            XAnalysisDepartment(redis_url=self.redis_url),
        ]

        for dept in self.departments:
            await dept.setup()

        logger.info(f"CEO initialized with {len(self.departments)} departments")

    async def observe(self) -> dict:
        """Observe the state of the entire empire."""
        observations = {
            "timestamp": datetime.now().isoformat(),
            "departments": {},
            "pending_ideas": [],
            "pending_tasks": [],
            "queue_status": {},
        }

        if self.redis:
            # Check each department
            agents = await self.redis.hgetall("empire:agents:status")
            observations["departments"] = agents

            # Check for new ideas
            ideas_count = await self.redis.llen("empire:ideas")
            if ideas_count > 0:
                ideas_raw = await self.redis.lrange("empire:ideas", 0, 9)
                observations["pending_ideas"] = [json.loads(i) for i in ideas_raw]

            # Check for new tasks
            tasks_count = await self.redis.llen("empire:tasks:new")
            if tasks_count > 0:
                tasks_raw = await self.redis.lrange("empire:tasks:new", 0, 9)
                observations["pending_tasks"] = [json.loads(t) for t in tasks_raw]

            # Queue status
            observations["queue_status"] = {
                "bulk_queue_length": await self.redis.llen("empire:queue:bulk"),
                "analysis_queue_length": await self.redis.llen("empire:x:analysis_queue"),
                "status": await self.redis.get("empire:queue:status") or "idle",
            }

        return observations

    async def propose(self, observations: dict) -> list[dict]:
        """Propose strategic actions based on observations."""
        proposals = []

        # Process new ideas
        for idea in observations.get("pending_ideas", []):
            if idea.get("status") == "new":
                proposals.append({
                    "action": "evaluate_idea",
                    "idea": idea,
                })

        # Assign unassigned tasks
        for task in observations.get("pending_tasks", []):
            if not task.get("assigned_to"):
                proposals.append({
                    "action": "assign_task",
                    "task": task,
                })

        # Daily standup check
        now = datetime.now()
        if now.hour == 8 and now.minute < 10:
            proposals.append({
                "action": "daily_standup",
                "observations": observations,
            })

        return proposals

    async def execute(self, proposal: dict) -> dict:
        """Execute a CEO-level proposal."""
        action = proposal.get("action")

        if action == "evaluate_idea":
            return await self._evaluate_idea(proposal["idea"])
        elif action == "assign_task":
            return await self._assign_task(proposal["task"])
        elif action == "daily_standup":
            return await self._generate_standup(proposal["observations"])

        return {"status": "unknown_action", "action": action}

    async def _evaluate_idea(self, idea: dict) -> dict:
        """Evaluate a business idea using Claude."""
        context = f"""Evaluiere diese Geschäftsidee für das AI Empire:

Idee: {idea['text']}

Bewerte nach:
1. Machbarkeit (technisch)
2. Marktpotenzial
3. Passt es zu unserem Fokus (AI, Automatisierung, SaaS)?
4. Geschätzter Aufwand
5. Empfehlung: UMSETZEN oder ABLEHNEN

Gib eine klare, strukturierte Bewertung."""

        evaluation = await self.think(context)
        idea["status"] = "evaluated"
        idea["evaluation"] = evaluation

        # Save evaluation
        await self.save_result(
            f"idea_eval_{idea['id']}.md",
            f"# Idee: {idea['text']}\n\n## Evaluierung\n\n{evaluation}",
            subdir="ideas",
        )

        await self.report(
            f"💡 Idee evaluiert: {idea['text'][:50]}...\n\n{evaluation[:500]}",
            priority="normal",
        )

        return {"status": "evaluated", "idea_id": idea["id"]}

    async def _assign_task(self, task: dict) -> dict:
        """Assign a task to the best department."""
        context = f"""Welche Abteilung soll diesen Task übernehmen?

Task: {task['title']}

Verfügbare Abteilungen:
- Research & Innovation
- Product Engineering
- Marketing & Growth
- X Analysis & Prompt Factory

Wähle die beste Abteilung und begründe kurz."""

        decision = await self.think(context)

        task["assigned_to"] = decision.split("\n")[0] if decision else "Engineering"

        if self.redis:
            await self.redis.hset(
                f"empire:task:{task['id']}",
                mapping={
                    "title": task["title"],
                    "assigned_to": task["assigned_to"],
                    "status": "in_progress",
                },
            )

        await self.report(
            f"📋 Task zugewiesen: {task['title']} → {task['assigned_to']}"
        )

        return {"status": "assigned", "task_id": task.get("id")}

    async def _generate_standup(self, observations: dict) -> dict:
        """Generate and send the daily standup report."""
        departments = observations.get("departments", {})
        queue = observations.get("queue_status", {})

        report_lines = [
            f"📊 Tägliches Stand-up - {datetime.now().strftime('%Y-%m-%d %H:%M')}",
            "",
            "Agenten-Status:",
        ]

        for name, status in departments.items():
            icon = "🟢" if status == "running" else "🔴"
            report_lines.append(f"  {icon} {name}: {status}")

        report_lines.extend([
            "",
            f"Queue: {queue.get('bulk_queue_length', 0)} Posts | Status: {queue.get('status', 'idle')}",
            "",
            "Prioritäten heute:",
            "  1. Neue Ideen evaluieren",
            "  2. Offene Tasks abarbeiten",
            "  3. X-Analyse Queue weiterverarbeiten",
        ])

        standup = "\n".join(report_lines)
        await self.report(standup, priority="high")
        await self.save_result(
            f"standup_{datetime.now().strftime('%Y%m%d')}.md",
            standup,
            subdir="standups",
        )

        return {"status": "standup_sent"}

    async def handle_command(self, command: dict):
        """Handle commands from Telegram."""
        action = command.get("action")

        if action == "generate_report":
            report_type = command.get("type", "daily")
            if report_type == "daily":
                obs = await self.observe()
                await self._generate_standup(obs)

        elif action == "kb_search":
            query = command.get("query", "")
            # Simple file-based search
            results = await self._search_kb(query)
            await self.report(
                f"🧠 KB-Suche nach '{query}':\n\n{results}",
                priority="normal",
            )

    async def _search_kb(self, query: str) -> str:
        """Simple knowledge base search across saved files."""
        kb_dir = "/app/shared-kb"
        results = []
        query_lower = query.lower()

        for root, _, files in os.walk(kb_dir):
            for f in files:
                if f.endswith((".md", ".json", ".jsonl", ".txt")):
                    filepath = os.path.join(root, f)
                    try:
                        with open(filepath) as fh:
                            content = fh.read()
                            if query_lower in content.lower():
                                results.append(f"📄 {filepath}: Match gefunden")
                    except Exception:
                        pass

        if not results:
            return "Keine Treffer gefunden."

        return "\n".join(results[:10])


async def main():
    """Start the CEO orchestrator with a report listener."""
    ceo = CEOAgent()

    # Also start a report forwarder to Telegram
    async def forward_reports():
        """Listen for reports and forward to Telegram via Redis."""
        r = redis.from_url(REDIS_URL, decode_responses=True)
        while True:
            try:
                # Pop reports from the queue
                report_raw = await r.lpop("empire:reports")
                if report_raw:
                    report = json.loads(report_raw)
                    # Publish to Telegram bot
                    await r.publish("empire:telegram:send", json.dumps({
                        "text": f"[{report['agent']}] {report['message']}",
                        "priority": report.get("priority", "normal"),
                    }))
                else:
                    await asyncio.sleep(5)
            except Exception as e:
                logger.error(f"Report forwarding error: {e}")
                await asyncio.sleep(10)

    # Run both concurrently
    await asyncio.gather(
        ceo.run(interval_seconds=300),  # 5 minute cycles
        forward_reports(),
    )


if __name__ == "__main__":
    asyncio.run(main())
