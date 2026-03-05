"""Pfeifer Galaxia OS - Main Entrypoint"""

import asyncio
import logging
import os
import signal
import sys

import structlog

from kernel.jarvis import JarvisKernel
from kernel.metrics import start_metrics_server
from kernel.telegram_interface import TelegramInterface

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
logger = logging.getLogger("galaxia")


async def main():
    # Config from env
    redis_url = os.getenv("REDIS_URL", "redis://localhost:6379/0")
    litellm_url = os.getenv("LITELLM_URL", "http://localhost:4000")
    litellm_key = os.getenv("LITELLM_API_KEY", "sk-galaxia-local")
    default_model = os.getenv("DEFAULT_MODEL", "ollama/qwen3:14b")
    telegram_token = os.getenv("TELEGRAM_BOT_TOKEN", "")

    logger.info("╔══════════════════════════════════════╗")
    logger.info("║   PFEIFER GALAXIA OS - JARVIS v1.0   ║")
    logger.info("╚══════════════════════════════════════╝")

    # Prometheus metrics server
    metrics_runner = await start_metrics_server()
    logger.info("Metrics server on :8080/metrics")

    # Boot Jarvis
    jarvis = JarvisKernel(
        redis_url=redis_url,
        litellm_url=litellm_url,
        litellm_api_key=litellm_key,
        default_model=default_model,
    )
    await jarvis.boot()

    # Telegram interface (optional)
    telegram = None
    if telegram_token:
        telegram = TelegramInterface(jarvis, telegram_token)
        await telegram.start()
        logger.info("Telegram interface active")
    else:
        logger.info("No TELEGRAM_BOT_TOKEN - Telegram interface disabled")

    # Graceful shutdown
    loop = asyncio.get_event_loop()
    stop_event = asyncio.Event()

    def handle_signal():
        stop_event.set()

    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, handle_signal)

    # Run dispatch loop until stopped
    dispatch_task = asyncio.create_task(jarvis.dispatch_loop())

    await stop_event.wait()

    # Shutdown
    dispatch_task.cancel()
    if telegram:
        await telegram.stop()
    await jarvis.shutdown()
    await metrics_runner.cleanup()
    logger.info("Galaxia OS shutdown complete")


if __name__ == "__main__":
    asyncio.run(main())
