"""
Report Listener
================
Runs inside the Telegram bot container.
Listens on Redis pub/sub for agent reports and forwards them to Telegram.
"""

import asyncio
import json
import logging

import redis.asyncio as redis
from aiogram import Bot

from config import BOT_TOKEN, ADMIN_CHAT_ID, REDIS_URL

logger = logging.getLogger("report-listener")


async def start_report_listener(bot: Bot):
    """Listen for agent reports and forward to admin chat."""
    if not ADMIN_CHAT_ID:
        logger.warning("No ADMIN_CHAT_ID set. Reports won't be forwarded to Telegram.")
        return

    r = redis.from_url(REDIS_URL, decode_responses=True)
    pubsub = r.pubsub()
    await pubsub.subscribe("empire:telegram:send", "empire:reports:live")

    logger.info("Report listener started. Waiting for messages...")

    async for msg in pubsub.listen():
        if msg["type"] != "message":
            continue

        try:
            data = json.loads(msg["data"])
            text = data.get("text", "")
            priority = data.get("priority", "normal")

            if not text:
                continue

            # Add priority indicator
            if priority == "high":
                text = f"🔴 {text}"
            elif priority == "low":
                text = f"🔵 {text}"

            # Truncate if too long for Telegram (4096 chars max)
            if len(text) > 4000:
                text = text[:4000] + "\n\n... (gekürzt)"

            await bot.send_message(ADMIN_CHAT_ID, text)

        except json.JSONDecodeError:
            logger.warning(f"Invalid JSON in report: {msg['data'][:100]}")
        except Exception as e:
            logger.error(f"Error forwarding report: {e}")
            await asyncio.sleep(5)
