"""Jarvis Kernel - Master Orchestrator for Pfeifer Galaxia OS."""

from __future__ import annotations

import asyncio
import logging
import time

from agents.base import PlannerAgent, ExecutorAgent, CriticAgent, CoordinatorAgent
from kernel.execution_engine import ExecutionEngine
from llm.client import LLMClient
from memory.memory import MemorySystem
from queue.task_queue import TaskQueue
from registry.agent_registry import AgentRegistry
from shared.models import (
    AgentRole,
    KernelState,
    Message,
    Task,
    TaskPriority,
    TaskStatus,
)
from shared.redis_bus import CHANNEL_KERNEL, RedisBus
from tools.tool_manager import ToolManager, register_builtin_tools

logger = logging.getLogger("galaxia.jarvis")


class JarvisKernel:
    """Jarvis - The central brain of Pfeifer Galaxia OS.

    Responsibilities:
    - Boot and manage all agents
    - Route tasks to appropriate agents
    - Monitor system health
    - Process task results
    - Dispatch work loop
    """

    def __init__(
        self,
        redis_url: str = "redis://localhost:6379/0",
        litellm_url: str = "http://localhost:4000",
        litellm_api_key: str = "sk-galaxia-local",
        default_model: str = "ollama/qwen3:14b",
    ):
        self._bus = RedisBus(redis_url)
        self._llm = LLMClient(litellm_url, litellm_api_key, default_model)
        self._registry = AgentRegistry(self._bus)
        self._task_queue = TaskQueue(self._bus)
        self._memory: MemorySystem | None = None
        self._tools = ToolManager()
        self._engine: ExecutionEngine | None = None
        self._agents = []
        self._start_time = 0.0
        self._messages_processed = 0
        self._running = False

    @property
    def bus(self) -> RedisBus:
        return self._bus

    @property
    def registry(self) -> AgentRegistry:
        return self._registry

    @property
    def task_queue(self) -> TaskQueue:
        return self._task_queue

    @property
    def llm(self) -> LLMClient:
        return self._llm

    @property
    def memory(self) -> MemorySystem | None:
        return self._memory

    @property
    def tools(self) -> ToolManager:
        return self._tools

    @property
    def engine(self) -> ExecutionEngine | None:
        return self._engine

    async def boot(self) -> None:
        """Boot sequence: connect, load state, spawn agents."""
        logger.info("=== JARVIS KERNEL BOOTING ===")
        self._start_time = time.time()

        # Connect to Redis
        await self._bus.connect()
        logger.info("[1/4] Redis connected")

        # Initialize memory, tools, execution engine
        self._memory = MemorySystem(self._bus.redis)
        register_builtin_tools(self._tools)
        self._engine = ExecutionEngine(self._llm, self._memory, self._tools)
        logger.info("[2/6] Memory + Tools + Engine initialized")

        # Load persisted state
        await self._registry.load_from_redis()
        await self._task_queue.load_from_redis()
        logger.info("[3/6] State loaded")

        # Subscribe to kernel channel
        await self._bus.subscribe(CHANNEL_KERNEL, self._handle_kernel_message)
        await self._bus.start_listening()
        logger.info("[4/6] Message bus listening")

        # Spawn default agents
        await self._spawn_agents()
        logger.info("[5/6] Agents spawned")

        # Store boot event in memory
        await self._memory.remember_long("system", "last_boot", {
            "time": time.time(),
            "agents": len(self._agents),
            "tools": len(self._tools.list_tools()),
        })
        logger.info("[6/6] Boot event stored")

        self._running = True
        logger.info("=== JARVIS KERNEL ONLINE ===")

    async def _spawn_agents(self) -> None:
        """Create and start the default agent fleet."""
        agent_classes = [
            (PlannerAgent, {}),
            (ExecutorAgent, {}),
            (ExecutorAgent, {}),  # 2 executors for parallelism
            (CriticAgent, {}),
            (CoordinatorAgent, {}),
        ]

        for cls, kwargs in agent_classes:
            agent = cls(
                bus=self._bus,
                registry=self._registry,
                task_queue=self._task_queue,
                llm=self._llm,
                **kwargs,
            )
            await agent.start()
            self._agents.append(agent)

        logger.info("Spawned %d agents", len(self._agents))

    async def shutdown(self) -> None:
        """Graceful shutdown."""
        logger.info("Jarvis shutting down...")
        self._running = False
        for agent in self._agents:
            await agent.stop()
        await self._bus.disconnect()
        logger.info("Jarvis offline")

    async def submit_task(
        self,
        title: str,
        description: str = "",
        priority: TaskPriority = TaskPriority.NORMAL,
    ) -> Task:
        """Submit a new task to the system."""
        task = await self._task_queue.submit(title, description, priority)
        logger.info("New task: %s [%s]", title, task.id)
        return task

    async def _handle_kernel_message(self, msg: Message) -> None:
        """Handle messages sent to the kernel."""
        self._messages_processed += 1

        if msg.msg_type == "task_result":
            task_id = msg.payload.get("task_id")
            status = msg.payload.get("status")
            logger.info("Task %s result: %s (from %s)", task_id, status, msg.sender)

        elif msg.msg_type == "heartbeat":
            await self._registry.heartbeat(msg.sender)

    async def dispatch_loop(self) -> None:
        """Main work loop: assign pending tasks to idle agents."""
        while self._running:
            try:
                task = await self._task_queue.next_task()
                if not task:
                    await asyncio.sleep(1)
                    continue

                # Find best agent for this task
                agent = await self._find_agent_for_task(task)
                if not agent:
                    # Re-enqueue if no agent available
                    await self._bus.enqueue_task(task.id, task.priority.value)
                    await asyncio.sleep(2)
                    continue

                # Assign task
                await self._bus.send_to_agent(
                    agent.id,
                    Message(
                        sender="jarvis",
                        recipient=agent.id,
                        msg_type="task_assign",
                        payload={"task": task.model_dump(mode="json")},
                    ),
                )

            except asyncio.CancelledError:
                break
            except Exception:
                logger.exception("Dispatch loop error")
                await asyncio.sleep(5)

    async def _find_agent_for_task(self, task: Task) -> AgentInfo | None:
        """Find the best idle agent for a task."""
        from shared.models import AgentInfo

        # Simple routing: if task has parent, it's a subtask -> executor
        # Otherwise -> planner first (to decompose)
        if task.parent_task_id:
            idle = self._registry.get_idle(AgentRole.EXECUTOR)
        else:
            idle = self._registry.get_idle(AgentRole.PLANNER)
            if not idle:
                idle = self._registry.get_idle(AgentRole.EXECUTOR)

        return idle[0] if idle else None

    def state(self) -> KernelState:
        """Get current kernel state snapshot."""
        tasks = self._task_queue.all_tasks()
        agents = self._registry.all_agents()
        return KernelState(
            uptime_seconds=time.time() - self._start_time if self._start_time else 0,
            active_agents=len([a for a in agents if a.status != "offline"]),
            pending_tasks=len([t for t in tasks if t.status == TaskStatus.PENDING]),
            running_tasks=len([t for t in tasks if t.status == TaskStatus.RUNNING]),
            completed_tasks=len([t for t in tasks if t.status == TaskStatus.COMPLETED]),
            failed_tasks=len([t for t in tasks if t.status == TaskStatus.FAILED]),
            messages_processed=self._messages_processed,
        )
