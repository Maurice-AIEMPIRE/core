#!/usr/bin/env python3
"""
BRAIN LOGGER
============
Zentrales Logging fuer das Brain System.
Schreibt alle Events als taeglich rotierende Markdown-Dateien nach ~/brain-logs/.

Nutzung:
    from brain_logger import log, log_alert, log_health, log_synapse
    log("temporal", "content_generated", {"posts": 3})
    log_alert("brainstem", "CRITICAL", {"ollama": "DOWN"})
"""

import json
import os
from datetime import datetime, timezone
from pathlib import Path

LOG_DIR = Path(os.path.expanduser("~/brain-logs"))

# ── Internes Schreiben ───────────────────────────────────────────────────────

def _today_log() -> Path:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    date_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    return LOG_DIR / f"{date_str}.md"


def _append(section: str, content: str) -> None:
    path = _today_log()
    now  = datetime.now(timezone.utc).strftime("%H:%M:%S")

    # Heading on first write of the day
    if not path.exists():
        date_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        path.write_text(f"# Brain Log — {date_str}\n\n", encoding="utf-8")

    with path.open("a", encoding="utf-8") as f:
        f.write(f"## {now} · {section}\n{content}\n\n")


# ── Public API ───────────────────────────────────────────────────────────────

def log(brain: str, event: str, data: dict | None = None) -> None:
    """Generic brain event."""
    payload = json.dumps(data, ensure_ascii=False) if data else ""
    _append(f"{brain.upper()} — {event}", f"```json\n{payload}\n```" if payload else "")


def log_health(report: str) -> None:
    """Write brainstem health report verbatim."""
    _append("BRAINSTEM — Health Report", report)


def log_briefing(briefing: str) -> None:
    """Write limbic morning briefing verbatim."""
    _append("LIMBIC — Morning Briefing", briefing)


def log_alert(from_brain: str, severity: str, systems: dict) -> None:
    """Red-flag entry for CRITICAL / HIGH alerts."""
    lines = "\n".join(
        f"- **{k}**: `{v}`" for k, v in systems.items()
    )
    _append(
        f"🚨 ALERT from {from_brain.upper()} [{severity}]",
        lines,
    )


def log_synapse(from_brain: str, to_brain: str, msg_type: str, payload: dict) -> None:
    """Log an inter-brain message."""
    body = json.dumps(payload, ensure_ascii=False, indent=2)
    _append(
        f"SYNAPSE {from_brain} → {to_brain} [{msg_type}]",
        f"```json\n{body}\n```",
    )


def log_xp(action: str, xp: int, total: int) -> None:
    """XP gain entry."""
    level = total // 100 + 1
    _append("LIMBIC — XP", f"+{xp} XP for **{action}** | Total: {total} | Level: {level}")


def log_model_fallback(preferred: str, used: str, rate: float) -> None:
    """Record when a model fallback was triggered."""
    _append(
        "⚠️  MODEL FALLBACK",
        f"Preferred `{preferred}` error rate {rate:.0%} → using `{used}`",
    )


def tail(n: int = 20) -> str:
    """Return last n lines of today's log (for status displays)."""
    path = _today_log()
    if not path.exists():
        return "(no log today yet)"
    lines = path.read_text(encoding="utf-8").splitlines()
    return "\n".join(lines[-n:])


# ── CLI ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Brain Logger CLI")
    parser.add_argument("--tail", type=int, default=30, help="Show last N lines of today's log")
    parser.add_argument("--list", action="store_true", help="List all log files")
    args = parser.parse_args()

    if args.list:
        logs = sorted(LOG_DIR.glob("*.md"), reverse=True)
        if not logs:
            print("No logs found in", LOG_DIR)
        for f in logs:
            size = f.stat().st_size
            print(f"  {f.name}  ({size:,} bytes)")
    else:
        print(f"=== Brain Log ({_today_log().name}) ===\n")
        print(tail(args.tail))
