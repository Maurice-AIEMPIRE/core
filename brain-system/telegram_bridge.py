#!/usr/bin/env python3
"""
TELEGRAM BRIDGE — Brain Command Interface
==========================================
Telegram → Brain System bidirectional bridge.

- Polls Telegram for new messages (getUpdates)
- Parses /commands and executes them against the brain system
- Sends results + errors back to Telegram immediately
- Runs as a daemon or single-shot via cron

Bot Commands:
  /health       → brainstem health check
  /morning      → limbic morning briefing
  /cycle        → full daily brain cycle
  /xp 50 [note] → add XP
  /streak name  → update streak
  /status       → pending synapses + model error rates
  /cleanup      → vacuum old synapses
  /log [n]      → last n lines of today's brain log
  /amygdala     → run risk scan now

Setup:
  export TELEGRAM_BOT_TOKEN="your-bot-token-from-botfather"
  export TELEGRAM_CHAT_ID="your-chat-id"   # use /start to discover it
  python telegram_bridge.py --daemon       # run continuously
  python telegram_bridge.py --once         # process pending commands once
"""

import json
import os
import subprocess
import sys
import time
import urllib.request
import urllib.error
from datetime import datetime, timezone
from pathlib import Path

# ── Config ────────────────────────────────────────────────────────────────────

BOT_TOKEN   = os.getenv("TELEGRAM_BOT_TOKEN", "")
CHAT_ID     = os.getenv("TELEGRAM_CHAT_ID", "")   # optional: restrict to one chat
POLL_SLEEP  = int(os.getenv("TELEGRAM_POLL_SLEEP", "10"))  # seconds between polls

BRAIN_SYSTEM_DIR = Path(__file__).parent
STATE_FILE = Path(os.path.expanduser("~/.openclaw/brain-system/telegram_offset.json"))
TELEGRAM_API = f"https://api.telegram.org/bot{BOT_TOKEN}"


# ── Telegram HTTP helpers ─────────────────────────────────────────────────────

def _tg_request(method: str, payload: dict | None = None) -> dict:
    url  = f"{TELEGRAM_API}/{method}"
    data = json.dumps(payload or {}, ensure_ascii=False).encode("utf-8")
    req  = urllib.request.Request(
        url, data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        result = json.loads(resp.read().decode())
    if not result.get("ok"):
        raise RuntimeError(f"Telegram [{method}]: {result.get('description')}")
    return result["result"]


def send_message(chat_id: int | str, text: str, reply_to: int | None = None) -> None:
    """Send a message, auto-split if > 4096 chars."""
    MAX = 4000
    chunks = [text[i:i+MAX] for i in range(0, len(text), MAX)]
    for i, chunk in enumerate(chunks):
        payload: dict = {
            "chat_id": chat_id,
            "text": chunk,
            "parse_mode": "Markdown",
        }
        if i == 0 and reply_to:
            payload["reply_to_message_id"] = reply_to
        try:
            _tg_request("sendMessage", payload)
        except Exception:
            # Fallback: retry without markdown (special chars may fail)
            payload.pop("parse_mode", None)
            _tg_request("sendMessage", payload)


def get_updates(offset: int = 0) -> list[dict]:
    return _tg_request("getUpdates", {
        "offset": offset,
        "limit": 100,
        "timeout": 0,
        "allowed_updates": ["message"],
    })


# ── Offset persistence ────────────────────────────────────────────────────────

def load_offset() -> int:
    try:
        return json.loads(STATE_FILE.read_text())["offset"]
    except Exception:
        return 0


def save_offset(offset: int) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps({"offset": offset}))


# ── Brain command execution ───────────────────────────────────────────────────

def _run_brain(args: list[str]) -> str:
    """Call orchestrator.py with given args, return stdout."""
    script = BRAIN_SYSTEM_DIR / "orchestrator.py"
    if not script.exists():
        return "orchestrator.py not found — check BRAIN_SYSTEM_DIR."
    try:
        result = subprocess.run(
            [sys.executable, str(script)] + args,
            capture_output=True, text=True, timeout=120,
            cwd=str(BRAIN_SYSTEM_DIR),
        )
        output = (result.stdout or "").strip()
        err    = (result.stderr or "").strip()
        if result.returncode != 0 and err:
            return f"⚠️ Error (rc={result.returncode}):\n{err}\n\n{output}"
        return output or "(no output)"
    except subprocess.TimeoutExpired:
        return "⏱ Timeout: brain command took > 120 s"
    except Exception as exc:
        return f"❌ Exception: {exc}"


def handle_command(text: str, chat_id: int, message_id: int) -> str:
    """Parse a /command and execute it. Returns response string."""
    parts = text.strip().split()
    cmd   = parts[0].lower().lstrip("/").split("@")[0]  # strip @botname suffix

    if cmd == "health":
        return _run_brain(["--health"])

    elif cmd == "morning":
        return _run_brain(["--morning"])

    elif cmd == "cycle":
        return _run_brain(["--cycle"])

    elif cmd == "xp":
        if len(parts) < 2:
            return "Usage: /xp <amount> [action description]"
        try:
            amount = int(parts[1])
        except ValueError:
            return "Amount must be a number, e.g. /xp 50 wrote LinkedIn post"
        action = " ".join(parts[2:]) if len(parts) > 2 else "telegram"
        return _run_brain(["--xp", str(amount), "--action", action])

    elif cmd == "streak":
        if len(parts) < 2:
            return "Usage: /streak <name>"
        return _run_brain(["--streak", parts[1]])

    elif cmd == "status":
        return _run_brain(["--status"])

    elif cmd == "cleanup":
        script = BRAIN_SYSTEM_DIR / "orchestrator_updates.py"
        if script.exists():
            try:
                exec_globals: dict = {}
                exec(script.read_text(), exec_globals)
                n = exec_globals["cleanup_old_synapses"]()
                return f"✅ Deleted {n} old synapses. DB vacuumed."
            except Exception as exc:
                return f"❌ cleanup failed: {exc}"
        return "orchestrator_updates.py not found."

    elif cmd == "log":
        n = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 30
        try:
            from brain_logger import tail  # type: ignore
            return f"```\n{tail(n)}\n```"
        except ImportError:
            return "brain_logger.py not in path."

    elif cmd == "amygdala":
        try:
            amygdala_script = BRAIN_SYSTEM_DIR / "amygdala.py"
            result = subprocess.run(
                [sys.executable, str(amygdala_script), "--run"],
                capture_output=True, text=True, timeout=60,
                cwd=str(BRAIN_SYSTEM_DIR),
            )
            return (result.stdout or result.stderr or "(no output)").strip()
        except Exception as exc:
            return f"❌ amygdala error: {exc}"

    elif cmd == "models":
        # Show model registry status
        try:
            result = subprocess.run(
                [sys.executable, str(BRAIN_SYSTEM_DIR / "model_registry.py"), "--brains"],
                capture_output=True, text=True, timeout=30,
                cwd=str(BRAIN_SYSTEM_DIR),
            )
            return f"```\n{(result.stdout or result.stderr).strip()[:3000]}\n```"
        except Exception as exc:
            return f"❌ model registry error: {exc}"

    elif cmd == "pullmodels":
        # Pull best models for a role: /pullmodels code 14
        role      = parts[1] if len(parts) > 1 else "code"
        max_p     = float(parts[2]) if len(parts) > 2 else 14.0
        try:
            result = subprocess.run(
                [sys.executable, str(BRAIN_SYSTEM_DIR / "model_registry.py"),
                 "--pull", role, "--max-params", str(max_p)],
                capture_output=True, text=True, timeout=300,
                cwd=str(BRAIN_SYSTEM_DIR),
            )
            return (result.stdout or result.stderr or "Pull started.").strip()[:2000]
        except Exception as exc:
            return f"❌ pull error: {exc}"

    elif cmd in ("start", "help"):
        return (
            "🧠 *Brain System Commands*\n\n"
            "/health — System health check\n"
            "/morning — Morning briefing + XP\n"
            "/cycle — Full daily brain cycle\n"
            "/xp 50 [note] — Add XP\n"
            "/streak name — Update streak\n"
            "/status — Synapse queue + model rates\n"
            "/amygdala — Risk scan now\n"
            "/cleanup — Vacuum old synapses\n"
            "/log [n] — Last n lines of today's log\n"
            "/models — Brain → optimal model mapping\n"
            "/pullmodels [role] [maxB] — Pull models\n\n"
            "📝 *Freie Notizen*: Einfach schreiben — Fehler werden automatisch erkannt und geloest."
        )

    else:
        return f"Unknown command: /{cmd}\nTry /help"


# ── Main polling loop ─────────────────────────────────────────────────────────

def process_once() -> int:
    """Fetch pending updates, process commands, return count processed."""
    offset = load_offset()
    try:
        updates = get_updates(offset)
    except Exception as exc:
        print(f"[{_now()}] getUpdates failed: {exc}", file=sys.stderr)
        return 0

    processed = 0
    for update in updates:
        update_id = update["update_id"]
        offset    = update_id + 1

        msg = update.get("message")
        if not msg:
            continue

        chat_id    = msg["chat"]["id"]
        message_id = msg["message_id"]
        text       = msg.get("text", "").strip()

        # Restrict to specific chat if configured
        if CHAT_ID and str(chat_id) != str(CHAT_ID):
            continue

        print(f"[{_now()}] Message from {chat_id}: {text[:60]!r}")

        if not text.startswith("/"):
            # Free-text note → error handler
            try:
                sys.path.insert(0, str(BRAIN_SYSTEM_DIR))
                from error_handler import handle_note  # type: ignore
                response = handle_note(text)
            except Exception as exc:
                response = f"❌ Fehler-Analyse fehlgeschlagen: {exc}"
            try:
                send_message(chat_id, response, reply_to=message_id)
            except Exception as exc:
                print(f"[{_now()}] send_message failed: {exc}", file=sys.stderr)
            save_offset(offset)
            processed += 1
            continue

        try:
            response = handle_command(text, chat_id, message_id)
        except Exception as exc:
            response = f"❌ Internal error: {exc}"

        try:
            send_message(chat_id, response, reply_to=message_id)
        except Exception as exc:
            print(f"[{_now()}] send_message failed: {exc}", file=sys.stderr)

        processed += 1

    save_offset(offset)
    return processed


def run_daemon() -> None:
    """Poll continuously."""
    print(f"[{_now()}] Telegram bridge started (polling every {POLL_SLEEP}s)")
    if not BOT_TOKEN:
        print("ERROR: TELEGRAM_BOT_TOKEN not set", file=sys.stderr)
        sys.exit(1)
    while True:
        try:
            n = process_once()
            if n:
                print(f"[{_now()}] Processed {n} command(s)")
        except KeyboardInterrupt:
            print("\nStopped.")
            break
        except Exception as exc:
            print(f"[{_now()}] Loop error: {exc}", file=sys.stderr)
        time.sleep(POLL_SLEEP)


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%H:%M:%S")


# ── CLI ───────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Telegram ↔ Brain Bridge")
    parser.add_argument("--daemon", action="store_true", help="Run polling loop")
    parser.add_argument("--once",   action="store_true", help="Process pending once and exit")
    parser.add_argument("--test",   action="store_true", help="Send test message to TELEGRAM_CHAT_ID")
    args = parser.parse_args()

    if not BOT_TOKEN:
        print("Set TELEGRAM_BOT_TOKEN first.")
        sys.exit(1)

    if args.test:
        if not CHAT_ID:
            print("Set TELEGRAM_CHAT_ID for --test")
            sys.exit(1)
        send_message(CHAT_ID, "🧠 Brain System connected via Telegram!")
        print("Test message sent.")

    elif args.once:
        n = process_once()
        print(f"Processed {n} command(s).")

    elif args.daemon:
        run_daemon()

    else:
        parser.print_help()
