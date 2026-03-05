"""Revenue Pipeline - 4-stage task pipeline with strict revenue focus.

Pipeline: galaxia.tasks -> Planner -> Research -> Build -> Review -> Done

Every task MUST have a revenue path or gets pruned.
All LLM calls go through LiteLLM (qwen3:14b, fallback llama3.1:8b).
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
import uuid
from typing import Any

import redis.asyncio as aioredis

from llm.client import LLMClient

logger = logging.getLogger("galaxia.pipeline")

# Queue names
Q_TASKS = "galaxia.tasks"
Q_RESEARCH = "galaxia.research"
Q_BUILD = "galaxia.build"
Q_REVIEW = "galaxia.review"
Q_REVENUE = "galaxia.revenue"
Q_COMPLETED = "galaxia.completed"
Q_PRUNED = "galaxia.pruned"

ALL_QUEUES = [Q_TASKS, Q_RESEARCH, Q_BUILD, Q_REVIEW, Q_REVENUE, Q_COMPLETED, Q_PRUNED]


class PipelineTask:
    """A task flowing through the revenue pipeline."""

    def __init__(
        self,
        title: str,
        description: str = "",
        revenue_estimate: float = 0,
        task_id: str | None = None,
    ):
        self.id = task_id or str(uuid.uuid4())[:8]
        self.title = title
        self.description = description
        self.revenue_estimate = revenue_estimate
        self.stage = "submitted"
        self.plan: str = ""
        self.research: str = ""
        self.build_result: str = ""
        self.review: dict = {}
        self.created_at: float = time.time()
        self.history: list[dict] = []

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "title": self.title,
            "description": self.description,
            "revenue_estimate": self.revenue_estimate,
            "stage": self.stage,
            "plan": self.plan,
            "research": self.research,
            "build_result": self.build_result,
            "review": self.review,
            "created_at": self.created_at,
            "history": self.history,
        }

    @classmethod
    def from_dict(cls, data: dict) -> PipelineTask:
        task = cls(
            title=data["title"],
            description=data.get("description", ""),
            revenue_estimate=data.get("revenue_estimate", 0),
            task_id=data.get("id"),
        )
        task.stage = data.get("stage", "submitted")
        task.plan = data.get("plan", "")
        task.research = data.get("research", "")
        task.build_result = data.get("build_result", "")
        task.review = data.get("review", {})
        task.created_at = data.get("created_at", time.time())
        task.history = data.get("history", [])
        return task

    def log_event(self, agent: str, event: str, data: dict | None = None):
        self.history.append({
            "agent": agent,
            "event": event,
            "data": data or {},
            "ts": time.time(),
        })


class PipelineAgent:
    """Base class for pipeline stage agents."""

    def __init__(
        self,
        name: str,
        input_queue: str,
        output_queue: str,
        redis: aioredis.Redis,
        llm: LLMClient,
    ):
        self.name = name
        self.input_queue = input_queue
        self.output_queue = output_queue
        self._redis = redis
        self._llm = llm
        self._running = False
        self._tasks_processed = 0

    async def start(self):
        self._running = True
        logger.info("%s agent started (listen: %s -> %s)", self.name, self.input_queue, self.output_queue)

    async def stop(self):
        self._running = False

    async def run_loop(self):
        """Main processing loop."""
        while self._running:
            try:
                # Blocking pop from input queue (5s timeout)
                result = await self._redis.brpop(self.input_queue, timeout=5)
                if not result:
                    continue

                _, raw = result
                task_data = json.loads(raw)
                task = PipelineTask.from_dict(task_data)

                logger.info("[%s] Processing task %s: %s", self.name, task.id, task.title[:60])

                # Process
                processed = await self.process(task)

                if processed:
                    # Push to next stage
                    await self._redis.lpush(
                        self.output_queue,
                        json.dumps(processed.to_dict(), default=str),
                    )
                    self._tasks_processed += 1
                    logger.info("[%s] Task %s -> %s", self.name, task.id, self.output_queue)

            except asyncio.CancelledError:
                break
            except Exception:
                logger.exception("[%s] Error processing task", self.name)
                await asyncio.sleep(2)

    async def process(self, task: PipelineTask) -> PipelineTask | None:
        """Override in subclass."""
        raise NotImplementedError


class PlannerPipelineAgent(PipelineAgent):
    """Stage 1: Plans the task and estimates revenue."""

    def __init__(self, redis, llm):
        super().__init__("Planner", Q_TASKS, Q_RESEARCH, redis, llm)

    async def process(self, task: PipelineTask) -> PipelineTask | None:
        system = (
            "Du bist der Planner-Agent. Dein Job:\n"
            "1. Bewerte ob diese Aufgabe REALEN Umsatz generieren kann\n"
            "2. Wenn ja: Erstelle einen konkreten Plan (3-5 Schritte)\n"
            "3. Schaetze den moeglichen Umsatz in EUR\n\n"
            "Antworte als JSON:\n"
            '{"is_revenue_relevant": true/false, "revenue_estimate_eur": 0, '
            '"plan": "Schritt 1: ...", "reasoning": "..."}\n'
            "NUR echte, realistische Umsatzschaetzungen. Keine Luftschloesser."
        )

        response = await self._llm.complete(
            f"Aufgabe: {task.title}\n{task.description}",
            system=system,
            temperature=0.3,
        )

        try:
            text = response.strip()
            if text.startswith("```"):
                text = text.split("\n", 1)[1].rsplit("```", 1)[0]
            result = json.loads(text)
        except json.JSONDecodeError:
            result = {"is_revenue_relevant": True, "plan": response, "revenue_estimate_eur": 0}

        # PRUNE non-revenue tasks
        if not result.get("is_revenue_relevant", True):
            task.stage = "pruned"
            task.log_event(self.name, "pruned", {"reason": result.get("reasoning", "no revenue path")})
            await self._redis.lpush(Q_PRUNED, json.dumps(task.to_dict(), default=str))
            logger.info("[Planner] PRUNED task %s: %s", task.id, result.get("reasoning", ""))
            return None

        task.stage = "planned"
        task.plan = result.get("plan", response)
        task.revenue_estimate = result.get("revenue_estimate_eur", 0)
        task.log_event(self.name, "planned", {
            "revenue_estimate": task.revenue_estimate,
            "plan_length": len(task.plan),
        })
        return task


class ResearchPipelineAgent(PipelineAgent):
    """Stage 2: Researches the planned task."""

    def __init__(self, redis, llm):
        super().__init__("Researcher", Q_RESEARCH, Q_BUILD, redis, llm)

    async def process(self, task: PipelineTask) -> PipelineTask | None:
        system = (
            "Du bist der Research-Agent. Analysiere den Plan und liefere:\n"
            "1. Marktanalyse (Zielgruppe, Wettbewerb)\n"
            "2. Technische Machbarkeit\n"
            "3. Konkrete Tools/Ressourcen die noetig sind\n"
            "4. Risiken und Mitigationen\n"
            "Fokus auf UMSETZBARKEIT mit dem vorhandenen AI-Stack."
        )

        response = await self._llm.complete(
            f"Aufgabe: {task.title}\nPlan: {task.plan}",
            system=system,
            temperature=0.4,
        )

        task.stage = "researched"
        task.research = response
        task.log_event(self.name, "researched", {"research_length": len(response)})
        return task


class BuilderPipelineAgent(PipelineAgent):
    """Stage 3: Builds/implements the task."""

    def __init__(self, redis, llm):
        super().__init__("Builder", Q_BUILD, Q_REVIEW, redis, llm)

    async def process(self, task: PipelineTask) -> PipelineTask | None:
        system = (
            "Du bist der Builder-Agent. Erstelle das konkrete Ergebnis:\n"
            "- Code, Konfiguration, Content, Funnel-Texte, etc.\n"
            "- Nutze den vorhandenen Stack: Python, Docker, n8n, Systeme.io\n"
            "- Liefere FERTIGES, kopierbares Material\n"
            "- Kein Theoretisieren - nur Output."
        )

        response = await self._llm.complete(
            f"Aufgabe: {task.title}\nPlan: {task.plan}\nResearch: {task.research[:500]}",
            system=system,
            temperature=0.5,
            max_tokens=4096,
        )

        task.stage = "built"
        task.build_result = response
        task.log_event(self.name, "built", {"result_length": len(response)})
        return task


class CriticPipelineAgent(PipelineAgent):
    """Stage 4: Reviews and scores the result."""

    def __init__(self, redis, llm):
        super().__init__("Critic", Q_REVIEW, Q_REVENUE, redis, llm)

    async def process(self, task: PipelineTask) -> PipelineTask | None:
        system = (
            "Du bist der Critic-Agent. Bewerte das Ergebnis:\n"
            '{"score": 1-10, "revenue_realistic": true/false, '
            '"improvements": "...", "approved": true/false, '
            '"estimated_revenue_eur": 0}\n'
            "Sei streng. Nur ECHTE Umsatzchancen durchlassen.\n"
            "Score < 6 oder revenue_realistic=false -> Task wird verworfen."
        )

        response = await self._llm.complete(
            f"Aufgabe: {task.title}\nErgebnis:\n{task.build_result[:1000]}",
            system=system,
            temperature=0.2,
        )

        try:
            text = response.strip()
            if text.startswith("```"):
                text = text.split("\n", 1)[1].rsplit("```", 1)[0]
            review = json.loads(text)
        except json.JSONDecodeError:
            review = {"score": 5, "approved": True, "improvements": response}

        task.review = review
        task.stage = "reviewed"

        if review.get("approved", True) and review.get("score", 0) >= 6:
            task.stage = "approved"
            task.log_event(self.name, "approved", review)
            # Push to completed
            await self._redis.lpush(Q_COMPLETED, json.dumps(task.to_dict(), default=str))
            logger.info("[Critic] APPROVED task %s (score=%s)", task.id, review.get("score"))
        else:
            task.stage = "rejected"
            task.log_event(self.name, "rejected", review)
            await self._redis.lpush(Q_PRUNED, json.dumps(task.to_dict(), default=str))
            logger.info("[Critic] REJECTED task %s (score=%s)", task.id, review.get("score"))

        # Also push to revenue queue for tracking
        return task


class RevenuePipeline:
    """Manages the full 4-stage pipeline."""

    def __init__(self, redis_url: str, llm: LLMClient):
        self._redis_url = redis_url
        self._llm = llm
        self._redis: aioredis.Redis | None = None
        self._agents: list[PipelineAgent] = []
        self._tasks: list[asyncio.Task] = []

    async def start(self):
        self._redis = aioredis.from_url(self._redis_url, decode_responses=True)
        await self._redis.ping()

        # Create pipeline agents
        self._agents = [
            PlannerPipelineAgent(self._redis, self._llm),
            ResearchPipelineAgent(self._redis, self._llm),
            BuilderPipelineAgent(self._redis, self._llm),
            CriticPipelineAgent(self._redis, self._llm),
        ]

        for agent in self._agents:
            await agent.start()
            task = asyncio.create_task(agent.run_loop())
            self._tasks.append(task)

        logger.info("Revenue pipeline started (4 stages)")

    async def stop(self):
        for agent in self._agents:
            await agent.stop()
        for task in self._tasks:
            task.cancel()
        if self._redis:
            await self._redis.close()

    async def submit(self, title: str, description: str = "", revenue_estimate: float = 0) -> PipelineTask:
        task = PipelineTask(title, description, revenue_estimate)
        await self._redis.lpush(Q_TASKS, json.dumps(task.to_dict(), default=str))
        logger.info("Pipeline task submitted: %s [%s]", title, task.id)
        return task

    async def queue_lengths(self) -> dict[str, int]:
        lengths = {}
        for q in ALL_QUEUES:
            lengths[q] = await self._redis.llen(q)
        return lengths

    async def get_completed(self, limit: int = 10) -> list[dict]:
        raw_list = await self._redis.lrange(Q_COMPLETED, 0, limit - 1)
        return [json.loads(r) for r in raw_list]

    async def get_pruned(self, limit: int = 10) -> list[dict]:
        raw_list = await self._redis.lrange(Q_PRUNED, 0, limit - 1)
        return [json.loads(r) for r in raw_list]

    async def prune_all_non_revenue(self) -> int:
        """Remove all tasks without revenue potential from all queues."""
        pruned = 0
        for q in [Q_TASKS, Q_RESEARCH, Q_BUILD, Q_REVIEW]:
            items = await self._redis.lrange(q, 0, -1)
            for raw in items:
                try:
                    data = json.loads(raw)
                    if data.get("revenue_estimate", 0) <= 0:
                        await self._redis.lrem(q, 1, raw)
                        await self._redis.lpush(Q_PRUNED, raw)
                        pruned += 1
                except Exception:
                    pass
        logger.info("Pruned %d non-revenue tasks", pruned)
        return pruned

    async def run(self):
        """Wait for all pipeline agent tasks to complete."""
        if self._tasks:
            await asyncio.gather(*self._tasks, return_exceptions=True)

    async def stats(self) -> dict:
        """Pipeline stats for Telegram dashboard."""
        lengths = await self.queue_lengths()
        return {
            "plan_queue": lengths.get(Q_TASKS, 0),
            "research_queue": lengths.get(Q_RESEARCH, 0),
            "build_queue": lengths.get(Q_BUILD, 0),
            "review_queue": lengths.get(Q_REVIEW, 0),
            "completed": lengths.get(Q_COMPLETED, 0),
            "pruned": lengths.get(Q_PRUNED, 0),
            "planned": sum(a._tasks_processed for a in self._agents if a.name == "Planner"),
            "researched": sum(a._tasks_processed for a in self._agents if a.name == "Researcher"),
            "built": sum(a._tasks_processed for a in self._agents if a.name == "Builder"),
            "approved": sum(a._tasks_processed for a in self._agents if a.name == "Critic"),
        }

    async def revenue_summary(self) -> dict:
        """Calculate total revenue pipeline."""
        completed = await self.get_completed(100)
        total_estimated = sum(t.get("revenue_estimate", 0) for t in completed)
        approved = [t for t in completed if t.get("stage") == "approved"]
        queues = await self.queue_lengths()
        return {
            "total_tasks_completed": len(completed),
            "approved_tasks": len(approved),
            "total_revenue_estimated_eur": total_estimated,
            "pipeline_queues": queues,
        }
