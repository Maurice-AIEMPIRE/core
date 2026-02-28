"""
X/Twitter Analysis Engine
===========================
Main service that processes the X analysis queue.
Workflow:
  1. Pop URL from queue
  2. Scrape post content (text, media, video)
  3. Transcribe video if present
  4. Analyze with Claude
  5. Generate prompts
  6. Push results to completed queue + save to disk
"""

import asyncio
import json
import logging
import os
from datetime import datetime

import redis.asyncio as redis

from scraper import scrape_post
from transcriber import transcribe_video

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [x-analyzer] %(levelname)s: %(message)s",
)
logger = logging.getLogger("x-analyzer")

REDIS_URL = os.environ.get("REDIS_URL", "redis://redis:6379/0")
RESULTS_DIR = "/empire/results/x-analyses"
OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://ollama:11434")
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "llama3.1:8b")


async def analyze_post(redis_client: redis.Redis, job: dict) -> dict:
    """
    Full analysis pipeline for a single X post.

    Returns result dict with content, transcript, and analysis status.
    """
    url = job.get("url", "")
    job_id = job.get("id", f"job_{datetime.now().strftime('%Y%m%d_%H%M%S')}")

    logger.info(f"Analyzing: {url} (Job: {job_id})")

    result = {
        "id": job_id,
        "url": url,
        "status": "processing",
        "content": "",
        "transcript": "",
        "error": None,
        "processed_at": datetime.now().isoformat(),
    }

    try:
        # Step 1: Scrape
        logger.info(f"[{job_id}] Scraping post...")
        post = await scrape_post(url, download_video=True)

        if post.error:
            result["status"] = "scrape_failed"
            result["error"] = post.error
            logger.warning(f"[{job_id}] Scrape failed: {post.error}")
        else:
            result["content"] = post.text
            result["author"] = post.author

            # Step 2: Transcribe video if present
            if post.video_path:
                logger.info(f"[{job_id}] Transcribing video...")
                transcript = await transcribe_video(post.video_path)
                result["transcript"] = transcript

                # Clean up video file
                try:
                    os.remove(post.video_path)
                    os.rmdir(os.path.dirname(post.video_path))
                except OSError:
                    pass

            result["status"] = "analyzed"

        # Save raw result to disk
        os.makedirs(RESULTS_DIR, exist_ok=True)
        result_file = os.path.join(RESULTS_DIR, f"{job_id}_raw.json")
        with open(result_file, "w") as f:
            json.dump(result, f, indent=2, ensure_ascii=False)

        # Push to completed queue for the XAnalysis department agent to evaluate
        await redis_client.rpush("empire:x:completed", json.dumps(result))

        # Update job status
        await redis_client.hset("empire:x:jobs", job_id, json.dumps(result))

        logger.info(f"[{job_id}] Analysis complete. Status: {result['status']}")

    except Exception as e:
        result["status"] = "error"
        result["error"] = str(e)
        logger.error(f"[{job_id}] Error: {e}", exc_info=True)

    return result


async def process_analysis_queue(redis_client: redis.Redis):
    """Process the single-post analysis queue."""
    while True:
        try:
            raw = await redis_client.lpop("empire:x:analysis_queue")
            if raw:
                job = json.loads(raw)
                await analyze_post(redis_client, job)
            else:
                await asyncio.sleep(2)
        except Exception as e:
            logger.error(f"Queue processing error: {e}")
            await asyncio.sleep(5)


async def process_bulk_queue(redis_client: redis.Redis):
    """Process the 10k bulk analysis queue."""
    while True:
        try:
            # Check if queue is paused
            status = await redis_client.get("empire:queue:status")
            if status == "paused":
                await asyncio.sleep(10)
                continue

            raw = await redis_client.lpop("empire:queue:bulk")
            if raw:
                job = json.loads(raw)
                job["id"] = f"bulk_{datetime.now().strftime('%Y%m%d_%H%M%S')}"

                await analyze_post(redis_client, job)

                # Update processed counter
                processed = int(await redis_client.get("empire:queue:processed") or "0")
                await redis_client.set("empire:queue:processed", str(processed + 1))

                # Brief pause to not overwhelm
                await asyncio.sleep(1)
            else:
                await asyncio.sleep(5)

        except Exception as e:
            logger.error(f"Bulk queue error: {e}")
            # Track failures
            failed = int(await redis_client.get("empire:queue:failed") or "0")
            await redis_client.set("empire:queue:failed", str(failed + 1))
            await asyncio.sleep(5)


async def report_progress(redis_client: redis.Redis):
    """Periodically report bulk queue progress via Telegram."""
    while True:
        await asyncio.sleep(600)  # Every 10 minutes

        try:
            queue_len = await redis_client.llen("empire:queue:bulk")
            processed = await redis_client.get("empire:queue:processed") or "0"
            total = await redis_client.get("empire:queue:total") or "0"
            status = await redis_client.get("empire:queue:status") or "idle"

            if int(total) > 0 and status == "running":
                progress = round(int(processed) / int(total) * 100, 1)
                await redis_client.publish("empire:telegram:send", json.dumps({
                    "text": (
                        f"📦 Bulk Queue Update:\n"
                        f"Fortschritt: {processed}/{total} ({progress}%)\n"
                        f"Verbleibend: {queue_len}"
                    ),
                    "priority": "low",
                }))

        except Exception as e:
            logger.error(f"Progress report error: {e}")


async def main():
    """Start the X analyzer service."""
    logger.info("X Analyzer starting...")

    redis_client = redis.from_url(REDIS_URL, decode_responses=True)

    # Ensure results directory exists
    os.makedirs(RESULTS_DIR, exist_ok=True)

    logger.info("X Analyzer ready. Waiting for jobs...")

    await asyncio.gather(
        process_analysis_queue(redis_client),
        process_bulk_queue(redis_client),
        report_progress(redis_client),
    )


if __name__ == "__main__":
    asyncio.run(main())
