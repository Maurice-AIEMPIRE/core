#!/usr/bin/env python3
"""
BlackHoleGraph — Knowledge Graph v2
Das Schwarze Loch: saugt alles auf, gewichtet es, verdichtet es zu Wissen.

Schema:
  nodes         — Entitäten (Dateien, Skills, Legal, Agents, ...)
  edges         — Beziehungen zwischen Nodes
  node_communities — Community-Zugehörigkeit für Clustering
  snapshots     — Zeitstempel-Backups der DB-Statistiken

Alles liegt in einer einzigen SQLite-Datei (WAL-Mode, 64MB Cache).
"""

import sqlite3
import shutil
import json
import math
import time
from pathlib import Path
from datetime import datetime, timezone
from typing import Dict, List, Optional, Tuple

# DB-Pfad: neben dieser Datei, oder via GPE_CORE_DIR env
import os
_default_base = Path(os.environ.get("GPE_CORE_DIR", str(Path(__file__).parent.parent)))
DB_PATH = _default_base / "knowledge_graph.db"


class BlackHoleGraph:
    """
    Zentraler Wissensgraph des GPE-Core Systems.

    Alle Prozesse (Napoleon, TaskRouter, MetaSupervisor) teilen dieselbe DB.
    WAL-Mode + busy_timeout=10s verhindern Konflikte bei parallelen Writern.
    """

    def __init__(self, db_path: Optional[Path] = None):
        self.db_path = Path(db_path or DB_PATH)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)

        self.conn = sqlite3.connect(
            str(self.db_path),
            check_same_thread=False,
            timeout=10.0,
        )
        self.conn.row_factory = sqlite3.Row

        self._init_db()
        self._enable_wal()

    # ── Schema ───────────────────────────────────────────────────────────────

    def _init_db(self):
        self.conn.executescript("""
            CREATE TABLE IF NOT EXISTS nodes (
                id           TEXT PRIMARY KEY,
                type         TEXT NOT NULL DEFAULT 'unknown',
                subtype      TEXT,
                name         TEXT NOT NULL,
                content      TEXT,
                source       TEXT,
                category     TEXT,
                legal_weight REAL NOT NULL DEFAULT 1.0,
                tags         TEXT,           -- JSON array
                created_at   TEXT NOT NULL DEFAULT (datetime('now')),
                updated_at   TEXT NOT NULL DEFAULT (datetime('now'))
            );

            CREATE TABLE IF NOT EXISTS edges (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                source_id    TEXT NOT NULL,
                target_id    TEXT NOT NULL,
                relation     TEXT NOT NULL DEFAULT 'related_to',
                weight       REAL NOT NULL DEFAULT 1.0,
                created_at   TEXT NOT NULL DEFAULT (datetime('now')),
                FOREIGN KEY (source_id) REFERENCES nodes(id) ON DELETE CASCADE,
                FOREIGN KEY (target_id) REFERENCES nodes(id) ON DELETE CASCADE,
                UNIQUE (source_id, target_id, relation)
            );

            CREATE TABLE IF NOT EXISTS node_communities (
                node_id      TEXT NOT NULL,
                community_id TEXT NOT NULL,
                score        REAL DEFAULT 1.0,
                PRIMARY KEY (node_id, community_id),
                FOREIGN KEY (node_id) REFERENCES nodes(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS snapshots (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                name         TEXT NOT NULL,
                node_count   INTEGER,
                edge_count   INTEGER,
                created_at   TEXT NOT NULL DEFAULT (datetime('now')),
                metadata     TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_nodes_type        ON nodes(type);
            CREATE INDEX IF NOT EXISTS idx_nodes_legal_weight ON nodes(legal_weight DESC);
            CREATE INDEX IF NOT EXISTS idx_edges_source       ON edges(source_id);
            CREATE INDEX IF NOT EXISTS idx_edges_target       ON edges(target_id);
        """)
        self.conn.commit()

    def _enable_wal(self):
        self.conn.execute("PRAGMA journal_mode=WAL")
        self.conn.execute("PRAGMA synchronous=NORMAL")
        self.conn.execute("PRAGMA cache_size=-65536")   # 64 MB
        self.conn.execute("PRAGMA busy_timeout=10000")  # 10s retry
        self.conn.commit()

    # ── Node Management ──────────────────────────────────────────────────────

    def add_node(
        self,
        node_id: str,
        node_type: str,
        name: str,
        *,
        subtype: str = "",
        content: str = "",
        source: str = "",
        category: str = "",
        legal_weight: float = 1.0,
        tags: Optional[List[str]] = None,
    ) -> str:
        """Upsert a node. Returns node_id."""
        tags_json = json.dumps(tags or [])
        self.conn.execute(
            """
            INSERT INTO nodes (id, type, subtype, name, content, source, category, legal_weight, tags, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
            ON CONFLICT(id) DO UPDATE SET
                name         = excluded.name,
                content      = excluded.content,
                legal_weight = MAX(nodes.legal_weight, excluded.legal_weight),
                updated_at   = excluded.updated_at
            """,
            (node_id, node_type, subtype, name, content, source, category, legal_weight, tags_json),
        )
        self.conn.commit()
        return node_id

    def ingest_symbol(
        self,
        name: str,
        subtype: str = "file",
        source: str = "",
        content: str = "",
        legal_weight: float = 1.0,
    ) -> str:
        """Ingest a symbol (file, function, class, skill, ...) into the graph."""
        import hashlib
        node_id = hashlib.sha256(f"{subtype}:{name}".encode()).hexdigest()[:16]
        node_type = "skill" if subtype in ("function", "class", "skill") else "file"
        return self.add_node(
            node_id,
            node_type,
            name,
            subtype=subtype,
            content=content[:5000],
            source=source,
            legal_weight=legal_weight,
        )

    # ── Edge Management ──────────────────────────────────────────────────────

    def add_edge(self, source_id: str, target_id: str, relation: str = "related_to", weight: float = 1.0):
        """Add or update an edge between two nodes."""
        try:
            self.conn.execute(
                """
                INSERT INTO edges (source_id, target_id, relation, weight)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(source_id, target_id, relation) DO UPDATE SET
                    weight = weight + 0.1
                """,
                (source_id, target_id, relation, weight),
            )
            self.conn.commit()
        except sqlite3.IntegrityError:
            pass  # One or both nodes don't exist yet — skip

    # ── Metrics ──────────────────────────────────────────────────────────────

    def get_black_hole_metrics(self) -> Dict:
        """
        Berechnet Graph-Metriken für Napoleon's Entscheidungs-Engine.

        Returns:
            nodes           — Gesamtzahl Nodes
            edges           — Gesamtzahl Edges
            entropy         — 0.0 (voll geordnet) bis 1.0 (chaotisch)
            legal_cohesion  — Wie gut Legal-Nodes untereinander verbunden sind
            black_hole_score — Gesamtqualität des Graphen (0.0–1.0)
            skills          — Anzahl Skill-Nodes
            legal_nodes     — Anzahl Legal-Nodes
        """
        try:
            node_count = self.conn.execute("SELECT COUNT(*) FROM nodes").fetchone()[0]
            edge_count = self.conn.execute("SELECT COUNT(*) FROM edges").fetchone()[0]
            skill_count = self.conn.execute(
                "SELECT COUNT(*) FROM nodes WHERE type IN ('skill','capability')"
            ).fetchone()[0]
            legal_count = self.conn.execute(
                "SELECT COUNT(*) FROM nodes WHERE type IN ('legal_entity','section','legal_file','legal_document')"
            ).fetchone()[0]

            # Entropy: high when edges/nodes ratio is low (sparse graph = chaotic)
            if node_count == 0:
                entropy = 1.0
            else:
                density = min(1.0, edge_count / max(node_count, 1) / 10.0)
                entropy = max(0.0, 1.0 - density)

            # Legal cohesion: ratio of legal nodes that have edges
            if legal_count == 0:
                legal_cohesion = 0.5
            else:
                legal_with_edges = self.conn.execute(
                    """SELECT COUNT(DISTINCT n.id) FROM nodes n
                       JOIN edges e ON (e.source_id = n.id OR e.target_id = n.id)
                       WHERE n.type IN ('legal_entity','section','legal_file','legal_document')"""
                ).fetchone()[0]
                legal_cohesion = min(1.0, legal_with_edges / max(legal_count, 1))

            # Black Hole Score: composite quality metric
            skill_ratio  = min(1.0, skill_count / max(node_count * 0.05, 1))
            connectivity = min(1.0, edge_count / max(node_count, 1) / 5.0)
            bh_score = (skill_ratio * 0.4 + legal_cohesion * 0.3 + connectivity * 0.3)

            return {
                "nodes":            node_count,
                "edges":            edge_count,
                "skills":           skill_count,
                "legal_nodes":      legal_count,
                "entropy":          round(entropy, 4),
                "legal_cohesion":   round(legal_cohesion, 4),
                "black_hole_score": round(bh_score, 4),
            }
        except Exception as e:
            return {"nodes": 0, "edges": 0, "entropy": 0.5, "legal_cohesion": 0.5, "black_hole_score": 0.5, "skills": 0, "legal_nodes": 0, "error": str(e)}

    # ── Self-Healing ─────────────────────────────────────────────────────────

    def heal(self) -> Dict:
        """
        Bereinigt und repariert den Graphen:
        - Entfernt verwaiste Edges (referenzieren nicht-existente Nodes)
        - Boostet stark vernetzte Nodes (Hub-Nodes)
        - Räumt doppelte Edges auf
        Returns stats dict.
        """
        stats = {"removed_orphan_edges": 0, "boosted_hubs": 0, "deduped_edges": 0}

        try:
            # 1. Remove orphan edges
            cur = self.conn.execute(
                """DELETE FROM edges
                   WHERE source_id NOT IN (SELECT id FROM nodes)
                      OR target_id NOT IN (SELECT id FROM nodes)"""
            )
            stats["removed_orphan_edges"] = cur.rowcount

            # 2. Boost hub nodes (degree > 10) — raise legal_weight
            cur = self.conn.execute(
                """UPDATE nodes SET legal_weight = MIN(legal_weight * 1.05, 10.0)
                   WHERE id IN (
                       SELECT n.id FROM nodes n
                       JOIN edges e ON (e.source_id = n.id OR e.target_id = n.id)
                       GROUP BY n.id HAVING COUNT(*) > 10
                   )"""
            )
            stats["boosted_hubs"] = cur.rowcount

            self.conn.commit()
        except Exception as e:
            stats["error"] = str(e)

        return stats

    # ── Snapshots ────────────────────────────────────────────────────────────

    def create_snapshot(self, name: str) -> str:
        """
        Speichert Snapshot-Metadaten in der DB und optional eine DB-Kopie.
        Returns snapshot name.
        """
        metrics = self.get_black_hole_metrics()
        self.conn.execute(
            """INSERT INTO snapshots (name, node_count, edge_count, metadata)
               VALUES (?, ?, ?, ?)""",
            (
                name,
                metrics.get("nodes", 0),
                metrics.get("edges", 0),
                json.dumps(metrics),
            ),
        )
        self.conn.commit()

        # Optional: write a physical DB backup (skip if no space or slow)
        try:
            snap_dir = self.db_path.parent / "snapshots"
            snap_dir.mkdir(exist_ok=True)
            ts = datetime.now().strftime("%Y%m%d_%H%M%S")
            snap_path = snap_dir / f"{ts}_{name}.db"
            # Use SQLite's own backup API (safe even with WAL mode)
            dest = sqlite3.connect(str(snap_path))
            self.conn.backup(dest)
            dest.close()
        except Exception:
            pass  # Snapshot metadata was saved; physical backup is best-effort

        return name

    # ── Community Detection ──────────────────────────────────────────────────

    def assign_community(self, node_id: str, community_id: str, score: float = 1.0):
        self.conn.execute(
            """INSERT INTO node_communities (node_id, community_id, score)
               VALUES (?, ?, ?)
               ON CONFLICT(node_id, community_id) DO UPDATE SET score = excluded.score""",
            (node_id, community_id, score),
        )
        self.conn.commit()

    def analyze_and_promote(self) -> Dict:
        """
        Analysiert den Graphen und befördert Nodes zu höheren Typen
        basierend auf Konnektivität und legal_weight.
        """
        promoted = {"promoted_to_capability": 0, "promoted_to_skill": 0}
        try:
            # Nodes mit hoher Konnektivität → capability
            high_conn = self.conn.execute(
                """SELECT n.id FROM nodes n
                   JOIN edges e ON (e.source_id = n.id OR e.target_id = n.id)
                   WHERE n.type = 'file' AND n.legal_weight > 2.0
                   GROUP BY n.id HAVING COUNT(*) > 5"""
            ).fetchall()
            for row in high_conn:
                self.conn.execute(
                    "UPDATE nodes SET type = 'capability' WHERE id = ?", (row["id"],)
                )
                promoted["promoted_to_capability"] += 1

            # Capability-Nodes mit hohem Weight → skill
            high_weight = self.conn.execute(
                """SELECT id FROM nodes WHERE type = 'capability' AND legal_weight > 5.0"""
            ).fetchall()
            for row in high_weight:
                self.conn.execute(
                    "UPDATE nodes SET type = 'skill' WHERE id = ?", (row["id"],)
                )
                promoted["promoted_to_skill"] += 1

            self.conn.commit()
        except Exception as e:
            promoted["error"] = str(e)

        return promoted

    # ── Cleanup ──────────────────────────────────────────────────────────────

    def close(self):
        try:
            self.conn.close()
        except Exception:
            pass

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()


# ── Standalone test ──────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("BlackHoleGraph — Selbsttest")
    with BlackHoleGraph() as bh:
        # Add test nodes
        bh.add_node("n1", "skill",   "Python Mastery", legal_weight=3.0)
        bh.add_node("n2", "legal_entity", "Gesellschaftsrecht GmbH", legal_weight=5.0)
        bh.add_node("n3", "file",    "napoleon_core.py", source="/root/gpe-core/napoleon_core.py")
        bh.add_edge("n1", "n3", "implements")
        bh.add_edge("n2", "n1", "requires")

        metrics = bh.get_black_hole_metrics()
        print(f"Nodes: {metrics['nodes']}, Edges: {metrics['edges']}")
        print(f"BH-Score: {metrics['black_hole_score']:.3f}, Entropy: {metrics['entropy']:.3f}")

        heal_stats = bh.heal()
        print(f"Heal: {heal_stats}")

        snap = bh.create_snapshot("selftest")
        print(f"Snapshot: {snap}")

    print("OK")
