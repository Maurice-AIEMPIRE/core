"""Self-Improvement Loop - Analyzes pipeline performance and generates improvements.

Runs every 30 minutes:
1. Query last 20 completed tasks
2. Calculate success_rate, revenue_impact, bottlenecks
3. Generate improvement tasks
4. Push to pipeline
"""

from __future__ import annotations

import asyncio
import json
import logging
import time

import redis.asyncio as aioredis

from llm.client import LLMClient

logger = logging.getLogger("galaxia.improve")


class SelfImproveLoop:
    """Analyzes system performance and generates improvement tasks."""

    def __init__(
        self,
        redis_url: str,
        llm: LLMClient,
        cycle_seconds: int = 1800,  # 30 min
    ):
        self._redis_url = redis_url
        self._llm = llm
        self._cycle_seconds = cycle_seconds
        self._redis: aioredis.Redis | None = None
        self._running = False
        self._cycles = 0

    async def start(self):
        self._redis = aioredis.from_url(self._redis_url, decode_responses=True)
        self._running = True
        logger.info("Self-Improvement loop started (cycle: %ds)", self._cycle_seconds)

    async def stop(self):
        self._running = False
        if self._redis:
            await self._redis.close()

    async def run_loop(self):
        # Wait 15 min before first cycle (offset from revenue engine)
        await asyncio.sleep(900)
        while self._running:
            try:
                await self._analyze_and_improve()
            except asyncio.CancelledError:
                break
            except Exception:
                logger.exception("Self-improvement cycle error")
            await asyncio.sleep(self._cycle_seconds)

    async def _analyze_and_improve(self):
        self._cycles += 1
        logger.info("Self-improvement cycle %d", self._cycles)

        # Gather data
        completed_raw = await self._redis.lrange("galaxia.completed", 0, 19)
        pruned_raw = await self._redis.lrange("galaxia.pruned", 0, 19)

        completed = [json.loads(r) for r in completed_raw]
        pruned = [json.loads(r) for r in pruned_raw]

        # Calculate metrics
        total = len(completed) + len(pruned)
        if total == 0:
            logger.info("No tasks to analyze yet")
            return

        success_rate = len(completed) / total * 100 if total > 0 else 0
        total_revenue = sum(t.get("revenue_estimate", 0) for t in completed)
        avg_revenue = total_revenue / len(completed) if completed else 0

        # Find bottlenecks (tasks stuck in queues)
        queue_lengths = {}
        for q in ["galaxia.tasks", "galaxia.research", "galaxia.build", "galaxia.review"]:
            queue_lengths[q] = await self._redis.llen(q)

        bottleneck = max(queue_lengths, key=queue_lengths.get) if queue_lengths else "none"

        metrics = {
            "success_rate": round(success_rate, 1),
            "total_revenue_eur": total_revenue,
            "avg_revenue_eur": round(avg_revenue, 1),
            "completed": len(completed),
            "pruned": len(pruned),
            "queue_lengths": queue_lengths,
            "bottleneck": bottleneck,
        }

        # Store metrics
        await self._redis.set(
            "galaxia:metrics:latest",
            json.dumps(metrics, default=str),
            ex=7200,
        )

        # Generate improvement tasks
        system = (
            "Du analysierst die Performance eines AI-Agent-Systems.\n"
            "Generiere 1 konkrete Verbesserung als JSON:\n"
            '{"title": "...", "description": "...", "revenue_eur": 0}\n'
            "Die Verbesserung muss entweder:\n"
            "- Bestehende Revenue-Tasks effizienter machen\n"
            "- Neue Revenue-Quellen erschliessen\n"
            "- Bottlenecks im Pipeline beseitigen\n"
            "Nur das JSON."
        )

        response = await self._llm.complete(
            f"Aktuelle Metriken:\n{json.dumps(metrics, indent=2)}",
            system=system,
            temperature=0.4,
        )

        try:
            text = response.strip()
            if text.startswith("```"):
                text = text.split("\n", 1)[1].rsplit("```", 1)[0]
            improvement = json.loads(text)

            task = {
                "id": f"imp-{int(time.time())}",
                "title": f"[IMPROVE] {improvement.get('title', 'System Improvement')}",
                "description": improvement.get("description", ""),
                "revenue_estimate": improvement.get("revenue_eur", 0),
                "stage": "submitted",
                "source": "self_improve",
                "plan": "", "research": "", "build_result": "", "review": {},
                "created_at": time.time(),
                "history": [{"agent": "SelfImprove", "event": "generated", "ts": time.time()}],
            }

            await self._redis.lpush("galaxia.tasks", json.dumps(task, default=str))
            logger.info("Improvement task: %s", improvement.get("title", ""))

        except json.JSONDecodeError:
            logger.warning("Could not parse improvement suggestion")

        logger.info(
            "Self-improve metrics: success=%.0f%% revenue=%d EUR bottleneck=%s",
            success_rate, total_revenue, bottleneck,
        )
