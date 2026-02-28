"""
Queue Worker
==============
Manages the persistent bulk task queue.
- Monitors queue health
- Handles retries for failed jobs
- Reports progress
- Manages pause/resume state
"""

import asyncio
import json
import logging
import os
from datetime import datetime

import redis.asyncio as redis

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [queue-worker] %(levelname)s: %(message)s",
)
logger = logging.getLogger("queue-worker")

REDIS_URL = os.environ.get("REDIS_URL", "redis://redis:6379/0")
RESULTS_DIR = "/empire/results/queue"


async def monitor_queue(redis_client: redis.Redis):
    """Monitor queue health and save periodic snapshots."""
    while True:
        try:
            bulk_len = await redis_client.llen("empire:queue:bulk")
            analysis_len = await redis_client.llen("empire:x:analysis_queue")
            processed = await redis_client.get("empire:queue:processed") or "0"
            failed = await redis_client.get("empire:queue:failed") or "0"
            total = await redis_client.get("empire:queue:total") or "0"
            status = await redis_client.get("empire:queue:status") or "idle"

            # Save snapshot
            snapshot = {
                "timestamp": datetime.now().isoformat(),
                "bulk_queue": bulk_len,
                "analysis_queue": analysis_len,
                "processed": int(processed),
                "failed": int(failed),
                "total": int(total),
                "status": status,
            }

            await redis_client.set("empire:queue:snapshot", json.dumps(snapshot))

            # Save to disk periodically
            os.makedirs(RESULTS_DIR, exist_ok=True)
            date_str = datetime.now().strftime("%Y-%m-%d")
            snapshot_file = os.path.join(RESULTS_DIR, f"snapshot_{date_str}.jsonl")
            with open(snapshot_file, "a") as f:
                f.write(json.dumps(snapshot) + "\n")

            logger.info(
                f"Queue status: bulk={bulk_len} analysis={analysis_len} "
                f"processed={processed}/{total} failed={failed} status={status}"
            )

        except Exception as e:
            logger.error(f"Monitor error: {e}")

        await asyncio.sleep(60)  # Check every minute


async def retry_failed(redis_client: redis.Redis):
    """Retry failed jobs from the dead letter queue."""
    while True:
        try:
            failed_raw = await redis_client.lpop("empire:queue:dead_letter")
            if failed_raw:
                job = json.loads(failed_raw)
                retries = job.get("retries", 0)

                if retries < 3:
                    job["retries"] = retries + 1
                    logger.info(f"Retrying job (attempt {job['retries']}): {job.get('url', 'unknown')}")
                    await redis_client.rpush("empire:queue:bulk", json.dumps(job))
                else:
                    logger.warning(f"Job permanently failed after 3 retries: {job.get('url', 'unknown')}")
                    # Save to permanent failures
                    os.makedirs(RESULTS_DIR, exist_ok=True)
                    with open(os.path.join(RESULTS_DIR, "permanent_failures.jsonl"), "a") as f:
                        f.write(json.dumps(job) + "\n")
            else:
                await asyncio.sleep(30)

        except Exception as e:
            logger.error(f"Retry error: {e}")
            await asyncio.sleep(30)


async def handle_commands(redis_client: redis.Redis):
    """Listen for queue-specific commands."""
    pubsub = redis_client.pubsub()
    await pubsub.subscribe("empire:commands")

    async for msg in pubsub.listen():
        if msg["type"] == "message":
            try:
                command = json.loads(msg["data"])
                action = command.get("action")

                if action == "queue_reset_stats":
                    await redis_client.set("empire:queue:processed", "0")
                    await redis_client.set("empire:queue:failed", "0")
                    await redis_client.set("empire:queue:total", "0")
                    logger.info("Queue stats reset")

                elif action == "queue_clear":
                    await redis_client.delete("empire:queue:bulk")
                    logger.info("Bulk queue cleared")

            except Exception as e:
                logger.error(f"Command handling error: {e}")


async def main():
    """Start the queue worker."""
    logger.info("Queue Worker starting...")

    redis_client = redis.from_url(REDIS_URL, decode_responses=True)

    # Initialize queue status if not set
    if not await redis_client.get("empire:queue:status"):
        await redis_client.set("empire:queue:status", "idle")

    os.makedirs(RESULTS_DIR, exist_ok=True)

    logger.info("Queue Worker ready.")

    await asyncio.gather(
        monitor_queue(redis_client),
        retry_failed(redis_client),
        handle_commands(redis_client),
    )


if __name__ == "__main__":
    asyncio.run(main())
