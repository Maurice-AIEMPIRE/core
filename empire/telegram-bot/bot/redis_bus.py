"""Redis message bus for inter-agent communication."""

import json
import redis.asyncio as redis
from typing import Callable, Optional


class RedisBus:
    def __init__(self, url: str = "redis://redis:6379"):
        self.redis = redis.from_url(url, decode_responses=True)
        self.pubsub = self.redis.pubsub()

    async def publish(self, channel: str, data: dict):
        await self.redis.publish(channel, json.dumps(data))

    async def enqueue(self, queue: str, data: dict):
        await self.redis.rpush(queue, json.dumps(data))

    async def dequeue(self, queue: str, timeout: int = 5) -> Optional[dict]:
        result = await self.redis.blpop(queue, timeout=timeout)
        if result:
            _, raw = result
            return json.loads(raw)
        return None

    async def get_queue_length(self, queue: str) -> int:
        return await self.redis.llen(queue)

    async def set_state(self, key: str, data: dict, ttl: int = 0):
        raw = json.dumps(data)
        if ttl > 0:
            await self.redis.setex(key, ttl, raw)
        else:
            await self.redis.set(key, raw)

    async def get_state(self, key: str) -> Optional[dict]:
        raw = await self.redis.get(key)
        return json.loads(raw) if raw else None

    async def close(self):
        await self.redis.close()
