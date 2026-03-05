"""Pfeifer Galaxia OS - Shared Data Models"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


# === Enums ===

class TaskStatus(str, Enum):
    PENDING = "pending"
    QUEUED = "queued"
    ASSIGNED = "assigned"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class TaskPriority(int, Enum):
    LOW = 1
    NORMAL = 5
    HIGH = 8
    CRITICAL = 10


class AgentRole(str, Enum):
    PLANNER = "planner"
    EXECUTOR = "executor"
    CRITIC = "critic"
    COORDINATOR = "coordinator"


class AgentStatus(str, Enum):
    IDLE = "idle"
    BUSY = "busy"
    ERROR = "error"
    OFFLINE = "offline"


# === Models ===

class Task(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4())[:8])
    title: str
    description: str = ""
    status: TaskStatus = TaskStatus.PENDING
    priority: TaskPriority = TaskPriority.NORMAL
    assigned_agent: str | None = None
    parent_task_id: str | None = None
    subtask_ids: list[str] = Field(default_factory=list)
    result: Any = None
    error: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    started_at: datetime | None = None
    completed_at: datetime | None = None

    def is_terminal(self) -> bool:
        return self.status in (TaskStatus.COMPLETED, TaskStatus.FAILED, TaskStatus.CANCELLED)


class AgentInfo(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4())[:8])
    name: str
    role: AgentRole
    status: AgentStatus = AgentStatus.IDLE
    capabilities: list[str] = Field(default_factory=list)
    model: str = "qwen3-14b"
    current_task_id: str | None = None
    tasks_completed: int = 0
    tasks_failed: int = 0
    last_heartbeat: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    metadata: dict[str, Any] = Field(default_factory=dict)


class Message(BaseModel):
    """Message sent between agents via Redis."""
    id: str = Field(default_factory=lambda: str(uuid.uuid4())[:8])
    sender: str
    recipient: str  # agent_id or "broadcast"
    msg_type: str  # "task_assign", "task_result", "heartbeat", "command"
    payload: dict[str, Any] = Field(default_factory=dict)
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class KernelState(BaseModel):
    """Snapshot of Jarvis Kernel state."""
    uptime_seconds: float = 0
    active_agents: int = 0
    pending_tasks: int = 0
    running_tasks: int = 0
    completed_tasks: int = 0
    failed_tasks: int = 0
    messages_processed: int = 0
