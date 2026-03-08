#!/usr/bin/env python3
"""
CALL LLM — Universal LLM Router
================================
Ruft Ollama (lokal) oder Kimi K2.5 (API) auf.
Trackt Fehlerrate und wechselt automatisch bei > 10%.

Unterstuetzte Modelle:
  - ollama:<model>   z.B. "ollama:qwen2.5-coder:7b"
  - kimi-k2.5        Moonshot AI API
  - kimi-k1.5        Moonshot AI (Fallback)
"""

import json
import os
import sqlite3
import urllib.error
import urllib.request
from datetime import datetime, timezone

# ── Konfiguration ────────────────────────────────────────────────────────────

OLLAMA_BASE   = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
KIMI_API_KEY  = os.getenv("MOONSHOT_API_KEY", "")
KIMI_BASE     = "https://api.moonshot.cn/v1"
KIMI_MODELS   = {
    "kimi-k2.5": "moonshot-v1-128k",
    "kimi-k1.5": "moonshot-v1-32k",
}

DB_PATH = os.path.expanduser("~/.openclaw/brain-system/synapses.db")

ERROR_THRESHOLD = 0.10   # 10 %
MIN_SAMPLES     = 5      # Mindestanzahl Calls bevor Fallback greift
TRACK_LAST_N    = 50     # Nur letzte N Calls bewerten

# ── Error Tracking ───────────────────────────────────────────────────────────

def _get_conn() -> sqlite3.Connection:
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute('''CREATE TABLE IF NOT EXISTS model_errors (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp  TEXT,
        model      TEXT,
        success    INTEGER
    )''')
    conn.commit()
    return conn


def track_model_call(model: str, success: bool) -> None:
    """Schreibt Erfolg/Fehler eines Modell-Calls in die DB."""
    conn = _get_conn()
    conn.execute(
        'INSERT INTO model_errors (timestamp, model, success) VALUES (?, ?, ?)',
        (datetime.now(timezone.utc).isoformat(), model, 1 if success else 0),
    )
    conn.commit()
    conn.close()


def get_error_rate(model: str) -> float:
    """Gibt Fehlerrate 0.0–1.0 fuer die letzten N Calls zurueck."""
    conn = _get_conn()
    rows = conn.execute(
        'SELECT success FROM model_errors WHERE model = ? ORDER BY id DESC LIMIT ?',
        (model, TRACK_LAST_N),
    ).fetchall()
    conn.close()
    if len(rows) < MIN_SAMPLES:
        return 0.0
    errors = sum(1 for r in rows if r[0] == 0)
    return errors / len(rows)


def select_model(preferred: str, fallbacks: list[str]) -> str:
    """
    Gibt das erste Modell mit Fehlerrate < 10% zurueck.
    Fallback-Kette: preferred → fallbacks[0] → fallbacks[1] → ...
    """
    for model in [preferred] + fallbacks:
        rate = get_error_rate(model)
        if rate < ERROR_THRESHOLD:
            if model != preferred:
                print(f"⚠️  [{preferred}] Fehlerrate {rate:.0%} > 10% → Fallback: {model}")
            return model
    last = fallbacks[-1] if fallbacks else preferred
    print(f"🔴 Alle Modelle >{ERROR_THRESHOLD:.0%} Fehlerrate — Notfall-Fallback: {last}")
    return last


# ── Ollama ───────────────────────────────────────────────────────────────────

def _call_ollama(model_tag: str, prompt: str, system: str = "", timeout: int = 120) -> str:
    """
    Ruft Ollama REST API auf.
    model_tag: alles nach 'ollama:' z.B. 'qwen2.5-coder:7b'
    """
    url = f"{OLLAMA_BASE}/api/generate"
    payload = {
        "model": model_tag,
        "prompt": prompt,
        "stream": False,
    }
    if system:
        payload["system"] = system

    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req  = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        result = json.loads(resp.read().decode())
    return result.get("response", "").strip()


# ── Kimi (Moonshot) ──────────────────────────────────────────────────────────

def _call_kimi(model_key: str, prompt: str, system: str = "", timeout: int = 120) -> str:
    """
    Ruft Moonshot AI (Kimi) Chat Completions auf.
    model_key: 'kimi-k2.5' oder 'kimi-k1.5'
    """
    if not KIMI_API_KEY:
        raise RuntimeError("MOONSHOT_API_KEY nicht gesetzt.")

    moonshot_model = KIMI_MODELS.get(model_key, "moonshot-v1-128k")
    url = f"{KIMI_BASE}/chat/completions"

    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})

    payload = {
        "model": moonshot_model,
        "messages": messages,
        "temperature": 0.3,
    }

    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req  = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type":  "application/json",
            "Authorization": f"Bearer {KIMI_API_KEY}",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        result = json.loads(resp.read().decode())
    return result["choices"][0]["message"]["content"].strip()


# ── Haupt-Interface ──────────────────────────────────────────────────────────

def call_llm(
    model: str,
    prompt: str,
    system: str = "",
    timeout: int = 120,
) -> str:
    """
    Universeller LLM-Call mit automatischem Error-Tracking.

    Args:
        model:   Modellname, z.B. "kimi-k2.5" oder "ollama:qwen2.5-coder:7b"
        prompt:  User-Prompt
        system:  System-Prompt (optional)
        timeout: Timeout in Sekunden

    Returns:
        Antwort als String

    Raises:
        RuntimeError: wenn der Call fehlschlaegt (wird getrackt)
    """
    try:
        if model.startswith("ollama:"):
            tag    = model[len("ollama:"):]
            result = _call_ollama(tag, prompt, system, timeout)
        elif model in KIMI_MODELS:
            result = _call_kimi(model, prompt, system, timeout)
        else:
            raise ValueError(f"Unbekanntes Modell: '{model}'")

        track_model_call(model, success=True)
        return result

    except Exception as exc:
        track_model_call(model, success=False)
        raise RuntimeError(f"[{model}] LLM-Call fehlgeschlagen: {exc}") from exc


def call_llm_with_fallback(
    preferred: str,
    fallbacks: list[str],
    prompt: str,
    system: str = "",
    timeout: int = 120,
) -> tuple[str, str]:
    """
    Wie call_llm(), aber mit automatischer Fehlerrate-Pruefung und Fallback.

    Returns:
        (antwort, genutztes_modell)

    Example:
        text, model_used = call_llm_with_fallback(
            preferred="kimi-k2.5",
            fallbacks=["ollama:qwen2.5-coder:7b"],
            prompt="Schreibe einen LinkedIn-Post ueber AI.",
            system="Du bist ein Marketing-Experte.",
        )
    """
    model = select_model(preferred, fallbacks)
    result = call_llm(model, prompt, system, timeout)
    return result, model


# ── CLI (Quick-Test) ─────────────────────────────────────────────────────────

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="LLM Router — Quick Test")
    parser.add_argument("--model",   default="ollama:qwen2.5-coder:7b")
    parser.add_argument("--prompt",  default="Sage 'Hallo' auf Deutsch.")
    parser.add_argument("--system",  default="")
    parser.add_argument("--rates",   action="store_true", help="Fehlerraten anzeigen")
    args = parser.parse_args()

    if args.rates:
        models = ["kimi-k2.5", "kimi-k1.5",
                  "ollama:qwen2.5-coder:7b", "ollama:llama3.2:3b"]
        print("Fehlerraten (letzte 50 Calls):\n")
        for m in models:
            rate = get_error_rate(m)
            bar  = "█" * int(rate * 20) + "░" * (20 - int(rate * 20))
            flag = " ⚠️ > 10%" if rate >= ERROR_THRESHOLD else ""
            print(f"  {m:<35} {rate:5.1%}  [{bar}]{flag}")
    else:
        print(f"Modell:  {args.model}")
        print(f"Prompt:  {args.prompt}\n")
        try:
            answer = call_llm(args.model, args.prompt, args.system)
            print(f"Antwort: {answer}")
        except RuntimeError as e:
            print(f"Fehler:  {e}")
