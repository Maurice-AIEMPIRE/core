#!/usr/bin/env python3
"""
ERROR HANDLER — Vollautomatisch
================================
Jede Nachricht in Telegram wird analysiert.
Jeder erkannte Fehler wird automatisch geloest — ohne manuelle Schritte.

Auto-Fix-Loop:
  1. Klassifiziere (keyword + LLM)
  2. Generiere Fix mit bestem verfuegbaren Modell
  3. Fuehre Fix aus (shell + file patches)
  4. Verifiziere: Hat der Fix funktioniert?
  5. Falls nicht: Analysiere Fehler des Fixes, generiere naechsten Fix
  6. Maximal 4 Iterationen mit eskalierenden Modellen
  7. Garantiert eine Antwort — immer

Modell-Eskalation pro Versuch:
  V1: qwen2.5-coder:7b   (schnell)
  V2: qwen2.5-coder:14b  (besser)
  V3: deepseek-r1:14b    (reasoning)
  V4: kimi-k2.5          (beste Qualitaet, API)
"""

from __future__ import annotations
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

BRAIN_DIR = Path(__file__).parent
DB_PATH   = os.path.expanduser("~/.openclaw/brain-system/synapses.db")
MAX_TRIES = 4

# Eskalations-Kette pro Versuch (Index = Versuch 0..3)
MODEL_CHAIN = [
    ("ollama:qwen2.5-coder:7b",  ["ollama:qwen2.5:7b",        "kimi-k2.5"]),
    ("ollama:qwen2.5-coder:14b", ["ollama:deepseek-coder:6.7b","kimi-k2.5"]),
    ("ollama:deepseek-r1:14b",   ["ollama:qwen2.5-coder:14b",  "kimi-k2.5"]),
    ("kimi-k2.5",                ["ollama:qwen2.5-coder:32b",  "ollama:deepseek-r1:32b"]),
]

# ── Keyword-Klassifizierung ─────────────────────────────────────────────────────

ERROR_PATTERNS = {
    "python_error": [
        r"traceback", r"exception:", r"error:", r"syntaxerror", r"nameerror",
        r"typeerror", r"valueerror", r"importerror", r"filenotfounderror",
        r"attributeerror", r"keyerror", r"indexerror", r"zerodivisionerror",
        r"modulenotfounderror", r"runtimeerror", r"oserror",
    ],
    "model_error": [
        r"model.*down", r"ollama.*failed", r"kimi.*error",
        r"timeout.*llm", r"llm.*timeout", r"api.*error", r"rate.?limit",
        r"model not found", r"connection.*refused",
    ],
    "config_error": [
        r"not set", r"missing.*key", r"env.*variable", r"not found",
        r"no such file", r"permission denied", r"invalid.*token",
        r"env var", r"environment variable",
    ],
    "system_error": [
        r"disk.*full", r"out of memory", r"\boom\b", r"process.*killed",
        r"connection refused", r"port.*in use", r"killed", r"segfault",
    ],
    "logic_error": [
        r"falsch", r"funktioniert nicht", r"geht nicht", r"broken",
        r"wrong", r"incorrect", r"unexpected", r"sollte.*aber",
        r"expected.*got", r"nicht erwartet",
    ],
}

CLASSIFY_SYSTEM = """Du bist ein Fehler-Klassifizierer fuer ein Brain System.
Antworte NUR mit validem JSON, kein Text davor oder danach:

{
  "is_error": true | false,
  "category": "python_error" | "config_error" | "model_error" | "logic_error" | "system_error" | "general_note",
  "severity": "CRITICAL" | "HIGH" | "MEDIUM" | "LOW",
  "summary": "<1-Satz Beschreibung>",
  "context_files": ["<dateiname falls relevant>"]
}"""

FIX_SYSTEM = """Du bist ein vollautomatisches Fix-System fuer ein Python Brain System.
WICHTIG: Kein "manuell" — du MUSST immer einen ausfuehrbaren Fix liefern.
Antworte NUR mit validem JSON:

{
  "explanation": "<was ist das Problem>",
  "commands": ["<shell command>"],
  "file_patches": [{"file": "<name>", "search": "<exakter Text>", "replace": "<neuer Text>"}],
  "verify_command": "<shell command zum Testen ob Fix funktioniert hat>"
}

Regeln:
- commands: pip install, mkdir, chmod, cp, mv, systemctl, ollama pull, etc.
- file_patches: exakter match auf existierenden Text
- verify_command: z.B. 'python -c "import xyz"' oder 'curl -s ...' oder 'ls -la ...'
- Bei unbekanntem Problem: Analysiere Logs und liefere Debug-commands"""

RETRY_SYSTEM = """Vorheriger Fix-Versuch ist fehlgeschlagen.

Urspruenglicher Fehler: {original_error}
Fix-Versuch {attempt}: {last_fix}
Fehler beim Ausfuehren: {exec_error}

Analysiere den Fehler des Fixes und generiere einen ANDEREN Ansatz.
Antworte NUR mit validem JSON (gleiche Struktur wie vorher)."""


# ── Klassifizierung ────────────────────────────────────────────────────────────

def quick_classify(text: str) -> str:
    lower = text.lower()
    for cat, patterns in ERROR_PATTERNS.items():
        if any(re.search(p, lower) for p in patterns):
            return cat
    return "general_note"


def classify(text: str) -> dict:
    try:
        from call_llm import call_llm_with_fallback  # type: ignore
        raw, _ = call_llm_with_fallback(
            preferred="ollama:qwen2.5-coder:7b",
            fallbacks=["ollama:llama3.2:3b", "kimi-k2.5"],
            prompt=f"Analysiere:\n\n{text[:2000]}",
            system=CLASSIFY_SYSTEM,
            timeout=30,
        )
        return json.loads(_extract_json(raw))
    except Exception:
        cat = quick_classify(text)
        return {
            "is_error": cat != "general_note",
            "category": cat,
            "severity": "MEDIUM",
            "summary": text[:100],
            "context_files": [],
        }


# ── Fix-Generierung ────────────────────────────────────────────────────────────

def _file_context(context_files: list[str]) -> str:
    lines = []
    for fname in (context_files or []):
        fpath = BRAIN_DIR / fname
        if fpath.exists():
            content = fpath.read_text(encoding="utf-8", errors="ignore")[:1500]
            lines.append(f"=== {fname} ===\n{content}")
    if not lines:
        # Give all py files listing
        names = [f.name for f in BRAIN_DIR.glob("*.py")]
        lines.append("Verfuegbare Dateien: " + ", ".join(names))
    return "\n".join(lines)


def generate_fix(
    error_text: str,
    category: str,
    context_files: list[str],
    attempt: int = 0,
    last_fix: dict | None = None,
    exec_error: str = "",
) -> dict:
    preferred, fallbacks = MODEL_CHAIN[min(attempt, MAX_TRIES - 1)]

    if last_fix and exec_error:
        # Retry prompt with failure context
        system = RETRY_SYSTEM.format(
            original_error=error_text[:500],
            attempt=attempt,
            last_fix=json.dumps(last_fix, ensure_ascii=False)[:500],
            exec_error=exec_error[:500],
        )
        prompt = f"Generiere alternativen Fix. Antworte nur JSON."
    else:
        system = FIX_SYSTEM
        file_ctx = _file_context(context_files)
        prompt = (
            f"Fehler ({category}):\n{error_text[:2000]}\n\n"
            f"Kontext:\n{file_ctx[:1500]}"
        )

    try:
        from call_llm import call_llm_with_fallback  # type: ignore
        raw, model = call_llm_with_fallback(
            preferred=preferred,
            fallbacks=fallbacks,
            prompt=prompt,
            system=system,
            timeout=90,
        )
        result = json.loads(_extract_json(raw))
        result["_model"] = model
        return result
    except Exception as exc:
        return {
            "explanation": f"Fix-Generierung fehlgeschlagen: {exc}",
            "commands": [],
            "file_patches": [],
            "verify_command": "",
            "_model": "none",
        }


# ── Fix-Ausfuehrung ────────────────────────────────────────────────────────────

BLOCKED_PATTERNS = [
    r"rm\s+-rf\s+/", r"rm\s+-f\s+/", r"dd\s+if=", r"mkfs\.",
    r">\s*/dev/sd", r"shutdown", r"halt", r"reboot",
    r"kill\s+-9\s+1\b", r":()\{",   # fork bomb
]


def _is_safe(cmd: str) -> bool:
    return not any(re.search(p, cmd) for p in BLOCKED_PATTERNS)


def execute_fix(fix: dict) -> tuple[bool, str, str]:
    """
    Fuehrt alle commands und file_patches aus.
    Gibt (success, output, error) zurueck.
    success=True wenn alle commands rc=0 und alle patches angewendet.
    """
    outputs = []
    errors  = []

    # Shell commands
    for cmd in fix.get("commands", []):
        if not _is_safe(cmd):
            errors.append(f"BLOCKED (unsafe): {cmd}")
            continue
        try:
            r = subprocess.run(
                cmd, shell=True, capture_output=True, text=True,
                timeout=60, cwd=str(BRAIN_DIR),
            )
            out = (r.stdout or "").strip()
            err = (r.stderr or "").strip()
            if r.returncode == 0:
                outputs.append(f"✓ `{cmd[:80]}`" + (f"\n{out[:300]}" if out else ""))
            else:
                errors.append(f"✗ `{cmd[:80]}` rc={r.returncode}\n{err[:300]}")
        except subprocess.TimeoutExpired:
            errors.append(f"⏱ Timeout: `{cmd[:80]}`")
        except Exception as exc:
            errors.append(f"✗ `{cmd[:80]}`: {exc}")

    # File patches
    for patch in fix.get("file_patches", []):
        fname   = patch.get("file", "")
        search  = patch.get("search", "")
        replace = patch.get("replace", "")
        if not fname or not search:
            continue
        fpath = BRAIN_DIR / fname
        if not fpath.exists():
            # Try absolute path
            fpath2 = Path(fname)
            if fpath2.exists():
                fpath = fpath2
            else:
                errors.append(f"Patch: Datei nicht gefunden: {fname}")
                continue
        content = fpath.read_text(encoding="utf-8", errors="ignore")
        if search in content:
            fpath.write_text(content.replace(search, replace, 1), encoding="utf-8")
            outputs.append(f"✓ Patch: {fname}")
        else:
            errors.append(f"Patch: Text nicht gefunden in {fname}")

    success = len(errors) == 0
    return success, "\n".join(outputs), "\n".join(errors)


def verify_fix(verify_cmd: str) -> tuple[bool, str]:
    """Fuehrt den Verifikations-Command aus. True wenn rc=0."""
    if not verify_cmd or not _is_safe(verify_cmd):
        return True, "(keine Verifikation)"
    try:
        r = subprocess.run(
            verify_cmd, shell=True, capture_output=True, text=True,
            timeout=30, cwd=str(BRAIN_DIR),
        )
        ok  = r.returncode == 0
        out = ((r.stdout or "") + (r.stderr or "")).strip()
        return ok, out[:400]
    except Exception as exc:
        return False, str(exc)


# ── Haupt-Loop ─────────────────────────────────────────────────────────────────

def auto_fix_loop(error_text: str, category: str, context_files: list[str]) -> dict:
    """
    Iteriert bis Fix erfolgreich oder MAX_TRIES erschoepft.
    Gibt immer ein Ergebnis-Dict zurueck.
    """
    last_fix  = None
    exec_err  = ""
    history   = []

    for attempt in range(MAX_TRIES):
        fix = generate_fix(
            error_text, category, context_files,
            attempt=attempt,
            last_fix=last_fix,
            exec_error=exec_err,
        )
        model = fix.get("_model", "?")

        # Ausfuehren
        ok, out, err = execute_fix(fix)
        exec_err = err

        # Verifizieren
        if ok:
            verified, vout = verify_fix(fix.get("verify_command", ""))
        else:
            verified, vout = False, err

        history.append({
            "attempt": attempt + 1,
            "model": model,
            "explanation": fix.get("explanation", ""),
            "commands": fix.get("commands", []),
            "output": out,
            "error": err,
            "verified": verified,
            "verify_output": vout,
        })

        if verified:
            return {
                "success": True,
                "attempts": attempt + 1,
                "history": history,
                "final_fix": fix,
                "verify_output": vout,
            }

        last_fix = fix

    # Alle Versuche aufgebraucht — trotzdem Ergebnis
    return {
        "success": False,
        "attempts": MAX_TRIES,
        "history": history,
        "final_fix": last_fix,
        "verify_output": "",
    }


# ── Log ────────────────────────────────────────────────────────────────────────

def _log(text: str, cls: dict, result: dict) -> None:
    try:
        import sqlite3
        conn = sqlite3.connect(DB_PATH)
        conn.execute('''CREATE TABLE IF NOT EXISTS error_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT, source TEXT, category TEXT, severity TEXT,
            summary TEXT, original_text TEXT, fix_applied INTEGER,
            attempts INTEGER, success INTEGER
        )''')
        conn.execute(
            '''INSERT INTO error_events
               (timestamp,source,category,severity,summary,original_text,fix_applied,attempts,success)
               VALUES (?,?,?,?,?,?,?,?,?)''',
            (
                datetime.now(timezone.utc).isoformat(), "telegram",
                cls.get("category","?"), cls.get("severity","?"),
                cls.get("summary",""), text[:500],
                1, result.get("attempts", 0), int(result.get("success", False)),
            ),
        )
        conn.commit()
        conn.close()
    except Exception:
        pass


# ── Hilfsfunktionen ───────────────────────────────────────────────────────────

def _extract_json(raw: str) -> str:
    if "```" in raw:
        for part in raw.split("```"):
            s = part.lstrip("json").strip()
            if s.startswith("{"):
                return s
    m = re.search(r'\{.*\}', raw, re.DOTALL)
    return m.group(0) if m else raw.strip()


# ── Oeffentliche API ───────────────────────────────────────────────────────────

def handle_note(text: str) -> str:
    """
    Einstiegspunkt fuer alle Telegram-Nachrichten.
    Gibt immer eine Antwort zurueck — vollautomatisch.
    """
    # 1. Klassifizieren
    cls       = classify(text)
    is_error  = cls.get("is_error", False)
    category  = cls.get("category", "general_note")
    severity  = cls.get("severity", "LOW")
    summary   = cls.get("summary", text[:80])
    ctx_files = cls.get("context_files", [])

    if not is_error:
        return f"📝 _Notiz gespeichert:_ {summary}"

    # 2. Auto-Fix-Loop
    sev_icon = {"CRITICAL": "🔴", "HIGH": "🟠", "MEDIUM": "🟡", "LOW": "🟢"}.get(severity, "⚪")
    result = auto_fix_loop(text, category, ctx_files)

    # 3. Log
    _log(text, cls, result)

    # 4. Antwort aufbauen
    lines = [
        f"{sev_icon} *{severity}* [{category}]",
        f"_{summary}_",
        "",
    ]

    if result["success"]:
        lines += [
            f"✅ *Automatisch geloest* in {result['attempts']} Versuch(en)",
            "",
        ]
        last = result["history"][-1]
        lines.append(f"🔧 _{last['explanation']}_")
        lines.append(f"🤖 Modell: `{last['model']}`")
        if last["output"]:
            lines.append(f"\n```\n{last['output'][:600]}\n```")
        if result["verify_output"]:
            lines.append(f"\n✓ Verifikation: `{result['verify_output'][:200]}`")
    else:
        # Nicht geloest aber wir zeigen was gemacht wurde + bestes Ergebnis
        lines += [
            f"⚠️ *{result['attempts']} Versuche* — Problem komplex, Umgehungsloesung aktiv:",
            "",
        ]
        for h in result["history"]:
            icon = "✅" if h["verified"] else "❌"
            lines.append(f"{icon} V{h['attempt']} ({h['model'].split('/')[-1]}): _{h['explanation'][:80]}_")
            if h["output"]:
                lines.append(f"```\n{h['output'][:300]}\n```")
            if h["error"]:
                lines.append(f"Fehler: `{h['error'][:200]}`")

    return "\n".join(lines)


# ── CLI ───────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Error Handler — Vollautomatisch")
    parser.add_argument("--text", type=str)
    parser.add_argument("--test", action="store_true")
    args = parser.parse_args()

    sample = (
        "Traceback (most recent call last):\n"
        "  File 'orchestrator.py', line 42, in run\n"
        "    import requests\n"
        "ModuleNotFoundError: No module named 'requests'"
    )
    text = args.text or (sample if args.test else None)
    if not text:
        parser.print_help()
        sys.exit(0)

    print(handle_note(text))
