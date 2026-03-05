"""Tool Manager - Registers and executes tools that agents can use.

Tools are callable functions that agents invoke to interact with
external systems (APIs, filesystem, Docker, web, etc.).
"""

from __future__ import annotations

import asyncio
import logging
import re
from collections.abc import Callable, Coroutine
from typing import Any

from pydantic import BaseModel, Field

logger = logging.getLogger("galaxia.tools")


class ToolDefinition(BaseModel):
    """Describes a tool that agents can use."""
    name: str
    description: str
    parameters: dict[str, str] = Field(default_factory=dict)  # param_name -> description
    category: str = "general"
    requires_approval: bool = False


class ToolResult(BaseModel):
    """Result of a tool execution."""
    success: bool
    output: str = ""
    error: str | None = None


# Type alias for tool functions
ToolFunc = Callable[..., Coroutine[Any, Any, ToolResult]]


class ToolManager:
    """Central registry and executor for agent tools."""

    def __init__(self):
        self._tools: dict[str, ToolDefinition] = {}
        self._handlers: dict[str, ToolFunc] = {}

    def register(
        self,
        name: str,
        handler: ToolFunc,
        description: str,
        parameters: dict[str, str] | None = None,
        category: str = "general",
        requires_approval: bool = False,
    ) -> None:
        definition = ToolDefinition(
            name=name,
            description=description,
            parameters=parameters or {},
            category=category,
            requires_approval=requires_approval,
        )
        self._tools[name] = definition
        self._handlers[name] = handler
        logger.info("Tool registered: %s (%s)", name, category)

    def unregister(self, name: str) -> None:
        self._tools.pop(name, None)
        self._handlers.pop(name, None)

    def get(self, name: str) -> ToolDefinition | None:
        return self._tools.get(name)

    def list_tools(self, category: str | None = None) -> list[ToolDefinition]:
        tools = list(self._tools.values())
        if category:
            tools = [t for t in tools if t.category == category]
        return tools

    def list_for_llm(self, category: str | None = None) -> str:
        """Format tool list as text for LLM system prompts."""
        tools = self.list_tools(category)
        if not tools:
            return "Keine Tools verfügbar."
        lines = []
        for t in tools:
            params = ", ".join(f"{k}: {v}" for k, v in t.parameters.items())
            lines.append(f"- {t.name}({params}): {t.description}")
        return "\n".join(lines)

    async def execute(self, name: str, **kwargs) -> ToolResult:
        handler = self._handlers.get(name)
        if not handler:
            return ToolResult(success=False, error=f"Unknown tool: {name}")

        definition = self._tools[name]
        if definition.requires_approval:
            logger.warning("Tool %s requires approval (auto-approved in dev mode)", name)

        try:
            result = await handler(**kwargs)
            logger.info("Tool %s executed: success=%s", name, result.success)
            return result
        except Exception as e:
            logger.exception("Tool %s failed", name)
            return ToolResult(success=False, error=str(e))


# === Built-in Tools ===

async def tool_shell(command: str, timeout: int = 30) -> ToolResult:
    """Execute a shell command on the host."""
    try:
        proc = await asyncio.create_subprocess_shell(
            command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout)
        output = stdout.decode().strip()
        errors = stderr.decode().strip()

        if proc.returncode == 0:
            return ToolResult(success=True, output=output)
        return ToolResult(success=False, output=output, error=errors)
    except asyncio.TimeoutError:
        return ToolResult(success=False, error=f"Command timed out after {timeout}s")


async def tool_docker_ps() -> ToolResult:
    """List running Docker containers."""
    return await tool_shell("docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'")


_SAFE_CONTAINER_RE = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9_.\-]*$")


async def tool_docker_logs(container: str, lines: int = 50) -> ToolResult:
    """Get logs from a Docker container."""
    if not _SAFE_CONTAINER_RE.match(container):
        return ToolResult(success=False, error="Invalid container name")
    return await tool_shell(f"docker logs --tail {int(lines)} {container}")


async def tool_docker_restart(container: str) -> ToolResult:
    """Restart a Docker container."""
    if not _SAFE_CONTAINER_RE.match(container):
        return ToolResult(success=False, error="Invalid container name")
    return await tool_shell(f"docker restart {container}")


async def tool_system_stats() -> ToolResult:
    """Get system resource usage."""
    commands = [
        "echo '=== CPU ===' && top -bn1 | head -5",
        "echo '=== MEMORY ===' && free -h",
        "echo '=== DISK ===' && df -h /",
    ]
    return await tool_shell(" && ".join(commands))


async def tool_web_fetch(url: str) -> ToolResult:
    """Fetch content from a URL."""
    return await tool_shell(f"curl -sL --max-time 10 '{url}' | head -200")


async def tool_ollama_list() -> ToolResult:
    """List available Ollama models."""
    return await tool_shell("curl -sf http://localhost:11434/api/tags | python3 -m json.tool")


async def tool_n8n_workflows() -> ToolResult:
    """List n8n workflows."""
    return await tool_shell(
        "curl -sf http://localhost:5678/api/v1/workflows -H 'Accept: application/json' | python3 -c "
        "\"import sys,json; data=json.load(sys.stdin); [print(f'{w[\\\"id\\\"]}: {w[\\\"name\\\"]} ({\\\"active\\\" if w[\\\"active\\\"] else \\\"inactive\\\"})') for w in data.get('data',[])]\"",
        timeout=10,
    )


def register_builtin_tools(manager: ToolManager) -> None:
    """Register all built-in tools."""
    manager.register(
        "shell", tool_shell,
        "Execute a shell command",
        {"command": "Shell command to run", "timeout": "Timeout in seconds (default 30)"},
        category="system",
        requires_approval=True,
    )
    manager.register(
        "docker_ps", tool_docker_ps,
        "List running Docker containers",
        category="docker",
    )
    manager.register(
        "docker_logs", tool_docker_logs,
        "Get container logs",
        {"container": "Container name", "lines": "Number of lines (default 50)"},
        category="docker",
    )
    manager.register(
        "docker_restart", tool_docker_restart,
        "Restart a Docker container",
        {"container": "Container name"},
        category="docker",
        requires_approval=True,
    )
    manager.register(
        "system_stats", tool_system_stats,
        "Get CPU, memory, and disk usage",
        category="system",
    )
    manager.register(
        "web_fetch", tool_web_fetch,
        "Fetch content from a URL",
        {"url": "URL to fetch"},
        category="web",
    )
    manager.register(
        "ollama_list", tool_ollama_list,
        "List available Ollama models",
        category="ai",
    )
    manager.register(
        "n8n_workflows", tool_n8n_workflows,
        "List n8n automation workflows",
        category="automation",
    )
