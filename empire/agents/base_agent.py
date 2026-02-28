"""
Base Agent class for all AI Empire agents.

Every agent follows the loop:
  Observe → Entrepreneurial Think → Propose → Execute or Reject → Report
"""

import asyncio
import json
import logging
import os
from abc import ABC, abstractmethod
from datetime import datetime
from typing import Optional

import anthropic
import redis.asyncio as redis


class BaseAgent(ABC):
    """Base class for all Empire agents."""

    def __init__(
        self,
        name: str,
        mission: str,
        kpis: list[str],
        redis_url: str = "redis://redis:6379/0",
    ):
        self.name = name
        self.mission = mission
        self.kpis = kpis
        self.logger = logging.getLogger(f"agent.{name}")
        self.redis_url = redis_url
        self.redis: Optional[redis.Redis] = None
        self.claude: Optional[anthropic.AsyncAnthropic] = None
        self._running = False

    async def setup(self):
        """Initialize connections."""
        self.redis = redis.from_url(self.redis_url, decode_responses=True)

        api_key = os.environ.get("ANTHROPIC_API_KEY")
        if api_key:
            self.claude = anthropic.AsyncAnthropic(api_key=api_key)

        # Register in Redis
        await self.redis.hset("empire:agents:status", self.name, "running")
        await self.redis.hset(f"empire:agent:{self.name}", mapping={
            "mission": self.mission,
            "kpis": json.dumps(self.kpis),
            "started_at": datetime.now().isoformat(),
            "last_action": "initialized",
        })

        self.logger.info(f"Agent '{self.name}' initialized. Mission: {self.mission}")

    async def teardown(self):
        """Cleanup connections."""
        if self.redis:
            await self.redis.hset("empire:agents:status", self.name, "stopped")
            await self.redis.aclose()

    async def think(self, context: str) -> str:
        """Use Claude to think about a problem/opportunity."""
        if not self.claude:
            return "No Claude API key configured. Cannot think autonomously."

        response = await self.claude.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=2048,
            system=f"""Du bist der {self.name}-Agent im AI Empire.
Deine Mission: {self.mission}
Deine KPIs: {', '.join(self.kpis)}

Du denkst unternehmerisch, bist proaktiv und findest Chancen.
Antworte immer in strukturierter Form: Analyse, Vorschlag, nächste Schritte.""",
            messages=[{"role": "user", "content": context}],
        )
        return response.content[0].text

    async def report(self, message: str, priority: str = "normal"):
        """Send a report via Redis (Telegram bot picks it up)."""
        if not self.redis:
            return

        report_data = {
            "agent": self.name,
            "message": message,
            "priority": priority,
            "timestamp": datetime.now().isoformat(),
        }

        await self.redis.rpush("empire:reports", json.dumps(report_data))

        # Also publish for real-time listeners
        await self.redis.publish("empire:reports:live", json.dumps(report_data))

        # Log to shared KB
        await self._log_to_kb(report_data)

    async def _log_to_kb(self, data: dict):
        """Log action to the shared knowledge base."""
        kb_dir = "/app/shared-kb/logs"
        os.makedirs(kb_dir, exist_ok=True)

        date_str = datetime.now().strftime("%Y-%m-%d")
        log_file = os.path.join(kb_dir, f"{self.name}_{date_str}.jsonl")

        with open(log_file, "a") as f:
            f.write(json.dumps(data, ensure_ascii=False) + "\n")

    async def save_result(self, filename: str, content: str, subdir: str = ""):
        """Save a result file to the empire results directory."""
        results_dir = "/empire/results"
        if subdir:
            results_dir = os.path.join(results_dir, subdir)
        os.makedirs(results_dir, exist_ok=True)

        filepath = os.path.join(results_dir, filename)
        with open(filepath, "w") as f:
            f.write(content)

        self.logger.info(f"Result saved: {filepath}")
        return filepath

    async def listen_for_commands(self):
        """Listen for commands from the Telegram bot via Redis pub/sub."""
        if not self.redis:
            return

        pubsub = self.redis.pubsub()
        await pubsub.subscribe("empire:commands")

        async for msg in pubsub.listen():
            if msg["type"] == "message":
                try:
                    command = json.loads(msg["data"])
                    await self.handle_command(command)
                except (json.JSONDecodeError, Exception) as e:
                    self.logger.error(f"Error handling command: {e}")

    async def handle_command(self, command: dict):
        """Override in subclasses to handle specific commands."""
        pass

    @abstractmethod
    async def observe(self) -> dict:
        """Observe the current state. Returns context dict."""
        ...

    @abstractmethod
    async def propose(self, observations: dict) -> list[dict]:
        """Propose actions based on observations. Returns list of proposals."""
        ...

    @abstractmethod
    async def execute(self, proposal: dict) -> dict:
        """Execute a single proposal. Returns result dict."""
        ...

    async def run_cycle(self):
        """Run one full agent cycle: Observe → Think → Propose → Execute → Report."""
        try:
            # 1. Observe
            observations = await self.observe()
            self.logger.info(f"Observations: {list(observations.keys())}")

            # 2. Propose
            proposals = await self.propose(observations)
            self.logger.info(f"Proposals: {len(proposals)}")

            # 3. Execute each proposal
            results = []
            for proposal in proposals:
                result = await self.execute(proposal)
                results.append(result)

                # Update last action
                if self.redis:
                    await self.redis.hset(
                        f"empire:agent:{self.name}",
                        "last_action",
                        f"{proposal.get('action', 'unknown')} at {datetime.now().strftime('%H:%M:%S')}",
                    )

            # 4. Report
            if results:
                summary = f"Zyklus abgeschlossen: {len(results)} Aktionen ausgeführt."
                await self.report(summary)

            return results

        except Exception as e:
            self.logger.error(f"Cycle error: {e}", exc_info=True)
            await self.report(f"Fehler im Zyklus: {e}", priority="high")
            return []

    async def run(self, interval_seconds: int = 300):
        """Main agent loop. Runs cycles at the given interval."""
        await self.setup()
        self._running = True

        # Start command listener in background
        asyncio.create_task(self.listen_for_commands())

        self.logger.info(f"Agent '{self.name}' main loop started (interval: {interval_seconds}s)")

        while self._running:
            await self.run_cycle()
            await asyncio.sleep(interval_seconds)

        await self.teardown()

    def stop(self):
        """Stop the agent loop."""
        self._running = False
