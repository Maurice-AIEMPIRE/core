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
import re
import sqlite3
import subprocess
import sys
import time
import urllib.request
import urllib.error
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

# ── Config ────────────────────────────────────────────────────────────────────

BOT_TOKEN      = os.getenv("TELEGRAM_BOT_TOKEN", "")
CHAT_ID        = os.getenv("TELEGRAM_CHAT_ID", "")     # restrict to one chat
ADMIN_IDS_RAW  = os.getenv("TELEGRAM_ADMIN_IDS", "")   # comma-separated user IDs
POLL_SLEEP     = int(os.getenv("TELEGRAM_POLL_SLEEP", "10"))
RATE_LIMIT_RPM = int(os.getenv("TELEGRAM_RATE_LIMIT", "20"))  # max msgs/min per user

BRAIN_SYSTEM_DIR = Path(__file__).parent
STATE_FILE   = Path(os.path.expanduser("~/.openclaw/brain-system/telegram_offset.json"))
SECURITY_DB  = Path(os.path.expanduser("~/.openclaw/brain-system/security_events.db"))
TELEGRAM_API = f"https://api.telegram.org/bot{BOT_TOKEN}"

# Parsed admin whitelist (empty = alle erlaubt, wenn CHAT_ID gesetzt)
ADMIN_IDS: set[str] = {x.strip() for x in ADMIN_IDS_RAW.split(",") if x.strip()}

# In-memory rate limiter: user_id -> list[timestamp]
_rate_buckets: dict[str, list[float]] = defaultdict(list)


# ── Prompt-Injection-Guard ────────────────────────────────────────────────────

# Muster die auf Injection-Versuche hinweisen
_INJECTION_PATTERNS = [
    # Role/persona override
    r"\[SYSTEM[_\s]?OVERRIDE",
    r"\[GODMODE",
    r"\[AUTONOMY",
    r"ignore\s+(all\s+)?(previous|prior|above)\s+instructions",
    r"forget\s+(all\s+)?(previous|prior)\s+instructions",
    r"you\s+are\s+now\s+(a\s+)?(?:DAN|JAILBREAK|godmode)",
    r"new\s+persona",
    r"act\s+as\s+(?:an?\s+)?(?:evil|unrestricted|uncensored)",
    # Fake system tags
    r"<\s*/?system\s*>",
    r"\[\[SYSTEM\]\]",
    r"###\s*SYSTEM\s*:",
    r"CRITICAL\s+DIRECTIVE\s*:",
    r"CORE\s+PROTOCOL",
    # Privilege escalation keywords
    r"sudo\s+mode",
    r"developer\s+mode\s+enabled",
    r"jailbreak",
    r"DAN\s+mode",
    # Data exfiltration attempts
    r"send\s+(all\s+)?(?:env|environment|credentials|tokens|secrets|api.?keys)",
    r"print\s+(all\s+)?(?:env|os\.environ)",
    r"exfiltrate",
    # Unauthorized deployment
    r"docker\s+(run|exec|compose)\s.*--rm",
    r"rm\s+-rf\s+/",
    r"curl\s+.*\|\s*(?:bash|sh|python)",
    r"wget\s+.*\|\s*(?:bash|sh)",
    # Fake authority
    r"anthropic\s+admin",
    r"system\s+administrator\s+override",
    r"master.control.program",
]

_INJECTION_RE = [re.compile(p, re.IGNORECASE) for p in _INJECTION_PATTERNS]


def detect_injection(text: str) -> list[str]:
    """
    Prueft text auf Prompt-Injection-Muster.
    Gibt Liste der gefundenen Muster zurueck (leer = sauber).
    """
    hits = []
    for pattern in _INJECTION_RE:
        m = pattern.search(text)
        if m:
            hits.append(m.group(0)[:60])
    return hits


# ── Rate Limiter ──────────────────────────────────────────────────────────────

def _check_rate_limit(user_id: str) -> bool:
    """True wenn User unter dem Limit ist, False wenn gedrosselt."""
    now    = time.time()
    window = 60.0
    bucket = _rate_buckets[user_id]
    # Entferne alte Eintraege
    _rate_buckets[user_id] = [t for t in bucket if now - t < window]
    if len(_rate_buckets[user_id]) >= RATE_LIMIT_RPM:
        return False
    _rate_buckets[user_id].append(now)
    return True


# ── Sender-Authentifizierung ──────────────────────────────────────────────────

def _is_authorized(user_id: str, chat_id: str) -> bool:
    """
    True wenn Absender autorisiert ist.
    Logik: CHAT_ID-Restriction greift zuerst, dann ADMIN_IDS.
    Wenn beides leer: alle erlaubt (offener Bot).
    """
    if CHAT_ID and str(chat_id) != str(CHAT_ID):
        return False
    if ADMIN_IDS and str(user_id) not in ADMIN_IDS:
        return False
    return True


# ── Security Event Log ────────────────────────────────────────────────────────

def _log_security_event(
    event_type: str,
    user_id: str,
    chat_id: str,
    text: str,
    details: str = "",
) -> None:
    try:
        SECURITY_DB.parent.mkdir(parents=True, exist_ok=True)
        conn = sqlite3.connect(str(SECURITY_DB))
        conn.execute('''CREATE TABLE IF NOT EXISTS events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT, event_type TEXT,
            user_id TEXT, chat_id TEXT,
            text TEXT, details TEXT
        )''')
        conn.execute(
            "INSERT INTO events (timestamp,event_type,user_id,chat_id,text,details) VALUES (?,?,?,?,?,?)",
            (datetime.now(timezone.utc).isoformat(), event_type,
             str(user_id), str(chat_id), text[:500], details[:500]),
        )
        conn.commit()
        conn.close()
    except Exception:
        pass


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

    elif cmd == "seclog":
        # Last N security events
        n = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 10
        try:
            conn = sqlite3.connect(str(SECURITY_DB))
            rows = conn.execute(
                "SELECT timestamp,event_type,user_id,chat_id,details FROM events ORDER BY id DESC LIMIT ?", (n,)
            ).fetchall()
            conn.close()
            if not rows:
                return "Keine Security-Events."
            lines = [f"🛡️ *Letzte {n} Security-Events:*\n"]
            for ts, etype, uid, cid, det in rows:
                lines.append(f"`{ts[11:19]}` `{etype}` user={uid} — {det[:60]}")
            return "\n".join(lines)
        except Exception as exc:
            return f"❌ seclog: {exc}"

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
            "/pullmodels [role] [maxB] — Pull models\n"
            "/seclog [n] — Letzte Security-Events\n\n"
            "📝 *Freie Notizen*: Einfach schreiben — Fehler werden vollautomatisch erkannt und geloest.\n"
            "🛡️ Injection-Schutz, Rate-Limit & Auth aktiv."
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

        user_id  = str(msg.get("from", {}).get("id", "unknown"))
        username = msg.get("from", {}).get("username", "?")

        # ── 1. Sender-Autorisierung ──
        if not _is_authorized(user_id, str(chat_id)):
            print(f"[{_now()}] UNAUTHORIZED: user={user_id} chat={chat_id}", file=sys.stderr)
            _log_security_event("UNAUTHORIZED", user_id, str(chat_id), text)
            save_offset(offset)
            continue

        # ── 2. Rate-Limit ──
        if not _check_rate_limit(user_id):
            print(f"[{_now()}] RATE_LIMITED: user={user_id}", file=sys.stderr)
            _log_security_event("RATE_LIMITED", user_id, str(chat_id), text)
            try:
                send_message(chat_id, "⏱ Zu viele Nachrichten — bitte kurz warten.", reply_to=message_id)
            except Exception:
                pass
            save_offset(offset)
            continue

        print(f"[{_now()}] user={user_id}(@{username}) chat={chat_id}: {text[:60]!r}")

        # ── 3. Prompt-Injection-Check ──
        injection_hits = detect_injection(text)
        if injection_hits:
            details = " | ".join(injection_hits)
            print(f"[{_now()}] INJECTION BLOCKED: {details}", file=sys.stderr)
            _log_security_event("INJECTION_ATTEMPT", user_id, str(chat_id), text, details)
            alert = (
                "🛡️ *Prompt-Injection blockiert*\n\n"
                f"User: `{user_id}` (@{username})\n"
                f"Muster: `{details[:200]}`\n\n"
                "Nachricht wurde verworfen. Event geloggt."
            )
            try:
                send_message(chat_id, alert, reply_to=message_id)
            except Exception:
                pass
            save_offset(offset)
            continue

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
