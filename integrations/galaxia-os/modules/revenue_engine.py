"""Revenue Engine - Auto-generates revenue-positive tasks.

Only creates tasks with clear monetization paths.
Runs every 30 minutes and pushes to the pipeline.
"""

from __future__ import annotations

import asyncio
import json
import logging
import time

import redis.asyncio as aioredis

from llm.client import LLMClient

logger = logging.getLogger("galaxia.revenue")

# Proven revenue categories for AI services
REVENUE_TEMPLATES = [
    {
        "category": "AI Automation Service",
        "examples": [
            "Bewerbungs-Automatisierung SaaS (500 EUR/Monat pro Kunde)",
            "Email-Marketing Automation Setup (800 EUR einmalig)",
            "Social Media Content Pipeline (300 EUR/Monat)",
            "Kundensupport Bot Setup (1500 EUR einmalig + 200 EUR/Monat)",
        ],
    },
    {
        "category": "Digital Products",
        "examples": [
            "AI Automation Kurs auf Systeme.io (297 EUR)",
            "Prompt Engineering Guide (47 EUR)",
            "n8n Workflow Templates Pack (97 EUR)",
            "AI Business Starter Kit (197 EUR)",
        ],
    },
    {
        "category": "Sales Funnels",
        "examples": [
            "Hetzner AI Server Setup Funnel (Lead Gen -> Consulting)",
            "AI Automation Audit Funnel (kostenlos Audit -> bezahltes Setup)",
            "KI-Beratung Landing Page (197 EUR/Stunde)",
        ],
    },
    {
        "category": "Consulting & Services",
        "examples": [
            "AI Stack Setup fuer KMUs (2000-5000 EUR)",
            "Ollama/LLM Integration Workshop (500 EUR/Teilnehmer)",
            "Custom Chatbot Development (3000 EUR)",
        ],
    },
]


class RevenueEngine:
    """Generates revenue-focused tasks for the pipeline."""

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
        self._tasks_generated = 0

    async def start(self):
        self._redis = aioredis.from_url(self._redis_url, decode_responses=True)
        await self._redis.ping()
        self._running = True
        logger.info("Revenue Engine started (cycle: %ds)", self._cycle_seconds)

    async def stop(self):
        self._running = False
        if self._redis:
            await self._redis.close()

    async def run(self):
        """Alias for run_loop."""
        await self.run_loop()

    async def run_loop(self):
        """Main revenue generation loop."""
        while self._running:
            try:
                await self._generate_cycle()
            except asyncio.CancelledError:
                break
            except Exception:
                logger.exception("Revenue engine cycle error")
            await asyncio.sleep(self._cycle_seconds)

    async def _generate_cycle(self):
        """Generate 1-3 revenue tasks per cycle."""
        logger.info("Revenue Engine: generating tasks...")

        # Get existing tasks to avoid duplicates
        existing = await self._redis.lrange("galaxia.tasks", 0, -1)
        existing_titles = set()
        for raw in existing:
            try:
                data = json.loads(raw)
                existing_titles.add(data.get("title", "").lower())
            except Exception:
                pass

        # Use LLM to generate context-aware revenue ideas
        system = (
            "Du bist ein Revenue-Generator fuer ein AI-Unternehmen.\n"
            "Infrastruktur: Ollama (14B Modelle), n8n, Redis, Docker, Telegram Bot.\n"
            "Generiere 2 KONKRETE, REALISTISCHE Umsatzideen.\n\n"
            "Regeln:\n"
            "- NUR echte Produkte/Services die mit dem Stack umsetzbar sind\n"
            "- Jede Idee muss einen konkreten EUR-Betrag haben\n"
            "- Keine Luftschloesser, keine '1M EUR in 30 Tagen'\n"
            "- Realistische Zielgruppe nennen\n\n"
            "Antworte als JSON-Array:\n"
            '[{"title": "...", "description": "...", "revenue_eur": 0, "timeframe_days": 0}]\n'
            "Nur das JSON."
        )

        # Include revenue templates as context
        import random
        template = random.choice(REVENUE_TEMPLATES)
        context = f"Kategorie-Fokus: {template['category']}\nBeispiele: {', '.join(template['examples'][:2])}"

        response = await self._llm.complete(
            f"Generiere 2 Revenue-Tasks.\n{context}",
            system=system,
            temperature=0.6,
        )

        try:
            text = response.strip()
            if text.startswith("```"):
                text = text.split("\n", 1)[1].rsplit("```", 1)[0]
            ideas = json.loads(text)
        except json.JSONDecodeError:
            logger.warning("Could not parse revenue ideas")
            return

        for idea in ideas[:3]:
            title = idea.get("title", "")
            if not title or title.lower() in existing_titles:
                continue

            task = {
                "id": f"rev-{int(time.time())}-{self._tasks_generated}",
                "title": title,
                "description": idea.get("description", ""),
                "revenue_estimate": idea.get("revenue_eur", 0),
                "stage": "submitted",
                "source": "revenue_engine",
                "plan": "",
                "research": "",
                "build_result": "",
                "review": {},
                "created_at": time.time(),
                "history": [{"agent": "RevenueEngine", "event": "generated", "ts": time.time()}],
            }

            await self._redis.lpush("galaxia.tasks", json.dumps(task, default=str))
            self._tasks_generated += 1
            logger.info("Revenue task generated: %s (est. %s EUR)", title, idea.get("revenue_eur", 0))

    async def get_stats(self) -> dict:
        return {
            "tasks_generated": self._tasks_generated,
            "cycle_seconds": self._cycle_seconds,
        }
