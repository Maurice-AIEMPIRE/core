"""Empire Brain - Autonomous business loop for Pfeifer Galaxia OS.

The Brain runs on a configurable cycle (default: 10 min) and:
1. Analyzes current state (revenue, agents, tasks, opportunities)
2. Uses LLM to generate strategic decisions
3. Creates actionable tasks from decisions
4. Routes tasks to specialized Agent Teams
5. Evaluates results and adapts strategy

This replaces the simple `while True: ask("generate business idea")` loop
with a structured, memory-backed, multi-agent decision system.
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field

from llm.client import LLMClient
from memory.memory import MemorySystem
from shared.models import TaskPriority

logger = logging.getLogger("galaxia.brain")

# Brain cycle interval
DEFAULT_CYCLE_SECONDS = 600  # 10 minutes


class BusinessDomain(str, Enum):
    REVENUE = "revenue"
    MARKETING = "marketing"
    PRODUCT = "product"
    DEVELOPMENT = "development"
    OPERATIONS = "operations"


class Decision(BaseModel):
    """A strategic decision made by the Empire Brain."""
    domain: BusinessDomain
    action: str
    reasoning: str
    priority: int = 5  # 1-10
    estimated_impact: str = ""


class BrainState(BaseModel):
    """Current state of the Empire Brain."""
    cycle_count: int = 0
    decisions_made: int = 0
    tasks_generated: int = 0
    last_cycle_at: float = 0
    active_strategies: list[str] = Field(default_factory=list)


class EmpireBrain:
    """The strategic AI brain that drives business decisions."""

    def __init__(
        self,
        llm: LLMClient,
        memory: MemorySystem,
        task_submitter,  # callable: async (title, desc, priority) -> Task
        cycle_seconds: int = DEFAULT_CYCLE_SECONDS,
    ):
        self._llm = llm
        self._memory = memory
        self._submit_task = task_submitter
        self._cycle_seconds = cycle_seconds
        self._state = BrainState()
        self._running = False
        self._strategies: list[str] = []

    async def start(self) -> None:
        """Load state and start the brain loop."""
        saved = await self._memory.recall_long("brain", "state")
        if saved:
            try:
                self._state = BrainState.model_validate(saved)
                logger.info("Brain state restored: %d cycles completed", self._state.cycle_count)
            except Exception:
                pass

        saved_strategies = await self._memory.recall_long("brain", "strategies")
        if saved_strategies:
            self._strategies = saved_strategies
            self._state.active_strategies = saved_strategies

        self._running = True
        logger.info("Empire Brain started (cycle: %ds)", self._cycle_seconds)

    async def stop(self) -> None:
        self._running = False
        await self._save_state()
        logger.info("Empire Brain stopped")

    async def run_loop(self) -> None:
        """Main brain loop - runs until stopped."""
        while self._running:
            try:
                await self._run_cycle()
            except asyncio.CancelledError:
                break
            except Exception:
                logger.exception("Brain cycle error")

            await asyncio.sleep(self._cycle_seconds)

    async def _run_cycle(self) -> None:
        """Execute one brain cycle: analyze -> decide -> act."""
        cycle_start = time.time()
        self._state.cycle_count += 1
        logger.info("=== BRAIN CYCLE %d ===", self._state.cycle_count)

        # 1. Gather context
        context = await self._gather_context()

        # 2. Generate decisions
        decisions = await self._think(context)

        # 3. Create tasks from decisions
        for decision in decisions:
            await self._act(decision)

        # 4. Save state
        self._state.last_cycle_at = time.time()
        await self._save_state()

        duration = time.time() - cycle_start
        logger.info(
            "Brain cycle %d complete: %d decisions, %.1fs",
            self._state.cycle_count, len(decisions), duration,
        )

    async def _gather_context(self) -> dict[str, Any]:
        """Gather current business state for the brain."""
        # Recent task results
        recent_results = await self._memory.recall_all_long("task_results")

        # Active strategies
        strategies = self._strategies

        # Knowledge base
        knowledge = await self._memory.search_knowledge("business")
        knowledge.extend(await self._memory.search_knowledge("revenue"))
        knowledge.extend(await self._memory.search_knowledge("marketing"))

        # Previous brain decisions
        prev_decisions = await self._memory.recall_long("brain", "last_decisions")

        return {
            "cycle": self._state.cycle_count,
            "active_strategies": strategies,
            "recent_results": list(recent_results.values())[-5:] if recent_results else [],
            "knowledge": [k.get("content", "") for k in knowledge[:5]],
            "previous_decisions": prev_decisions or [],
            "total_decisions": self._state.decisions_made,
            "total_tasks": self._state.tasks_generated,
        }

    async def _think(self, context: dict) -> list[Decision]:
        """Use LLM to generate strategic decisions."""
        system = (
            "Du bist der strategische Brain eines autonomen KI-Unternehmens "
            "(Pfeifer Galaxia OS). Dein Ziel: Umsatz generieren durch AI-Services.\n\n"
            "Geschäftsfelder:\n"
            "- AI Automation Services (n8n Workflows für Kunden)\n"
            "- Content Generation (Blog, Social Media, Newsletter)\n"
            "- Lead Generation (Systeme.io Funnels)\n"
            "- Digital Products (Kurse, Templates, Tools)\n"
            "- AI Consulting (Setup, Training)\n\n"
            "Verfügbare Infrastruktur:\n"
            "- Ollama (70B/72B Modelle), LiteLLM, n8n, Telegram Bot\n"
            "- Vector DBs (Qdrant, Chroma), Neo4j, Redis\n"
            "- 5 spezialisierte Agents\n\n"
            "Antworte als JSON-Array mit max 3 Entscheidungen:\n"
            '[{"domain": "revenue|marketing|product|development|operations", '
            '"action": "Konkrete Aktion", "reasoning": "Warum", '
            '"priority": 1-10, "estimated_impact": "Erwarteter Effekt"}]\n'
            "Nur das JSON, keine Erklärung."
        )

        context_str = json.dumps(context, default=str, ensure_ascii=False, indent=2)
        prompt = f"Aktueller Status:\n{context_str}\n\nWas sind die nächsten 1-3 strategischen Aktionen?"

        response = await self._llm.complete(prompt, system=system, temperature=0.4)

        decisions = []
        try:
            text = response.strip()
            if text.startswith("```"):
                text = text.split("\n", 1)[1].rsplit("```", 1)[0]
            raw = json.loads(text)
            for item in raw[:3]:
                decisions.append(Decision.model_validate(item))
        except (json.JSONDecodeError, Exception) as e:
            logger.warning("Could not parse brain response: %s", e)
            # Fallback: create one generic decision
            decisions.append(Decision(
                domain=BusinessDomain.OPERATIONS,
                action="System-Health-Check durchführen",
                reasoning="Parsing fehlgeschlagen, Fallback-Aktion",
                priority=3,
            ))

        self._state.decisions_made += len(decisions)
        await self._memory.remember_long("brain", "last_decisions",
            [d.model_dump() for d in decisions])

        return decisions

    async def _act(self, decision: Decision) -> None:
        """Turn a decision into an actionable task."""
        priority_map = {
            (1, 3): TaskPriority.LOW,
            (4, 6): TaskPriority.NORMAL,
            (7, 9): TaskPriority.HIGH,
            (10, 10): TaskPriority.CRITICAL,
        }
        task_priority = TaskPriority.NORMAL
        for (lo, hi), tp in priority_map.items():
            if lo <= decision.priority <= hi:
                task_priority = tp
                break

        task = await self._submit_task(
            title=f"[{decision.domain.upper()}] {decision.action}",
            description=(
                f"Strategische Entscheidung von Empire Brain (Zyklus {self._state.cycle_count}).\n\n"
                f"Begründung: {decision.reasoning}\n"
                f"Erwarteter Impact: {decision.estimated_impact}\n"
                f"Priorität: {decision.priority}/10"
            ),
            priority=task_priority,
        )
        self._state.tasks_generated += 1

        # Log to memory
        await self._memory.log_task(task.id, "brain_decision", {
            "domain": decision.domain,
            "action": decision.action,
            "cycle": self._state.cycle_count,
        })

        logger.info(
            "Brain -> Task [%s] %s (priority=%d)",
            decision.domain, decision.action[:60], decision.priority,
        )

    async def _save_state(self) -> None:
        await self._memory.remember_long("brain", "state", self._state.model_dump())
        await self._memory.remember_long("brain", "strategies", self._strategies)

    # === Manual Controls ===

    async def add_strategy(self, strategy: str) -> None:
        """Add a strategic focus area."""
        self._strategies.append(strategy)
        self._state.active_strategies = self._strategies
        await self._save_state()
        logger.info("Strategy added: %s", strategy)

    async def force_cycle(self) -> list[Decision]:
        """Force an immediate brain cycle (from Telegram /think command)."""
        context = await self._gather_context()
        decisions = await self._think(context)
        for d in decisions:
            await self._act(d)
        await self._save_state()
        return decisions

    def get_state(self) -> BrainState:
        return self._state
