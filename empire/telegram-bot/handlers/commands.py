"""
Core command handlers for the AI Empire Telegram Bot.
"""

import json
import os
from datetime import datetime

from aiogram import Dispatcher, F
from aiogram.filters import Command, CommandStart
from aiogram.types import Message

from config import ADMIN_CHAT_ID, RESULTS_DIR, TASKS_DIR


def admin_only(handler):
    """Decorator: only allow the admin user."""

    async def wrapper(message: Message, **kwargs):
        if ADMIN_CHAT_ID and message.from_user.id != ADMIN_CHAT_ID:
            await message.reply("⛔ Nicht autorisiert. Nur der Admin kann diesen Bot nutzen.")
            return
        return await handler(message, **kwargs)

    return wrapper


def register_command_handlers(dp: Dispatcher):
    @dp.message(CommandStart())
    @admin_only
    async def cmd_start(message: Message):
        await message.reply(
            "🏢 <b>Willkommen im AI Empire Control Center!</b>\n\n"
            "Ich bin dein Command Bot. Über mich steuerst du alles.\n\n"
            "Sende /help für alle verfügbaren Befehle."
        )

    @dp.message(Command("help"))
    @admin_only
    async def cmd_help(message: Message):
        await message.reply(
            "📋 <b>AI Empire - Alle Befehle</b>\n\n"
            "<b>🔧 System</b>\n"
            "/status - System-Status aller Agenten\n"
            "/health - Healthcheck aller Services\n"
            "/logs [service] - Logs eines Services\n"
            "/rebuild [service|all] - Service(s) neu bauen\n"
            "/restart [service|all] - Service(s) neustarten\n\n"
            "<b>🤖 Agenten</b>\n"
            "/agents - Liste aller Agenten\n"
            "/agent_start [name] - Agent starten\n"
            "/agent_stop [name] - Agent stoppen\n"
            "/agent_status [name] - Agent-Detail-Status\n\n"
            "<b>🐦 X/Twitter Analyse</b>\n"
            "/analyze [url] - X-Post analysieren\n"
            "/analyze_thread [url] - Thread analysieren\n"
            "/bulk_analyze - 10k-Queue Status\n"
            "/bulk_add [urls...] - URLs zur Queue hinzufügen\n"
            "/bulk_pause - Queue pausieren\n"
            "/bulk_resume - Queue fortsetzen\n\n"
            "<b>💡 Tasks & Ideen</b>\n"
            "/new_idea [text] - Neue Geschäftsidee einreichen\n"
            "/tasks - Task-Board anzeigen\n"
            "/task_add [text] - Neuen Task anlegen\n"
            "/task_done [id] - Task abschließen\n\n"
            "<b>📊 Reports</b>\n"
            "/report_daily - Tagesbericht\n"
            "/report_agents - Agenten-Leistungsbericht\n"
            "/report_x - X-Analyse-Bericht\n\n"
            "<b>☁️ Cloud</b>\n"
            "/sync - Cloud-Sync sofort starten\n"
            "/sync_status - Sync-Status anzeigen\n\n"
            "<b>🧠 Knowledge Base</b>\n"
            "/kb_search [query] - KB durchsuchen\n"
            "/kb_stats - KB Statistiken"
        )

    @dp.message(Command("status"))
    @admin_only
    async def cmd_status(message: Message):
        redis_client = dp["redis"]

        # Gather status from all agents via Redis
        agents = await redis_client.hgetall("empire:agents:status")
        queue_len = await redis_client.llen("empire:queue:bulk")
        queue_status = await redis_client.get("empire:queue:status") or "idle"

        lines = ["🏢 <b>AI Empire Status</b>\n"]
        lines.append(f"⏰ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")

        if agents:
            lines.append("<b>Agenten:</b>")
            for name, status in agents.items():
                icon = "🟢" if status == "running" else "🔴" if status == "stopped" else "🟡"
                lines.append(f"  {icon} {name}: {status}")
        else:
            lines.append("⚠️ Noch keine Agenten registriert.")

        lines.append(f"\n<b>10k-Queue:</b> {queue_len} Posts | Status: {queue_status}")

        # Check cloud sync
        sync_status = await redis_client.get("empire:sync:last") or "Noch kein Sync"
        lines.append(f"\n<b>Cloud Sync:</b> {sync_status}")

        await message.reply("\n".join(lines))

    @dp.message(Command("health"))
    @admin_only
    async def cmd_health(message: Message):
        redis_client = dp["redis"]

        checks = []
        # Check Redis
        try:
            await redis_client.ping()
            checks.append("🟢 Redis: OK")
        except Exception:
            checks.append("🔴 Redis: FEHLER")

        # Check Ollama LLM
        try:
            import aiohttp
            async with aiohttp.ClientSession() as session:
                async with session.get("http://ollama:11434/api/tags", timeout=aiohttp.ClientTimeout(total=5)) as resp:
                    if resp.status == 200:
                        data = await resp.json()
                        models = [m["name"] for m in data.get("models", [])]
                        checks.append(f"🟢 Ollama LLM: OK ({', '.join(models[:3]) or 'kein Modell'})")
                    else:
                        checks.append("🟡 Ollama LLM: Läuft, aber Status unklar")
        except Exception:
            checks.append("🔴 Ollama LLM: NICHT ERREICHBAR")

        # Check results dir
        if os.path.isdir(RESULTS_DIR):
            file_count = sum(len(files) for _, _, files in os.walk(RESULTS_DIR))
            checks.append(f"🟢 Results Dir: OK ({file_count} Dateien)")
        else:
            checks.append("🔴 Results Dir: Nicht vorhanden")

        # Check tasks dir
        if os.path.isdir(TASKS_DIR):
            checks.append("🟢 Tasks Dir: OK")
        else:
            checks.append("🔴 Tasks Dir: Nicht vorhanden")

        await message.reply(
            "🏥 <b>Health Check</b>\n\n" + "\n".join(checks)
        )

    @dp.message(Command("agents"))
    @admin_only
    async def cmd_agents(message: Message):
        redis_client = dp["redis"]
        agents = await redis_client.hgetall("empire:agents:status")

        if not agents:
            await message.reply(
                "🤖 <b>Agenten</b>\n\n"
                "Noch keine Agenten aktiv. Sie starten automatisch beim nächsten Orchestrator-Zyklus."
            )
            return

        lines = ["🤖 <b>Aktive Agenten</b>\n"]
        for name, status in sorted(agents.items()):
            info = await redis_client.hgetall(f"empire:agent:{name}") or {}
            icon = "🟢" if status == "running" else "🔴"
            mission = info.get("mission", "N/A")
            last_action = info.get("last_action", "N/A")
            lines.append(f"{icon} <b>{name}</b>")
            lines.append(f"   Mission: {mission}")
            lines.append(f"   Letzte Aktion: {last_action}\n")

        await message.reply("\n".join(lines))

    @dp.message(Command("new_idea"))
    @admin_only
    async def cmd_new_idea(message: Message):
        redis_client = dp["redis"]

        text = message.text.replace("/new_idea", "", 1).strip()
        if not text:
            await message.reply("💡 Nutzung: /new_idea [deine Idee hier]")
            return

        idea = {
            "id": f"idea_{datetime.now().strftime('%Y%m%d_%H%M%S')}",
            "text": text,
            "submitted_at": datetime.now().isoformat(),
            "status": "new",
            "evaluation": None,
        }

        await redis_client.rpush("empire:ideas", json.dumps(idea))

        # Save to file
        ideas_dir = f"{RESULTS_DIR}/ideas"
        os.makedirs(ideas_dir, exist_ok=True)
        with open(f"{ideas_dir}/{idea['id']}.json", "w") as f:
            json.dump(idea, f, indent=2)

        await message.reply(
            f"💡 <b>Neue Idee registriert!</b>\n\n"
            f"ID: <code>{idea['id']}</code>\n"
            f"Text: {text}\n\n"
            "Die Agenten werden diese Idee evaluieren und dir einen Report schicken."
        )

    @dp.message(Command("sync"))
    @admin_only
    async def cmd_sync(message: Message):
        redis_client = dp["redis"]
        await redis_client.publish("empire:commands", json.dumps({
            "action": "sync_now",
            "requested_by": "admin",
            "timestamp": datetime.now().isoformat(),
        }))
        await message.reply("☁️ Cloud-Sync wurde getriggert. Du bekommst eine Bestätigung wenn fertig.")

    @dp.message(Command("sync_status"))
    @admin_only
    async def cmd_sync_status(message: Message):
        redis_client = dp["redis"]
        last_sync = await redis_client.get("empire:sync:last") or "Noch kein Sync durchgeführt"
        sync_errors = await redis_client.get("empire:sync:errors") or "0"
        await message.reply(
            f"☁️ <b>Cloud Sync Status</b>\n\n"
            f"Letzter Sync: {last_sync}\n"
            f"Fehler: {sync_errors}"
        )

    @dp.message(Command("kb_search"))
    @admin_only
    async def cmd_kb_search(message: Message):
        query = message.text.replace("/kb_search", "", 1).strip()
        if not query:
            await message.reply("🧠 Nutzung: /kb_search [suchbegriff]")
            return

        redis_client = dp["redis"]
        # Publish search request to agent system
        await redis_client.publish("empire:commands", json.dumps({
            "action": "kb_search",
            "query": query,
            "reply_chat_id": message.chat.id,
            "timestamp": datetime.now().isoformat(),
        }))
        await message.reply(f"🧠 Suche in Knowledge Base nach: <i>{query}</i>\nErgebnisse kommen gleich...")

    @dp.message(Command("kb_stats"))
    @admin_only
    async def cmd_kb_stats(message: Message):
        redis_client = dp["redis"]
        stats = await redis_client.hgetall("empire:kb:stats") or {}
        total_docs = stats.get("total_docs", "0")
        last_update = stats.get("last_update", "N/A")
        await message.reply(
            f"🧠 <b>Knowledge Base Stats</b>\n\n"
            f"Dokumente: {total_docs}\n"
            f"Letztes Update: {last_update}"
        )

    @dp.message(Command("report_daily"))
    @admin_only
    async def cmd_report_daily(message: Message):
        redis_client = dp["redis"]
        await redis_client.publish("empire:commands", json.dumps({
            "action": "generate_report",
            "type": "daily",
            "reply_chat_id": message.chat.id,
            "timestamp": datetime.now().isoformat(),
        }))
        await message.reply("📊 Tagesbericht wird generiert... Du bekommst ihn in Kürze.")

    @dp.message(Command("logs"))
    @admin_only
    async def cmd_logs(message: Message):
        service = message.text.replace("/logs", "", 1).strip()
        if not service:
            await message.reply("📋 Nutzung: /logs [service-name]\nVerfügbar: telegram-bot, agent-orchestrator, x-analyzer, queue-worker, cloud-sync")
            return
        await message.reply(
            f"📋 Logs für <b>{service}</b> können auf dem Server mit:\n"
            f"<code>docker compose logs -f {service} --tail 50</code>\n"
            "abgerufen werden."
        )
