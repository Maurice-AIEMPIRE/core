"""Agent Teams - Specialized agent groups for business domains.

SuperGrok Fleet: 50 agents across 10 specialized teams:
- Revenue Team (8): sales funnels, pricing, offers, upselling
- Marketing Team (6): content, social media, campaigns, SEO
- Dev Team (6): code, automation, tooling, APIs
- Research Team (4): market analysis, competitors, trends
- Operations Team (4): system health, optimization, monitoring
- Funnel Team (5): Systeme.io funnels, landing pages, email sequences
- Consulting Team (4): client management, proposals, onboarding
- Content Team (5): blog, video scripts, courses, lead magnets
- Analytics Team (4): data analysis, KPIs, reporting, forecasting
- Growth Team (4): scaling, partnerships, affiliate, outreach
"""

from __future__ import annotations

import logging
import os

from agents.base import BaseAgent, ExecutorAgent
from llm.client import LLMClient
from taskqueue.task_queue import TaskQueue
from registry.agent_registry import AgentRegistry
from shared.models import AgentRole
from shared.redis_bus import RedisBus

logger = logging.getLogger("galaxia.teams")

# Number of agents per team - configurable via env
FLEET_SIZE = int(os.getenv("GALAXIA_FLEET_SIZE", "50"))


class RevenueAgent(ExecutorAgent):
    """Specialized agent for revenue generation tasks."""

    def __init__(self, bus, registry, task_queue, llm, instance=0, **kwargs):
        super().__init__(bus, registry, task_queue, llm, **kwargs)
        self.info.name = f"Revenue Agent #{instance + 1}"
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

    def __init__(self, bus, registry, task_queue, llm, instance=0, **kwargs):
        super().__init__(bus, registry, task_queue, llm, **kwargs)
        self.info.name = f"Marketing Agent #{instance + 1}"
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

    def __init__(self, bus, registry, task_queue, llm, instance=0, **kwargs):
        super().__init__(bus, registry, task_queue, llm, **kwargs)
        self.info.name = f"Dev Agent #{instance + 1}"
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

    def __init__(self, bus, registry, task_queue, llm, instance=0, **kwargs):
        super().__init__(bus, registry, task_queue, llm, **kwargs)
        self.info.name = f"Research Agent #{instance + 1}"
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

    def __init__(self, bus, registry, task_queue, llm, instance=0, **kwargs):
        super().__init__(bus, registry, task_queue, llm, **kwargs)
        self.info.name = f"Ops Agent #{instance + 1}"
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


class FunnelAgent(ExecutorAgent):
    """Specialized agent for Systeme.io funnels and email sequences."""

    def __init__(self, bus, registry, task_queue, llm, instance=0, **kwargs):
        super().__init__(bus, registry, task_queue, llm, **kwargs)
        self.info.name = f"Funnel Agent #{instance + 1}"
        self.info.capabilities = [
            "systemeio_funnel", "landing_page", "email_sequence",
            "checkout", "ab_testing", "conversion",
        ]

    async def execute(self, task):
        system = (
            "Du bist ein Funnel-Agent spezialisiert auf Systeme.io.\n"
            "Du erstellst: Landing Pages, Email-Sequenzen, Checkout-Flows, A/B Tests.\n"
            "Ziel: Maximale Conversion Rate und Customer Lifetime Value."
        )
        return await self._llm.complete(
            f"Aufgabe: {task.title}\n{task.description}",
            system=system,
            temperature=0.4,
        )


class ConsultingAgent(ExecutorAgent):
    """Specialized agent for consulting and client management."""

    def __init__(self, bus, registry, task_queue, llm, instance=0, **kwargs):
        super().__init__(bus, registry, task_queue, llm, **kwargs)
        self.info.name = f"Consulting Agent #{instance + 1}"
        self.info.capabilities = [
            "client_management", "proposals", "onboarding",
            "project_management", "consulting",
        ]

    async def execute(self, task):
        system = (
            "Du bist ein Consulting-Agent. Du managst Kunden und Projekte.\n"
            "Du erstellst: Angebote, Onboarding-Pläne, Projekt-Updates.\n"
            "Kommuniziere professionell, klar und ergebnisorientiert."
        )
        return await self._llm.complete(
            f"Aufgabe: {task.title}\n{task.description}",
            system=system,
            temperature=0.4,
        )


class ContentAgent(ExecutorAgent):
    """Specialized agent for content creation (blogs, courses, lead magnets)."""

    def __init__(self, bus, registry, task_queue, llm, instance=0, **kwargs):
        super().__init__(bus, registry, task_queue, llm, **kwargs)
        self.info.name = f"Content Agent #{instance + 1}"
        self.info.capabilities = [
            "blog_writing", "video_script", "course_creation",
            "lead_magnet", "ebook", "whitepaper",
        ]

    async def execute(self, task):
        system = (
            "Du bist ein Content-Agent. Du erstellst hochwertige Inhalte.\n"
            "Du schreibst: Blog-Posts, Video-Skripte, Kurs-Inhalte, Lead Magnets.\n"
            "Stil: Deutsch, Expertenlevel, SEO-optimiert, actionable."
        )
        return await self._llm.complete(
            f"Aufgabe: {task.title}\n{task.description}",
            system=system,
            temperature=0.7,
        )


class AnalyticsAgent(ExecutorAgent):
    """Specialized agent for data analytics, KPIs, and forecasting."""

    def __init__(self, bus, registry, task_queue, llm, instance=0, **kwargs):
        super().__init__(bus, registry, task_queue, llm, **kwargs)
        self.info.name = f"Analytics Agent #{instance + 1}"
        self.info.capabilities = [
            "data_analysis", "kpi_tracking", "reporting",
            "forecasting", "dashboard", "metrics",
        ]

    async def execute(self, task):
        system = (
            "Du bist ein Analytics-Agent. Du analysierst Daten und KPIs.\n"
            "Du erstellst: Reports, Dashboards, Forecasts, Empfehlungen.\n"
            "Arbeite datengetrieben und liefere klare Zahlen."
        )
        return await self._llm.complete(
            f"Aufgabe: {task.title}\n{task.description}",
            system=system,
            temperature=0.3,
        )


class GrowthAgent(ExecutorAgent):
    """Specialized agent for growth, partnerships, and scaling."""

    def __init__(self, bus, registry, task_queue, llm, instance=0, **kwargs):
        super().__init__(bus, registry, task_queue, llm, **kwargs)
        self.info.name = f"Growth Agent #{instance + 1}"
        self.info.capabilities = [
            "scaling", "partnerships", "affiliate_marketing",
            "outreach", "growth_hacking", "referral",
        ]

    async def execute(self, task):
        system = (
            "Du bist ein Growth-Agent. Du skalierst das Business.\n"
            "Du findest: Partnerschaften, Affiliate-Deals, Outreach-Strategien.\n"
            "Fokus auf skalierbare, automatisierbare Wachstumskanäle."
        )
        return await self._llm.complete(
            f"Aufgabe: {task.title}\n{task.description}",
            system=system,
            temperature=0.5,
        )


# Team configuration: (AgentClass, count)
# Total: 8+6+6+4+4+5+4+5+4+4 = 50 agents
TEAM_CONFIG = [
    (RevenueAgent, 8),
    (MarketingAgent, 6),
    (DevAgent, 6),
    (ResearchAgent, 4),
    (OpsAgent, 4),
    (FunnelAgent, 5),
    (ConsultingAgent, 4),
    (ContentAgent, 5),
    (AnalyticsAgent, 4),
    (GrowthAgent, 4),
]


def create_agent_teams(
    bus: RedisBus,
    registry: AgentRegistry,
    task_queue: TaskQueue,
    llm: LLMClient,
) -> list[BaseAgent]:
    """Create the 50-agent SuperGrok fleet across 10 specialized teams."""
    agents: list[BaseAgent] = []

    for agent_cls, count in TEAM_CONFIG:
        for i in range(count):
            agents.append(agent_cls(bus, registry, task_queue, llm, instance=i))

    logger.info(
        "SuperGrok fleet created: %d agents across %d teams",
        len(agents),
        len(TEAM_CONFIG),
    )
    return agents
