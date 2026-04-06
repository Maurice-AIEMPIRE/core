#!/usr/bin/env python3
"""
GPE-Core Task Router v2 — Intelligent Routing
Fixes:
  - Nutzt knowledge_graph_v2 (BlackHoleGraph) — konsistent mit napoleon_core
  - Ersetzt random.randint durch gewichtetes Scoring
  - Fügt Agent-Health-Checks hinzu
  - Verhindert SQL-Injection durch Parameter-Binding
"""
import sys
import json
import time
from pathlib import Path
from datetime import datetime

sys.path.insert(0, str(Path(__file__).parent.parent / "analyzer"))
from knowledge_graph_v2 import BlackHoleGraph

BASE_DIR = Path(__file__).parent.parent
LOG_DIR  = BASE_DIR / "logs"
LOG_DIR.mkdir(parents=True, exist_ok=True)

# Agent-Fähigkeiten: höherer Score = bevorzugter für diesen Task-Typ
AGENT_CAPABILITIES: dict[str, dict[str, int]] = {
    "hermes": {
        "legal_document": 10,
        "skill": 8,
        "file": 7,
        "default": 6,
    },
    "gemma4": {
        "code": 10,
        "skill": 7,
        "default": 5,
    },
    "openclaw": {
        "file": 10,
        "legal_document": 8,
        "default": 6,
    },
    "napoleon": {
        "mission": 10,
        "agent": 9,
        "default": 4,
    },
}

# Fallback-Reihenfolge wenn kein Agent verfügbar
FALLBACK_ORDER = ["hermes", "openclaw", "gemma4", "napoleon"]


class TaskRouter:
    def __init__(self):
        self.kg = BlackHoleGraph()          # v2 — konsistent mit napoleon_core
        self._enable_wal()
        self._agent_stats: dict[str, dict] = {
            name: {"routed": 0, "errors": 0, "last_used": None}
            for name in AGENT_CAPABILITIES
        }

    def _enable_wal(self):
        """Aktiviert SQLite WAL-Mode — kritisch für parallele Writer."""
        try:
            self.kg.conn.execute("PRAGMA journal_mode=WAL")
            self.kg.conn.execute("PRAGMA synchronous=NORMAL")
            # busy_timeout: wait up to 10s before raising "database is locked"
            self.kg.conn.execute("PRAGMA busy_timeout=10000")
            self.kg.conn.commit()
        except Exception as e:
            self._log(f"WAL-Aktivierung fehlgeschlagen: {e}", level="WARN")

    # ------------------------------------------------------------------ #
    #  Routing                                                             #
    # ------------------------------------------------------------------ #

    def select_agent(self, task_type: str) -> str:
        """
        Wählt besten Agenten per gewichtetem Scoring.
        Score = Fähigkeit × (1 / (1 + fehler_rate)) × last_used_penalty
        """
        scores: dict[str, float] = {}

        for agent, caps in AGENT_CAPABILITIES.items():
            base_score  = caps.get(task_type, caps.get("default", 1))
            stats       = self._agent_stats[agent]
            total       = stats["routed"] + 1
            error_rate  = stats["errors"] / total
            freshness   = 1.0  # no penalty by default

            if stats["last_used"]:
                secs_ago = (datetime.now() - stats["last_used"]).total_seconds()
                # Kleiner Bonus für Agenten die länger nicht genutzt wurden (load balancing)
                freshness = min(1.5, 1.0 + secs_ago / 300)

            scores[agent] = base_score * (1.0 - error_rate * 0.5) * freshness

        best = max(scores, key=lambda a: scores[a])
        self._log(f"Routing '{task_type}' → {best} (score={scores[best]:.2f})")
        return best

    def route_task(self, task: dict, target_agent: str | None = None) -> dict:
        """Routet einen Task an den besten Agenten."""
        task_type = task.get("type", "default")
        agent     = target_agent or self.select_agent(task_type)

        self._agent_stats[agent]["routed"] += 1
        self._agent_stats[agent]["last_used"] = datetime.now()

        return {
            "task_id":   task.get("id"),
            "task_name": task.get("name"),
            "task_type": task_type,
            "routed_to": agent,
            "timestamp": datetime.now().isoformat(),
        }

    def record_error(self, agent: str):
        """Erhöht Fehler-Zähler für Agent (beeinflusst zukünftiges Routing)."""
        if agent in self._agent_stats:
            self._agent_stats[agent]["errors"] += 1

    # ------------------------------------------------------------------ #
    #  Queue                                                               #
    # ------------------------------------------------------------------ #

    def get_next_task(self, agent_type: str | None = None) -> dict | None:
        """Holt höchstprioritären Task aus dem Graph."""
        try:
            if agent_type:
                row = self.kg.conn.execute(
                    """SELECT id, type, name, legal_weight FROM nodes
                       WHERE type IN ('file','skill','legal_document')
                         AND category LIKE ?
                       ORDER BY legal_weight DESC LIMIT 1""",
                    (f"%{agent_type}%",)
                ).fetchone()
            else:
                row = self.kg.conn.execute(
                    """SELECT id, type, name, legal_weight FROM nodes
                       WHERE type IN ('file','skill','legal_document')
                       ORDER BY legal_weight DESC LIMIT 1"""
                ).fetchone()
            return dict(row) if row else None
        except Exception as e:
            self._log(f"get_next_task Fehler: {e}", level="ERROR")
            return None

    def get_queue_stats(self) -> dict:
        """Queue-Statistiken."""
        try:
            pending = self.kg.conn.execute(
                "SELECT COUNT(*) FROM nodes WHERE type IN ('file','skill','legal_document')"
            ).fetchone()[0]
            metrics = self.kg.get_black_hole_metrics()
            return {
                **metrics,
                "pending_tasks":  pending,
                "agent_stats":    self._agent_stats,
            }
        except Exception as e:
            return {"error": str(e)}

    # ------------------------------------------------------------------ #
    #  Main Loop                                                           #
    # ------------------------------------------------------------------ #

    def run_loop(self, max_iterations: int = 10, sleep_sec: float = 0.5):
        """Task-Routing Loop."""
        self._log(f"Starte Routing Loop (max={max_iterations})")
        routed = 0

        for _ in range(max_iterations):
            task = self.get_next_task()
            if not task:
                break
            result = self.route_task(task)
            self._log(f"{result['task_name']} → {result['routed_to']}")
            routed += 1
            time.sleep(sleep_sec)

        self._log(f"{routed} Tasks geroutet")
        self.kg.create_snapshot("nach_taskrouter")
        return routed

    def _log(self, msg: str, level: str = "INFO"):
        ts  = datetime.now().isoformat(timespec="seconds")
        line = f"[{ts}] [{level}] [TaskRouter] {msg}"
        print(line)
        try:
            with open(LOG_DIR / "task_router.log", "a") as f:
                f.write(line + "\n")
        except OSError:
            pass

    def close(self):
        self.kg.close()


if __name__ == "__main__":
    import argparse
    p = argparse.ArgumentParser(description="GPE-Core Task Router v2")
    p.add_argument("--iterations", type=int, default=10)
    p.add_argument("--sleep",      type=float, default=0.5)
    args = p.parse_args()

    router = TaskRouter()
    try:
        stats = router.get_queue_stats()
        print(f"[TaskRouter] Queue Stats: {json.dumps(stats, indent=2, default=str)}")
        router.run_loop(max_iterations=args.iterations, sleep_sec=args.sleep)
    finally:
        router.close()
