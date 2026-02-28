"""Cloud Sync Service - iCloud + Dropbox via rclone.

Automatically syncs all empire results to personal clouds.
Can read/write from iCloud and Dropbox.
Triggered periodically or on-demand via Telegram.
"""

import asyncio
import json
import logging
import os
import subprocess
import time

import redis.asyncio as redis
from dotenv import load_dotenv

load_dotenv()
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("cloud-sync")


class CloudSync:
    def __init__(self):
        self.redis = redis.from_url(
            os.environ.get("REDIS_URL", "redis://redis:6379"),
            decode_responses=True,
        )
        self.pubsub = self.redis.pubsub()
        self.icloud_remote = os.environ.get("RCLONE_ICLOUD_REMOTE", "icloud")
        self.dropbox_remote = os.environ.get("RCLONE_DROPBOX_REMOTE", "dropbox")
        self.sync_interval = int(os.environ.get("RCLONE_SYNC_INTERVAL", "300"))
        self.local_results = "/empire/results"

    def _run_rclone(self, args: list[str]) -> tuple[bool, str]:
        try:
            result = subprocess.run(
                ["rclone"] + args,
                capture_output=True,
                text=True,
                timeout=300,
            )
            if result.returncode == 0:
                return True, result.stdout
            return False, result.stderr
        except FileNotFoundError:
            return False, "rclone not found - install it or configure the container"
        except Exception as e:
            return False, str(e)

    def check_remotes(self) -> dict:
        """Check which rclone remotes are configured."""
        ok, output = self._run_rclone(["listremotes"])
        if not ok:
            return {"icloud": False, "dropbox": False, "error": output}

        remotes = output.strip().split("\n") if output.strip() else []
        return {
            "icloud": f"{self.icloud_remote}:" in remotes,
            "dropbox": f"{self.dropbox_remote}:" in remotes,
            "configured": remotes,
        }

    def sync_to_icloud(self) -> tuple[bool, str]:
        """Sync results to iCloud Drive."""
        return self._run_rclone([
            "sync",
            self.local_results,
            f"{self.icloud_remote}:UserAI-Empire/results",
            "--progress",
            "-v",
        ])

    def sync_to_dropbox(self) -> tuple[bool, str]:
        """Sync results to Dropbox."""
        return self._run_rclone([
            "sync",
            self.local_results,
            f"{self.dropbox_remote}:UserAI-Empire/results",
            "--progress",
            "-v",
        ])

    def read_from_cloud(self, remote: str, path: str, local_dest: str) -> tuple[bool, str]:
        """Read a file from cloud storage."""
        return self._run_rclone([
            "copy",
            f"{remote}:{path}",
            local_dest,
        ])

    async def do_sync(self):
        """Perform full sync to all configured remotes."""
        status = self.check_remotes()
        results = []

        if status.get("icloud"):
            ok, msg = self.sync_to_icloud()
            results.append(f"iCloud: {'OK' if ok else 'FAIL'}")
            if not ok:
                logger.warning(f"iCloud sync failed: {msg}")
        else:
            results.append("iCloud: Not configured")

        if status.get("dropbox"):
            ok, msg = self.sync_to_dropbox()
            results.append(f"Dropbox: {'OK' if ok else 'FAIL'}")
            if not ok:
                logger.warning(f"Dropbox sync failed: {msg}")
        else:
            results.append("Dropbox: Not configured")

        return results

    async def listen_triggers(self):
        """Listen for manual sync triggers."""
        await self.pubsub.subscribe("cloud-sync:trigger")
        async for message in self.pubsub.listen():
            if message["type"] == "message":
                try:
                    data = json.loads(message["data"])
                    if data.get("action") == "sync_now":
                        logger.info("Manual sync triggered")
                        results = await self.do_sync()
                        await self.redis.rpush(
                            "telegram:results",
                            json.dumps({
                                "task_id": "cloud-sync",
                                "department": "telegram",
                                "success": True,
                                "message": f"<b>Cloud Sync Report:</b>\n" + "\n".join(results),
                            }),
                        )
                except Exception as e:
                    logger.error(f"Sync trigger error: {e}")

    async def periodic_sync(self):
        """Run periodic sync."""
        while True:
            await asyncio.sleep(self.sync_interval)
            try:
                results = await self.do_sync()
                logger.info(f"Periodic sync: {results}")
            except Exception as e:
                logger.error(f"Periodic sync error: {e}")

    async def run(self):
        logger.info(f"Cloud Sync starting (interval: {self.sync_interval}s)")
        status = self.check_remotes()
        logger.info(f"Configured remotes: {status}")

        await asyncio.gather(
            self.listen_triggers(),
            self.periodic_sync(),
        )


async def main():
    sync = CloudSync()
    await sync.run()


if __name__ == "__main__":
    asyncio.run(main())
