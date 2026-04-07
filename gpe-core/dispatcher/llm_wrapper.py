#!/usr/bin/env python3
"""
GPE-Core LLM Wrapper v2
Fixes & Improvements:
  - Claude Modell aktualisiert auf claude-sonnet-4-6 (aktuelles Modell)
  - Anthropic SDK statt raw requests (offiziell, robuster)
  - Retry-Logik mit exponential backoff
  - Timeout erhöht auf 120s (AI braucht Zeit)
  - Streaming-Support
  - Token-Usage Tracking
  - Ollama /api/chat statt /api/generate (stabiler für Multi-Turn)
"""
import os
import json
import time
import logging
from pathlib import Path
from typing import Generator

import requests

logger = logging.getLogger(__name__)

OLLAMA_URL     = os.getenv("OLLAMA_URL",      "http://localhost:11434")
CLAUDE_API_KEY = os.getenv("CLAUDE_API_KEY",  "")
DEFAULT_MODEL  = os.getenv("GPE_DEFAULT_MODEL", "gemma4:latest")

# Aktuelles Claude-Modell (Stand 2026-04)
CLAUDE_MODEL   = "claude-sonnet-4-6"

MAX_RETRIES    = 3
RETRY_BASE_SEC = 2.0   # exponential: 2, 4, 8 Sekunden
TIMEOUT_SEC    = 120   # erhöht von 60 auf 120s


class LLMWrapper:

    def __init__(self):
        self._usage: dict[str, int] = {"prompt_tokens": 0, "completion_tokens": 0}

        # Anthropic SDK — nur laden wenn Key vorhanden
        self._anthropic_client = None
        if CLAUDE_API_KEY:
            try:
                import anthropic
                self._anthropic_client = anthropic.Anthropic(api_key=CLAUDE_API_KEY)
            except ImportError:
                logger.warning("anthropic package fehlt — pip install anthropic")

    # ------------------------------------------------------------------ #
    #  Ollama                                                              #
    # ------------------------------------------------------------------ #

    def query_ollama(
        self,
        prompt: str,
        model: str | None = None,
        stream: bool = False,
        system: str | None = None,
    ) -> str:
        """
        Ollama-Query via /api/chat (besser als /api/generate für Agents).
        Unterstützt streaming und retry.
        """
        model    = model or DEFAULT_MODEL
        messages = []
        if system:
            messages.append({"role": "system", "content": system})
        messages.append({"role": "user", "content": prompt})

        payload = {
            "model":    model,
            "messages": messages,
            "stream":   stream,
        }

        for attempt in range(MAX_RETRIES):
            try:
                resp = requests.post(
                    f"{OLLAMA_URL}/api/chat",
                    json=payload,
                    timeout=TIMEOUT_SEC,
                    stream=stream,
                )
                resp.raise_for_status()

                if stream:
                    return self._consume_ollama_stream(resp)

                data = resp.json()
                content = data.get("message", {}).get("content", "")
                # Token-Tracking
                if "prompt_eval_count" in data:
                    self._usage["prompt_tokens"]     += data.get("prompt_eval_count", 0)
                    self._usage["completion_tokens"] += data.get("eval_count", 0)
                return content

            except requests.exceptions.Timeout:
                wait = RETRY_BASE_SEC * (2 ** attempt)
                logger.warning(f"Ollama Timeout (Versuch {attempt+1}/{MAX_RETRIES}) — warte {wait}s")
                if attempt < MAX_RETRIES - 1:
                    time.sleep(wait)
            except requests.exceptions.ConnectionError:
                logger.error("Ollama nicht erreichbar — läuft 'systemctl status ollama'?")
                return "[Ollama] Verbindung fehlgeschlagen"
            except Exception as e:
                logger.error(f"Ollama Fehler: {e}")
                return f"[Ollama Error] {e}"

        return "[Ollama] Alle Versuche fehlgeschlagen"

    def _consume_ollama_stream(self, response: requests.Response) -> str:
        """Liest Ollama-Stream und gibt vollständige Antwort zurück."""
        parts = []
        for line in response.iter_lines():
            if not line:
                continue
            try:
                chunk = json.loads(line)
                parts.append(chunk.get("message", {}).get("content", ""))
                if chunk.get("done"):
                    break
            except json.JSONDecodeError:
                continue
        return "".join(parts)

    def stream_ollama(
        self, prompt: str, model: str | None = None, system: str | None = None
    ) -> Generator[str, None, None]:
        """Yields Ollama-Antwort Token für Token (für Live-Output)."""
        model    = model or DEFAULT_MODEL
        messages = []
        if system:
            messages.append({"role": "system", "content": system})
        messages.append({"role": "user", "content": prompt})

        try:
            resp = requests.post(
                f"{OLLAMA_URL}/api/chat",
                json={"model": model, "messages": messages, "stream": True},
                timeout=TIMEOUT_SEC,
                stream=True,
            )
            resp.raise_for_status()
            for line in resp.iter_lines():
                if not line:
                    continue
                chunk = json.loads(line)
                token = chunk.get("message", {}).get("content", "")
                if token:
                    yield token
                if chunk.get("done"):
                    break
        except Exception as e:
            yield f"[Stream Error] {e}"

    # ------------------------------------------------------------------ #
    #  Claude                                                              #
    # ------------------------------------------------------------------ #

    def query_claude(
        self,
        prompt: str,
        model: str = CLAUDE_MODEL,
        max_tokens: int = 4096,
        system: str | None = None,
    ) -> str:
        """
        Claude-Query via offiziellem Anthropic SDK.
        Modell: claude-sonnet-4-6 (aktuell, 2026-04)
        """
        if not self._anthropic_client:
            if not CLAUDE_API_KEY:
                return "[Claude] CLAUDE_API_KEY nicht gesetzt"
            return "[Claude] anthropic package fehlt — pip install anthropic"

        for attempt in range(MAX_RETRIES):
            try:
                kwargs: dict = {
                    "model":      model,
                    "max_tokens": max_tokens,
                    "messages":   [{"role": "user", "content": prompt}],
                }
                if system:
                    kwargs["system"] = system

                msg = self._anthropic_client.messages.create(**kwargs)

                # Token-Tracking
                self._usage["prompt_tokens"]     += msg.usage.input_tokens
                self._usage["completion_tokens"] += msg.usage.output_tokens

                return msg.content[0].text

            except Exception as e:
                err_name = type(e).__name__
                # Rate-Limit oder temporärer Fehler → retry
                if "rate" in err_name.lower() or "overloaded" in str(e).lower():
                    wait = RETRY_BASE_SEC * (2 ** attempt)
                    logger.warning(f"Claude {err_name} (Versuch {attempt+1}) — warte {wait}s")
                    if attempt < MAX_RETRIES - 1:
                        time.sleep(wait)
                        continue
                logger.error(f"Claude Fehler: {e}")
                return f"[Claude Error] {e}"

        return "[Claude] Alle Versuche fehlgeschlagen"

    # ------------------------------------------------------------------ #
    #  Smart Routing                                                       #
    # ------------------------------------------------------------------ #

    def route_query(
        self,
        prompt: str,
        prefer: str | None = None,
        system: str | None = None,
    ) -> str:
        """
        Routet Query intelligent:
        - 'ollama'  → direkt Ollama
        - 'claude'  → direkt Claude
        - None      → Ollama zuerst, bei Fehler Claude fallback
        """
        if prefer == "claude":
            return self.query_claude(prompt, system=system)
        if prefer == "ollama":
            return self.query_ollama(prompt, system=system)

        # Default: Ollama → Claude fallback
        result = self.query_ollama(prompt, system=system)
        if "[Error]" in result or "[Fehler]" in result:
            logger.info("Ollama Fehler — Fallback zu Claude")
            return self.query_claude(prompt, system=system)
        return result

    # ------------------------------------------------------------------ #
    #  Utils                                                               #
    # ------------------------------------------------------------------ #

    def list_ollama_models(self) -> list[str]:
        """Gibt verfügbare Ollama-Modelle zurück."""
        try:
            resp = requests.get(f"{OLLAMA_URL}/api/tags", timeout=10)
            resp.raise_for_status()
            return [m["name"] for m in resp.json().get("models", [])]
        except Exception:
            return []

    def get_status(self) -> dict:
        """Systemstatus + Token-Usage."""
        models = self.list_ollama_models()
        return {
            "ollama_url":        OLLAMA_URL,
            "ollama_reachable":  bool(models),
            "ollama_models":     models,
            "claude_configured": bool(CLAUDE_API_KEY),
            "claude_model":      CLAUDE_MODEL,
            "default_model":     DEFAULT_MODEL,
            "token_usage":       self._usage,
        }

    def get_usage(self) -> dict[str, int]:
        return self._usage.copy()


if __name__ == "__main__":
    wrapper = LLMWrapper()
    status  = wrapper.get_status()
    print(f"[LLMWrapper] Status:\n{json.dumps(status, indent=2)}")

    if status["ollama_reachable"]:
        print("\n[Test] Ollama Query...")
        result = wrapper.query_ollama("Antworte mit 'OK'")
        print(f"Antwort: {result}")
