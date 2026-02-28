"""
AI Empire - Telegram Control Bot
=================================
Hauptschnittstelle für das gesamte AI Empire.
Alle Befehle, Tasks, Reports laufen über diesen Bot.
"""

import asyncio
import json
import logging
import os
from datetime import datetime

import redis.asyncio as redis
from aiogram import Bot, Dispatcher, F
from aiogram.filters import Command, CommandStart
from aiogram.types import Message
from aiogram.enums import ParseMode

from config import BOT_TOKEN, ADMIN_CHAT_ID, REDIS_URL, RESULTS_DIR, TASKS_DIR, KB_DIR
from handlers.commands import register_command_handlers
from handlers.x_analysis import register_x_handlers
from handlers.tasks import register_task_handlers
from report_listener import start_report_listener

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
)
logger = logging.getLogger("empire-bot")


async def main():
    bot = Bot(token=BOT_TOKEN, parse_mode=ParseMode.HTML)
    dp = Dispatcher()

    # Redis connection
    redis_client = redis.from_url(REDIS_URL, decode_responses=True)

    # Ensure directories exist
    for d in [RESULTS_DIR, TASKS_DIR, KB_DIR]:
        os.makedirs(d, exist_ok=True)

    # Store shared resources in dispatcher data
    dp["redis"] = redis_client
    dp["bot"] = bot

    # Register all handlers
    register_command_handlers(dp)
    register_x_handlers(dp)
    register_task_handlers(dp)

    # Startup notification
    if ADMIN_CHAT_ID:
        try:
            me = await bot.get_me()
            await bot.send_message(
                ADMIN_CHAT_ID,
                "🏢 <b>AI Empire Control Bot ist ONLINE</b>\n\n"
                f"🤖 Bot: @{me.username}\n"
                f"⏰ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
                f"🧠 LLM: Ollama ({os.environ.get('OLLAMA_MODEL', 'llama3.1:8b')})\n"
                "💰 Kosten: $0 (alles Open Source)\n\n"
                "Alle Systeme bereit. Sende /help für alle Befehle.",
            )
        except Exception as e:
            logger.warning(f"Could not send startup message: {e}")

    logger.info("AI Empire Telegram Bot starting...")

    # Start report listener in background
    asyncio.create_task(start_report_listener(bot))

    await dp.start_polling(bot)


if __name__ == "__main__":
    asyncio.run(main())
