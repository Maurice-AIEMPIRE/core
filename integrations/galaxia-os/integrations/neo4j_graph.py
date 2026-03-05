"""Neo4j Graph Integration - Task/Agent dependency tracking.

Stores task pipeline events as a graph:
- Nodes: Task, Agent, Result
- Edges: PLANNED_BY, RESEARCHED_BY, BUILT_BY, REVIEWED_BY, REVENUE_IMPACT
"""

from __future__ import annotations

import logging
import os
from typing import Any

logger = logging.getLogger("galaxia.neo4j")

# Neo4j driver import (optional - graceful fallback if not installed)
try:
    from neo4j import GraphDatabase
    NEO4J_AVAILABLE = True
except ImportError:
    NEO4J_AVAILABLE = False
    logger.warning("neo4j driver not installed - graph features disabled")


class Neo4jGraph:
    """Neo4j graph for task/agent relationship tracking."""

    def __init__(
        self,
        uri: str | None = None,
        user: str | None = None,
        password: str | None = None,
    ):
        uri = uri or os.environ.get("NEO4J_URI", "bolt://localhost:7687")
        user = user or os.environ.get("NEO4J_USER", "neo4j")
        password = password or os.environ.get("NEO4J_PASSWORD", "")
        self._uri = uri
        self._user = user
        self._password = password
        self._driver = None

    def connect(self) -> bool:
        if not NEO4J_AVAILABLE:
            logger.warning("Neo4j driver not available")
            return False
        try:
            self._driver = GraphDatabase.driver(self._uri, auth=(self._user, self._password))
            self._driver.verify_connectivity()
            logger.info("Connected to Neo4j at %s", self._uri)
            return True
        except Exception as e:
            logger.error("Neo4j connection failed: %s", e)
            return False

    def close(self):
        if self._driver:
            self._driver.close()

    def _run(self, query: str, **params) -> list[dict]:
        if not self._driver:
            return []
        with self._driver.session() as session:
            result = session.run(query, **params)
            return [dict(record) for record in result]

    # === Agent Registration ===

    def register_agent(self, agent_id: str, name: str, role: str, agent_type: str = "systemd") -> None:
        self._run(
            "MERGE (a:Agent {id: $id}) "
            "SET a.name = $name, a.role = $role, a.type = $type, a.registered_at = timestamp()",
            id=agent_id, name=name, role=role, type=agent_type,
        )

    def register_existing_agents(self, count: int = 30) -> None:
        """Register agent-01 through agent-N."""
        for i in range(1, count + 1):
            agent_id = f"agent-{i:02d}"
            self.register_agent(agent_id, agent_id, "worker", "systemd")
        logger.info("Registered %d existing agents", count)

    def register_pipeline_agents(self) -> None:
        """Register the 4 pipeline agents."""
        roles = [
            ("planner-01", "Planner Agent", "planner"),
            ("researcher-01", "Research Agent", "researcher"),
            ("builder-01", "Builder Agent", "builder"),
            ("critic-01", "Critic Agent", "critic"),
        ]
        for aid, name, role in roles:
            self.register_agent(aid, name, role, "pipeline")
        logger.info("Registered 4 pipeline agents")

    # === Task Tracking ===

    def log_task(self, task_id: str, title: str, stage: str, revenue_estimate: float = 0) -> None:
        self._run(
            "MERGE (t:Task {id: $id}) "
            "SET t.title = $title, t.stage = $stage, "
            "t.revenue_estimate = $revenue, t.updated_at = timestamp()",
            id=task_id, title=title, stage=stage, revenue=revenue_estimate,
        )

    _ALLOWED_REL_TYPES = frozenset({
        "PLANNED_BY", "RESEARCHED_BY", "BUILT_BY", "REVIEWED_BY", "PROCESSED_BY",
    })

    def log_agent_action(self, task_id: str, agent_id: str, action: str) -> None:
        """Create relationship between task and agent."""
        rel_type = {
            "planned": "PLANNED_BY",
            "researched": "RESEARCHED_BY",
            "built": "BUILT_BY",
            "reviewed": "REVIEWED_BY",
        }.get(action, "PROCESSED_BY")

        if rel_type not in self._ALLOWED_REL_TYPES:
            logger.error("Invalid relationship type: %s", rel_type)
            return

        self._run(
            f"MATCH (t:Task {{id: $task_id}}) "
            f"MATCH (a:Agent {{id: $agent_id}}) "
            f"MERGE (t)-[r:{rel_type}]->(a) "
            f"SET r.timestamp = timestamp()",
            task_id=task_id, agent_id=agent_id,
        )

    def log_revenue_impact(self, task_id: str, amount: float, description: str = "") -> None:
        self._run(
            "MATCH (t:Task {id: $task_id}) "
            "CREATE (r:Result {amount: $amount, description: $desc, created_at: timestamp()}) "
            "CREATE (t)-[:REVENUE_IMPACT]->(r)",
            task_id=task_id, amount=amount, desc=description,
        )

    # === Queries ===

    def get_graph_summary(self) -> dict:
        """Get a summary of the task graph."""
        agents = self._run("MATCH (a:Agent) RETURN count(a) as count")
        tasks = self._run("MATCH (t:Task) RETURN count(t) as count")
        revenue = self._run(
            "MATCH (t:Task) WHERE t.revenue_estimate > 0 "
            "RETURN sum(t.revenue_estimate) as total, count(t) as count"
        )
        stages = self._run(
            "MATCH (t:Task) RETURN t.stage as stage, count(t) as count ORDER BY count DESC"
        )

        return {
            "agents": agents[0]["count"] if agents else 0,
            "tasks": tasks[0]["count"] if tasks else 0,
            "revenue_total": revenue[0]["total"] if revenue else 0,
            "revenue_tasks": revenue[0]["count"] if revenue else 0,
            "stages": {r["stage"]: r["count"] for r in stages},
        }

    def get_mermaid_graph(self) -> str:
        """Generate a Mermaid diagram of the task graph."""
        tasks = self._run(
            "MATCH (t:Task)-[r]->(a:Agent) "
            "RETURN t.id as task_id, t.title as title, t.stage as stage, "
            "type(r) as rel, a.name as agent "
            "ORDER BY t.id LIMIT 20"
        )

        lines = ["graph TD"]
        seen = set()

        for row in tasks:
            tid = row["task_id"]
            title = (row["title"] or "")[:30]
            agent = row["agent"]
            rel = row["rel"]

            if tid not in seen:
                stage_icon = {"approved": "✅", "pruned": "❌", "built": "🔨"}.get(row["stage"], "📋")
                lines.append(f'    {tid}["{stage_icon} {title}"]')
                seen.add(tid)

            lines.append(f'    {tid} -->|{rel}| {agent.replace(" ", "_")}')

        if len(lines) == 1:
            lines.append('    empty["Noch keine Tasks im Graph"]')

        return "\n".join(lines)

    def get_recent_tasks(self, limit: int = 20) -> list[dict]:
        return self._run(
            "MATCH (t:Task) RETURN t ORDER BY t.updated_at DESC LIMIT $limit",
            limit=limit,
        )
