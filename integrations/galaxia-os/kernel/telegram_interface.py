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
        self._app.add_handler(CommandHandler("think", self._cmd_think))
        self._app.add_handler(CommandHandler("brain", self._cmd_brain))
        self._app.add_handler(CommandHandler("revenue", self._cmd_revenue))
        self._app.add_handler(CommandHandler("leads", self._cmd_leads))
        self._app.add_handler(CommandHandler("product", self._cmd_product))
        self._app.add_handler(CommandHandler("memory", self._cmd_memory))
        self._app.add_handler(CommandHandler("tools", self._cmd_tools))
        self._app.add_handler(CommandHandler("help", self._cmd_help))

        # Sprint 9 commands
        self._app.add_handler(CommandHandler("graph", self._cmd_graph))
        self._app.add_handler(CommandHandler("prune", self._cmd_prune))
        self._app.add_handler(CommandHandler("tenk", self._cmd_10k))
        self._app.add_handler(CommandHandler("pipeline", self._cmd_pipeline))

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
            "🌌 *M4st3rCL4W - Pfeifer Galaxia OS*\n\n"
            "SuperGrok Fleet: 50 Agents online.\n"
            "Jarvis Kernel aktiv.\n\n"
            "Befehle:\n"
            "*System:*\n"
            "/status - Systemstatus\n"
            "/agents - Aktive Agents (50 SuperGrok Fleet)\n"
            "/tasks - Aufgabenliste\n"
            "/tools - Verfügbare Tools\n"
            "/memory - Memory Stats\n\n"
            "*Business:*\n"
            "/run <Aufgabe> - Aufgabe starten\n"
            "/think - Brain-Zyklus erzwingen\n"
            "/brain - Brain-Status\n"
            "/revenue <Idee> - Revenue-Task\n"
            "/leads <Zielgruppe> - Lead-Gen starten\n"
            "/product <Idee> - Produkt entwickeln\n"
            "/draft <Text> - Content erstellen\n"
            "/deploy - System deployen\n\n"
            "*Sprint 9:*\n"
            "/pipeline - Pipeline Status\n"
            "/graph - Neo4j Task Graph\n"
            "/prune - Non-Revenue Tasks löschen\n"
            "/tenk - 10k€ Revenue Dashboard\n"
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

    async def _cmd_think(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
        """Force a brain cycle."""
        brain = self._jarvis.brain
        if not brain:
            await update.message.reply_text("Brain nicht aktiv.")
            return

        await update.message.reply_text("🧠 Brain denkt nach...")
        decisions = await brain.force_cycle()

        lines = ["🧠 *Brain-Entscheidungen:*\n"]
        for d in decisions:
            lines.append(f"*[{d.domain.upper()}]* {d.action}")
            lines.append(f"   _{d.reasoning}_")
            lines.append(f"   Impact: {d.estimated_impact} | Priorität: {d.priority}/10\n")
        await update.message.reply_text("\n".join(lines), parse_mode="Markdown")

    async def _cmd_brain(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
        """Show brain status."""
        brain = self._jarvis.brain
        if not brain:
            await update.message.reply_text("Brain nicht aktiv.")
            return

        state = brain.get_state()
        text = (
            "🧠 *Empire Brain Status*\n\n"
            f"Zyklen: {state.cycle_count}\n"
            f"Entscheidungen: {state.decisions_made}\n"
            f"Tasks generiert: {state.tasks_generated}\n"
            f"Strategien: {', '.join(state.active_strategies) or 'keine'}"
        )
        await update.message.reply_text(text, parse_mode="Markdown")

    async def _cmd_revenue(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
        """Create a revenue task."""
        text = " ".join(ctx.args) if ctx.args else "Neue Umsatzquelle identifizieren"
        task = await self._jarvis.submit_task(
            title=f"[REVENUE] {text}",
            description=f"Revenue-Aufgabe: {text}\nZiel: Konkreter Umsatz-Plan mit Zahlen.",
            priority=TaskPriority.HIGH,
        )
        await update.message.reply_text(
            f"💰 Revenue-Task erstellt: `{task.id}`\n*{text}*",
            parse_mode="Markdown",
        )

    async def _cmd_leads(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
        """Create a lead generation task."""
        target = " ".join(ctx.args) if ctx.args else "KMU mit AI-Bedarf"
        task = await self._jarvis.submit_task(
            title=f"[MARKETING] Lead Generation: {target}",
            description=(
                f"Zielgruppe: {target}\n"
                "Erstelle eine Lead-Gen Strategie mit:\n"
                "1. Idealer Kunde (ICP)\n"
                "2. Kanal-Strategie\n"
                "3. Systeme.io Funnel Konzept\n"
                "4. Lead Magnet Idee"
            ),
            priority=TaskPriority.HIGH,
        )
        await update.message.reply_text(
            f"🎯 Lead-Gen Task erstellt: `{task.id}`\nZielgruppe: *{target}*",
            parse_mode="Markdown",
        )

    async def _cmd_product(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
        """Create a product development task."""
        text = " ".join(ctx.args) if ctx.args else "AI-Automation Kurs"
        task = await self._jarvis.submit_task(
            title=f"[PRODUCT] {text}",
            description=(
                f"Produkt-Idee: {text}\n"
                "Erstelle:\n"
                "1. Produktbeschreibung\n"
                "2. Zielgruppe\n"
                "3. Preismodell\n"
                "4. MVP-Features\n"
                "5. Launch-Plan"
            ),
            priority=TaskPriority.NORMAL,
        )
        await update.message.reply_text(
            f"🏗 Produkt-Task erstellt: `{task.id}`\n*{text}*",
            parse_mode="Markdown",
        )

    async def _cmd_memory(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
        """Show memory stats."""
        if not self._jarvis.memory:
            await update.message.reply_text("Memory nicht aktiv.")
            return
        stats = await self._jarvis.memory.stats()
        text = (
            "🧠 *Memory Status*\n\n"
            f"Short-term: {stats['short_term_entries']} Einträge\n"
            f"Long-term: {stats['long_term_namespaces']} Namespaces\n"
            f"Knowledge: {stats['knowledge_topics']} Topics"
        )
        await update.message.reply_text(text, parse_mode="Markdown")

    async def _cmd_tools(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
        """List available tools."""
        tools = self._jarvis.tools.list_tools()
        lines = ["🔧 *Verfügbare Tools*\n"]
        for t in tools:
            lines.append(f"• `{t.name}` - {t.description}")
        await update.message.reply_text("\n".join(lines), parse_mode="Markdown")

    async def _cmd_graph(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
        """Show Neo4j task graph as Mermaid diagram."""
        try:
            from integrations.neo4j_graph import Neo4jGraph
            graph = Neo4jGraph()
            if not graph.connect():
                await update.message.reply_text("Neo4j nicht erreichbar.")
                return
            summary = graph.get_graph_summary()
            mermaid = graph.get_mermaid_graph()
            graph.close()

            text = (
                "📊 *Task Graph*\n\n"
                f"Agents: {summary['agents']}\n"
                f"Tasks: {summary['tasks']}\n"
                f"Revenue: €{summary['revenue_total']:.0f} "
                f"({summary['revenue_tasks']} Tasks)\n\n"
                f"```\n{mermaid}\n```"
            )
            await update.message.reply_text(text, parse_mode="Markdown")
        except Exception as e:
            await update.message.reply_text(f"Graph-Fehler: {e}")

    async def _cmd_prune(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
        """Prune non-revenue tasks from queue."""
        tasks = self._jarvis.task_queue.all_tasks()
        pruned = 0
        for t in tasks:
            if t.status == "pending" and "[REVENUE]" not in t.title:
                await self._jarvis.task_queue.update_status(t.id, "cancelled")
                pruned += 1
        await update.message.reply_text(
            f"🗑 *Pruned {pruned} non-revenue Tasks*\n"
            f"Verbleibend: {len(tasks) - pruned} Tasks",
            parse_mode="Markdown",
        )

    async def _cmd_10k(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
        """30-day revenue forecast."""
        state = self._jarvis.state()
        pipeline = self._jarvis.pipeline

        # Gather pipeline stats
        pipeline_info = ""
        if pipeline:
            stats = await pipeline.stats()
            pipeline_info = (
                f"\n*Pipeline:*\n"
                f"  Planned: {stats.get('planned', 0)}\n"
                f"  Research: {stats.get('researched', 0)}\n"
                f"  Built: {stats.get('built', 0)}\n"
                f"  Approved: {stats.get('approved', 0)}\n"
                f"  Pruned: {stats.get('pruned', 0)}\n"
            )

        text = (
            "💰 *10k€ Revenue Dashboard*\n\n"
            f"*System:*\n"
            f"  Active Agents: {state.active_agents}\n"
            f"  Completed Tasks: {state.completed_tasks}\n"
            f"  Running Tasks: {state.running_tasks}\n"
            f"{pipeline_info}\n"
            f"*Ziel:* 10.000€ in 30 Tagen\n"
            f"*Strategie:*\n"
            f"  1. AI Automation Services (€2-5k/Auftrag)\n"
            f"  2. Digital Products via Systeme.io\n"
            f"  3. Consulting & Setup-Pakete\n"
            f"  4. Recurring Revenue (Hosting/Support)\n\n"
            f"_Revenue Engine generiert automatisch Tasks alle 30 Min._"
        )
        await update.message.reply_text(text, parse_mode="Markdown")

    async def _cmd_pipeline(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
        """Show pipeline status."""
        pipeline = self._jarvis.pipeline
        if not pipeline:
            await update.message.reply_text("Pipeline nicht aktiv.")
            return

        stats = await pipeline.stats()
        text = (
            "🔄 *Revenue Pipeline*\n\n"
            f"📋 Plan Queue: {stats.get('plan_queue', 0)}\n"
            f"🔍 Research Queue: {stats.get('research_queue', 0)}\n"
            f"🔨 Build Queue: {stats.get('build_queue', 0)}\n"
            f"✅ Review Queue: {stats.get('review_queue', 0)}\n\n"
            f"*Ergebnisse:*\n"
            f"  Completed: {stats.get('completed', 0)}\n"
            f"  Pruned: {stats.get('pruned', 0)}"
        )
        await update.message.reply_text(text, parse_mode="Markdown")

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
