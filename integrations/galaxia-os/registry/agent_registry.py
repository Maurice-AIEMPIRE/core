"""Agent Registry - Manages agent lifecycle, health, and task assignment."""

from __future__ import annotations

import logging
from datetime import datetime, timezone

from shared.models import AgentInfo, AgentRole, AgentStatus, Task
from shared.redis_bus import RedisBus

logger = logging.getLogger("galaxia.registry")


class AgentRegistry:
    """Central registry for all Galaxia agents."""

    def __init__(self, bus: RedisBus):
        self._bus = bus
        self._agents: dict[str, AgentInfo] = {}

    async def register(self, agent: AgentInfo) -> None:
        self._agents[agent.id] = agent
        await self._bus.store_agent(agent.id, agent.model_dump(mode="json"))
        logger.info("Agent registered: %s (%s) role=%s", agent.name, agent.id, agent.role)

    async def unregister(self, agent_id: str) -> None:
        if agent_id in self._agents:
            del self._agents[agent_id]
        await self._bus.remove_agent(agent_id)
        logger.info("Agent unregistered: %s", agent_id)

    async def heartbeat(self, agent_id: str) -> None:
        agent = self._agents.get(agent_id)
        if agent:
            agent.last_heartbeat = datetime.now(timezone.utc)
            await self._bus.store_agent(agent_id, agent.model_dump(mode="json"))

    def get(self, agent_id: str) -> AgentInfo | None:
        return self._agents.get(agent_id)

    def get_by_role(self, role: AgentRole) -> list[AgentInfo]:
        return [a for a in self._agents.values() if a.role == role]

    def get_idle(self, role: AgentRole | None = None) -> list[AgentInfo]:
        agents = self._agents.values()
        if role:
            agents = [a for a in agents if a.role == role]
        return [a for a in agents if a.status == AgentStatus.IDLE]

    def all_agents(self) -> list[AgentInfo]:
        return list(self._agents.values())

    async def assign_task(self, agent_id: str, task: Task) -> bool:
        agent = self._agents.get(agent_id)
        if not agent or agent.status != AgentStatus.IDLE:
            return False

        agent.status = AgentStatus.BUSY
        agent.current_task_id = task.id
        await self._bus.store_agent(agent_id, agent.model_dump(mode="json"))
        logger.info("Task %s assigned to agent %s (%s)", task.id, agent.name, agent.id)
        return True

    async def complete_task(self, agent_id: str, success: bool = True) -> None:
        agent = self._agents.get(agent_id)
        if not agent:
            return

        agent.status = AgentStatus.IDLE
        agent.current_task_id = None
        if success:
            agent.tasks_completed += 1
        else:
            agent.tasks_failed += 1
        await self._bus.store_agent(agent_id, agent.model_dump(mode="json"))

    async def load_from_redis(self) -> None:
        """Reload agent state from Redis (after restart)."""
        stored = await self._bus.get_all_agents()
        for agent_id, data in stored.items():
            try:
                agent = AgentInfo.model_validate(data)
                self._agents[agent_id] = agent
            except Exception:
                logger.warning("Could not load agent %s from Redis", agent_id)
        logger.info("Loaded %d agents from Redis", len(self._agents))
