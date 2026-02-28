"""Task board - persistent markdown-based task management."""

import json
import os
import time
from dataclasses import dataclass, field, asdict
from enum import Enum
from pathlib import Path
from typing import Optional


class TaskStatus(str, Enum):
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    FAILED = "failed"
    PAUSED = "paused"


class TaskPriority(str, Enum):
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"


@dataclass
class Task:
    id: str
    title: str
    description: str
    department: str
    status: TaskStatus = TaskStatus.PENDING
    priority: TaskPriority = TaskPriority.MEDIUM
    created_at: float = field(default_factory=time.time)
    updated_at: float = field(default_factory=time.time)
    assigned_to: Optional[str] = None
    result: Optional[str] = None
    error: Optional[str] = None


class TaskBoard:
    def __init__(self, data_dir: str = "/empire"):
        self.tasks_dir = Path(data_dir) / "tasks"
        self.tasks_dir.mkdir(parents=True, exist_ok=True)
        self.tasks_file = self.tasks_dir / "tasks.json"
        self._tasks: dict[str, Task] = {}
        self._load()

    def _load(self):
        if self.tasks_file.exists():
            try:
                data = json.loads(self.tasks_file.read_text())
                for tid, tdata in data.items():
                    tdata["status"] = TaskStatus(tdata["status"])
                    tdata["priority"] = TaskPriority(tdata["priority"])
                    self._tasks[tid] = Task(**tdata)
            except Exception:
                self._tasks = {}

    def _save(self):
        data = {tid: asdict(t) for tid, t in self._tasks.items()}
        # Convert enums to strings for JSON
        for tid in data:
            data[tid]["status"] = data[tid]["status"].value
            data[tid]["priority"] = data[tid]["priority"].value
        self.tasks_file.write_text(json.dumps(data, indent=2, default=str))
        self._write_markdown()

    def _write_markdown(self):
        md = "# Empire Task Board\n\n"
        md += f"_Updated: {time.strftime('%Y-%m-%d %H:%M:%S')}_\n\n"

        for status in TaskStatus:
            tasks = [t for t in self._tasks.values() if t.status == status]
            if tasks:
                md += f"## {status.value.upper().replace('_', ' ')} ({len(tasks)})\n\n"
                for t in sorted(tasks, key=lambda x: x.priority.value):
                    icon = {"critical": "!!!", "high": "!!", "medium": "!", "low": ""}.get(
                        t.priority.value, ""
                    )
                    md += f"- [{icon}] **{t.title}** ({t.department})\n"
                    if t.assigned_to:
                        md += f"  - Assigned: {t.assigned_to}\n"
                    if t.result:
                        md += f"  - Result: {t.result[:100]}\n"
                md += "\n"

        (self.tasks_dir / "BOARD.md").write_text(md)

    def add(self, task: Task) -> Task:
        self._tasks[task.id] = task
        self._save()
        return task

    def update_status(self, task_id: str, status: TaskStatus, result: str = None):
        if task_id in self._tasks:
            self._tasks[task_id].status = status
            self._tasks[task_id].updated_at = time.time()
            if result:
                self._tasks[task_id].result = result
            self._save()

    def get(self, task_id: str) -> Optional[Task]:
        return self._tasks.get(task_id)

    def list_by_status(self, status: TaskStatus) -> list[Task]:
        return [t for t in self._tasks.values() if t.status == status]

    def list_by_department(self, department: str) -> list[Task]:
        return [t for t in self._tasks.values() if t.department == department]

    def summary(self) -> str:
        counts = {}
        for status in TaskStatus:
            counts[status.value] = len(self.list_by_status(status))
        total = len(self._tasks)
        return (
            f"Tasks: {total} total | "
            f"{counts['in_progress']} active | "
            f"{counts['pending']} pending | "
            f"{counts['completed']} done | "
            f"{counts['failed']} failed"
        )
