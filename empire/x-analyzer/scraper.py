"""
X/Twitter Post Scraper
=======================
Extracts content from X/Twitter posts without API.
Uses yt-dlp for video content and basic web scraping for text.
"""

import json
import logging
import os
import re
import subprocess
import tempfile
from dataclasses import dataclass, field

logger = logging.getLogger("x-scraper")


@dataclass
class XPostContent:
    """Represents extracted content from an X post."""
    url: str
    text: str = ""
    author: str = ""
    media_urls: list[str] = field(default_factory=list)
    video_path: str | None = None
    is_thread: bool = False
    thread_posts: list[dict] = field(default_factory=list)
    error: str | None = None


def extract_post_id(url: str) -> str | None:
    """Extract the post/status ID from an X/Twitter URL."""
    match = re.search(r"/status/(\d+)", url)
    return match.group(1) if match else None


async def scrape_post(url: str, download_video: bool = True) -> XPostContent:
    """
    Scrape content from an X/Twitter post.

    Uses yt-dlp as primary method (handles videos, embedded content).
    Falls back to basic scraping for text-only posts.
    """
    result = XPostContent(url=url)

    # Normalize URL
    url = url.replace("twitter.com", "x.com")

    try:
        # Method 1: Use yt-dlp to extract info (works for video posts)
        info = await _extract_with_ytdlp(url, download_video)
        if info:
            result.text = info.get("description", "")
            result.author = info.get("uploader", "") or info.get("channel", "")
            result.video_path = info.get("video_path")

            # Extract any image URLs from description/thumbnails
            if info.get("thumbnail"):
                result.media_urls.append(info["thumbnail"])

            return result

        # Method 2: Try using syndication/embed endpoint (public, no auth)
        post_id = extract_post_id(url)
        if post_id:
            embed_data = await _fetch_embed_data(post_id)
            if embed_data:
                result.text = embed_data.get("text", "")
                result.author = embed_data.get("author", "")
                return result

        result.error = "Could not extract post content. Post may be private or deleted."

    except Exception as e:
        logger.error(f"Scraping error for {url}: {e}")
        result.error = str(e)

    return result


async def _extract_with_ytdlp(url: str, download_video: bool) -> dict | None:
    """Use yt-dlp to extract post information and optionally download video."""
    try:
        cmd = ["yt-dlp", "--dump-json", "--no-download", url]
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=30)

        if proc.returncode != 0:
            logger.debug(f"yt-dlp info extraction failed: {proc.stderr[:200]}")
            return None

        info = json.loads(proc.stdout)
        result = {
            "description": info.get("description", ""),
            "uploader": info.get("uploader", ""),
            "channel": info.get("channel", ""),
            "thumbnail": info.get("thumbnail"),
            "duration": info.get("duration"),
        }

        # Download video if requested and available
        if download_video and info.get("duration"):
            video_dir = tempfile.mkdtemp(prefix="empire_video_")
            video_path = os.path.join(video_dir, "video.mp4")

            dl_cmd = [
                "yt-dlp",
                "-f", "best[height<=720]",
                "-o", video_path,
                url,
            ]
            dl_proc = subprocess.run(dl_cmd, capture_output=True, text=True, timeout=120)

            if dl_proc.returncode == 0 and os.path.exists(video_path):
                result["video_path"] = video_path
                logger.info(f"Video downloaded: {video_path}")

        return result

    except subprocess.TimeoutExpired:
        logger.warning(f"yt-dlp timeout for {url}")
        return None
    except Exception as e:
        logger.debug(f"yt-dlp error: {e}")
        return None


async def _fetch_embed_data(post_id: str) -> dict | None:
    """Fetch post data via the public syndication endpoint."""
    import aiohttp

    embed_url = f"https://cdn.syndication.twimg.com/tweet-result?id={post_id}&token=0"

    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(embed_url, timeout=aiohttp.ClientTimeout(total=15)) as resp:
                if resp.status == 200:
                    data = await resp.json()
                    return {
                        "text": data.get("text", ""),
                        "author": data.get("user", {}).get("name", ""),
                    }
    except Exception as e:
        logger.debug(f"Embed fetch failed: {e}")

    return None
