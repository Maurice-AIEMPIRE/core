"""Prometheus metrics endpoint for Jarvis Kernel."""

from __future__ import annotations

import asyncio
import os
from aiohttp import web
from prometheus_client import Counter, Gauge, generate_latest, CONTENT_TYPE_LATEST

# Metrics
TASKS_SUBMITTED = Counter("galaxia_tasks_submitted_total", "Total tasks submitted")
TASKS_COMPLETED = Counter("galaxia_tasks_completed_total", "Total tasks completed")
TASKS_FAILED = Counter("galaxia_tasks_failed_total", "Total tasks failed")
AGENTS_ACTIVE = Gauge("galaxia_agents_active", "Currently active agents")
TASKS_PENDING = Gauge("galaxia_tasks_pending", "Currently pending tasks")
TASKS_RUNNING = Gauge("galaxia_tasks_running", "Currently running tasks")
MESSAGES_TOTAL = Counter("galaxia_messages_total", "Total messages processed")


async def metrics_handler(request):
    body = generate_latest()
    return web.Response(body=body, headers={"Content-Type": CONTENT_TYPE_LATEST})


async def health_handler(request):
    return web.Response(text="OK")


async def start_metrics_server(host: str = "0.0.0.0", port: int | None = None):
    if port is None:
        port = int(os.environ.get("METRICS_PORT", 8080))
    app = web.Application()
    app.router.add_get("/metrics", metrics_handler)
    app.router.add_get("/health", health_handler)
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, host, port)
    await site.start()
    return runner
