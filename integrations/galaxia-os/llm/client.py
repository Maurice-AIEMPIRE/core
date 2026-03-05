"""LLM Client - Routes requests through LiteLLM to Ollama/OpenAI."""

from __future__ import annotations

import json
import logging
from typing import Any

import litellm

logger = logging.getLogger("galaxia.llm")


class LLMClient:
    """Unified LLM client that routes through LiteLLM proxy."""

    def __init__(
        self,
        litellm_url: str = "http://localhost:4000",
        api_key: str = "sk-galaxia-local",
        default_model: str = "ollama/qwen3:14b",
    ):
        self._base_url = litellm_url
        self._api_key = api_key
        self._default_model = default_model
        litellm.api_base = litellm_url
        litellm.drop_params = True

    async def complete(
        self,
        prompt: str,
        model: str | None = None,
        system: str | None = None,
        temperature: float = 0.7,
        max_tokens: int = 2048,
    ) -> str:
        model = model or self._default_model
        messages: list[dict[str, str]] = []

        if system:
            messages.append({"role": "system", "content": system})
        messages.append({"role": "user", "content": prompt})

        return await self.chat(messages, model=model, temperature=temperature, max_tokens=max_tokens)

    async def chat(
        self,
        messages: list[dict[str, str]],
        model: str | None = None,
        temperature: float = 0.7,
        max_tokens: int = 2048,
    ) -> str:
        model = model or self._default_model

        try:
            response = await litellm.acompletion(
                model=model,
                messages=messages,
                temperature=temperature,
                max_tokens=max_tokens,
                api_base=self._base_url,
                api_key=self._api_key,
                timeout=300,
            )
            content = response.choices[0].message.content
            logger.debug("LLM response (%s): %s chars", model, len(content))
            return content

        except Exception:
            logger.exception("LLM call failed (model=%s)", model)
            raise

    async def plan_task(self, task_description: str) -> list[dict[str, str]]:
        """Use LLM to break a task into subtasks."""
        system = (
            "Du bist ein Task-Planner. Zerlege die Aufgabe in 2-5 konkrete Schritte. "
            "Antworte als JSON-Array: [{\"title\": \"...\", \"description\": \"...\"}]"
            "Nur das JSON, kein Markdown, keine Erklärung."
        )
        response = await self.complete(
            prompt=f"Aufgabe: {task_description}",
            system=system,
            temperature=0.3,
        )


        try:
            # Strip markdown code fences if present
            text = response.strip()
            if text.startswith("```"):
                text = text.split("\n", 1)[1].rsplit("```", 1)[0]
            return json.loads(text)
        except json.JSONDecodeError:
            logger.warning("Could not parse planner response as JSON")
            return [{"title": task_description, "description": response}]

    async def evaluate_result(self, task: str, result: str) -> dict[str, Any]:
        """Use LLM as Critic to evaluate task result."""
        system = (
            "Du bist ein Qualitäts-Reviewer. Bewerte das Ergebnis der Aufgabe. "
            "Antworte als JSON: {\"score\": 1-10, \"feedback\": \"...\", \"approved\": true/false}"
            "Nur das JSON."
        )
        response = await self.complete(
            prompt=f"Aufgabe: {task}\n\nErgebnis:\n{result}",
            system=system,
            temperature=0.2,
        )


        try:
            text = response.strip()
            if text.startswith("```"):
                text = text.split("\n", 1)[1].rsplit("```", 1)[0]
            return json.loads(text)
        except json.JSONDecodeError:
            return {"score": 5, "feedback": response, "approved": True}
