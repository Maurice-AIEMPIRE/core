"""Memory System - Short-term and long-term memory for Galaxia agents.

Architecture:
- Short-term: Redis lists with TTL (conversation context, recent results)
- Long-term: Redis hashes (agent knowledge, task history, learned patterns)
- Semantic: Key-value store with search capability (future: vector embeddings)
"""

from __future__ import annotations

import json
import logging
import time
from typing import Any

import redis.asyncio as aioredis

logger = logging.getLogger("galaxia.memory")

# Key prefixes
PREFIX_SHORT = "galaxia:mem:short:"    # Short-term (TTL)
PREFIX_LONG = "galaxia:mem:long:"      # Long-term (persistent)
PREFIX_CONTEXT = "galaxia:mem:ctx:"    # Conversation context per agent
PREFIX_HISTORY = "galaxia:mem:hist:"   # Task execution history
PREFIX_KNOWLEDGE = "galaxia:mem:kb:"   # Knowledge base entries


class MemorySystem:
    """Unified memory system for all Galaxia agents."""

    def __init__(self, redis: aioredis.Redis):
        self._redis = redis

    # === Short-Term Memory (TTL-based, auto-expires) ===

    async def remember_short(
        self, key: str, value: Any, ttl_seconds: int = 3600
    ) -> None:
        """Store a value in short-term memory with TTL."""
        full_key = f"{PREFIX_SHORT}{key}"
        await self._redis.set(full_key, json.dumps(value, default=str), ex=ttl_seconds)

    async def recall_short(self, key: str) -> Any | None:
        """Recall a value from short-term memory."""
        raw = await self._redis.get(f"{PREFIX_SHORT}{key}")
        return json.loads(raw) if raw else None

    # === Long-Term Memory (persistent) ===

    async def remember_long(self, namespace: str, key: str, value: Any) -> None:
        """Store in long-term memory (persisted across restarts)."""
        await self._redis.hset(
            f"{PREFIX_LONG}{namespace}",
            key,
            json.dumps(value, default=str),
        )

    async def recall_long(self, namespace: str, key: str) -> Any | None:
        """Recall from long-term memory."""
        raw = await self._redis.hget(f"{PREFIX_LONG}{namespace}", key)
        return json.loads(raw) if raw else None

    async def recall_all_long(self, namespace: str) -> dict[str, Any]:
        """Recall all entries from a long-term namespace."""
        raw = await self._redis.hgetall(f"{PREFIX_LONG}{namespace}")
        return {k: json.loads(v) for k, v in raw.items()}

    async def forget_long(self, namespace: str, key: str) -> None:
        await self._redis.hdel(f"{PREFIX_LONG}{namespace}", key)

    # === Conversation Context (per-agent rolling window) ===

    async def add_context(
        self, agent_id: str, role: str, content: str, max_messages: int = 20
    ) -> None:
        """Add a message to an agent's conversation context."""
        key = f"{PREFIX_CONTEXT}{agent_id}"
        entry = json.dumps({"role": role, "content": content, "ts": time.time()})
        pipe = self._redis.pipeline()
        pipe.rpush(key, entry)
        pipe.ltrim(key, -max_messages, -1)  # Keep only last N
        pipe.expire(key, 7200)  # 2h TTL
        await pipe.execute()

    async def get_context(self, agent_id: str) -> list[dict[str, str]]:
        """Get an agent's conversation context as LLM messages."""
        key = f"{PREFIX_CONTEXT}{agent_id}"
        raw_list = await self._redis.lrange(key, 0, -1)
        messages = []
        for raw in raw_list:
            entry = json.loads(raw)
            messages.append({"role": entry["role"], "content": entry["content"]})
        return messages

    async def clear_context(self, agent_id: str) -> None:
        await self._redis.delete(f"{PREFIX_CONTEXT}{agent_id}")

    # === Task History (append-only log) ===

    async def log_task(self, task_id: str, event: str, data: dict | None = None) -> None:
        """Log a task event to history."""
        key = f"{PREFIX_HISTORY}{task_id}"
        entry = json.dumps({
            "event": event,
            "data": data or {},
            "ts": time.time(),
        }, default=str)
        await self._redis.rpush(key, entry)
        await self._redis.expire(key, 86400 * 7)  # 7 days

    async def get_task_history(self, task_id: str) -> list[dict]:
        """Get full history of a task."""
        key = f"{PREFIX_HISTORY}{task_id}"
        raw_list = await self._redis.lrange(key, 0, -1)
        return [json.loads(r) for r in raw_list]

    # === Knowledge Base (persistent key-value) ===

    async def learn(self, topic: str, content: str, source: str = "") -> None:
        """Store knowledge that agents can reference."""
        await self._redis.hset(
            f"{PREFIX_KNOWLEDGE}topics",
            topic,
            json.dumps({
                "content": content,
                "source": source,
                "learned_at": time.time(),
            }),
        )
        logger.info("Knowledge stored: %s", topic)

    async def recall_knowledge(self, topic: str) -> str | None:
        """Recall knowledge by topic."""
        raw = await self._redis.hget(f"{PREFIX_KNOWLEDGE}topics", topic)
        if raw:
            data = json.loads(raw)
            return data["content"]
        return None

    async def search_knowledge(self, query: str) -> list[dict]:
        """Simple keyword search across knowledge base."""
        all_topics = await self._redis.hgetall(f"{PREFIX_KNOWLEDGE}topics")
        results = []
        query_lower = query.lower()
        for topic, raw in all_topics.items():
            data = json.loads(raw)
            if query_lower in topic.lower() or query_lower in data["content"].lower():
                results.append({"topic": topic, **data})
        return results

    # === Stats ===

    async def stats(self) -> dict[str, int]:
        """Get memory usage statistics."""
        short_keys = 0
        long_keys = 0
        async for _ in self._redis.scan_iter(f"{PREFIX_SHORT}*"):
            short_keys += 1
        async for _ in self._redis.scan_iter(f"{PREFIX_LONG}*"):
            long_keys += 1
        kb_count = await self._redis.hlen(f"{PREFIX_KNOWLEDGE}topics")
        return {
            "short_term_entries": short_keys,
            "long_term_namespaces": long_keys,
            "knowledge_topics": kb_count,
        }
