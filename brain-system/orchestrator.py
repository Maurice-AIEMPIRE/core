#!/usr/bin/env python3
"""
ORCHESTRATOR — The Central Brain Controller
============================================
Koordiniert alle Gehirnbereiche des Brain Systems.
Wird von telegram_bridge.py über CLI-Flags aufgerufen.

CLI-Interface:
  python orchestrator.py --health         → Brainstem health check
  python orchestrator.py --morning        → Limbic morning briefing
  python orchestrator.py --cycle          → Vollständiger Tageszyklus
  python orchestrator.py --xp 50 --action "LinkedIn post"
  python orchestrator.py --streak coding
  python orchestrator.py --status         → Offene Synapsen + Fehlerraten
  python orchestrator.py --cleanup        → Alte Synapsen löschen + VACUUM

Abhängigkeiten:
  brain_logger.py, call_llm.py, amygdala.py, model_registry.py
"""

from __future__ import annotations

import json
import os
import platform
import sqlite3
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

# ── Pfade ─────────────────────────────────────────────────────────────────────

BRAIN_DIR = Path(__file__).parent
DB_PATH   = os.path.expanduser("~/.openclaw/brain-system/synapses.db")
XP_DB     = os.path.expanduser("~/.openclaw/brain-system/xp.db")

# ── Brain-Definitionen ────────────────────────────────────────────────────────

BRAINS = {
    "brainstem": {
        "name": "The Guard",
        "model": "bash",
        "fallbacks": [],
        "schedule": ["06:00", "hourly"],
        "priority": 0,
    },
    "neocortex": {
        "name": "The Visionary",
        "model": "kimi-k2.5",
        "fallbacks": ["ollama:llama3.3:70b-instruct-q4_K_M", "ollama:qwen2.5-coder:14b"],
        "schedule": ["08:00", "sunday-10:00"],
        "priority": 1,
    },
    "prefrontal": {
        "name": "The CEO",
        "model": "kimi-k2.5",
        "fallbacks": ["ollama:llama3.3:70b-instruct-q4_K_M", "ollama:qwen2.5-coder:14b"],
        "schedule": ["09:00", "18:00"],
        "priority": 1,
    },
    "temporal": {
        "name": "The Mouth",
        "model": "kimi-k2.5",
        "fallbacks": ["ollama:llama3.3:70b-instruct-q4_K_M", "ollama:qwen2.5-coder:14b"],
        "schedule": ["10:00-16:00"],
        "priority": 2,
    },
    "parietal": {
        "name": "The Numbers",
        "model": "ollama:deepseek-r1:14b",
        "fallbacks": ["ollama:qwen2.5-coder:14b", "ollama:qwen2.5-coder:7b"],
        "schedule": ["17:00", "sunday-report"],
        "priority": 2,
    },
    "limbic": {
        "name": "The Drive",
        "model": "ollama:qwen2.5-coder:14b",
        "fallbacks": ["ollama:qwen2.5-coder:7b"],
        "schedule": ["07:00", "19:00"],
        "priority": 3,
    },
    "cerebellum": {
        "name": "The Hands",
        "model": "ollama:qwen2.5-coder:14b",
        "fallbacks": ["ollama:qwen2.5-coder:7b"],
        "schedule": ["10:00-16:00", "night"],
        "priority": 2,
    },
    "hippocampus": {
        "name": "The Memory",
        "model": "sqlite+redplanet",
        "fallbacks": [],
        "schedule": ["continuous", "22:00-consolidation"],
        "priority": 1,
    },
    "amygdala": {
        "name": "The Sentinel",
        "model": "ollama:qwen2.5-coder:7b",
        "fallbacks": ["ollama:llama3.2:3b"],
        "schedule": ["event-driven"],
        "priority": 0,
    },
}

# ── Datenbank ─────────────────────────────────────────────────────────────────

def init_synapse_db() -> None:
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS synapses (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp    TEXT,
            from_brain   TEXT,
            to_brain     TEXT,
            message_type TEXT,
            payload      TEXT,
            priority     INTEGER DEFAULT 5,
            processed    INTEGER DEFAULT 0,
            processed_at TEXT
        );
        CREATE TABLE IF NOT EXISTS xp_events (
            id        INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT,
            action    TEXT,
            xp        INTEGER,
            total     INTEGER
        );
        CREATE TABLE IF NOT EXISTS streaks (
            name        TEXT PRIMARY KEY,
            last_update TEXT,
            count       INTEGER DEFAULT 1
        );
    """)
    conn.commit()
    conn.close()


def _get_xp_total() -> int:
    try:
        conn = sqlite3.connect(DB_PATH)
        row = conn.execute(
            "SELECT total FROM xp_events ORDER BY id DESC LIMIT 1"
        ).fetchone()
        conn.close()
        return row[0] if row else 0
    except Exception:
        return 0


# ── Synapse-Kommunikation ─────────────────────────────────────────────────────

def send_synapse(
    from_brain: str, to_brain: str,
    msg_type: str, payload: dict,
    priority: int = 5,
) -> None:
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        """INSERT INTO synapses
           (timestamp, from_brain, to_brain, message_type, payload, priority)
           VALUES (?, ?, ?, ?, ?, ?)""",
        (datetime.now(timezone.utc).isoformat(), from_brain, to_brain,
         msg_type, json.dumps(payload, ensure_ascii=False), priority),
    )
    conn.commit()
    conn.close()


def receive_synapses(brain_name: str, limit: int = 10) -> list[dict]:
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute(
        """SELECT id, from_brain, message_type, payload, priority
           FROM synapses
           WHERE to_brain = ? AND processed = 0
           ORDER BY priority ASC, timestamp ASC LIMIT ?""",
        (brain_name, limit),
    )
    rows = c.fetchall()
    for row in rows:
        c.execute(
            "UPDATE synapses SET processed = 1, processed_at = ? WHERE id = ?",
            (datetime.now(timezone.utc).isoformat(), row[0]),
        )
    conn.commit()
    conn.close()

    result = []
    for r in rows:
        try:
            payload = json.loads(r[3])
        except (json.JSONDecodeError, TypeError):
            payload = {"raw": str(r[3])}
        result.append({"id": r[0], "from": r[1], "type": r[2],
                        "payload": payload, "priority": r[4]})
    return result


def cleanup_old_synapses(keep_days: int = 30) -> int:
    cutoff = (datetime.now(timezone.utc) - timedelta(days=keep_days)).isoformat()
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute(
        "DELETE FROM synapses WHERE processed = 1 AND timestamp < ?", (cutoff,)
    )
    deleted = c.rowcount
    conn.commit()
    conn.execute("VACUUM")
    conn.close()
    return deleted


# ── Brainstem: System-Health ──────────────────────────────────────────────────

def _check_ollama() -> dict:
    """Prüft ob Ollama läuft und welche Modelle verfügbar sind."""
    import urllib.request
    import urllib.error
    ollama_url = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
    try:
        with urllib.request.urlopen(f"{ollama_url}/api/tags", timeout=5) as r:
            data = json.loads(r.read().decode())
        models = [m["name"] for m in data.get("models", [])]
        return {"status": "OK", "models": models, "count": len(models)}
    except Exception as exc:
        return {"status": "DOWN", "error": str(exc)}


def _disk_info() -> dict:
    """Freier Speicher auf Home-Partition."""
    try:
        home = os.path.expanduser("~")
        st   = os.statvfs(home)
        free_gb  = (st.f_bavail * st.f_frsize) / 1_073_741_824
        total_gb = (st.f_blocks * st.f_frsize) / 1_073_741_824
        used_pct = 100 - (100 * st.f_bavail / st.f_blocks)
        return {
            "free_gb": round(free_gb, 1),
            "total_gb": round(total_gb, 1),
            "used_pct": round(used_pct, 1),
            "status": "WARN" if used_pct > 85 else "OK",
        }
    except Exception as exc:
        return {"status": "ERROR", "error": str(exc)}


def _memory_info() -> dict:
    """RAM-Nutzung."""
    try:
        with open("/proc/meminfo") as f:
            lines = f.readlines()
        info = {}
        for line in lines:
            k, v = line.split(":", 1)
            info[k.strip()] = int(v.strip().split()[0])
        total_gb = info.get("MemTotal", 0) / 1_048_576
        avail_gb = info.get("MemAvailable", 0) / 1_048_576
        used_pct = 100 * (1 - avail_gb / total_gb) if total_gb else 0
        return {
            "total_gb": round(total_gb, 1),
            "avail_gb": round(avail_gb, 1),
            "used_pct": round(used_pct, 1),
            "status": "WARN" if used_pct > 90 else "OK",
        }
    except Exception:
        return {"status": "UNKNOWN"}


def run_brainstem() -> str:
    """Vollständiger System-Health-Check."""
    lines = [
        f"🧠 *BRAINSTEM Health Check* — {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}",
        "",
    ]

    # OS
    lines.append(f"🖥️  OS: `{platform.system()} {platform.release()}`")

    # Disk
    disk = _disk_info()
    disk_icon = "⚠️" if disk.get("status") == "WARN" else "✅"
    lines.append(
        f"{disk_icon} Disk: `{disk.get('free_gb', '?')} GB free` / "
        f"`{disk.get('total_gb', '?')} GB total` ({disk.get('used_pct', '?')}% used)"
    )

    # RAM
    mem = _memory_info()
    mem_icon = "⚠️" if mem.get("status") == "WARN" else "✅"
    lines.append(
        f"{mem_icon} RAM: `{mem.get('avail_gb', '?')} GB avail` / "
        f"`{mem.get('total_gb', '?')} GB total` ({mem.get('used_pct', '?')}% used)"
    )

    # Ollama
    ollama = _check_ollama()
    ollama_icon = "✅" if ollama["status"] == "OK" else "🔴"
    if ollama["status"] == "OK":
        models_str = ", ".join(ollama["models"][:5])
        if len(ollama["models"]) > 5:
            models_str += f" (+{len(ollama['models'])-5} more)"
        lines.append(f"{ollama_icon} Ollama: `{ollama['count']} models` — {models_str}")
    else:
        lines.append(f"{ollama_icon} Ollama: `DOWN` — {ollama.get('error', '')[:60]}")

    # DB
    try:
        conn = sqlite3.connect(DB_PATH)
        pending = conn.execute(
            "SELECT COUNT(*) FROM synapses WHERE processed = 0"
        ).fetchone()[0]
        total   = conn.execute("SELECT COUNT(*) FROM synapses").fetchone()[0]
        conn.close()
        lines.append(f"✅ SynapseDB: `{pending} pending` / `{total} total`")
    except Exception as exc:
        lines.append(f"⚠️  SynapseDB: `{exc}`")

    # Python
    lines.append(f"✅ Python: `{sys.version.split()[0]}`")
    lines.append("")

    # Alert on warnings
    warnings = [
        l for l in lines if "⚠️" in l or "🔴" in l
    ]
    if warnings:
        lines.append(f"🚨 *{len(warnings)} warning(s) — check items above*")
    else:
        lines.append("✅ *All systems nominal.*")

    return "\n".join(lines)


# ── Limbic: Morning Briefing ──────────────────────────────────────────────────

def run_limbic_morning() -> str:
    """Motivierendes Morgen-Briefing mit aktuellem XP und Zielen."""
    xp_total = _get_xp_total()
    level    = xp_total // 100 + 1
    xp_next  = level * 100 - xp_total

    now = datetime.now(timezone.utc)
    weekday = now.strftime("%A")
    date_str = now.strftime("%d. %B %Y")

    # Streak-Infos
    streak_lines = []
    try:
        conn = sqlite3.connect(DB_PATH)
        streaks = conn.execute(
            "SELECT name, count, last_update FROM streaks ORDER BY count DESC LIMIT 5"
        ).fetchall()
        conn.close()
        for name, count, last in streaks:
            fire = "🔥" * min(count // 3 + 1, 5)
            streak_lines.append(f"  {fire} `{name}`: {count} days")
    except Exception:
        pass

    lines = [
        f"🌅 *Good Morning — {weekday}, {date_str}*",
        "",
        f"⚡ Level `{level}` — `{xp_total} XP` total",
        f"🎯 `{xp_next} XP` until next level",
        "",
    ]

    if streak_lines:
        lines.append("🔥 *Active Streaks:*")
        lines.extend(streak_lines)
        lines.append("")

    # Pending synapses als Aufgaben
    try:
        conn = sqlite3.connect(DB_PATH)
        pending = conn.execute(
            """SELECT from_brain, message_type, payload
               FROM synapses WHERE processed = 0
               ORDER BY priority ASC LIMIT 5"""
        ).fetchall()
        conn.close()
        if pending:
            lines.append("📋 *Pending Brain Signals:*")
            for from_b, mtype, payload in pending:
                try:
                    p = json.loads(payload)
                    note = p.get("quota") or p.get("date", "")[:10] or ""
                except Exception:
                    note = ""
                lines.append(f"  → `{from_b}` → {mtype}" + (f" ({note})" if note else ""))
            lines.append("")
    except Exception:
        pass

    lines += [
        "💡 *Today's focus:*",
        "  1. Ship one meaningful thing",
        "  2. Log progress → /xp",
        "  3. Keep the streak alive",
        "",
        "_The brain is primed. Let's build._",
    ]

    return "\n".join(lines)


# ── Daily Cycle ───────────────────────────────────────────────────────────────

def run_daily_cycle() -> str:
    """Vollständiger Tageszyklus: Health → Amygdala → Limbic → Signale."""
    init_synapse_db()
    lines = [
        f"🔄 *Daily Brain Cycle* — {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}",
        "",
    ]

    # Phase 1: Brainstem
    lines.append("🧠 *Phase 1: BRAINSTEM Health Check*")
    health = run_brainstem()
    # Nur die letzte Zeile (Zusammenfassung)
    summary_line = [l for l in health.splitlines() if l.strip()][-1]
    lines.append(f"  {summary_line}")
    lines.append("")

    try:
        from brain_logger import log_health
        log_health(health)
    except ImportError:
        pass

    # Phase 2: Amygdala
    lines.append("🛡️  *Phase 2: AMYGDALA Risk Scan*")
    try:
        sys.path.insert(0, str(BRAIN_DIR))
        from amygdala import run_amygdala
        result = run_amygdala()
        if result:
            sev = result.get("severity", "INFO")
            summary = result.get("summary", "")
            lines.append(f"  → `{sev}` — {summary}")
        else:
            lines.append("  → No risks detected.")
    except ImportError:
        lines.append("  → amygdala.py not found, skipped.")
    except Exception as exc:
        lines.append(f"  → ⚠️ {exc}")
    lines.append("")

    # Phase 3: Limbic
    lines.append("🔥 *Phase 3: LIMBIC Morning Briefing*")
    briefing = run_limbic_morning()
    xp_line = next((l for l in briefing.splitlines() if "XP" in l and "Level" in l), "")
    lines.append(f"  {xp_line}")
    lines.append("")

    try:
        from brain_logger import log_briefing
        log_briefing(briefing)
    except ImportError:
        pass

    # Phase 4: Signale
    lines.append("📡 *Phase 4: Signaling all brains*")
    signals = [
        ("neocortex",  "START_DAY",          {"date": datetime.now().isoformat()}),
        ("prefrontal", "START_DAY",          {"date": datetime.now().isoformat()}),
        ("temporal",   "START_CONTENT",      {"quota": 5}),
        ("parietal",   "PREPARE_KPI",        {}),
        ("cerebellum", "CHECK_AUTOMATIONS",  {}),
    ]
    for to_brain, msg_type, payload in signals:
        send_synapse("orchestrator", to_brain, msg_type, payload)
        lines.append(f"  ✓ `orchestrator` → `{to_brain}` [{msg_type}]")

    lines += [
        "",
        f"✅ *Cycle complete.* {len(BRAINS)} brains active.",
        f"📂 Log: `~/brain-logs/{datetime.now().strftime('%Y-%m-%d')}.md`",
    ]

    return "\n".join(lines)


# ── XP System ─────────────────────────────────────────────────────────────────

def add_xp(amount: int, action: str) -> str:
    """XP hinzufügen und Level berechnen."""
    init_synapse_db()
    current = _get_xp_total()
    new_total = current + amount
    level_before = current // 100 + 1
    level_after  = new_total // 100 + 1

    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        "INSERT INTO xp_events (timestamp, action, xp, total) VALUES (?, ?, ?, ?)",
        (datetime.now(timezone.utc).isoformat(), action, amount, new_total),
    )
    conn.commit()
    conn.close()

    try:
        from brain_logger import log_xp
        log_xp(action, amount, new_total)
    except ImportError:
        pass

    lines = [
        f"⚡ *+{amount} XP* — _{action}_",
        f"Total: `{new_total} XP` | Level: `{level_after}`",
    ]

    if level_after > level_before:
        lines.insert(1, f"🎉 *LEVEL UP! {level_before} → {level_after}*")

    xp_next = level_after * 100 - new_total
    lines.append(f"🎯 `{xp_next} XP` to next level")

    return "\n".join(lines)


# ── Streak System ─────────────────────────────────────────────────────────────

def update_streak(name: str) -> str:
    """Streak für eine Aktivität aktualisieren."""
    init_synapse_db()
    now_str = datetime.now(timezone.utc).date().isoformat()

    conn = sqlite3.connect(DB_PATH)
    row = conn.execute(
        "SELECT count, last_update FROM streaks WHERE name = ?", (name,)
    ).fetchone()

    if row is None:
        conn.execute(
            "INSERT INTO streaks (name, last_update, count) VALUES (?, ?, 1)",
            (name, now_str),
        )
        count = 1
        msg = f"🔥 *New streak started:* `{name}`\nDay 1 — keep it going!"
    else:
        count, last = row
        last_date = datetime.fromisoformat(last).date()
        today = datetime.now(timezone.utc).date()
        delta = (today - last_date).days

        if delta == 0:
            conn.close()
            fire = "🔥" * min(count // 3 + 1, 5)
            return f"{fire} `{name}` already logged today — Day {count}"
        elif delta == 1:
            count += 1
            conn.execute(
                "UPDATE streaks SET count = ?, last_update = ? WHERE name = ?",
                (count, now_str, name),
            )
            msg = f"🔥 *Streak extended:* `{name}`\nDay {count} — {'🔥' * min(count // 3 + 1, 5)}"
        else:
            # Streak broken
            conn.execute(
                "UPDATE streaks SET count = 1, last_update = ? WHERE name = ?",
                (now_str, name),
            )
            count = 1
            msg = f"💔 *Streak reset:* `{name}` (gap: {delta} days)\nDay 1 — restart!"

    conn.commit()
    conn.close()
    return msg


# ── Status ────────────────────────────────────────────────────────────────────

def get_status() -> str:
    """Offene Synapsen, XP-Stand und Modell-Fehlerraten."""
    lines = [
        f"📊 *Brain Status* — {datetime.now(timezone.utc).strftime('%H:%M UTC')}",
        "",
    ]

    # Synapse queue
    try:
        conn = sqlite3.connect(DB_PATH)
        pending_rows = conn.execute(
            """SELECT to_brain, COUNT(*) as n
               FROM synapses WHERE processed = 0
               GROUP BY to_brain ORDER BY n DESC"""
        ).fetchall()
        total_pending = sum(r[1] for r in pending_rows)
        conn.close()

        lines.append(f"📡 *Synapse Queue:* `{total_pending} pending`")
        for brain, count in pending_rows:
            lines.append(f"  → `{brain}`: {count}")
        lines.append("")
    except Exception as exc:
        lines.append(f"⚠️ SynapseDB: {exc}\n")

    # XP
    xp_total = _get_xp_total()
    level    = xp_total // 100 + 1
    xp_next  = level * 100 - xp_total
    lines += [
        f"⚡ *XP:* `{xp_total}` | Level `{level}` | `{xp_next}` to next",
        "",
    ]

    # Model error rates
    try:
        sys.path.insert(0, str(BRAIN_DIR))
        from call_llm import get_error_rate, ERROR_THRESHOLD
        tracked = [
            "kimi-k2.5", "kimi-k1.5",
            "ollama:qwen2.5-coder:14b", "ollama:qwen2.5-coder:7b",
            "ollama:deepseek-r1:14b", "ollama:llama3.2:3b",
        ]
        lines.append("🤖 *Model Error Rates (last 50 calls):*")
        for m in tracked:
            rate = get_error_rate(m)
            bar  = "█" * int(rate * 10) + "░" * (10 - int(rate * 10))
            flag = " ⚠️" if rate >= ERROR_THRESHOLD else ""
            short = m.split(":")[-1][:20]
            lines.append(f"  `{short:<20}` {rate:4.0%} [{bar}]{flag}")
    except ImportError:
        pass
    except Exception as exc:
        lines.append(f"⚠️ Model rates: {exc}")

    return "\n".join(lines)


# ── CLI ───────────────────────────────────────────────────────────────────────

def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Brain Orchestrator")
    parser.add_argument("--health",  action="store_true", help="Brainstem health check")
    parser.add_argument("--morning", action="store_true", help="Limbic morning briefing")
    parser.add_argument("--cycle",   action="store_true", help="Full daily brain cycle")
    parser.add_argument("--status",  action="store_true", help="Status: queue + model rates")
    parser.add_argument("--cleanup", action="store_true", help="Delete old synapses + VACUUM")
    parser.add_argument("--xp",      type=int,            help="XP amount to add")
    parser.add_argument("--action",  type=str, default="telegram", help="XP action description")
    parser.add_argument("--streak",  type=str,            help="Streak name to update")
    parser.add_argument("--brains",  action="store_true", help="List all brain definitions")
    args = parser.parse_args()

    init_synapse_db()

    if args.health:
        print(run_brainstem())

    elif args.morning:
        print(run_limbic_morning())

    elif args.cycle:
        print(run_daily_cycle())

    elif args.status:
        print(get_status())

    elif args.cleanup:
        n = cleanup_old_synapses()
        print(f"✅ Deleted {n} old synapses. DB vacuumed.")

    elif args.xp is not None:
        print(add_xp(args.xp, args.action))

    elif args.streak:
        print(update_streak(args.streak))

    elif args.brains:
        lines = ["🧠 *Registered Brains:*\n"]
        for brain_id, cfg in BRAINS.items():
            lines.append(
                f"  `{brain_id:<12}` {cfg['name']:<16} model={cfg['model']}"
            )
        print("\n".join(lines))

    else:
        parser.print_help()


if __name__ == "__main__":
    main()
