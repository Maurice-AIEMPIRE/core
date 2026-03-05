"""Base Agent - Abstract base class for all Galaxia agents."""

from __future__ import annotations

import asyncio
import logging
from abc import ABC, abstractmethod

from llm.client import LLMClient
from shared.models import AgentInfo, AgentRole, AgentStatus, Message, Task, TaskStatus
from shared.redis_bus import RedisBus, agent_channel, CHANNEL_BROADCAST
from registry.agent_registry import AgentRegistry
from taskqueue.task_queue import TaskQueue

logger = logging.getLogger("galaxia.agent")


class BaseAgent(ABC):
    """Base class for all Galaxia OS agents."""

    def __init__(
        self,
        name: str,
        role: AgentRole,
        bus: RedisBus,
        registry: AgentRegistry,
        task_queue: TaskQueue,
        llm: LLMClient,
        capabilities: list[str] | None = None,
        model: str = "qwen3-14b",
    ):
        self.info = AgentInfo(
            name=name,
            role=role,
            capabilities=capabilities or [],
            model=model,
        )
        self._bus = bus
        self._registry = registry
        self._task_queue = task_queue
        self._llm = llm
        self._running = False

    @property
    def id(self) -> str:
        return self.info.id

    @property
    def name(self) -> str:
        return self.info.name

    async def start(self) -> None:
        await self._registry.register(self.info)
        await self._bus.subscribe(agent_channel(self.id), self._handle_message)
        await self._bus.subscribe(CHANNEL_BROADCAST, self._handle_message)
        self._running = True
        logger.info("Agent %s (%s) started", self.name, self.id)

    async def stop(self) -> None:
        self._running = False
        await self._registry.unregister(self.id)
        logger.info("Agent %s stopped", self.name)

    async def _handle_message(self, msg: Message) -> None:
        if msg.msg_type == "task_assign":
            task_data = msg.payload.get("task")
            if task_data:
                task = Task.model_validate(task_data)
                await self._execute_task(task)
        elif msg.msg_type == "command":
            await self.handle_command(msg)

    async def _execute_task(self, task: Task) -> None:
        if not await self._registry.assign_task(self.id, task):
            logger.warning("Agent %s could not accept task %s", self.name, task.id)
            return

        await self._task_queue.update_status(
            task.id, TaskStatus.RUNNING, assigned_agent=self.id
        )

        try:
            result = await self.execute(task)
            await self._task_queue.update_status(
                task.id, TaskStatus.COMPLETED, result=result
            )
            await self._registry.complete_task(self.id, success=True)

            # Notify kernel
            await self._bus.publish(
                "galaxia:kernel",
                Message(
                    sender=self.id,
                    recipient="kernel",
                    msg_type="task_result",
                    payload={"task_id": task.id, "status": "completed", "result": result},
                ),
            )
            logger.info("Agent %s completed task %s", self.name, task.id)

        except Exception as e:
            error = str(e)
            await self._task_queue.update_status(
                task.id, TaskStatus.FAILED, error=error
            )
            await self._registry.complete_task(self.id, success=False)

            await self._bus.publish(
                "galaxia:kernel",
                Message(
                    sender=self.id,
                    recipient="kernel",
                    msg_type="task_result",
                    payload={"task_id": task.id, "status": "failed", "error": error},
                ),
            )
            logger.error("Agent %s failed task %s: %s", self.name, task.id, error)

    @abstractmethod
    async def execute(self, task: Task) -> str:
        """Execute a task. Returns result string."""

    async def handle_command(self, msg: Message) -> None:
        """Override to handle custom commands."""


class PlannerAgent(BaseAgent):
    """Breaks down complex tasks into subtasks."""

    def __init__(self, bus, registry, task_queue, llm, **kwargs):
        super().__init__(
            name="Planner",
            role=AgentRole.PLANNER,
            bus=bus,
            registry=registry,
            task_queue=task_queue,
            llm=llm,
            capabilities=["planning", "decomposition", "strategy"],
            **kwargs,
        )

    async def execute(self, task: Task) -> str:
        subtasks = await self._llm.plan_task(f"{task.title}: {task.description}")

        created_ids = []
        for st in subtasks:
            sub = await self._task_queue.submit(
                title=st.get("title", "Untitled"),
                description=st.get("description", ""),
                parent_task_id=task.id,
            )
            created_ids.append(sub.id)

        return f"Created {len(created_ids)} subtasks: {', '.join(created_ids)}"


class ExecutorAgent(BaseAgent):
    """Executes tasks using LLM."""

    def __init__(self, bus, registry, task_queue, llm, **kwargs):
        super().__init__(
            name="Executor",
            role=AgentRole.EXECUTOR,
            bus=bus,
            registry=registry,
            task_queue=task_queue,
            llm=llm,
            capabilities=["coding", "research", "content", "automation"],
            **kwargs,
        )

    async def execute(self, task: Task) -> str:
        system = (
            "Du bist ein Executor-Agent im Pfeifer Galaxia OS. "
            "Führe die Aufgabe präzise aus und liefere das Ergebnis."
        )
        prompt = f"Aufgabe: {task.title}\n\nDetails: {task.description}"
        return await self._llm.complete(prompt, system=system)


class CriticAgent(BaseAgent):
    """Evaluates results and provides feedback."""

    def __init__(self, bus, registry, task_queue, llm, **kwargs):
        super().__init__(
            name="Critic",
            role=AgentRole.CRITIC,
            bus=bus,
            registry=registry,
            task_queue=task_queue,
            llm=llm,
            capabilities=["review", "quality", "feedback"],
            **kwargs,
        )

    async def execute(self, task: Task) -> str:
        result_to_review = task.metadata.get("result_to_review", "")
        evaluation = await self._llm.evaluate_result(task.title, result_to_review)
        import json
        return json.dumps(evaluation, ensure_ascii=False)


class CoordinatorAgent(BaseAgent):
    """Decides next actions and assigns tasks to agents."""

    def __init__(self, bus, registry, task_queue, llm, **kwargs):
        super().__init__(
            name="Coordinator",
            role=AgentRole.COORDINATOR,
            bus=bus,
            registry=registry,
            task_queue=task_queue,
            llm=llm,
            capabilities=["coordination", "scheduling", "routing"],
            **kwargs,
        )

    async def execute(self, task: Task) -> str:
        # Coordinator logic: find idle executor and assign
        idle_executors = self._registry.get_idle(AgentRole.EXECUTOR)
        if idle_executors:
            agent = idle_executors[0]
            await self._bus.send_to_agent(
                agent.id,
                Message(
                    sender=self.id,
                    recipient=agent.id,
                    msg_type="task_assign",
                    payload={"task": task.model_dump(mode="json")},
                ),
            )
            return f"Routed task to {agent.name} ({agent.id})"
        return "No idle executors available, task remains in queue"
