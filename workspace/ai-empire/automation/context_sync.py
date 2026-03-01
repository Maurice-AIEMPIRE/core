#!/usr/bin/env python3
"""
Context Sync — Lokale stündliche Kontext-Zusammenfassung.

Liest lokale Quellen (nur Filesystem) und schreibt einen kompakten
CONTEXT_SNAPSHOT.md. Keine Cloud-Calls, keine Secrets.

Nutzung:
    python3 context_sync.py
    python3 context_sync.py --dry-run
    python3 context_sync.py --base-dir ~/.openclaw/workspace/ai-empire
"""

import argparse
import glob
import os
import re
import sys
from collections import Counter
from datetime import datetime, timedelta
from pathlib import Path

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

DEFAULT_BASE = os.path.expanduser("~/.openclaw/workspace/ai-empire")
MEMORY_DIR = "memory"
SHARED_CONTEXT_DIR = "shared-context"
SNAPSHOT_FILE = "CONTEXT_SNAPSHOT.md"
MAX_BULLETS = 5
MAX_REPETITIVE = 10
MAX_NEXT_ACTIONS = 5
MAX_FILE_SIZE_KB = 500  # Skip files larger than this


def parse_args():
    parser = argparse.ArgumentParser(description="Local context sync for AI Empire")
    parser.add_argument(
        "--base-dir",
        default=DEFAULT_BASE,
        help=f"Base directory (default: {DEFAULT_BASE})",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print snapshot to stdout instead of writing file",
    )
    return parser.parse_args()


# ---------------------------------------------------------------------------
# File reading helpers
# ---------------------------------------------------------------------------


def safe_read(path: str, max_kb: int = MAX_FILE_SIZE_KB) -> str:
    """Read file safely, skip if too large or unreadable."""
    try:
        size = os.path.getsize(path)
        if size > max_kb * 1024:
            return ""
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return f.read()
    except (OSError, PermissionError):
        return ""


def find_files(directory: str, pattern: str = "*.md") -> list:
    """Find matching files in directory, sorted by mtime descending."""
    if not os.path.isdir(directory):
        return []
    files = glob.glob(os.path.join(directory, "**", pattern), recursive=True)
    files.sort(key=lambda f: os.path.getmtime(f), reverse=True)
    return files


def date_str(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%d")


# ---------------------------------------------------------------------------
# Content extraction
# ---------------------------------------------------------------------------


def extract_bullets(text: str, max_bullets: int = MAX_BULLETS) -> list:
    """Extract bullet points or key lines from text."""
    bullets = []

    # Look for markdown bullets
    for line in text.splitlines():
        line = line.strip()
        if line.startswith(("- ", "* ", "• ")):
            clean = line.lstrip("-*• ").strip()
            if clean and len(clean) > 5:
                bullets.append(clean)

    # If no bullets found, take first non-empty lines
    if not bullets:
        for line in text.splitlines():
            line = line.strip()
            if line and not line.startswith("#") and len(line) > 10:
                bullets.append(line[:200])
            if len(bullets) >= max_bullets:
                break

    # Deduplicate while preserving order
    seen = set()
    unique = []
    for b in bullets:
        key = b.lower()[:50]
        if key not in seen:
            seen.add(key)
            unique.append(b)

    return unique[:max_bullets]


def extract_tasks(text: str) -> list:
    """Extract task-like items (TODO, FIXME, action items)."""
    tasks = []
    patterns = [
        r"(?:TODO|FIXME|HACK|ACTION|NEXT)[\s:]+(.+)",
        r"\[ \]\s+(.+)",  # Unchecked checkboxes
        r"(?:next|todo|action)[\s:]+(.+)",
    ]
    for pattern in patterns:
        for match in re.finditer(pattern, text, re.IGNORECASE):
            task = match.group(1).strip()
            if task and len(task) > 5:
                tasks.append(task[:200])
    return tasks


def find_repetitive_patterns(all_text: str) -> list:
    """Find frequently mentioned topics/tasks that could be automated."""
    # Extract meaningful words/phrases
    words = re.findall(r"\b[a-zA-Z][a-zA-Z_-]{3,}\b", all_text.lower())
    # Filter common stop words
    stop_words = {
        "this", "that", "with", "from", "have", "been", "will", "were",
        "they", "them", "their", "what", "when", "where", "which", "while",
        "could", "would", "should", "about", "after", "before", "between",
        "each", "every", "other", "some", "such", "than", "then", "these",
        "those", "into", "over", "under", "again", "once", "here", "there",
        "just", "also", "very", "much", "more", "most", "only", "same",
        "still", "well", "back", "even", "make", "like", "time", "file",
        "line", "code", "data", "note", "true", "false", "none",
    }
    filtered = [w for w in words if w not in stop_words and len(w) > 3]
    counter = Counter(filtered)
    # Return most common as candidates for automation
    return [
        f"{word} (mentioned {count}x)"
        for word, count in counter.most_common(MAX_REPETITIVE)
        if count >= 2
    ]


# ---------------------------------------------------------------------------
# Snapshot generation
# ---------------------------------------------------------------------------


def redact_secrets(text: str) -> str:
    """Remove anything that looks like a secret/key/token."""
    patterns = [
        r"(?:api[_-]?key|token|secret|password|credential|auth)[\s=:]+\S+",
        r"sk-[a-zA-Z0-9]{20,}",
        r"ghp_[a-zA-Z0-9]{36}",
        r"xoxb-[a-zA-Z0-9-]+",
        r"AIza[a-zA-Z0-9_-]{35}",
    ]
    for pattern in patterns:
        text = re.sub(pattern, "<REDACTED>", text, flags=re.IGNORECASE)
    return text


def generate_snapshot(base_dir: str) -> str:
    now = datetime.now()
    yesterday = now - timedelta(days=1)

    memory_dir = os.path.join(base_dir, MEMORY_DIR)
    shared_dir = os.path.join(base_dir, SHARED_CONTEXT_DIR)

    # Collect content from today and yesterday
    today_text = ""
    yesterday_text = ""
    all_text = ""

    # Read memory files
    for f in find_files(memory_dir):
        content = safe_read(f)
        if not content:
            continue
        mtime = datetime.fromtimestamp(os.path.getmtime(f))
        if date_str(mtime) == date_str(now):
            today_text += content + "\n"
        elif date_str(mtime) == date_str(yesterday):
            yesterday_text += content + "\n"
        all_text += content + "\n"

    # Read shared context files (except old snapshots)
    for f in find_files(shared_dir):
        if SNAPSHOT_FILE in f:
            continue
        content = safe_read(f)
        if not content:
            continue
        mtime = datetime.fromtimestamp(os.path.getmtime(f))
        if date_str(mtime) == date_str(now):
            today_text += content + "\n"
        elif date_str(mtime) == date_str(yesterday):
            yesterday_text += content + "\n"
        all_text += content + "\n"

    # Extract information
    today_bullets = extract_bullets(today_text)
    yesterday_bullets = extract_bullets(yesterday_text)
    all_tasks = extract_tasks(all_text)
    repetitive = find_repetitive_patterns(all_text)

    # Build snapshot
    lines = [
        "# Context Snapshot",
        "",
        f"**Generated:** {now.strftime('%Y-%m-%d %H:%M:%S')}",
        f"**Source:** Local filesystem only (no cloud)",
        "",
        "---",
        "",
        "## Yesterday",
        "",
    ]

    if yesterday_bullets:
        for b in yesterday_bullets:
            lines.append(f"- {b}")
    else:
        lines.append("- No data from yesterday available")

    lines.extend(["", "## Today", ""])

    if today_bullets:
        for b in today_bullets:
            lines.append(f"- {b}")
    else:
        lines.append("- No data from today yet")

    lines.extend(["", "## Repetitive Tasks Candidates", ""])

    if repetitive:
        for i, r in enumerate(repetitive, 1):
            lines.append(f"{i}. {r}")
    else:
        lines.append("- Not enough data to detect patterns yet")

    lines.extend(["", "## Next Actions", ""])

    if all_tasks:
        for i, t in enumerate(all_tasks[:MAX_NEXT_ACTIONS], 1):
            lines.append(f"{i}. {t}")
    else:
        lines.append("1. Run context_sync.py after accumulating memory files")
        lines.append("2. Check CONTEXT_SNAPSHOT.md for updates")
        lines.append("3. Add memory entries to memory/ directory")

    lines.extend(["", "---", "", "*Local-only. No secrets. No cloud uploads.*", ""])

    snapshot = "\n".join(lines)
    return redact_secrets(snapshot)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main():
    args = parse_args()
    base_dir = os.path.expanduser(args.base_dir)

    if not os.path.isdir(base_dir):
        print(f"Warning: Base directory does not exist: {base_dir}", file=sys.stderr)
        print(f"Creating directory structure...", file=sys.stderr)
        os.makedirs(os.path.join(base_dir, MEMORY_DIR), exist_ok=True)
        os.makedirs(os.path.join(base_dir, SHARED_CONTEXT_DIR), exist_ok=True)

    snapshot = generate_snapshot(base_dir)

    if args.dry_run:
        print(snapshot)
    else:
        out_dir = os.path.join(base_dir, SHARED_CONTEXT_DIR)
        os.makedirs(out_dir, exist_ok=True)
        out_path = os.path.join(out_dir, SNAPSHOT_FILE)
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(snapshot)
        print(f"Snapshot written to: {out_path}")


if __name__ == "__main__":
    main()
