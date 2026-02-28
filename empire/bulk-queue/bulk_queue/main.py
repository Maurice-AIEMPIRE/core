"""10k Posts Bulk Queue Processor.

Permanent background queue that:
- Can be started/paused/resumed via Telegram
- Saves partial results continuously
- Reports progress periodically
- Syncs results to shared KB + cloud
"""

import asyncio
import json
import logging
import os
import time
from pathlib import Path

import redis.asyncio as redis
from dotenv import load_dotenv

load_dotenv()
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("bulk-queue")


class BulkQueueProcessor:
    def __init__(self):
        self.redis = redis.from_url(
            os.environ.get("REDIS_URL", "redis://redis:6379"),
            decode_responses=True,
        )
        self.results_dir = Path("/empire/results/bulk-queue")
        self.results_dir.mkdir(parents=True, exist_ok=True)
        self.pubsub = self.redis.pubsub()
        self._paused = False
        self._running = False

    async def get_state(self) -> dict:
        raw = await self.redis.get("bulk-queue:state")
        return json.loads(raw) if raw else {
            "status": "idle",
            "processed": 0,
            "total": 0,
            "errors": 0,
            "last_update": 0,
        }

    async def set_state(self, state: dict):
        state["last_update"] = time.time()
        await self.redis.set("bulk-queue:state", json.dumps(state))

    async def listen_controls(self):
        """Listen for start/pause/resume commands."""
        await self.pubsub.subscribe("bulk-queue:control")
        async for message in self.pubsub.listen():
            if message["type"] == "message":
                try:
                    data = json.loads(message["data"])
                    action = data.get("action")

                    if action == "start":
                        self._paused = False
                        self._running = True
                        logger.info("Bulk queue: STARTED")
                    elif action == "pause":
                        self._paused = True
                        logger.info("Bulk queue: PAUSED")
                    elif action == "resume":
                        self._paused = False
                        logger.info("Bulk queue: RESUMED")
                    elif action == "stop":
                        self._running = False
                        self._paused = False
                        logger.info("Bulk queue: STOPPED")
                except Exception as e:
                    logger.error(f"Control message error: {e}")

    async def process_batch(self, batch_start: int, batch_size: int = 10) -> int:
        """Process a batch of items from the queue."""
        processed = 0

        for i in range(batch_size):
            if self._paused or not self._running:
                break

            # Try to dequeue an item
            result = await self.redis.blpop("bulk-queue:items", timeout=2)
            if not result:
                break

            _, raw = result
            try:
                item = json.loads(raw)

                # Forward to X analysis engine for processing
                await self.redis.rpush("x-analysis:queue", json.dumps({
                    "job_id": f"bulk-{batch_start + i}",
                    "url_or_text": item.get("url", item.get("text", "")),
                    "requester": "bulk-queue",
                    "auto_execute": item.get("auto_execute", False),
                }))

                processed += 1

                # Save partial result reference
                partial_path = self.results_dir / f"batch_{batch_start // batch_size}.jsonl"
                with open(partial_path, "a") as f:
                    f.write(json.dumps({
                        "index": batch_start + i,
                        "item": item,
                        "status": "queued_for_analysis",
                        "timestamp": time.time(),
                    }) + "\n")

            except Exception as e:
                logger.error(f"Batch item error: {e}")

            # Small delay to avoid overwhelming the system
            await asyncio.sleep(0.5)

        return processed

    async def run_processor(self):
        """Main processing loop."""
        logger.info("Bulk queue processor ready, waiting for start command...")

        while True:
            if not self._running or self._paused:
                await asyncio.sleep(2)
                continue

            state = await self.get_state()
            processed = state.get("processed", 0)
            total = state.get("total", 0)

            if total > 0 and processed >= total:
                state["status"] = "completed"
                await self.set_state(state)
                self._running = False

                # Notify completion
                await self.redis.rpush("telegram:results", json.dumps({
                    "task_id": "bulk-complete",
                    "department": "x-analysis",
                    "success": True,
                    "message": (
                        f"<b>10k Bulk Queue abgeschlossen!</b>\n"
                        f"Verarbeitet: {processed}/{total}\n"
                        f"Fehler: {state.get('errors', 0)}\n"
                        f"Ergebnisse: /empire/results/bulk-queue/"
                    ),
                }))
                continue

            # Process batch
            batch_count = await self.process_batch(processed, batch_size=10)
            state["processed"] = processed + batch_count
            state["status"] = "running"
            await self.set_state(state)

            # Periodic progress report every 100 items
            if state["processed"] % 100 == 0 and state["processed"] > 0:
                pct = state["processed"] / total * 100 if total > 0 else 0
                await self.redis.rpush("telegram:results", json.dumps({
                    "task_id": "bulk-progress",
                    "department": "x-analysis",
                    "success": True,
                    "message": (
                        f"<b>Bulk Queue Progress:</b> {state['processed']}/{total} ({pct:.1f}%)\n"
                        f"Fehler: {state.get('errors', 0)}"
                    ),
                }))

            await asyncio.sleep(1)

    async def run(self):
        await asyncio.gather(
            self.listen_controls(),
            self.run_processor(),
        )


async def main():
    processor = BulkQueueProcessor()
    await processor.run()


if __name__ == "__main__":
    asyncio.run(main())
