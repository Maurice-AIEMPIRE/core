#!/usr/bin/env python3
"""
Napoleon Core v2 — Yang Agent (10x Upgrade)
Fixes & Improvements:
  - SQLite WAL-Mode beim Start (verhindert Corruption durch parallele Writer)
  - Weighted Decision Engine ersetzt starres if/elif
  - Action-History verhindert Endlos-Loops (gleiche Aktion nicht 3x hintereinander)
  - Fehler-tolerante Graph-Analyse (krasht nicht bei leerem DB)
  - Strukturiertes JSON-Logging
  - Graceful Shutdown via SIGTERM
"""
import sys
import json
import signal
import threading
import time
import logging
from pathlib import Path
from datetime import datetime, timezone
from typing import Dict, List, Optional
from collections import deque

sys.path.insert(0, str(Path(__file__).parent / "analyzer"))
from knowledge_graph_v2 import BlackHoleGraph

BASE_DIR     = Path("/root/gpe-core")
MISSIONS_DIR = BASE_DIR / "missions"
LOG_DIR      = BASE_DIR / "logs"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] [Napoleon] %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(LOG_DIR / "napoleon.log"),
    ],
)
log = logging.getLogger("napoleon")


# ------------------------------------------------------------------ #
#  Entscheidungs-Engine                                                #
# ------------------------------------------------------------------ #

class ActionScorer:
    """
    Gewichtetes Scoring aller möglichen Aktionen.
    Ersetzt das starre if/elif — jede Aktion bekommt einen Score
    basierend auf Graph-Metriken. Höchster Score gewinnt.
    """

    ACTIONS = [
        "densify",
        "link_legal",
        "self_improve",
        "snapshot",
        "maintain",
    ]

    def score(self, metrics: Dict) -> Dict[str, float]:
        entropy        = metrics.get("entropy",        0.5)
        legal_cohesion = metrics.get("legal_cohesion", 0.5)
        bh_score       = metrics.get("black_hole_score", 0.5)
        node_count     = metrics.get("nodes",          0)

        scores = {
            # Densify: wichtig wenn Entropie hoch UND genug Nodes vorhanden
            "densify":      entropy * 10 * min(1.0, node_count / 20),

            # Link Legal: wichtig wenn Legal-Cohesion niedrig
            "link_legal":   (1.0 - legal_cohesion) * 8,

            # Self-Improve: wichtig wenn Black Hole Score niedrig
            "self_improve": (1.0 - bh_score) * 7,

            # Snapshot: immer leicht sinnvoll (Backup)
            "snapshot":     2.0,

            # Maintain: Basis-Score — greift wenn alles gut ist
            "maintain":     max(0.5, bh_score * 3),
        }
        return scores

    def decide(self, metrics: Dict, history: deque) -> Dict:
        """Wählt Aktion mit höchstem Score — aber nicht dieselbe 3x hintereinander."""
        scores = self.score(metrics)

        # Sortiere nach Score absteigend
        ranked = sorted(scores.items(), key=lambda x: x[1], reverse=True)

        for action_type, score in ranked:
            # Verhindert Loops: nicht dieselbe Aktion 3x hintereinander
            recent = list(history)[-3:] if len(history) >= 3 else list(history)
            if recent.count(action_type) >= 3:
                continue

            priority = min(10, int(score + 0.5))
            return {
                "type":     action_type,
                "priority": priority,
                "score":    round(score, 3),
                "reason":   self._reason(action_type, metrics),
            }

        # Absoluter Fallback
        return {"type": "maintain", "priority": 1, "score": 0.0, "reason": "Fallback"}

    @staticmethod
    def _reason(action_type: str, metrics: Dict) -> str:
        reasons = {
            "densify":     f"Entropie={metrics.get('entropy', '?'):.2f} — Graph verdichten",
            "link_legal":  f"Legal-Cohesion={metrics.get('legal_cohesion', '?'):.2f} — Legal verknüpfen",
            "self_improve":f"BH-Score={metrics.get('black_hole_score', '?'):.2f} — Optimierung",
            "snapshot":    "Regelmäßiger Snapshot",
            "maintain":    "System stabil",
        }
        return reasons.get(action_type, "Unbekannt")


# ------------------------------------------------------------------ #
#  Napoleon Core                                                       #
# ------------------------------------------------------------------ #

class NapoleonCore:
    """Napoleon — Yang Agent für strategische Entscheidungen (v2)."""

    def __init__(self, brain_agent: str = "brain_napoleon"):
        MISSIONS_DIR.mkdir(parents=True, exist_ok=True)
        LOG_DIR.mkdir(parents=True, exist_ok=True)

        self.kg          = BlackHoleGraph()
        self.brain_agent = brain_agent
        self.scorer      = ActionScorer()
        self.history: deque = deque(maxlen=20)
        # Use threading.Event for signal-safe shutdown signaling — a plain
        # boolean assignment is not guaranteed atomic across all Python
        # implementations and can race with DB operations mid-transaction.
        self._stop_event = threading.Event()
        self._running    = True  # kept for backwards-compat reads

        self._enable_wal()
        self._setup_signal_handlers()

        self.priorities = {
            "legal": 10.0, "mission": 8.0,
            "agent": 6.0,  "skill":   4.0, "file": 2.0,
        }

    def _enable_wal(self):
        """WAL-Mode — verhindert DB-Corruption bei parallelen Writern."""
        try:
            self.kg.conn.execute("PRAGMA journal_mode=WAL")
            self.kg.conn.execute("PRAGMA synchronous=NORMAL")
            self.kg.conn.execute("PRAGMA cache_size=-65536")  # 64MB Cache
            # busy_timeout: wait up to 10s instead of raising "database is
            # locked" immediately when another writer holds the WAL lock.
            self.kg.conn.execute("PRAGMA busy_timeout=10000")
            self.kg.conn.commit()
            log.info("SQLite WAL-Mode aktiviert")
        except Exception as e:
            log.warning(f"WAL-Aktivierung fehlgeschlagen: {e}")

    def _setup_signal_handlers(self):
        """Graceful Shutdown bei SIGTERM / SIGINT."""
        def _shutdown(signum, frame):
            # threading.Event.set() is async-signal-safe in CPython and
            # coordinates cleanly with the main loop's is_set() check,
            # avoiding races with in-progress DB transactions.
            log.info(f"Signal {signum} — Shutdown...")
            self._stop_event.set()
            self._running = False  # legacy flag

        signal.signal(signal.SIGTERM, _shutdown)
        signal.signal(signal.SIGINT,  _shutdown)

    # ------------------------------------------------------------------ #
    #  Analyse                                                             #
    # ------------------------------------------------------------------ #

    def analyze_graph(self) -> Dict:
        """Analysiert aktuellen Graph-Zustand — fehler-tolerant."""
        try:
            metrics = self.kg.get_black_hole_metrics()
        except Exception as e:
            log.warning(f"Metrics-Fehler: {e}")
            metrics = {"entropy": 0.5, "legal_cohesion": 0.5, "black_hole_score": 0.5, "nodes": 0}

        try:
            top_nodes = self.kg.conn.execute(
                "SELECT id, type, name, legal_weight FROM nodes ORDER BY legal_weight DESC LIMIT 10"
            ).fetchall()
        except Exception:
            top_nodes = []

        try:
            communities = self.kg.conn.execute(
                "SELECT community_id, COUNT(*) as count FROM node_communities GROUP BY community_id ORDER BY count DESC LIMIT 5"
            ).fetchall()
        except Exception:
            communities = []

        return {
            "metrics":     metrics,
            "top_nodes":   [dict(n) for n in top_nodes],
            "communities": [dict(c) for c in communities],
            "timestamp":   datetime.now(timezone.utc).isoformat(),
        }

    # ------------------------------------------------------------------ #
    #  Aktionen                                                            #
    # ------------------------------------------------------------------ #

    def execute_action(self, action: Dict) -> bool:
        action_type = action["type"]
        dispatch = {
            "densify":      self._densify_graph,
            "link_legal":   self._link_legal_nodes,
            "self_improve": self._self_improve,
            "snapshot":     lambda: bool(self.kg.create_snapshot(f"napoleon_{datetime.now().strftime('%Y%m%d_%H%M%S')}")),
            "maintain":     lambda: True,
        }
        fn = dispatch.get(action_type)
        if fn:
            return fn()
        log.warning(f"Unbekannte Aktion: {action_type}")
        return False

    def _densify_graph(self) -> bool:
        try:
            nodes = self.kg.conn.execute(
                "SELECT id, type, legal_weight FROM nodes WHERE legal_weight > 1.0 ORDER BY legal_weight DESC LIMIT 20"
            ).fetchall()
            created = 0
            for i, n1 in enumerate(nodes):
                for n2 in nodes[i+1:i+3]:
                    if n1["type"] != n2["type"]:
                        self.kg.add_edge(n1["id"], n2["id"], "relevant_for")
                        created += 1
            log.info(f"Densify: {created} Edges erstellt")
            return True
        except Exception as e:
            log.error(f"Densify Fehler: {e}")
            return False

    def _link_legal_nodes(self) -> bool:
        try:
            nodes = self.kg.conn.execute(
                "SELECT id, name FROM nodes WHERE type IN ('legal_entity','section','legal_file') ORDER BY legal_weight DESC LIMIT 10"
            ).fetchall()
            for i in range(len(nodes) - 1):
                self.kg.add_edge(nodes[i]["id"], nodes[i+1]["id"], "strengthened_by")
            log.info(f"Link Legal: {len(nodes)-1} Edges erstellt")
            return True
        except Exception as e:
            log.error(f"Link Legal Fehler: {e}")
            return False

    def _self_improve(self) -> bool:
        try:
            stats = self.kg.heal()
            log.info(f"Self-Improve: {stats}")
            return True
        except Exception as e:
            log.error(f"Self-Improve Fehler: {e}")
            return False

    # ------------------------------------------------------------------ #
    #  Missionen                                                           #
    # ------------------------------------------------------------------ #

    def create_mission(self, mission_type: str, description: str) -> str:
        mission_id   = f"mission_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        mission_file = MISSIONS_DIR / f"{mission_id}.json"
        mission_data = {
            "id":          mission_id,
            "type":        mission_type,
            "description": description,
            "status":      "pending",
            "created":     datetime.now(timezone.utc).isoformat(),
            "priority":    self.priorities.get(mission_type, 5.0),
        }
        with open(mission_file, "w") as f:
            json.dump(mission_data, f, indent=2)
        log.info(f"Mission erstellt: {mission_id}")
        return mission_id

    # ------------------------------------------------------------------ #
    #  Brain Loop                                                          #
    # ------------------------------------------------------------------ #

    def run_brain_loop(self, iterations: int = 1):
        log.info(f"NAPOLEON BRAIN LOOP — {iterations} Iterationen")

        for i in range(iterations):
            if self._stop_event.is_set():
                log.info("Shutdown-Signal — Loop unterbrochen")
                break

            log.info(f"--- Iteration {i+1}/{iterations} ---")

            # 1. Analysiere
            analysis = self.analyze_graph()
            metrics  = analysis["metrics"]
            log.info(f"Graph: nodes={metrics.get('nodes',0)} bh_score={metrics.get('black_hole_score',0):.2f} entropy={metrics.get('entropy',0):.2f}")

            # 2. Entscheide (weighted scoring)
            action = self.scorer.decide(metrics, self.history)
            self.history.append(action["type"])
            log.info(f"Aktion: {action['type']} score={action['score']} — {action['reason']}")

            # 3. Führe aus
            success = self.execute_action(action)
            log.info(f"Ausführung: {'✓' if success else '✗'}")

            # 4. JSON-Log für Meta-Supervisor
            self._write_json_log(i+1, metrics, action, success)

            # 5. Snapshot nach jeder Iteration
            self.kg.create_snapshot(f"napoleon_loop_{i+1}")

            time.sleep(1)

        log.info("Napoleon Loop abgeschlossen")

    def _write_json_log(self, iteration: int, metrics: Dict, action: Dict, success: bool):
        """Strukturiertes JSON-Log für Meta-Supervisor und Dashboard."""
        entry = {
            "ts":        datetime.now(timezone.utc).isoformat(),
            "iteration": iteration,
            "metrics":   metrics,
            "action":    action,
            "success":   success,
            "agent":     self.brain_agent,
        }
        log_file = LOG_DIR / "napoleon_structured.jsonl"
        with open(log_file, "a") as f:
            f.write(json.dumps(entry) + "\n")

    def close(self):
        self.kg.close()
        log.info("Napoleon Core geschlossen")


if __name__ == "__main__":
    import argparse

    p = argparse.ArgumentParser(description="Napoleon Core v2 — Yang Agent")
    p.add_argument("--brain-agent", default="brain_napoleon")
    p.add_argument("--iterations",  type=int, default=1)
    p.add_argument("--daemon",      action="store_true", help="Dauerhaft laufen (alle 60s)")
    args = p.parse_args()

    napoleon = NapoleonCore(brain_agent=args.brain_agent)

    try:
        if args.daemon:
            log.info("Napoleon Daemon gestartet")
            while not napoleon._stop_event.is_set():
                napoleon.run_brain_loop(iterations=1)
                # Use Event.wait() so SIGTERM wakes the sleep immediately
                napoleon._stop_event.wait(timeout=60)
        else:
            napoleon.run_brain_loop(iterations=args.iterations)
    finally:
        napoleon.close()
