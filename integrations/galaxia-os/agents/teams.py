"""Agent Teams - Specialized agent groups for business domains.

Instead of 1000 generic agents, we use 5 focused teams:
- Revenue Team: sales funnels, pricing, offers
- Marketing Team: content, social media, campaigns
- Dev Team: code, automation, tooling
- Research Team: market analysis, competitors, trends
- Operations Team: system health, optimization, monitoring
"""

from __future__ import annotations

import logging

from agents.base import BaseAgent, ExecutorAgent
from llm.client import LLMClient
from taskqueue.task_queue import TaskQueue
from registry.agent_registry import AgentRegistry
from shared.models import AgentRole
from shared.redis_bus import RedisBus

logger = logging.getLogger("galaxia.teams")


class RevenueAgent(ExecutorAgent):
    """Specialized agent for revenue generation tasks."""

    def __init__(self, bus, registry, task_queue, llm, **kwargs):
        super().__init__(bus, registry, task_queue, llm, **kwargs)
        self.info.name = "Revenue Agent"
        self.info.capabilities = [
            "sales_funnel", "pricing", "offer_creation",
            "lead_generation", "systemeio", "upsell",
        ]

    async def execute(self, task):
        system = (
            "Du bist ein Revenue-Agent. Dein Ziel: Umsatz generieren.\n"
            "Du kennst: Systeme.io Funnels, Email-Marketing, Preisstrategien.\n"
            "Liefere konkrete, umsetzbare Ergebnisse."
        )
        return await self._llm.complete(
            f"Aufgabe: {task.title}\n{task.description}",
            system=system,
            temperature=0.5,
        )


class MarketingAgent(ExecutorAgent):
    """Specialized agent for marketing and content."""

    def __init__(self, bus, registry, task_queue, llm, **kwargs):
        super().__init__(bus, registry, task_queue, llm, **kwargs)
        self.info.name = "Marketing Agent"
        self.info.capabilities = [
            "content_creation", "social_media", "newsletter",
            "copywriting", "seo", "campaign",
        ]

    async def execute(self, task):
        system = (
            "Du bist ein Marketing-Agent. Du erstellst Content und Kampagnen.\n"
            "Du kennst: Social Media, Newsletter, SEO, Copywriting.\n"
            "Schreibe in deutscher Sprache, professionell aber nahbar."
        )
        return await self._llm.complete(
            f"Aufgabe: {task.title}\n{task.description}",
            system=system,
            temperature=0.7,
        )


class DevAgent(ExecutorAgent):
    """Specialized agent for development and automation."""

    def __init__(self, bus, registry, task_queue, llm, **kwargs):
        super().__init__(bus, registry, task_queue, llm, **kwargs)
        self.info.name = "Dev Agent"
        self.info.capabilities = [
            "coding", "automation", "n8n_workflows",
            "docker", "api", "scripting",
        ]

    async def execute(self, task):
        system = (
            "Du bist ein Dev-Agent. Du schreibst Code und baust Automationen.\n"
            "Stack: Python, TypeScript, Docker, n8n, Redis, PostgreSQL.\n"
            "Schreibe sauberen, produktionsreifen Code."
        )
        return await self._llm.complete(
            f"Aufgabe: {task.title}\n{task.description}",
            system=system,
            temperature=0.3,
        )


class ResearchAgent(ExecutorAgent):
    """Specialized agent for research and analysis."""

    def __init__(self, bus, registry, task_queue, llm, **kwargs):
        super().__init__(bus, registry, task_queue, llm, **kwargs)
        self.info.name = "Research Agent"
        self.info.capabilities = [
            "market_research", "competitor_analysis", "trend_analysis",
            "data_analysis", "report",
        ]

    async def execute(self, task):
        system = (
            "Du bist ein Research-Agent. Du analysierst Märkte und Trends.\n"
            "Liefere datengetriebene Erkenntnisse und konkrete Empfehlungen.\n"
            "Fokus auf AI-Services, Automation, Digital Products."
        )
        return await self._llm.complete(
            f"Aufgabe: {task.title}\n{task.description}",
            system=system,
            temperature=0.4,
        )


class OpsAgent(ExecutorAgent):
    """Specialized agent for operations and monitoring."""

    def __init__(self, bus, registry, task_queue, llm, **kwargs):
        super().__init__(bus, registry, task_queue, llm, **kwargs)
        self.info.name = "Ops Agent"
        self.info.capabilities = [
            "monitoring", "health_check", "optimization",
            "docker_management", "resource_management",
        ]

    async def execute(self, task):
        system = (
            "Du bist ein Ops-Agent. Du überwachst und optimierst das System.\n"
            "Du kennst: Docker, Prometheus, Grafana, Redis, Ollama.\n"
            "Liefere konkrete Diagnosen und Fixvorschläge."
        )
        return await self._llm.complete(
            f"Aufgabe: {task.title}\n{task.description}",
            system=system,
            temperature=0.2,
        )


def create_agent_teams(
    bus: RedisBus,
    registry: AgentRegistry,
    task_queue: TaskQueue,
    llm: LLMClient,
) -> list[BaseAgent]:
    """Create the 5-agent team fleet."""
    return [
        RevenueAgent(bus, registry, task_queue, llm),
        MarketingAgent(bus, registry, task_queue, llm),
        DevAgent(bus, registry, task_queue, llm),
        ResearchAgent(bus, registry, task_queue, llm),
        OpsAgent(bus, registry, task_queue, llm),
    ]
