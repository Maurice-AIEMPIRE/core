"""UserAI Empire - Telegram Control Bot.

Main interface for commanding the entire AI empire.
All commands, tasks, and reports flow through here.
"""

import asyncio
import json
import logging
import time
import uuid
from pathlib import Path

from aiogram import Bot, Dispatcher, F, Router
from aiogram.enums import ParseMode
from aiogram.filters import Command, CommandStart
from aiogram.types import Message
from dotenv import load_dotenv

from bot.config import Config
from bot.claude_client import ClaudeClient
from bot.task_board import TaskBoard, Task, TaskStatus, TaskPriority
from bot.redis_bus import RedisBus

load_dotenv()
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("empire-bot")

config = Config.from_env()
bot = Bot(token=config.telegram_token, parse_mode=ParseMode.HTML)
dp = Dispatcher()
router = Router()

# Core services
claude = ClaudeClient(config.claude_api_key)
task_board = TaskBoard(config.empire_data_dir)
bus = RedisBus(config.redis_url)

# Department registry
DEPARTMENTS = {
    "ceo": "CEO / Strategic Command",
    "research": "Research & Innovation Lab",
    "product": "Product Engineering",
    "marketing": "Marketing & Growth",
    "sales": "Sales & CRM",
    "finance": "Finance & Ops",
    "legal": "Legal & Compliance",
    "hr": "HR & Culture",
    "customer": "Customer Success",
    "meta": "Meta-Skill-Agent",
    "telegram": "Telegram Control Bot",
    "x-analysis": "X Analysis & Prompt Factory",
}


def is_admin(message: Message) -> bool:
    return message.from_user and message.from_user.id == config.admin_chat_id


def admin_only(handler):
    async def wrapper(message: Message, *args, **kwargs):
        if not is_admin(message):
            await message.reply("Zugriff verweigert. Nur Admin.")
            return
        return await handler(message, *args, **kwargs)
    wrapper.__name__ = handler.__name__
    return wrapper


# ========== COMMANDS ==========


@router.message(CommandStart())
@admin_only
async def cmd_start(message: Message):
    text = (
        "<b>UserAI Empire - Command Center</b>\n\n"
        "Dein AI-Unternehmen ist online.\n\n"
        "<b>Befehle:</b>\n"
        "/status - Empire-Status\n"
        "/departments - Alle Abteilungen\n"
        "/tasks - Task Board\n"
        "/new_task [dept] [beschreibung] - Neuen Task erstellen\n"
        "/analyze [x-url] - X Post analysieren\n"
        "/bulk_start - 10k Queue starten\n"
        "/bulk_status - 10k Queue Status\n"
        "/bulk_pause - 10k Queue pausieren\n"
        "/idea [beschreibung] - Neue Geschaeftsidee\n"
        "/ask [frage] - Claude direkt fragen\n"
        "/sync - Cloud Sync triggern\n"
        "/standup - Tagesreport\n"
        "/rebuild - Alle Agenten neu starten\n"
        "/logs [service] - Service Logs\n\n"
        "Oder schreib einfach eine Nachricht - ich verstehe natuerliche Sprache."
    )
    await message.reply(text)


@router.message(Command("status"))
@admin_only
async def cmd_status(message: Message):
    # Gather status from all services
    try:
        queue_len = await bus.get_queue_length("x-analysis:queue")
        bulk_state = await bus.get_state("bulk-queue:state") or {}
    except Exception:
        queue_len = 0
        bulk_state = {}

    bulk_progress = bulk_state.get("processed", 0)
    bulk_total = bulk_state.get("total", 0)
    bulk_status = bulk_state.get("status", "idle")

    text = (
        "<b>Empire Status Report</b>\n"
        "━━━━━━━━━━━━━━━━━━━━\n\n"
        f"<b>Task Board:</b> {task_board.summary()}\n\n"
        f"<b>X-Analysis Queue:</b> {queue_len} pending\n"
        f"<b>10k Bulk Queue:</b> {bulk_status} ({bulk_progress}/{bulk_total})\n\n"
        f"<b>Departments:</b> {len(DEPARTMENTS)} active\n"
        f"<b>Cloud Sync:</b> {'Active' if bulk_state else 'Idle'}\n\n"
        f"<i>Uptime since last restart</i>"
    )
    await message.reply(text)


@router.message(Command("departments"))
@admin_only
async def cmd_departments(message: Message):
    text = "<b>Empire Departments</b>\n━━━━━━━━━━━━━━━━━━━━\n\n"
    for key, name in DEPARTMENTS.items():
        tasks = task_board.list_by_department(key)
        active = len([t for t in tasks if t.status == TaskStatus.IN_PROGRESS])
        done = len([t for t in tasks if t.status == TaskStatus.COMPLETED])
        text += f"<b>{name}</b>\n  Active: {active} | Done: {done}\n\n"
    await message.reply(text)


@router.message(Command("tasks"))
@admin_only
async def cmd_tasks(message: Message):
    text = "<b>Task Board</b>\n━━━━━━━━━━━━━━━━━━━━\n\n"

    for status in [TaskStatus.IN_PROGRESS, TaskStatus.PENDING, TaskStatus.FAILED]:
        tasks = task_board.list_by_status(status)
        if tasks:
            icon = {"in_progress": "🔄", "pending": "⏳", "failed": "❌"}.get(
                status.value, ""
            )
            text += f"<b>{icon} {status.value.upper()}</b>\n"
            for t in tasks[:10]:
                text += f"  - <code>{t.id[:8]}</code> [{t.department}] {t.title}\n"
            text += "\n"

    if not any(task_board.list_by_status(s) for s in [TaskStatus.IN_PROGRESS, TaskStatus.PENDING]):
        text += "<i>Keine aktiven Tasks.</i>"

    await message.reply(text)


@router.message(Command("new_task"))
@admin_only
async def cmd_new_task(message: Message):
    args = message.text.split(maxsplit=2)
    if len(args) < 3:
        await message.reply("Usage: /new_task [department] [beschreibung]\nDepartments: " + ", ".join(DEPARTMENTS.keys()))
        return

    dept = args[1].lower()
    description = args[2]

    if dept not in DEPARTMENTS:
        await message.reply(f"Unbekannte Abteilung: {dept}\nVerfuegbar: {', '.join(DEPARTMENTS.keys())}")
        return

    task = Task(
        id=str(uuid.uuid4()),
        title=description[:80],
        description=description,
        department=dept,
        priority=TaskPriority.MEDIUM,
    )
    task_board.add(task)

    # Send to orchestrator via Redis
    await bus.enqueue("orchestrator:tasks", {
        "task_id": task.id,
        "department": dept,
        "description": description,
        "priority": "medium",
    })

    await message.reply(
        f"Task erstellt!\n"
        f"ID: <code>{task.id[:8]}</code>\n"
        f"Abteilung: {DEPARTMENTS[dept]}\n"
        f"Status: Pending -> wird an Orchestrator weitergeleitet"
    )


@router.message(Command("analyze"))
@admin_only
async def cmd_analyze(message: Message):
    args = message.text.split(maxsplit=1)
    if len(args) < 2:
        await message.reply("Usage: /analyze [x-url oder text]\nBeispiel: /analyze https://x.com/user/status/123456")
        return

    target = args[1].strip()
    await message.reply(f"Analyse gestartet: {target}\nDie X-Analysis Engine arbeitet...")

    # Queue for X analysis
    job_id = str(uuid.uuid4())
    await bus.enqueue("x-analysis:queue", {
        "job_id": job_id,
        "url_or_text": target,
        "requester": "admin",
        "auto_execute": False,
    })

    # Create tracking task
    task = Task(
        id=job_id,
        title=f"X-Analyse: {target[:60]}",
        description=f"Analysiere X-Post/Content: {target}",
        department="x-analysis",
        status=TaskStatus.IN_PROGRESS,
        priority=TaskPriority.HIGH,
    )
    task_board.add(task)


@router.message(Command("bulk_start"))
@admin_only
async def cmd_bulk_start(message: Message):
    await bus.publish("bulk-queue:control", {"action": "start"})
    await bus.set_state("bulk-queue:state", {"status": "running", "processed": 0, "total": 10000})
    await message.reply(
        "<b>10k Bulk Queue gestartet!</b>\n"
        "Die Queue verarbeitet Posts im Hintergrund.\n"
        "Check: /bulk_status"
    )


@router.message(Command("bulk_status"))
@admin_only
async def cmd_bulk_status(message: Message):
    state = await bus.get_state("bulk-queue:state") or {}
    status = state.get("status", "idle")
    processed = state.get("processed", 0)
    total = state.get("total", 0)
    errors = state.get("errors", 0)

    pct = (processed / total * 100) if total > 0 else 0
    bar_len = 20
    filled = int(bar_len * pct / 100)
    bar = "█" * filled + "░" * (bar_len - filled)

    await message.reply(
        f"<b>10k Bulk Queue</b>\n"
        f"Status: {status}\n"
        f"[{bar}] {pct:.1f}%\n"
        f"Verarbeitet: {processed}/{total}\n"
        f"Fehler: {errors}"
    )


@router.message(Command("bulk_pause"))
@admin_only
async def cmd_bulk_pause(message: Message):
    await bus.publish("bulk-queue:control", {"action": "pause"})
    state = await bus.get_state("bulk-queue:state") or {}
    state["status"] = "paused"
    await bus.set_state("bulk-queue:state", state)
    await message.reply("10k Bulk Queue pausiert.")


@router.message(Command("idea"))
@admin_only
async def cmd_idea(message: Message):
    args = message.text.split(maxsplit=1)
    if len(args) < 2:
        await message.reply("Usage: /idea [deine geschaeftsidee oder kontext]")
        return

    idea = args[1]
    await message.reply("Denke ueber deine Idee nach...")

    result = await claude.think(
        f"Analysiere diese Geschaeftsidee fuer mein AI Empire:\n\n{idea}\n\n"
        "Gib mir:\n"
        "1. Bewertung (1-10)\n"
        "2. Marktpotenzial\n"
        "3. Umsetzbarkeit mit unseren Ressourcen\n"
        "4. Naechste Schritte (konkret)\n"
        "5. Risiken\n"
        "6. Empfehlung: Umsetzen oder ablehnen?"
    )

    # Save to KB
    task = Task(
        id=str(uuid.uuid4()),
        title=f"Idee: {idea[:60]}",
        description=idea,
        department="ceo",
        status=TaskStatus.COMPLETED,
        result=result[:500],
    )
    task_board.add(task)

    # Split long messages for Telegram (4096 char limit)
    for i in range(0, len(result), 4000):
        await message.reply(result[i:i + 4000])


@router.message(Command("ask"))
@admin_only
async def cmd_ask(message: Message):
    args = message.text.split(maxsplit=1)
    if len(args) < 2:
        await message.reply("Usage: /ask [deine frage]")
        return

    question = args[1]
    await message.reply("Denke nach...")

    result = await claude.think(question)

    for i in range(0, len(result), 4000):
        await message.reply(result[i:i + 4000])


@router.message(Command("sync"))
@admin_only
async def cmd_sync(message: Message):
    await bus.publish("cloud-sync:trigger", {"action": "sync_now"})
    await message.reply("Cloud Sync getriggert (iCloud + Dropbox).\nErgebnisse werden synchronisiert.")


@router.message(Command("standup"))
@admin_only
async def cmd_standup(message: Message):
    active = task_board.list_by_status(TaskStatus.IN_PROGRESS)
    completed_today = [
        t for t in task_board.list_by_status(TaskStatus.COMPLETED)
        if t.updated_at > time.time() - 86400
    ]
    pending = task_board.list_by_status(TaskStatus.PENDING)
    failed = task_board.list_by_status(TaskStatus.FAILED)

    bulk_state = await bus.get_state("bulk-queue:state") or {}

    text = (
        f"<b>Daily Stand-up Report</b>\n"
        f"━━━━━━━━━━━━━━━━━━━━\n"
        f"<i>{time.strftime('%Y-%m-%d %H:%M')}</i>\n\n"
        f"<b>Erledigt (24h):</b> {len(completed_today)} Tasks\n"
    )
    for t in completed_today[:5]:
        text += f"  - [{t.department}] {t.title}\n"

    text += f"\n<b>In Arbeit:</b> {len(active)} Tasks\n"
    for t in active[:5]:
        text += f"  - [{t.department}] {t.title}\n"

    text += f"\n<b>Wartend:</b> {len(pending)} Tasks\n"
    if failed:
        text += f"\n<b>Fehlgeschlagen:</b> {len(failed)} Tasks\n"

    bp = bulk_state.get("processed", 0)
    bt = bulk_state.get("total", 0)
    text += f"\n<b>10k Queue:</b> {bp}/{bt} ({bulk_state.get('status', 'idle')})\n"

    text += "\n<i>Empire laeuft. Alle Systeme operativ.</i>"
    await message.reply(text)


@router.message(Command("rebuild"))
@admin_only
async def cmd_rebuild(message: Message):
    await message.reply(
        "Rebuild-Befehl erhalten.\n"
        "Fuehre auf dem Server aus:\n"
        "<code>cd /empire && docker compose up -d --build</code>"
    )


@router.message(Command("logs"))
@admin_only
async def cmd_logs(message: Message):
    args = message.text.split(maxsplit=1)
    services = ["telegram-bot", "orchestrator", "x-analysis", "bulk-queue", "cloud-sync", "redis", "chromadb"]
    if len(args) < 2:
        await message.reply(f"Usage: /logs [service]\nServices: {', '.join(services)}")
        return
    service = args[1].strip()
    await message.reply(
        f"Logs fuer {service}:\n"
        f"<code>docker logs empire-{service} --tail 50</code>\n\n"
        f"<i>Server-seitiger Befehl - direkt ausfuehren oder Portainer nutzen (Port 9443)</i>"
    )


# ========== NATURAL LANGUAGE HANDLER ==========


@router.message(F.text)
@admin_only
async def handle_text(message: Message):
    """Handle natural language messages - route to Claude for interpretation."""
    text = message.text.strip()

    # Quick route detection
    if any(x in text.lower() for x in ["x.com/", "twitter.com/", "x post", "tweet"]):
        # Auto-route to X analysis
        await message.reply("X-Content erkannt, starte Analyse...")
        await bus.enqueue("x-analysis:queue", {
            "job_id": str(uuid.uuid4()),
            "url_or_text": text,
            "requester": "admin",
            "auto_execute": False,
        })
        return

    # Send to Claude for interpretation
    await message.reply("Verarbeite...")
    result = await claude.think(
        f"Der Admin hat folgendes geschrieben:\n\n{text}\n\n"
        "Interpretiere den Befehl und fuehre ihn aus. "
        "Wenn es ein Task ist, erstelle einen konkreten Aktionsplan. "
        "Wenn es eine Frage ist, beantworte sie. "
        "Wenn es eine Idee ist, bewerte sie."
    )

    for i in range(0, len(result), 4000):
        await message.reply(result[i:i + 4000])


# ========== SCHEDULED TASKS ==========


async def daily_standup():
    """Send daily standup at 8:00 server time."""
    while True:
        now = time.localtime()
        # Calculate seconds until next 8:00
        target_hour = 8
        seconds_until = (
            ((target_hour - now.tm_hour) % 24) * 3600
            - now.tm_min * 60
            - now.tm_sec
        )
        if seconds_until <= 0:
            seconds_until += 86400

        await asyncio.sleep(seconds_until)

        try:
            active = task_board.list_by_status(TaskStatus.IN_PROGRESS)
            completed = [
                t for t in task_board.list_by_status(TaskStatus.COMPLETED)
                if t.updated_at > time.time() - 86400
            ]
            bulk_state = await bus.get_state("bulk-queue:state") or {}

            text = (
                f"<b>Good Morning! Daily Empire Report</b>\n"
                f"━━━━━━━━━━━━━━━━━━━━\n"
                f"{time.strftime('%Y-%m-%d %H:%M')}\n\n"
                f"Gestern erledigt: {len(completed)}\n"
                f"Aktuell in Arbeit: {len(active)}\n"
                f"10k Queue: {bulk_state.get('processed', 0)}/{bulk_state.get('total', 0)}\n\n"
                f"Was soll ich heute priorisieren?"
            )
            await bot.send_message(config.admin_chat_id, text)
        except Exception as e:
            logger.error(f"Daily standup failed: {e}")


async def result_listener():
    """Listen for results from agents and forward to Telegram."""
    while True:
        try:
            result = await bus.dequeue("telegram:results", timeout=5)
            if result:
                text = (
                    f"<b>Agent Report</b>\n"
                    f"Von: {result.get('department', 'unknown')}\n"
                    f"Task: {result.get('task_id', 'N/A')[:8]}\n\n"
                    f"{result.get('message', 'Kein Inhalt')}"
                )
                await bot.send_message(config.admin_chat_id, text[:4000])

                # Update task board
                if result.get("task_id"):
                    status = TaskStatus.COMPLETED if result.get("success") else TaskStatus.FAILED
                    task_board.update_status(
                        result["task_id"], status, result.get("message", "")[:500]
                    )
        except Exception as e:
            logger.error(f"Result listener error: {e}")
            await asyncio.sleep(5)


# ========== MAIN ==========


async def main():
    dp.include_router(router)

    # Start background tasks
    asyncio.create_task(daily_standup())
    asyncio.create_task(result_listener())

    logger.info("Empire Telegram Bot starting...")
    logger.info(f"Admin Chat ID: {config.admin_chat_id}")

    await dp.start_polling(bot)


if __name__ == "__main__":
    asyncio.run(main())
