"""
X/Twitter Analysis handlers for the Telegram bot.
Receives URLs, sends them to the X Analyzer service via Redis.
"""

import json
import os
from datetime import datetime

from aiogram import Dispatcher
from aiogram.filters import Command
from aiogram.types import Message

from config import ADMIN_CHAT_ID, RESULTS_DIR


def register_x_handlers(dp: Dispatcher):
    @dp.message(Command("analyze"))
    async def cmd_analyze(message: Message):
        if ADMIN_CHAT_ID and message.from_user.id != ADMIN_CHAT_ID:
            return

        redis_client = dp["redis"]
        url = message.text.replace("/analyze", "", 1).strip()

        if not url:
            await message.reply(
                "🐦 <b>X/Twitter Analyse</b>\n\n"
                "Nutzung: /analyze [URL zum X-Post]\n"
                "Beispiel: <code>/analyze https://x.com/user/status/123456</code>\n\n"
                "Der Bot wird:\n"
                "1. Post/Video holen & transkribieren\n"
                "2. Konkrete Prompts daraus bauen\n"
                "3. Prüfen ob es zum Empire passt\n"
                "4. Report an dich senden"
            )
            return

        # Validate URL
        if "x.com" not in url and "twitter.com" not in url:
            await message.reply("⚠️ Bitte gib eine gültige X/Twitter URL an.")
            return

        job_id = f"x_analysis_{datetime.now().strftime('%Y%m%d_%H%M%S')}"

        job = {
            "id": job_id,
            "url": url,
            "type": "single",
            "requested_by": message.from_user.id,
            "reply_chat_id": message.chat.id,
            "submitted_at": datetime.now().isoformat(),
            "status": "queued",
        }

        # Push to analysis queue
        await redis_client.rpush("empire:x:analysis_queue", json.dumps(job))
        await redis_client.hset("empire:x:jobs", job_id, json.dumps(job))

        await message.reply(
            f"🐦 <b>X-Analyse gestartet!</b>\n\n"
            f"URL: {url}\n"
            f"Job-ID: <code>{job_id}</code>\n\n"
            "Ich analysiere den Post und schicke dir den Report."
        )

    @dp.message(Command("analyze_thread"))
    async def cmd_analyze_thread(message: Message):
        if ADMIN_CHAT_ID and message.from_user.id != ADMIN_CHAT_ID:
            return

        redis_client = dp["redis"]
        url = message.text.replace("/analyze_thread", "", 1).strip()

        if not url:
            await message.reply("🧵 Nutzung: /analyze_thread [URL zum Thread-Start]")
            return

        if "x.com" not in url and "twitter.com" not in url:
            await message.reply("⚠️ Bitte gib eine gültige X/Twitter URL an.")
            return

        job_id = f"x_thread_{datetime.now().strftime('%Y%m%d_%H%M%S')}"

        job = {
            "id": job_id,
            "url": url,
            "type": "thread",
            "requested_by": message.from_user.id,
            "reply_chat_id": message.chat.id,
            "submitted_at": datetime.now().isoformat(),
            "status": "queued",
        }

        await redis_client.rpush("empire:x:analysis_queue", json.dumps(job))
        await redis_client.hset("empire:x:jobs", job_id, json.dumps(job))

        await message.reply(
            f"🧵 <b>Thread-Analyse gestartet!</b>\n\n"
            f"URL: {url}\n"
            f"Job-ID: <code>{job_id}</code>\n\n"
            "Thread wird vollständig analysiert."
        )

    @dp.message(Command("bulk_analyze"))
    async def cmd_bulk_status(message: Message):
        if ADMIN_CHAT_ID and message.from_user.id != ADMIN_CHAT_ID:
            return

        redis_client = dp["redis"]
        queue_len = await redis_client.llen("empire:queue:bulk")
        processed = await redis_client.get("empire:queue:processed") or "0"
        failed = await redis_client.get("empire:queue:failed") or "0"
        status = await redis_client.get("empire:queue:status") or "idle"
        total = await redis_client.get("empire:queue:total") or "0"

        progress = 0
        if int(total) > 0:
            progress = round(int(processed) / int(total) * 100, 1)

        await message.reply(
            f"📦 <b>10k Bulk Queue Status</b>\n\n"
            f"Status: <b>{status}</b>\n"
            f"In Queue: {queue_len}\n"
            f"Verarbeitet: {processed} / {total} ({progress}%)\n"
            f"Fehlgeschlagen: {failed}\n\n"
            "Befehle:\n"
            "/bulk_add [urls] - URLs hinzufügen\n"
            "/bulk_pause - Pausieren\n"
            "/bulk_resume - Fortsetzen"
        )

    @dp.message(Command("bulk_add"))
    async def cmd_bulk_add(message: Message):
        if ADMIN_CHAT_ID and message.from_user.id != ADMIN_CHAT_ID:
            return

        redis_client = dp["redis"]
        text = message.text.replace("/bulk_add", "", 1).strip()

        if not text:
            await message.reply(
                "📦 Nutzung: /bulk_add [URLs, eine pro Zeile oder durch Leerzeichen getrennt]"
            )
            return

        urls = [u.strip() for u in text.replace(",", " ").split() if u.strip()]
        valid_urls = [u for u in urls if "x.com" in u or "twitter.com" in u]

        if not valid_urls:
            await message.reply("⚠️ Keine gültigen X/Twitter URLs gefunden.")
            return

        for url in valid_urls:
            job = {
                "url": url,
                "type": "bulk",
                "submitted_at": datetime.now().isoformat(),
                "status": "queued",
            }
            await redis_client.rpush("empire:queue:bulk", json.dumps(job))

        # Update total counter
        current_total = int(await redis_client.get("empire:queue:total") or "0")
        await redis_client.set("empire:queue:total", str(current_total + len(valid_urls)))

        await message.reply(
            f"📦 <b>{len(valid_urls)} URLs zur Bulk Queue hinzugefügt!</b>\n\n"
            f"Neue Queue-Größe: {await redis_client.llen('empire:queue:bulk')}"
        )

    @dp.message(Command("bulk_pause"))
    async def cmd_bulk_pause(message: Message):
        if ADMIN_CHAT_ID and message.from_user.id != ADMIN_CHAT_ID:
            return

        redis_client = dp["redis"]
        await redis_client.set("empire:queue:status", "paused")
        await message.reply("⏸️ Bulk Queue pausiert.")

    @dp.message(Command("bulk_resume"))
    async def cmd_bulk_resume(message: Message):
        if ADMIN_CHAT_ID and message.from_user.id != ADMIN_CHAT_ID:
            return

        redis_client = dp["redis"]
        await redis_client.set("empire:queue:status", "running")
        await message.reply("▶️ Bulk Queue läuft wieder.")
