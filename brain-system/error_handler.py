#!/usr/bin/env python3
"""
ERROR HANDLER — Auto-Detect & Auto-Fix
=======================================
Erkennt Fehler in Telegram-Notizen und findet automatisch eine Loesung.

Flow:
  1. Telegram-Nachricht kommt rein (kein /command)
  2. LLM klassifiziert: Ist das ein Fehler / Bug / Problem?
  3. Wenn ja: LLM analysiert und schlaegt Fix vor
  4. Fix wird direkt ausgefuehrt (Python/Shell) oder als Patch zurueck gesendet
  5. Ergebnis wird auf Telegram bestaetigt

Fehler-Kategorien:
  python_error   — Traceback / Exception / SyntaxError
  config_error   — Missing env var, wrong path, missing file
  model_error    — LLM unavailable, timeout, bad response
  logic_error    — Beschreibung eines falschen Verhaltens
  system_error   — Disk, memory, process down
  general_note   — Allgemeine Notiz (kein Fehler)
"""

from __future__ import annotations
import json
import os
import re
import subprocess
import sys
import traceback
from datetime import datetime, timezone
from pathlib import Path

BRAIN_DIR = Path(__file__).parent
DB_PATH   = os.path.expanduser("~/.openclaw/brain-system/synapses.db")

# Error keywords for fast pre-classification (no LLM needed)
ERROR_PATTERNS = {
    "python_error": [
        r"traceback",
        r"exception:",
        r"error:",
        r"syntaxerror",
        r"nameerror",
        r"typeerror",
        r"valueerror",
        r"importerror",
        r"filenotfounderror",
        r"attributeerror",
        r"keyerror",
        r"indexerror",
        r"zerodivisionerror",
    ],
    "model_error": [
        r"model.*down",
        r"ollama.*failed",
        r"kimi.*error",
        r"timeout.*llm",
        r"llm.*timeout",
        r"api.*error",
        r"rate.limit",
    ],
    "config_error": [
        r"not set",
        r"missing.*key",
        r"env.*variable",
        r"not found",
        r"no such file",
        r"permission denied",
        r"invalid.*token",
    ],
    "system_error": [
        r"disk.*full",
        r"out of memory",
        r"oom",
        r"process.*killed",
        r"connection refused",
        r"port.*in use",
    ],
}

CLASSIFY_PROMPT = """Du bist ein Fehler-Klassifizierer fuer ein Brain System.

Analysiere diese Nachricht und antworte NUR mit validem JSON:

{
  "is_error": true | false,
  "category": "python_error" | "config_error" | "model_error" | "logic_error" | "system_error" | "general_note",
  "severity": "CRITICAL" | "HIGH" | "MEDIUM" | "LOW",
  "summary": "<1-Satz Beschreibung des Problems>",
  "fixable": true | false,
  "fix_type": "code_patch" | "shell_command" | "config_change" | "restart" | "manual" | null
}

Kein Text ausserhalb des JSON-Blocks."""

FIX_PROMPT = """Du bist ein Auto-Fix-System fuer ein Python Brain System.

Fehler:
{error_text}

Kategorie: {category}

Das System besteht aus diesen Dateien:
{file_list}

Antworte NUR mit validem JSON:
{{
  "explanation": "<kurze Erklaerung was das Problem ist>",
  "fix_type": "code_patch" | "shell_command" | "config_change" | "manual",
  "commands": ["<shell command 1>", "<shell command 2>"],
  "file_patches": [
    {{
      "file": "<relativer Pfad>",
      "search": "<exakter Text der ersetzt wird>",
      "replace": "<neuer Text>"
    }}
  ],
  "manual_steps": ["<Schritt 1 falls manuell>"],
  "confidence": 0.0-1.0
}}

Wenn confidence < 0.5: fix_type = "manual", gib nur manual_steps an.
Kein Text ausserhalb des JSON-Blocks."""


# ── Classification ─────────────────────────────────────────────────────────────

def quick_classify(text: str) -> str | None:
    """Fast keyword-based classification, no LLM. Returns category or None."""
    lower = text.lower()
    for category, patterns in ERROR_PATTERNS.items():
        if any(re.search(p, lower) for p in patterns):
            return category
    return None


def classify_with_llm(text: str) -> dict:
    """Full LLM classification. Returns parsed JSON dict."""
    try:
        from call_llm import call_llm_with_fallback  # type: ignore
        raw, _ = call_llm_with_fallback(
            preferred="ollama:qwen2.5-coder:7b",
            fallbacks=["ollama:llama3.2:3b", "kimi-k2.5"],
            prompt=f"Analysiere:\n\n{text[:2000]}",
            system=CLASSIFY_PROMPT,
            timeout=30,
        )
        raw = _extract_json(raw)
        return json.loads(raw)
    except Exception as exc:
        # Fallback: keyword-based
        cat = quick_classify(text) or "general_note"
        return {
            "is_error": cat != "general_note",
            "category": cat,
            "severity": "MEDIUM",
            "summary": text[:100],
            "fixable": False,
            "fix_type": "manual",
            "_classify_error": str(exc),
        }


# ── Fix generation ─────────────────────────────────────────────────────────────

def generate_fix(error_text: str, category: str) -> dict:
    """Ask LLM to generate a fix plan."""
    file_list = "\n".join(
        f"  {f.name}" for f in BRAIN_DIR.glob("*.py") if f.is_file()
    )
    prompt = FIX_PROMPT.format(
        error_text=error_text[:3000],
        category=category,
        file_list=file_list,
    )
    try:
        from call_llm import call_llm_with_fallback  # type: ignore
        raw, model = call_llm_with_fallback(
            preferred="ollama:qwen2.5-coder:14b",
            fallbacks=["ollama:deepseek-r1:14b", "kimi-k2.5", "ollama:qwen2.5-coder:7b"],
            prompt=prompt,
            system="Du bist ein Python-Experte. Antworte nur mit JSON.",
            timeout=60,
        )
        raw = _extract_json(raw)
        result = json.loads(raw)
        result["_model_used"] = model
        return result
    except Exception as exc:
        return {
            "explanation": f"Fix-Generierung fehlgeschlagen: {exc}",
            "fix_type": "manual",
            "commands": [],
            "file_patches": [],
            "manual_steps": ["Fix konnte nicht automatisch generiert werden — bitte manuell pruefen."],
            "confidence": 0.0,
        }


# ── Fix execution ──────────────────────────────────────────────────────────────

def apply_fix(fix: dict) -> tuple[bool, str]:
    """
    Execute the fix. Returns (success, result_message).
    Only executes if confidence >= 0.7.
    """
    confidence = fix.get("confidence", 0.0)
    fix_type   = fix.get("fix_type", "manual")

    if confidence < 0.7 or fix_type == "manual":
        steps = fix.get("manual_steps", [])
        return False, "Manuell erforderlich:\n" + "\n".join(f"• {s}" for s in steps)

    results = []

    # Apply shell commands (safe subset only)
    for cmd in fix.get("commands", []):
        if _is_safe_command(cmd):
            try:
                r = subprocess.run(
                    cmd, shell=True, capture_output=True, text=True, timeout=30,
                    cwd=str(BRAIN_DIR),
                )
                results.append(f"`{cmd}` → rc={r.returncode}")
                if r.returncode != 0 and r.stderr:
                    results.append(f"  stderr: {r.stderr[:200]}")
            except Exception as exc:
                results.append(f"`{cmd}` → ERROR: {exc}")
        else:
            results.append(f"Skipped (unsafe): `{cmd}`")

    # Apply file patches
    for patch in fix.get("file_patches", []):
        fname   = patch.get("file", "")
        search  = patch.get("search", "")
        replace = patch.get("replace", "")
        if not fname or not search:
            continue

        fpath = BRAIN_DIR / fname
        if not fpath.exists():
            results.append(f"Patch: file not found: {fname}")
            continue

        content = fpath.read_text(encoding="utf-8")
        if search in content:
            fpath.write_text(content.replace(search, replace, 1), encoding="utf-8")
            results.append(f"Patched: {fname}")
        else:
            results.append(f"Patch: search string not found in {fname}")

    return True, "\n".join(results) if results else "Fix applied (no output)"


def _is_safe_command(cmd: str) -> bool:
    """Block destructive commands."""
    blocked = ["rm -rf", "rm -f /", "format", "dd if=", "mkfs",
               "> /dev/", "shutdown", "reboot", "kill -9 1"]
    return not any(b in cmd for b in blocked)


def _extract_json(raw: str) -> str:
    """Extract JSON from markdown code blocks."""
    if "```" in raw:
        parts = raw.split("```")
        for part in parts:
            if part.startswith("json"):
                part = part[4:]
            stripped = part.strip()
            if stripped.startswith("{"):
                return stripped
    # Try to find { ... } directly
    match = re.search(r'\{.*\}', raw, re.DOTALL)
    if match:
        return match.group(0)
    return raw.strip()


# ── Log to DB ─────────────────────────────────────────────────────────────────

def log_error_event(text: str, classification: dict, fix: dict | None) -> None:
    """Store error event in synapses DB for brain-system awareness."""
    try:
        import sqlite3
        conn = sqlite3.connect(DB_PATH)
        conn.execute('''CREATE TABLE IF NOT EXISTS error_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT,
            source TEXT,
            category TEXT,
            severity TEXT,
            summary TEXT,
            original_text TEXT,
            fix_applied INTEGER,
            fix_confidence REAL
        )''')
        conn.execute('''INSERT INTO error_events
            (timestamp, source, category, severity, summary, original_text, fix_applied, fix_confidence)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)''', (
            datetime.now(timezone.utc).isoformat(),
            "telegram",
            classification.get("category", "unknown"),
            classification.get("severity", "MEDIUM"),
            classification.get("summary", ""),
            text[:500],
            1 if fix else 0,
            fix.get("confidence", 0.0) if fix else 0.0,
        ))
        conn.commit()
        conn.close()
    except Exception:
        pass  # Never block on logging failure


# ── Main entry ────────────────────────────────────────────────────────────────

def handle_note(text: str) -> str:
    """
    Main entry point. Takes any text note from Telegram.
    Returns a response string to send back.
    """
    # Step 1: Quick keyword check
    quick_cat = quick_classify(text)

    # Step 2: Full LLM classification
    classification = classify_with_llm(text)
    is_error  = classification.get("is_error", False)
    category  = classification.get("category", "general_note")
    severity  = classification.get("severity", "LOW")
    summary   = classification.get("summary", text[:80])
    fixable   = classification.get("fixable", False)

    if not is_error:
        return f"📝 Notiz gespeichert: _{summary}_"

    # Step 3: Generate fix
    fix = generate_fix(text, category) if fixable else None
    confidence = fix.get("confidence", 0.0) if fix else 0.0

    # Step 4: Try to apply fix
    fix_applied = False
    fix_result  = ""
    if fix and confidence >= 0.7:
        fix_applied, fix_result = apply_fix(fix)

    # Step 5: Log
    log_error_event(text, classification, fix)

    # Step 6: Build response
    sev_icon = {"CRITICAL": "🔴", "HIGH": "🟠", "MEDIUM": "🟡", "LOW": "🟢"}.get(severity, "⚪")
    lines = [
        f"{sev_icon} *Fehler erkannt* [{category}] — {severity}",
        f"_{summary}_",
        "",
    ]

    if fix:
        conf_pct = f"{confidence:.0%}"
        lines.append(f"🔧 *Fix gefunden* (Konfidenz: {conf_pct})")
        lines.append(f"_{fix.get('explanation', ''[:200])}_")
        lines.append("")

        if fix_applied:
            lines.append(f"✅ *Auto-Fix angewendet:*\n```\n{fix_result[:800]}\n```")
        else:
            if fix.get("manual_steps"):
                lines.append("📋 *Manuelle Schritte:*")
                for step in fix["manual_steps"][:5]:
                    lines.append(f"• {step}")
            if fix.get("commands"):
                lines.append("\n💻 *Commands (manuell ausfuehren):*")
                for cmd in fix["commands"][:3]:
                    lines.append(f"`{cmd}`")
    else:
        lines.append("ℹ️ Kein automatischer Fix moeglich — bitte manuell pruefen.")

    return "\n".join(lines)


# ── CLI ───────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Error Handler CLI")
    parser.add_argument("--text", type=str, help="Error text to analyze")
    parser.add_argument("--test", action="store_true", help="Run with a sample error")
    args = parser.parse_args()

    sample = (
        "Traceback (most recent call last):\n"
        "  File 'orchestrator.py', line 42, in run_brainstem\n"
        "    r = subprocess.run(['curl', ...], timeout=5)\n"
        "FileNotFoundError: [Errno 2] No such file or directory: 'curl'"
    )

    text = args.text if args.text else (sample if args.test else None)
    if not text:
        parser.print_help()
        sys.exit(0)

    print("Analysiere...\n")
    result = handle_note(text)
    print(result)
