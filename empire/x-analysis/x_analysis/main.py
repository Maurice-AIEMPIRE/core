"""X/Twitter Analysis Engine + Prompt Factory.

Workflow:
1. Fetch X post/video content
2. Transcribe/analyze
3. Build concrete prompts from content
4. Check: fits empire goals, budget, ethics?
5. If yes -> execute immediately
6. If no -> reject with explanation
7. Always report: what was done, what wasn't, why, links, file paths
"""

import asyncio
import json
import logging
import os
import re
import subprocess
import time
from pathlib import Path

import anthropic
import httpx
import redis.asyncio as redis
from dotenv import load_dotenv

load_dotenv()
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("x-analysis")


class XAnalysisEngine:
    def __init__(self):
        self.redis = redis.from_url(
            os.environ.get("REDIS_URL", "redis://redis:6379"),
            decode_responses=True,
        )
        api_key = os.environ.get("CLAUDE_API_KEY", "")
        self.claude = anthropic.Anthropic(api_key=api_key) if api_key else None
        self.x_bearer = os.environ.get("X_BEARER_TOKEN", "")
        self.results_dir = Path("/empire/results/x-analysis")
        self.results_dir.mkdir(parents=True, exist_ok=True)

    def extract_tweet_id(self, url: str) -> str | None:
        match = re.search(r"(?:twitter\.com|x\.com)/\w+/status/(\d+)", url)
        return match.group(1) if match else None

    async def fetch_tweet(self, tweet_id: str) -> dict | None:
        if not self.x_bearer:
            return None

        url = f"https://api.x.com/2/tweets/{tweet_id}"
        params = {
            "tweet.fields": "text,author_id,created_at,public_metrics,entities,attachments",
            "expansions": "author_id,attachments.media_keys",
            "media.fields": "type,url,preview_image_url,variants",
            "user.fields": "name,username,description",
        }

        async with httpx.AsyncClient() as client:
            try:
                resp = await client.get(
                    url,
                    headers={"Authorization": f"Bearer {self.x_bearer}"},
                    params=params,
                )
                if resp.status_code == 200:
                    return resp.json()
                logger.warning(f"X API returned {resp.status_code}: {resp.text}")
            except Exception as e:
                logger.error(f"X API fetch error: {e}")
        return None

    def download_video(self, url: str, output_path: str) -> str | None:
        """Download video from X post using yt-dlp."""
        try:
            result = subprocess.run(
                ["yt-dlp", "-x", "--audio-format", "mp3", "-o", output_path, url],
                capture_output=True,
                text=True,
                timeout=120,
            )
            if result.returncode == 0:
                return output_path
            logger.warning(f"yt-dlp failed: {result.stderr}")
        except Exception as e:
            logger.error(f"Video download error: {e}")
        return None

    async def analyze_content(self, content: str, source_url: str) -> dict:
        """Use Claude to analyze X content and build prompts."""
        if not self.claude:
            return {
                "analysis": "Claude API nicht verfuegbar",
                "prompts": [],
                "should_execute": False,
                "reason": "API Key fehlt",
            }

        try:
            response = self.claude.messages.create(
                model="claude-sonnet-4-20250514",
                max_tokens=3000,
                system=(
                    "Du bist die X-Analysis Engine des UserAI Empire. "
                    "Analysiere den folgenden X/Twitter Content und erstelle daraus "
                    "konkrete, umsetzbare Prompts fuer unser AI-System.\n\n"
                    "Pruefe jeden Prompt gegen diese Kriterien:\n"
                    "- Passt zum Empire (AI-Unternehmen, Automatisierung, Wachstum)?\n"
                    "- Technisch umsetzbar mit unseren Ressourcen?\n"
                    "- Ethisch vertretbar?\n"
                    "- Positiver ROI erwartbar?\n\n"
                    "Antworte IMMER als JSON mit diesem Schema:\n"
                    "{\n"
                    '  "summary": "Kurze Zusammenfassung des Posts",\n'
                    '  "key_insights": ["Insight 1", "Insight 2"],\n'
                    '  "prompts": [\n'
                    "    {\n"
                    '      "title": "Prompt-Titel",\n'
                    '      "prompt": "Der konkrete Prompt",\n'
                    '      "department": "target department",\n'
                    '      "should_execute": true/false,\n'
                    '      "reason": "Warum ausfuehren/ablehnen"\n'
                    "    }\n"
                    "  ],\n"
                    '  "overall_value": 1-10,\n'
                    '  "recommendation": "Klare Empfehlung"\n'
                    "}"
                ),
                messages=[
                    {
                        "role": "user",
                        "content": f"Analysiere diesen X-Post/Content:\n\nQuelle: {source_url}\n\n{content}",
                    }
                ],
            )

            text = response.content[0].text
            # Try to parse JSON from response
            json_match = re.search(r"\{[\s\S]*\}", text)
            if json_match:
                return json.loads(json_match.group())
            return {"analysis": text, "prompts": [], "should_execute": False, "reason": "Parsing failed"}
        except Exception as e:
            return {"analysis": f"Error: {e}", "prompts": [], "should_execute": False, "reason": str(e)}

    async def process_job(self, job: dict):
        job_id = job["job_id"]
        url_or_text = job["url_or_text"]
        auto_execute = job.get("auto_execute", False)

        logger.info(f"Processing X analysis job: {job_id[:8]}")

        # Step 1: Determine if URL or text
        tweet_id = self.extract_tweet_id(url_or_text)
        content = url_or_text
        source_url = url_or_text

        # Step 2: Fetch tweet data if URL
        if tweet_id:
            tweet_data = await self.fetch_tweet(tweet_id)
            if tweet_data and "data" in tweet_data:
                content = tweet_data["data"].get("text", url_or_text)
                # Check for media
                includes = tweet_data.get("includes", {})
                if includes.get("media"):
                    for media in includes["media"]:
                        content += f"\n[Media: {media.get('type', 'unknown')}]"

        # Step 3: Analyze with Claude
        analysis = await self.analyze_content(content, source_url)

        # Step 4: Save report
        report_path = self.results_dir / f"{job_id[:8]}_report.json"
        report_path.write_text(json.dumps(analysis, indent=2, ensure_ascii=False))

        # Step 5: Build readable report
        md_report = f"# X-Analyse Report\n\n"
        md_report += f"**Quelle:** {source_url}\n"
        md_report += f"**Datum:** {time.strftime('%Y-%m-%d %H:%M')}\n\n"
        md_report += f"## Zusammenfassung\n{analysis.get('summary', 'N/A')}\n\n"

        insights = analysis.get("key_insights", [])
        if insights:
            md_report += "## Key Insights\n"
            for i in insights:
                md_report += f"- {i}\n"
            md_report += "\n"

        prompts = analysis.get("prompts", [])
        executed = []
        rejected = []

        md_report += "## Generierte Prompts\n\n"
        for p in prompts:
            status = "AUSFUEHREN" if p.get("should_execute") else "ABGELEHNT"
            md_report += f"### {p.get('title', 'Untitled')} [{status}]\n"
            md_report += f"**Prompt:** {p.get('prompt', 'N/A')}\n"
            md_report += f"**Abteilung:** {p.get('department', 'N/A')}\n"
            md_report += f"**Grund:** {p.get('reason', 'N/A')}\n\n"

            if p.get("should_execute") and auto_execute:
                # Route to orchestrator
                await self.redis.rpush(
                    "orchestrator:tasks",
                    json.dumps({
                        "task_id": f"{job_id}-{len(executed)}",
                        "department": p.get("department", "ceo"),
                        "description": p.get("prompt", ""),
                        "priority": "high",
                        "source": f"x-analysis:{source_url}",
                    }),
                )
                executed.append(p.get("title", ""))
            elif p.get("should_execute"):
                executed.append(p.get("title", ""))
            else:
                rejected.append(p.get("title", ""))

        value = analysis.get("overall_value", "N/A")
        md_report += f"\n## Bewertung: {value}/10\n"
        md_report += f"**Empfehlung:** {analysis.get('recommendation', 'N/A')}\n"

        md_path = self.results_dir / f"{job_id[:8]}_report.md"
        md_path.write_text(md_report)

        # Step 6: Report back to Telegram
        tg_message = (
            f"<b>X-Analyse abgeschlossen</b>\n"
            f"Quelle: {source_url}\n"
            f"Wert: {value}/10\n\n"
            f"<b>Zusammenfassung:</b> {analysis.get('summary', 'N/A')[:300]}\n\n"
            f"<b>Prompts erstellt:</b> {len(prompts)}\n"
            f"Ausfuehren: {len(executed)} ({', '.join(executed[:3])})\n"
            f"Abgelehnt: {len(rejected)} ({', '.join(rejected[:3])})\n\n"
            f"Report: {md_path}"
        )

        await self.redis.rpush(
            "telegram:results",
            json.dumps({
                "task_id": job_id,
                "department": "x-analysis",
                "success": True,
                "message": tg_message,
                "file_path": str(md_path),
            }),
        )

    async def run(self):
        logger.info("X Analysis Engine starting...")
        while True:
            try:
                result = await self.redis.blpop("x-analysis:queue", timeout=5)
                if result:
                    _, raw = result
                    job = json.loads(raw)
                    await self.process_job(job)
            except Exception as e:
                logger.error(f"X Analysis error: {e}")
                await asyncio.sleep(5)


async def main():
    engine = XAnalysisEngine()
    await engine.run()


if __name__ == "__main__":
    asyncio.run(main())
