"""
ORCHESTRATOR UPDATES — Drop-in patches for orchestrator.py
============================================================
Apply these changes to orchestrator.py:

1. BRAINS config  → upgraded models (14b/32b) + amygdala added
2. receive_synapses()  → safe JSON decode
3. send_synapse()  → ensure_ascii=False
4. init_synapse_db()  → datetime(timezone.utc)
5. cleanup_old_synapses()  → periodic VACUUM
6. run_daily_cycle()  → calls amygdala + brain_logger

Copy the blocks below into orchestrator.py, replacing the originals.
"""

# ════════════════════════════════════════════════════════════════════
# 1.  BRAINS — upgraded for 2026 hardware
# ════════════════════════════════════════════════════════════════════
# Notes on model selection:
#   - qwen2.5-coder:14b  → solid upgrade from 7b, runs fine on 16 GB VRAM
#   - deepseek-r1:14b    → strong reasoning, good for numbers/code
#   - llama3.3:70b-q4    → top-tier local model (needs 24+ GB VRAM / Mac M4 Max)
#   - qwen2.5-coder:7b   → kept as lightweight fallback
#
# Change any model to match YOUR available hardware.

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
        "model": "ollama:deepseek-r1:14b",        # ← upgraded: better math/analysis
        "fallbacks": ["ollama:qwen2.5-coder:14b", "ollama:qwen2.5-coder:7b"],
        "schedule": ["17:00", "sunday-report"],
        "priority": 2,
    },
    "limbic": {
        "name": "The Drive",
        "model": "ollama:qwen2.5-coder:14b",      # ← upgraded: richer motivation
        "fallbacks": ["ollama:qwen2.5-coder:7b"],
        "schedule": ["07:00", "19:00"],
        "priority": 3,
    },
    "cerebellum": {
        "name": "The Hands",
        "model": "ollama:qwen2.5-coder:14b",      # ← upgraded: better code quality
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
    # ── NEW ──────────────────────────────────────────────────────────
    "amygdala": {
        "name": "The Sentinel",
        "model": "ollama:qwen2.5-coder:7b",       # fast, always-available
        "fallbacks": ["ollama:llama3.2:3b"],
        "schedule": ["event-driven"],              # triggered by ALERT synapses
        "priority": 0,                             # highest priority, same as brainstem
    },
}


# ════════════════════════════════════════════════════════════════════
# 2.  receive_synapses() — safe JSON decode
# ════════════════════════════════════════════════════════════════════

def receive_synapses(brain_name, limit=10):
    """Receive pending messages for a brain (with safe JSON decode)."""
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''SELECT id, from_brain, message_type, payload, priority
        FROM synapses WHERE to_brain = ? AND processed = 0
        ORDER BY priority ASC, timestamp ASC LIMIT ?''',
        (brain_name, limit))
    messages = c.fetchall()

    for msg in messages:
        c.execute('UPDATE synapses SET processed = 1, processed_at = ? WHERE id = ?',
                  (datetime.now(timezone.utc).isoformat(), msg[0]))
    conn.commit()
    conn.close()

    result = []
    for m in messages:
        try:
            payload = json.loads(m[3])
        except (json.JSONDecodeError, TypeError):
            payload = {"raw": str(m[3])}
        result.append({"id": m[0], "from": m[1], "type": m[2],
                        "payload": payload, "priority": m[4]})
    return result


# ════════════════════════════════════════════════════════════════════
# 3.  send_synapse() — ensure_ascii=False for German umlauts
# ════════════════════════════════════════════════════════════════════

def send_synapse(from_brain, to_brain, msg_type, payload, priority=5):
    """Send a message between brains."""
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''INSERT INTO synapses
        (timestamp, from_brain, to_brain, message_type, payload, priority)
        VALUES (?, ?, ?, ?, ?, ?)''',
        (datetime.now(timezone.utc).isoformat(), from_brain, to_brain,
         msg_type, json.dumps(payload, ensure_ascii=False), priority))
    conn.commit()
    conn.close()


# ════════════════════════════════════════════════════════════════════
# 4.  cleanup_old_synapses() — periodic VACUUM (add to cron / weekly)
# ════════════════════════════════════════════════════════════════════

def cleanup_old_synapses(keep_days: int = 30) -> int:
    """
    Delete processed synapses older than keep_days and VACUUM the DB.
    Returns number of deleted rows.
    Run weekly (e.g. sunday-22:00) or call with --cleanup flag.
    """
    from datetime import timedelta
    cutoff = (datetime.now(timezone.utc) - timedelta(days=keep_days)).isoformat()

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('DELETE FROM synapses WHERE processed = 1 AND timestamp < ?', (cutoff,))
    deleted = c.rowcount
    conn.commit()
    conn.execute('VACUUM')
    conn.close()

    return deleted


# ════════════════════════════════════════════════════════════════════
# 5.  run_daily_cycle() — add amygdala check + brain_logger
#     Replace the existing run_daily_cycle() in orchestrator.py
# ════════════════════════════════════════════════════════════════════

def run_daily_cycle():
    """Run the complete daily brain cycle."""
    from brain_logger import log_health, log_briefing, log_synapse

    init_synapse_db()
    reports = {}

    print("=" * 60)
    print(f"BRAIN SYSTEM — Daily Cycle {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    print("=" * 60)

    # Phase 1: BRAINSTEM
    print("\n🧠 BRAINSTEM — Health Check...")
    reports["brainstem"] = run_brainstem()
    log_health(reports["brainstem"])
    print(reports["brainstem"])

    # Phase 1b: AMYGDALA — immediate risk scan after health check
    print("\n🛡️  AMYGDALA — Risk Scan...")
    try:
        from amygdala import run_amygdala
        amygdala_result = run_amygdala()
        if amygdala_result:
            reports["amygdala"] = amygdala_result
            print(f"  → {amygdala_result.get('severity')} | {amygdala_result.get('summary')}")
        else:
            print("  → No risks detected.")
    except ImportError:
        print("  → amygdala.py not found, skipping.")

    # Phase 2: LIMBIC
    print("\n🔥 LIMBIC — Morning Briefing...")
    reports["limbic"] = run_limbic_morning()
    log_briefing(reports["limbic"])
    print(reports["limbic"])

    # Phase 3: Signal to other brains
    signals = [
        ("neocortex",   "START_DAY",           {"date": datetime.now().isoformat()}),
        ("prefrontal",  "START_DAY",           {"date": datetime.now().isoformat()}),
        ("temporal",    "START_CONTENT",       {"quota": 5}),
        ("parietal",    "PREPARE_KPI",         {}),
        ("cerebellum",  "CHECK_AUTOMATIONS",   {}),
    ]
    for to_brain, msg_type, payload in signals:
        send_synapse("orchestrator", to_brain, msg_type, payload)
        log_synapse("orchestrator", to_brain, msg_type, payload)

    print("\n✅ All brains signaled. Daily cycle initialized.")
    print(f"Active brains: {len(BRAINS)}")
    print(f"Check logs: ~/brain-logs/{datetime.now().strftime('%Y-%m-%d')}.md")

    return reports


# ════════════════════════════════════════════════════════════════════
# Add --cleanup to the argparse block in orchestrator.py:
#
#   parser.add_argument('--cleanup', action='store_true',
#                       help='Delete old synapses + VACUUM DB')
#   ...
#   elif args.cleanup:
#       n = cleanup_old_synapses()
#       print(f"Deleted {n} old synapses. DB vacuumed.")
# ════════════════════════════════════════════════════════════════════
