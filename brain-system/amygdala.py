#!/usr/bin/env python3
"""
AMYGDALA — The Sentinel
========================
Fear/risk detection brain.
Event-driven: wakes up only when brainstem sends ALERT synapses.
Fast local 7b/8b model — no API dependency.

Responsibilities:
  - Scan recent synapses + health reports for risk keywords
  - Classify severity: INFO / WARN / CRITICAL
  - Ping prefrontal with structured risk assessment
  - Write desktop notification (macOS / Linux)
  - Log to ~/brain-logs/

Model: ollama:qwen2.5-coder:7b (fast, local, zero cost)
Fallback: ollama:llama3.2:3b (even faster for quick triage)
"""

import json
import os
import sqlite3
import subprocess
from datetime import datetime, timezone

from brain_logger import log, log_alert
from call_llm import call_llm_with_fallback

DB_PATH = os.path.expanduser("~/.openclaw/brain-system/synapses.db")

AMYGDALA_MODEL    = "ollama:qwen2.5-coder:7b"
AMYGDALA_FALLBACK = ["ollama:llama3.2:3b"]

RISK_KEYWORDS = {
    "CRITICAL": ["DOWN", "CRITICAL", "crash", "fatal", "offline", "unreachable"],
    "HIGH":     ["ERROR", "ALERT", "failed", "timeout", "disk full"],
    "WARN":     ["WARN", "slow", "high load", "retry", "degraded"],
}

SYSTEM_PROMPT = """Du bist AMYGDALA, das Risikoerkennungs-Gehirn eines autonomen AI-Systems.
Deine einzige Aufgabe: eingehende Alarme analysieren und eine klare Risikobewertung liefern.

Antworte NUR mit validen JSON:
{
  "severity": "CRITICAL" | "HIGH" | "WARN" | "INFO",
  "summary": "<1 Satz was das Problem ist>",
  "affected_systems": ["<system1>", ...],
  "recommended_action": "<konkrete Massnahme>",
  "escalate_to_prefrontal": true | false
}

Keine Erklaerungen ausserhalb des JSON-Blocks."""


# ── Risk scanning ────────────────────────────────────────────────────────────

def _scan_keywords(text: str) -> str:
    """Quick keyword-based severity without LLM (for pre-filter)."""
    text_upper = text.upper()
    for severity, words in RISK_KEYWORDS.items():
        if any(w.upper() in text_upper for w in words):
            return severity
    return "INFO"


def _get_recent_alerts(limit: int = 20) -> list[dict]:
    """Pull recent unprocessed ALERT synapses from DB."""
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''
        SELECT id, from_brain, message_type, payload, timestamp
        FROM synapses
        WHERE message_type IN ('ALERT', 'HEALTH_WARN', 'CRITICAL')
          AND processed = 0
        ORDER BY priority ASC, timestamp DESC
        LIMIT ?
    ''', (limit,))
    rows = c.fetchall()
    conn.close()
    return [
        {"id": r[0], "from": r[1], "type": r[2],
         "payload": _safe_json(r[3]), "timestamp": r[4]}
        for r in rows
    ]


def _safe_json(raw: str) -> dict:
    try:
        return json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return {"raw": str(raw)}


def _send_synapse(to_brain: str, msg_type: str, payload: dict, priority: int = 1) -> None:
    conn = sqlite3.connect(DB_PATH)
    conn.execute('''
        INSERT INTO synapses (timestamp, from_brain, to_brain, message_type, payload, priority)
        VALUES (?, ?, ?, ?, ?, ?)
    ''', (datetime.now(timezone.utc).isoformat(), "amygdala", to_brain,
          msg_type, json.dumps(payload, ensure_ascii=False), priority))
    conn.commit()
    conn.close()


# ── Notification ─────────────────────────────────────────────────────────────

def _notify(title: str, message: str) -> None:
    """Desktop notification — macOS + Linux (notify-send)."""
    try:
        if subprocess.run(["which", "osascript"], capture_output=True).returncode == 0:
            script = f'display notification "{message}" with title "{title}" sound name "Basso"'
            subprocess.run(["osascript", "-e", script], capture_output=True, timeout=5)
        elif subprocess.run(["which", "notify-send"], capture_output=True).returncode == 0:
            subprocess.run(["notify-send", "-u", "critical", title, message],
                           capture_output=True, timeout=5)
    except Exception:
        pass  # Notification failure must never block the main flow


# ── LLM triage ───────────────────────────────────────────────────────────────

def _triage_with_llm(alerts: list[dict]) -> dict:
    """Let the local LLM do deep risk analysis."""
    alert_text = json.dumps(alerts, ensure_ascii=False, indent=2)
    prompt = f"Analysiere diese System-Alarme und bewerte das Risiko:\n\n{alert_text}"

    try:
        raw, model_used = call_llm_with_fallback(
            preferred=AMYGDALA_MODEL,
            fallbacks=AMYGDALA_FALLBACK,
            prompt=prompt,
            system=SYSTEM_PROMPT,
            timeout=30,
        )
        # Extract JSON block (model may wrap it in ```json ... ```)
        if "```" in raw:
            raw = raw.split("```")[1]
            if raw.startswith("json"):
                raw = raw[4:]
        return json.loads(raw.strip())
    except Exception as exc:
        # Fallback: keyword-based triage
        combined = json.dumps(alerts)
        severity  = _scan_keywords(combined)
        return {
            "severity": severity,
            "summary": f"Keyword-Triage (LLM unavailable: {exc})",
            "affected_systems": [],
            "recommended_action": "Manually review alerts",
            "escalate_to_prefrontal": severity in ("CRITICAL", "HIGH"),
        }


# ── Main entry point ─────────────────────────────────────────────────────────

def run_amygdala() -> dict | None:
    """
    Main amygdala cycle.
    Returns triage result dict or None if no alerts pending.
    """
    alerts = _get_recent_alerts()
    if not alerts:
        return None

    print(f"🧠 AMYGDALA — {len(alerts)} alert(s) detected, triaging...")

    triage = _triage_with_llm(alerts)
    severity = triage.get("severity", "WARN")
    summary  = triage.get("summary", "Unknown risk")

    # Log to brain-logs/
    log("amygdala", "triage_complete", triage)
    if severity in ("CRITICAL", "HIGH"):
        log_alert("amygdala", severity, {
            "summary": summary,
            "systems": str(triage.get("affected_systems", [])),
            "action":  triage.get("recommended_action", ""),
        })

    # Desktop notification for CRITICAL/HIGH
    if severity in ("CRITICAL", "HIGH"):
        _notify(
            f"🚨 AMYGDALA [{severity}]",
            summary[:120],
        )

    # Escalate to prefrontal if needed
    if triage.get("escalate_to_prefrontal"):
        _send_synapse("prefrontal", "RISK_ASSESSMENT", triage, priority=1)
        print(f"  → Escalated to PREFRONTAL: {summary}")

    # Always inform limbic (for motivation/context)
    _send_synapse("limbic", "RISK_DETECTED", {
        "severity": severity, "summary": summary
    }, priority=3)

    print(f"  Severity: {severity} | {summary}")
    return triage


# ── CLI ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Amygdala — Risk Detection Brain")
    parser.add_argument("--run",  action="store_true", help="Process pending alerts")
    parser.add_argument("--test", action="store_true", help="Inject a test CRITICAL alert")
    args = parser.parse_args()

    if args.test:
        # Inject a fake critical alert for testing
        conn = sqlite3.connect(DB_PATH)
        os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
        conn.execute('''CREATE TABLE IF NOT EXISTS synapses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT, from_brain TEXT, to_brain TEXT,
            message_type TEXT, payload TEXT,
            priority INTEGER DEFAULT 5, processed INTEGER DEFAULT 0,
            processed_at TEXT
        )''')
        conn.execute('''INSERT INTO synapses
            (timestamp, from_brain, to_brain, message_type, payload, priority)
            VALUES (?, ?, ?, ?, ?, ?)''',
            (datetime.now(timezone.utc).isoformat(), "brainstem", "amygdala",
             "ALERT", json.dumps({"systems": {"ollama": "DOWN", "disk_free": "2G"}}), 0))
        conn.commit()
        conn.close()
        print("Test alert injected.")

    if args.run or args.test:
        result = run_amygdala()
        if result:
            print(json.dumps(result, ensure_ascii=False, indent=2))
        else:
            print("No pending alerts.")
    else:
        parser.print_help()
