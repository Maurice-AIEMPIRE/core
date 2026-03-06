"""Multi-Bot Manager - Startet alle Telegram Bots mit verschiedenen AI-Modellen.

Jeder Bot bekommt sein eigenes Modell zum Testen.
Auto-restart bei Fehlern, Health-Monitoring, graceful shutdown.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import signal
import sys
import time

import structlog

from ai_chat_bot import AIChatBot, BotConfig

# Structured logging
structlog.configure(
    processors=[
        structlog.stdlib.add_log_level,
        structlog.stdlib.add_logger_name,
        structlog.dev.ConsoleRenderer(colors=True),
    ],
    wrapper_class=structlog.stdlib.BoundLogger,
    logger_factory=structlog.stdlib.LoggerFactory(),
)
logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"), format="%(message)s")
logger = logging.getLogger("bot-manager")

# ============================================================
# BOT CONFIGURATION
# ============================================================
# Each bot needs its own Telegram Bot Token (from @BotFather)
# and uses a different AI model via LiteLLM.
#
# Set these environment variables:
#   BOT_1_TOKEN  = Telegram token for Claude Haiku bot
#   BOT_2_TOKEN  = Telegram token for GPT-4o-mini bot
#   BOT_3_TOKEN  = Telegram token for Claude Sonnet bot
#   BOT_4_TOKEN  = Telegram token for Llama bot
#
# Or use BOTS_CONFIG_JSON for custom configuration.
# ============================================================

DEFAULT_BOTS = [
    {
        "name": "Haiku Bot",
        "token_env": "BOT_1_TOKEN",
        "model": "anthropic/claude-haiku-4-5-20251001",
        "system_prompt": (
            "Du bist der Haiku Bot - schnell, praezise, effizient. "
            "Du antwortest auf Deutsch, kurz und knackig. "
            "Dein Modell ist Claude Haiku 4.5 von Anthropic."
        ),
        "temperature": 0.5,
        "max_tokens": 2048,
    },
    {
        "name": "GPT Bot",
        "token_env": "BOT_2_TOKEN",
        "model": "openai/gpt-4o-mini",
        "system_prompt": (
            "Du bist der GPT Bot - kreativ und vielseitig. "
            "Du antwortest auf Deutsch, hilfreich und ausfuehrlich. "
            "Dein Modell ist GPT-4o-mini von OpenAI."
        ),
        "temperature": 0.7,
        "max_tokens": 2048,
    },
    {
        "name": "Sonnet Bot",
        "token_env": "BOT_3_TOKEN",
        "model": "anthropic/claude-sonnet-4-6",
        "system_prompt": (
            "Du bist der Sonnet Bot - intelligent und gruendlich. "
            "Du antwortest auf Deutsch, durchdacht und strukturiert. "
            "Dein Modell ist Claude Sonnet 4.6 von Anthropic."
        ),
        "temperature": 0.6,
        "max_tokens": 4096,
    },
    {
        "name": "Llama Bot",
        "token_env": "BOT_4_TOKEN",
        "model": "ollama/llama3.1:8b",
        "system_prompt": (
            "Du bist der Llama Bot - Open Source und lokal gehostet. "
            "Du antwortest auf Deutsch, direkt und praktisch. "
            "Dein Modell ist Llama 3.1 8B von Meta, lokal via Ollama."
        ),
        "temperature": 0.7,
        "max_tokens": 2048,
    },
]


def load_bot_configs() -> list[BotConfig]:
    """Load bot configurations from environment."""
    litellm_url = os.getenv("LITELLM_URL", "http://litellm:4000")
    litellm_key = os.getenv("LITELLM_API_KEY", "sk-galaxia-local")

    # Check for custom JSON config
    custom_config = os.getenv("BOTS_CONFIG_JSON")
    if custom_config:
        try:
            bots_data = json.loads(custom_config)
            logger.info("Loaded %d bots from BOTS_CONFIG_JSON", len(bots_data))
        except json.JSONDecodeError as e:
            logger.error("Invalid BOTS_CONFIG_JSON: %s", e)
            bots_data = DEFAULT_BOTS
    else:
        bots_data = DEFAULT_BOTS

    configs = []
    for bot_def in bots_data:
        token_env = bot_def.get("token_env", "")
        token = os.getenv(token_env, "")

        if not token:
            logger.warning(
                "Skipping '%s' - no token in %s", bot_def["name"], token_env
            )
            continue

        configs.append(
            BotConfig(
                name=bot_def["name"],
                token=token,
                model=bot_def["model"],
                litellm_url=litellm_url,
                litellm_api_key=litellm_key,
                system_prompt=bot_def.get("system_prompt", ""),
                max_tokens=bot_def.get("max_tokens", 2048),
                temperature=bot_def.get("temperature", 0.7),
            )
        )

    return configs


async def run_bot_with_restart(bot: AIChatBot, restart_delay: float = 5.0) -> None:
    """Run a bot with automatic restart on failure."""
    while True:
        try:
            await bot.start()
            # Keep running until cancelled
            while True:
                await asyncio.sleep(60)
        except asyncio.CancelledError:
            logger.info("[%s] Shutting down...", bot.config.name)
            await bot.stop()
            return
        except Exception as e:
            logger.error(
                "[%s] Crashed: %s - restarting in %.0fs",
                bot.config.name,
                e,
                restart_delay,
            )
            try:
                await bot.stop()
            except Exception:
                pass
            await asyncio.sleep(restart_delay)


async def health_monitor(bots: list[AIChatBot], interval: float = 300.0) -> None:
    """Log health status of all bots periodically."""
    while True:
        await asyncio.sleep(interval)
        logger.info("=== Health Check ===")
        for bot in bots:
            uptime_h = int(bot.uptime_seconds // 3600)
            uptime_m = int((bot.uptime_seconds % 3600) // 60)
            logger.info(
                "  [%s] model=%s uptime=%dh%dm requests=%d errors=%d",
                bot.config.name,
                bot.config.model,
                uptime_h,
                uptime_m,
                bot._request_count,
                bot._error_count,
            )
        logger.info("====================")


async def main() -> None:
    logger.info("=" * 50)
    logger.info("  TELEGRAM MULTI-BOT MANAGER")
    logger.info("  Jeder Bot = anderes AI-Modell")
    logger.info("=" * 50)

    configs = load_bot_configs()

    if not configs:
        logger.error(
            "Keine Bots konfiguriert! Setze mindestens einen BOT_X_TOKEN.\n"
            "  BOT_1_TOKEN = Claude Haiku\n"
            "  BOT_2_TOKEN = GPT-4o-mini\n"
            "  BOT_3_TOKEN = Claude Sonnet\n"
            "  BOT_4_TOKEN = Llama 3.1"
        )
        sys.exit(1)

    logger.info("Starte %d Bots:", len(configs))
    for c in configs:
        logger.info("  - %s -> %s", c.name, c.model)

    bots = [AIChatBot(config) for config in configs]

    # Graceful shutdown
    stop_event = asyncio.Event()
    loop = asyncio.get_event_loop()

    def handle_signal():
        stop_event.set()

    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, handle_signal)

    # Start all bots + health monitor
    tasks = [asyncio.create_task(run_bot_with_restart(bot)) for bot in bots]
    tasks.append(asyncio.create_task(health_monitor(bots)))

    logger.info("Alle Bots gestartet! Health-Check alle 5 Minuten.")

    await stop_event.wait()

    # Shutdown all
    logger.info("Shutdown signal empfangen...")
    for t in tasks:
        t.cancel()
    await asyncio.gather(*tasks, return_exceptions=True)
    logger.info("Alle Bots gestoppt. Bye!")


if __name__ == "__main__":
    asyncio.run(main())
