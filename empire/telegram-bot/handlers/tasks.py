"""
Task management handlers for the Telegram bot.
Simple file-based + Redis task board.
"""

import json
import os
from datetime import datetime

from aiogram import Dispatcher
from aiogram.filters import Command
from aiogram.types import Message

from config import ADMIN_CHAT_ID, TASKS_DIR


def _load_tasks():
    """Load tasks from the task board file."""
    path = os.path.join(TASKS_DIR, "board.json")
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    return {"tasks": []}


def _save_tasks(data):
    """Save tasks to the task board file."""
    os.makedirs(TASKS_DIR, exist_ok=True)
    path = os.path.join(TASKS_DIR, "board.json")
    with open(path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


def register_task_handlers(dp: Dispatcher):
    @dp.message(Command("tasks"))
    async def cmd_tasks(message: Message):
        if ADMIN_CHAT_ID and message.from_user.id != ADMIN_CHAT_ID:
            return

        data = _load_tasks()
        tasks = data.get("tasks", [])

        if not tasks:
            await message.reply("📋 <b>Task Board</b>\n\nKeine Tasks vorhanden. Erstelle einen mit /task_add")
            return

        lines = ["📋 <b>Task Board</b>\n"]

        status_groups = {"open": [], "in_progress": [], "done": []}
        for t in tasks:
            status_groups.get(t.get("status", "open"), status_groups["open"]).append(t)

        if status_groups["in_progress"]:
            lines.append("<b>🔄 In Arbeit:</b>")
            for t in status_groups["in_progress"]:
                lines.append(f"  [{t['id']}] {t['title']}")
                if t.get("assigned_to"):
                    lines.append(f"      → Agent: {t['assigned_to']}")

        if status_groups["open"]:
            lines.append("\n<b>📌 Offen:</b>")
            for t in status_groups["open"]:
                lines.append(f"  [{t['id']}] {t['title']}")

        if status_groups["done"]:
            lines.append(f"\n<b>✅ Erledigt:</b> {len(status_groups['done'])} Tasks")

        await message.reply("\n".join(lines))

    @dp.message(Command("task_add"))
    async def cmd_task_add(message: Message):
        if ADMIN_CHAT_ID and message.from_user.id != ADMIN_CHAT_ID:
            return

        title = message.text.replace("/task_add", "", 1).strip()
        if not title:
            await message.reply("📋 Nutzung: /task_add [Beschreibung des Tasks]")
            return

        data = _load_tasks()
        task_id = len(data["tasks"]) + 1

        task = {
            "id": task_id,
            "title": title,
            "status": "open",
            "created_at": datetime.now().isoformat(),
            "assigned_to": None,
            "completed_at": None,
        }

        data["tasks"].append(task)
        _save_tasks(data)

        # Also publish to Redis for agents to pick up
        redis_client = dp["redis"]
        await redis_client.rpush("empire:tasks:new", json.dumps(task))

        await message.reply(
            f"📋 <b>Neuer Task erstellt!</b>\n\n"
            f"ID: <b>{task_id}</b>\n"
            f"Titel: {title}\n"
            f"Status: offen\n\n"
            "Agenten können diesen Task übernehmen."
        )

    @dp.message(Command("task_done"))
    async def cmd_task_done(message: Message):
        if ADMIN_CHAT_ID and message.from_user.id != ADMIN_CHAT_ID:
            return

        task_id_str = message.text.replace("/task_done", "", 1).strip()
        if not task_id_str or not task_id_str.isdigit():
            await message.reply("📋 Nutzung: /task_done [task-id]")
            return

        task_id = int(task_id_str)
        data = _load_tasks()

        found = False
        for task in data["tasks"]:
            if task["id"] == task_id:
                task["status"] = "done"
                task["completed_at"] = datetime.now().isoformat()
                found = True
                break

        if not found:
            await message.reply(f"⚠️ Task #{task_id} nicht gefunden.")
            return

        _save_tasks(data)
        await message.reply(f"✅ Task #{task_id} als erledigt markiert!")
