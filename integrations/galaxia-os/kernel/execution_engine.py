"""Execution Engine - Runs tasks with retry, tool-calling, and memory integration."""

from __future__ import annotations

import asyncio
import json
import logging
import re
import time
from typing import Any

from llm.client import LLMClient
from memory.memory import MemorySystem
from shared.models import Task, TaskStatus
from tools.tool_manager import ToolManager, ToolResult

logger = logging.getLogger("galaxia.engine")

MAX_RETRIES = 3
RETRY_DELAYS = [2, 5, 10]  # seconds
MAX_TOOL_CALLS_PER_TASK = 5


class ExecutionEngine:
    """Executes tasks with LLM, tools, memory, and retry logic."""

    def __init__(
        self,
        llm: LLMClient,
        memory: MemorySystem,
        tools: ToolManager,
    ):
        self._llm = llm
        self._memory = memory
        self._tools = tools

    async def run(self, task: Task, agent_id: str) -> str:
        """Execute a task with full engine support."""
        start = time.time()

        # Log task start
        await self._memory.log_task(task.id, "started", {
            "agent": agent_id,
            "title": task.title,
        })

        # Load agent context
        context = await self._memory.get_context(agent_id)

        # Build system prompt with available tools
        tool_list = self._tools.list_for_llm()
        system = (
            "Du bist ein Agent im Pfeifer Galaxia OS.\n"
            "Führe die Aufgabe aus. Du kannst Tools verwenden.\n\n"
            f"Verfügbare Tools:\n{tool_list}\n\n"
            "Um ein Tool zu verwenden, schreibe: [TOOL:name(param=value)]\n"
            "Beispiel: [TOOL:docker_ps()]\n"
            "Beispiel: [TOOL:shell(command=ls -la)]\n\n"
            "Wenn du kein Tool brauchst, antworte direkt."
        )

        # Build messages
        messages = [{"role": "system", "content": system}]
        messages.extend(context)
        messages.append({"role": "user", "content": f"Aufgabe: {task.title}\n\n{task.description}"})

        # Execute with retry
        result = await self._execute_with_retry(task, agent_id, messages)

        # Log completion
        duration = time.time() - start
        await self._memory.log_task(task.id, "completed", {
            "agent": agent_id,
            "duration_s": round(duration, 2),
            "result_length": len(result),
        })

        # Store in agent context
        await self._memory.add_context(agent_id, "user", task.title)
        await self._memory.add_context(agent_id, "assistant", result[:500])

        return result

    async def _execute_with_retry(
        self, task: Task, agent_id: str, messages: list[dict]
    ) -> str:
        """Execute with exponential backoff retry."""
        last_error = None

        for attempt in range(MAX_RETRIES):
            try:
                result = await self._llm.chat(messages)

                # Check for tool calls in the response
                result = await self._process_tool_calls(result, messages, task.id)

                return result

            except Exception as e:
                last_error = e
                if attempt < MAX_RETRIES - 1:
                    delay = RETRY_DELAYS[attempt]
                    logger.warning(
                        "Task %s attempt %d failed: %s. Retrying in %ds...",
                        task.id, attempt + 1, e, delay,
                    )
                    await self._memory.log_task(task.id, "retry", {
                        "attempt": attempt + 1,
                        "error": str(e),
                        "delay": delay,
                    })
                    await asyncio.sleep(delay)

        error_msg = f"Task failed after {MAX_RETRIES} attempts: {last_error}"
        await self._memory.log_task(task.id, "failed", {"error": error_msg})
        raise RuntimeError(error_msg)

    async def _process_tool_calls(
        self, response: str, messages: list[dict], task_id: str
    ) -> str:
        """Parse and execute tool calls from LLM response."""
        tool_pattern = r'\[TOOL:(\w+)\((.*?)\)\]'
        tool_calls_made = 0

        while re.search(tool_pattern, response) and tool_calls_made < MAX_TOOL_CALLS_PER_TASK:
            match = re.search(tool_pattern, response)
            if not match:
                break

            tool_name = match.group(1)
            params_str = match.group(2)
            tool_calls_made += 1

            # Parse parameters
            kwargs = self._parse_tool_params(params_str)

            logger.info("Tool call: %s(%s) for task %s", tool_name, kwargs, task_id)
            await self._memory.log_task(task_id, "tool_call", {
                "tool": tool_name,
                "params": kwargs,
            })

            # Execute tool
            result = await self._tools.execute(tool_name, **kwargs)

            # Replace tool call with result in response
            tool_output = f"\n[Tool {tool_name} result: {'OK' if result.success else 'FAIL'}]\n{result.output or result.error}\n"
            response = response[:match.start()] + tool_output + response[match.end():]

            # Add tool result to conversation and get follow-up
            messages.append({"role": "assistant", "content": response})
            messages.append({"role": "user", "content": f"Tool-Ergebnis für {tool_name}:\n{result.output or result.error}\n\nFahre fort."})

            response = await self._llm.chat(messages)

        return response

    @staticmethod
    def _parse_tool_params(params_str: str) -> dict[str, Any]:
        """Parse tool parameters from string format: key=value, key2=value2."""
        kwargs = {}
        if not params_str.strip():
            return kwargs

        for part in params_str.split(","):
            part = part.strip()
            if "=" in part:
                key, value = part.split("=", 1)
                key = key.strip()
                value = value.strip()
                # Try to parse as int
                try:
                    value = int(value)
                except ValueError:
                    pass
                kwargs[key] = value
        return kwargs
