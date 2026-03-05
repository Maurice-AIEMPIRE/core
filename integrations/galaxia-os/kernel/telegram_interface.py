"""Telegram Command Interface for Pfeifer Galaxia OS."""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone

from telegram import Update
from telegram.ext import (
    Application,
    CommandHandler,
    ContextTypes,
    MessageHandler,
    filters,
)

from shared.models import TaskPriority

logger = logging.getLogger("galaxia.telegram")


class TelegramInterface:
    """Telegram bot for interacting with Jarvis."""

    def __init__(self, jarvis, token: str):
        self._jarvis = jarvis
        self._token = token
        self._app: Application | None = None

    async def start(self) -> None:
        self._app = Application.builder().token(self._token).build()

        # Register commands
        self._app.add_handler(CommandHandler("start", self._cmd_start))
        self._app.add_handler(CommandHandler("status", self._cmd_status))
        self._app.add_handler(CommandHandler("agents", self._cmd_agents))
        self._app.add_handler(CommandHandler("tasks", self._cmd_tasks))
        self._app.add_handler(CommandHandler("run", self._cmd_run))
        self._app.add_handler(CommandHandler("draft", self._cmd_draft))
        self._app.add_handler(CommandHandler("deploy", self._cmd_deploy))
        self._app.add_handler(CommandHandler("help", self._cmd_help))

        # Natural language fallback
        self._app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, self._handle_text))

        await self._app.initialize()
        await self._app.start()
        await self._app.updater.start_polling()
        logger.info("Telegram bot started")

    async def stop(self) -> None:
        if self._app:
            await self._app.updater.stop()
            await self._app.stop()
            await self._app.shutdown()

    async def _cmd_start(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
        await update.message.reply_text(
            "🌌 *Pfeifer Galaxia OS*\n\n"
            "Jarvis Kernel ist online.\n\n"
            "Befehle:\n"
            "/status - Systemstatus\n"
            "/agents - Aktive Agents\n"
            "/tasks - Aufgabenliste\n"
            "/run <Aufgabe> - Aufgabe starten\n"
            "/draft <Text> - Content erstellen\n"
            "/deploy - System deployen\n"
            "/help - Hilfe",
            parse_mode="Markdown",
        )

    async def _cmd_status(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
        state = self._jarvis.state()
        uptime_h = int(state.uptime_seconds // 3600)
        uptime_m = int((state.uptime_seconds % 3600) // 60)

        text = (
            "📊 *Galaxia OS Status*\n\n"
            f"⏱ Uptime: {uptime_h}h {uptime_m}m\n"
            f"🤖 Agents: {state.active_agents}\n"
            f"📋 Pending: {state.pending_tasks}\n"
            f"🔄 Running: {state.running_tasks}\n"
            f"✅ Completed: {state.completed_tasks}\n"
            f"❌ Failed: {state.failed_tasks}\n"
            f"💬 Messages: {state.messages_processed}"
        )
        await update.message.reply_text(text, parse_mode="Markdown")

    async def _cmd_agents(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
        agents = self._jarvis.registry.all_agents()
        if not agents:
            await update.message.reply_text("Keine Agents registriert.")
            return

        lines = ["🤖 *Agents*\n"]
        for a in agents:
            icon = {"idle": "🟢", "busy": "🟡", "error": "🔴", "offline": "⚫"}.get(a.status, "⚪")
            lines.append(f"{icon} *{a.name}* ({a.role}) - {a.status}")
            lines.append(f"   Tasks: ✅{a.tasks_completed} ❌{a.tasks_failed}")
        await update.message.reply_text("\n".join(lines), parse_mode="Markdown")

    async def _cmd_tasks(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
        tasks = self._jarvis.task_queue.all_tasks()
        if not tasks:
            await update.message.reply_text("Keine Aufgaben in der Queue.")
            return

        # Show last 10
        recent = sorted(tasks, key=lambda t: t.created_at, reverse=True)[:10]
        lines = ["📋 *Aufgaben* (letzte 10)\n"]
        for t in recent:
            icon = {
                "pending": "⏳", "running": "🔄", "completed": "✅",
                "failed": "❌", "cancelled": "🚫",
            }.get(t.status, "❓")
            lines.append(f"{icon} `{t.id}` {t.title}")
        await update.message.reply_text("\n".join(lines), parse_mode="Markdown")

    async def _cmd_run(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
        text = " ".join(ctx.args) if ctx.args else ""
        if not text:
            await update.message.reply_text("Nutzung: /run <Aufgabenbeschreibung>")
            return

        task = await self._jarvis.submit_task(
            title=text,
            priority=TaskPriority.HIGH,
        )
        await update.message.reply_text(
            f"🚀 Aufgabe erstellt: `{task.id}`\n\n*{task.title}*\n\nStatus: ⏳ pending",
            parse_mode="Markdown",
        )

    async def _cmd_draft(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
        text = " ".join(ctx.args) if ctx.args else ""
        if not text:
            await update.message.reply_text("Nutzung: /draft <Was soll erstellt werden?>")
            return

        task = await self._jarvis.submit_task(
            title=f"Content Draft: {text}",
            description=f"Erstelle einen Entwurf für: {text}",
            priority=TaskPriority.NORMAL,
        )
        await update.message.reply_text(
            f"📝 Draft-Aufgabe erstellt: `{task.id}`\n\n*{text}*",
            parse_mode="Markdown",
        )

    async def _cmd_deploy(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
        await update.message.reply_text(
            "🚧 Deploy-Funktion wird in Sprint 6 implementiert.\n"
            "Aktuell: `cd /opt/ki-power && docker compose up -d`"
        )

    async def _cmd_help(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
        await self._cmd_start(update, ctx)

    async def _handle_text(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
        """Handle natural language messages as tasks."""
        text = update.message.text.strip()
        if len(text) < 3:
            return

        task = await self._jarvis.submit_task(
            title=text[:100],
            description=text,
            priority=TaskPriority.NORMAL,
        )
        await update.message.reply_text(
            f"💬 Verstanden. Aufgabe erstellt: `{task.id}`\n\n"
            f"Jarvis arbeitet daran...",
            parse_mode="Markdown",
        )
