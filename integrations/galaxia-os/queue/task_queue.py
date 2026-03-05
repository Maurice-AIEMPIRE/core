"""Task Queue - Priority-based task management via Redis."""

from __future__ import annotations

import logging
from datetime import datetime, timezone

from shared.models import Task, TaskPriority, TaskStatus
from shared.redis_bus import RedisBus

logger = logging.getLogger("galaxia.queue")


class TaskQueue:
    """Priority queue for tasks, backed by Redis sorted sets."""

    def __init__(self, bus: RedisBus):
        self._bus = bus
        self._tasks: dict[str, Task] = {}

    async def submit(
        self,
        title: str,
        description: str = "",
        priority: TaskPriority = TaskPriority.NORMAL,
        parent_task_id: str | None = None,
        metadata: dict | None = None,
    ) -> Task:
        task = Task(
            title=title,
            description=description,
            priority=priority,
            parent_task_id=parent_task_id,
            metadata=metadata or {},
        )
        self._tasks[task.id] = task
        await self._bus.store_task(task.id, task.model_dump(mode="json"))
        await self._bus.enqueue_task(task.id, priority.value)
        await self._bus.increment_metric("tasks_submitted")
        logger.info("Task submitted: %s [%s] priority=%s", task.title, task.id, priority.name)
        return task

    async def next_task(self) -> Task | None:
        task_id = await self._bus.dequeue_task()
        if not task_id:
            return None
        task = self._tasks.get(task_id)
        if not task:
            data = await self._bus.get_task(task_id)
            if data:
                task = Task.model_validate(data)
                self._tasks[task_id] = task
        return task

    async def update_status(self, task_id: str, status: TaskStatus, **kwargs) -> Task | None:
        task = self._tasks.get(task_id)
        if not task:
            return None

        task.status = status

        if status == TaskStatus.RUNNING:
            task.started_at = datetime.now(timezone.utc)
        elif status in (TaskStatus.COMPLETED, TaskStatus.FAILED):
            task.completed_at = datetime.now(timezone.utc)

        if "result" in kwargs:
            task.result = kwargs["result"]
        if "error" in kwargs:
            task.error = kwargs["error"]
        if "assigned_agent" in kwargs:
            task.assigned_agent = kwargs["assigned_agent"]

        self._tasks[task_id] = task
        await self._bus.store_task(task_id, task.model_dump(mode="json"))
        await self._bus.increment_metric(f"tasks_{status.value}")
        return task

    def get(self, task_id: str) -> Task | None:
        return self._tasks.get(task_id)

    def get_by_status(self, status: TaskStatus) -> list[Task]:
        return [t for t in self._tasks.values() if t.status == status]

    def all_tasks(self) -> list[Task]:
        return list(self._tasks.values())

    async def pending_count(self) -> int:
        return await self._bus.queue_length()

    async def load_from_redis(self) -> None:
        """Reload tasks from Redis (after restart)."""
        stored = await self._bus.get_all_tasks()
        for task_id, data in stored.items():
            try:
                task = Task.model_validate(data)
                self._tasks[task_id] = task
            except Exception:
                logger.warning("Could not load task %s from Redis", task_id)
        logger.info("Loaded %d tasks from Redis", len(self._tasks))
