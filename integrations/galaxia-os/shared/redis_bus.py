"""Redis Message Bus - Core communication layer for Galaxia OS agents."""

from __future__ import annotations

import asyncio
import json
import logging
from collections.abc import Callable
from typing import Any

import redis.asyncio as aioredis

from shared.models import Message

logger = logging.getLogger("galaxia.bus")

# Redis channels
CHANNEL_BROADCAST = "galaxia:broadcast"
CHANNEL_KERNEL = "galaxia:kernel"
CHANNEL_TASKS = "galaxia:tasks"
CHANNEL_HEARTBEAT = "galaxia:heartbeat"

# Redis keys
KEY_TASKS = "galaxia:tasks:store"
KEY_AGENTS = "galaxia:agents:store"
KEY_QUEUE_PREFIX = "galaxia:queue:"  # per-priority queues
KEY_METRICS = "galaxia:metrics"


def agent_channel(agent_id: str) -> str:
    return f"galaxia:agent:{agent_id}"


class RedisBus:
    """Async Redis message bus for inter-agent communication."""

    def __init__(self, redis_url: str = "redis://localhost:6379/0"):
        self._url = redis_url
        self._redis: aioredis.Redis | None = None
        self._pubsub: aioredis.client.PubSub | None = None
        self._handlers: dict[str, list[Callable]] = {}
        self._listener_task: asyncio.Task | None = None

    async def connect(self) -> None:
        self._redis = aioredis.from_url(self._url, decode_responses=True)
        await self._redis.ping()
        self._pubsub = self._redis.pubsub()
        logger.info("Connected to Redis at %s", self._url)

    async def disconnect(self) -> None:
        if self._listener_task:
            self._listener_task.cancel()
        if self._pubsub:
            await self._pubsub.close()
        if self._redis:
            await self._redis.close()
        logger.info("Disconnected from Redis")

    @property
    def redis(self) -> aioredis.Redis:
        if not self._redis:
            raise RuntimeError("RedisBus not connected")
        return self._redis

    # === Pub/Sub ===

    async def subscribe(self, channel: str, handler: Callable) -> None:
        if channel not in self._handlers:
            self._handlers[channel] = []
            await self._pubsub.subscribe(channel)
        self._handlers[channel].append(handler)
        logger.debug("Subscribed to %s", channel)

    async def publish(self, channel: str, message: Message) -> None:
        data = message.model_dump_json()
        await self.redis.publish(channel, data)

    async def send_to_agent(self, agent_id: str, message: Message) -> None:
        await self.publish(agent_channel(agent_id), message)

    async def broadcast(self, message: Message) -> None:
        await self.publish(CHANNEL_BROADCAST, message)

    async def start_listening(self) -> None:
        self._listener_task = asyncio.create_task(self._listen_loop())

    async def _listen_loop(self) -> None:
        try:
            async for raw in self._pubsub.listen():
                if raw["type"] != "message":
                    continue
                channel = raw["channel"]
                handlers = self._handlers.get(channel, [])
                if not handlers:
                    continue
                try:
                    msg = Message.model_validate_json(raw["data"])
                    for handler in handlers:
                        await handler(msg)
                except Exception:
                    logger.exception("Error handling message on %s", channel)
        except asyncio.CancelledError:
            pass

    # === Task Store (Redis Hash) ===

    async def store_task(self, task_id: str, data: dict[str, Any]) -> None:
        await self.redis.hset(KEY_TASKS, task_id, json.dumps(data, default=str))

    async def get_task(self, task_id: str) -> dict[str, Any] | None:
        raw = await self.redis.hget(KEY_TASKS, task_id)
        return json.loads(raw) if raw else None

    async def get_all_tasks(self) -> dict[str, dict]:
        raw = await self.redis.hgetall(KEY_TASKS)
        return {k: json.loads(v) for k, v in raw.items()}

    # === Agent Store (Redis Hash) ===

    async def store_agent(self, agent_id: str, data: dict[str, Any]) -> None:
        await self.redis.hset(KEY_AGENTS, agent_id, json.dumps(data, default=str))

    async def get_agent(self, agent_id: str) -> dict[str, Any] | None:
        raw = await self.redis.hget(KEY_AGENTS, agent_id)
        return json.loads(raw) if raw else None

    async def get_all_agents(self) -> dict[str, dict]:
        raw = await self.redis.hgetall(KEY_AGENTS)
        return {k: json.loads(v) for k, v in raw.items()}

    async def remove_agent(self, agent_id: str) -> None:
        await self.redis.hdel(KEY_AGENTS, agent_id)

    # === Task Queue (Redis Sorted Set by priority) ===

    async def enqueue_task(self, task_id: str, priority: int) -> None:
        await self.redis.zadd("galaxia:task_queue", {task_id: -priority})

    async def dequeue_task(self) -> str | None:
        result = await self.redis.zpopmin("galaxia:task_queue", count=1)
        if result:
            return result[0][0]
        return None

    async def queue_length(self) -> int:
        return await self.redis.zcard("galaxia:task_queue")

    # === Metrics Counter ===

    async def increment_metric(self, name: str, amount: int = 1) -> None:
        await self.redis.hincrby(KEY_METRICS, name, amount)

    async def get_metrics(self) -> dict[str, int]:
        raw = await self.redis.hgetall(KEY_METRICS)
        return {k: int(v) for k, v in raw.items()}
