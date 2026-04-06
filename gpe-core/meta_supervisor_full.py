#!/usr/bin/env python3
"""
Meta-Supervisor FULL v2 — Anti-Zombie, PID-basiertes Process Management
Fixes:
  - PID-Files prüfen statt pgrep (kein "Namen raten")
  - Keine neuen Instanzen wenn alter Prozess noch läuft (kein Zombie-Stacking)
  - Restart-Cooldown: nicht sofort restarten nach Crash (back-off)
  - Strukturiertes JSON-Logging für Dashboard
  - Graceful Shutdown
"""
import subprocess
import threading
import time
import sys
import json
import signal
import logging
from pathlib import Path
from datetime import datetime, timezone

sys.path.insert(0, str(Path(__file__).parent / "analyzer"))
from knowledge_graph_v2 import BlackHoleGraph

BASE_DIR  = Path("/root/gpe-core")
LOG_DIR   = BASE_DIR / "logs"
PID_DIR   = BASE_DIR / "pids"

LOG_DIR.mkdir(parents=True, exist_ok=True)
PID_DIR.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] [MetaSupervisor] %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(LOG_DIR / "meta_supervisor.log"),
    ],
)
log = logging.getLogger("meta_supervisor")

# Service-Definitionen: name → script path
SERVICES: dict[str, str] = {
    "napoleon":     str(BASE_DIR / "napoleon_core.py"),
    "task_router":  str(BASE_DIR / "dispatcher" / "task_router.py"),
    "intake":       str(BASE_DIR / "intake" / "file_scanner.py"),
    "data_cleaner": str(BASE_DIR / "analyzer" / "data_cleaner.py"),
    "legal_parser": str(BASE_DIR / "analyzer" / "legal_parser.py"),
    "health_check": str(BASE_DIR / "health_check.py"),
}

# Restart-Backoff pro Service (Sekunden)
RESTART_BACKOFF: dict[str, int] = {}
MAX_BACKOFF = 120


class MetaSupervisorFull:

    def __init__(self):
        self.kg           = BlackHoleGraph()
        self.check_interval = 30          # Sekunden zwischen Checks
        self._stop_event  = threading.Event()
        self._running     = True  # kept for backwards-compat
        self._crash_count: dict[str, int] = {s: 0 for s in SERVICES}

        self._setup_signal_handlers()
        self._enable_wal()

    def _enable_wal(self):
        try:
            self.kg.conn.execute("PRAGMA journal_mode=WAL")
            self.kg.conn.execute("PRAGMA synchronous=NORMAL")
            # busy_timeout: wait up to 10s before raising "database is locked"
            self.kg.conn.execute("PRAGMA busy_timeout=10000")
            self.kg.conn.commit()
        except Exception as e:
            log.warning(f"WAL-Aktivierung: {e}")

    def _setup_signal_handlers(self):
        def _stop(sig, frame):
            log.info(f"Signal {sig} — Supervisor Shutdown")
            self._stop_event.set()
            self._running = False  # legacy flag
        signal.signal(signal.SIGTERM, _stop)
        signal.signal(signal.SIGINT,  _stop)

    # ------------------------------------------------------------------ #
    #  Process Management                                                  #
    # ------------------------------------------------------------------ #

    def _is_running(self, name: str) -> tuple[bool, int | None]:
        """Prüft PID-File + tatsächlichen Prozess-Status."""
        pidfile = PID_DIR / f"{name}.pid"
        if not pidfile.exists():
            return False, None
        try:
            pid = int(pidfile.read_text().strip())
            Path(f"/proc/{pid}").stat()   # OSError wenn tot
            return True, pid
        except (OSError, ValueError):
            pidfile.unlink(missing_ok=True)
            return False, None

    def _start_service(self, name: str) -> bool:
        """Startet Service — nur wenn nicht bereits läuft."""
        running, pid = self._is_running(name)
        if running:
            log.info(f"⏩ {name} läuft bereits (PID {pid})")
            return True

        script = SERVICES.get(name)
        if not script or not Path(script).exists():
            log.error(f"Script nicht gefunden: {script}")
            return False

        # Backoff prüfen
        backoff = RESTART_BACKOFF.get(name, 0)
        if backoff > 0:
            log.info(f"⏳ {name}: {backoff}s Backoff")
            time.sleep(min(backoff, MAX_BACKOFF))
            RESTART_BACKOFF[name] = min(backoff * 2, MAX_BACKOFF)
        else:
            RESTART_BACKOFF[name] = 5  # Erster Restart: 5s Backoff

        logfile = LOG_DIR / f"{name}.log"
        pidfile = PID_DIR / f"{name}.pid"

        import os
        # Security: only pass explicitly safe env vars to child processes.
        # Never call env.update(os.environ) — that leaks secrets (API keys,
        # tokens, passwords) into every spawned subprocess.
        _safe_keys = {"HOME", "USER", "LANG", "LC_ALL", "LC_CTYPE", "TERM", "TZ", "TMPDIR"}
        env = {
            # Safe keys from parent first
            **{k: v for k, v in os.environ.items() if k in _safe_keys},
            # Then our controlled values (override any conflicts)
            "PATH":        "/usr/local/bin:/usr/bin:/bin",
            "PYTHONPATH":  f"{BASE_DIR}:{BASE_DIR}/analyzer:{BASE_DIR}/dispatcher",
            "OLLAMA_URL":  os.environ.get("OLLAMA_URL", "http://localhost:11434"),
            "ENABLE_SELF_IMPROVEMENT": "0",
        }

        try:
            with open(logfile, "a") as lf:
                proc = subprocess.Popen(
                    ["python3", script],
                    stdout=lf,
                    stderr=subprocess.STDOUT,
                    env=env,
                    cwd=str(BASE_DIR),
                )
            pidfile.write_text(str(proc.pid))
            log.info(f"▶ {name} gestartet (PID {proc.pid})")
            self._crash_count[name] = 0
            return True
        except Exception as e:
            log.error(f"Start fehlgeschlagen für {name}: {e}")
            return False

    def _stop_service(self, name: str):
        running, pid = self._is_running(name)
        if running and pid:
            try:
                import os
                os.kill(pid, signal.SIGTERM)
                log.info(f"⏹ {name} gestoppt (PID {pid})")
            except OSError:
                pass
        pidfile = PID_DIR / f"{name}.pid"
        pidfile.unlink(missing_ok=True)

    # ------------------------------------------------------------------ #
    #  Monitoring                                                          #
    # ------------------------------------------------------------------ #

    def monitor_services(self) -> dict[str, str]:
        """Prüft alle Services — startet bei Bedarf neu."""
        statuses: dict[str, str] = {}

        for name in SERVICES:
            running, pid = self._is_running(name)

            if running:
                statuses[name] = f"running:{pid}"
            else:
                self._crash_count[name] = self._crash_count.get(name, 0) + 1
                log.warning(f"🔴 {name} nicht aktiv (Crashes: {self._crash_count[name]})")

                if self._crash_count[name] > 5:
                    log.error(f"❌ {name} zu viele Crashes ({self._crash_count[name]}) — Neustart pausiert")
                    statuses[name] = f"failed:{self._crash_count[name]}_crashes"
                    continue

                success = self._start_service(name)
                statuses[name] = "restarted" if success else "restart_failed"

        return statuses

    def auto_optimize_napoleon(self) -> dict:
        """Graph-Optimierung wenn Metriken schlechte Werte zeigen."""
        try:
            metrics = self.kg.get_black_hole_metrics()
        except Exception as e:
            log.warning(f"Metrics-Fehler: {e}")
            return {}

        if metrics.get("entropy", 0) > 0.7:
            log.info("🔄 Hohe Entropie — Self-Healing")
            try:
                self.kg.heal()
            except Exception as e:
                log.error(f"Heal-Fehler: {e}")

        if metrics.get("legal_cohesion", 1) < 0.3:
            log.info("⚖️ Legal Cohesion niedrig — Boost")
            try:
                legal = self.kg.conn.execute(
                    "SELECT id FROM nodes WHERE legal_weight > 1.0 LIMIT 20"
                ).fetchall()
                for node in legal:
                    self.kg.conn.execute(
                        "UPDATE nodes SET legal_weight = legal_weight * 1.1 WHERE id = ?",
                        (node["id"],)
                    )
                self.kg.conn.commit()
            except Exception as e:
                log.error(f"Legal-Boost Fehler: {e}")

        ts = f"auto_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        try:
            self.kg.create_snapshot(ts)
        except Exception:
            pass

        return metrics

    def _write_status_json(self, statuses: dict, metrics: dict):
        """Schreibt aktuellen Status als JSON für Dashboard."""
        status_file = LOG_DIR / "supervisor_status.json"
        data = {
            "ts":       datetime.now(timezone.utc).isoformat(),
            "services": statuses,
            "metrics":  metrics,
            "crashes":  self._crash_count,
        }
        try:
            with open(status_file, "w") as f:
                json.dump(data, f, indent=2, default=str)
        except OSError:
            pass

    # ------------------------------------------------------------------ #
    #  Main Loop                                                           #
    # ------------------------------------------------------------------ #

    def run(self):
        log.info(f"Meta-Supervisor gestartet — Check-Interval: {self.check_interval}s")

        while not self._stop_event.is_set():
            try:
                statuses = self.monitor_services()
                metrics  = self.auto_optimize_napoleon()
                self._write_status_json(statuses, metrics)

                running_count = sum(1 for s in statuses.values() if "running" in s)
                log.info(f"Status: {running_count}/{len(SERVICES)} Services aktiv")

            except Exception as e:
                log.error(f"Supervisor-Fehler: {e}")

            # Event.wait() wakes immediately on SIGTERM instead of sleeping
            # the full interval, enabling faster graceful shutdown.
            self._stop_event.wait(timeout=self.check_interval)

        log.info("Meta-Supervisor beendet")
        self.kg.close()


if __name__ == "__main__":
    supervisor = MetaSupervisorFull()
    supervisor.run()
