#!/usr/bin/env python3
"""
GPE-Core Health Check Server
Leichtgewichtiger HTTP-Endpunkt für Monitoring.
Port 8765 (konfigurierbar via HEALTH_PORT).

Endpunkte:
  GET /          → {"status":"ok",...}
  GET /health    → {"status":"ok",...}
  GET /metrics   → Graph-Metriken
  GET /agents    → Agent-Status via PID-Files
  GET /logs      → Letzte 20 Log-Zeilen je Service
"""
import os
import sys
import json
import signal
import logging
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from datetime import datetime, timezone

sys.path.insert(0, str(Path(__file__).parent / "analyzer"))

BASE_DIR  = Path("/root/gpe-core")
LOG_DIR   = BASE_DIR / "logs"
PID_DIR   = BASE_DIR / "pids"
PORT      = int(os.getenv("HEALTH_PORT", "8765"))
START_TS  = datetime.now(timezone.utc).isoformat()

log = logging.getLogger("health_check")
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")


def _get_graph_metrics() -> dict:
    try:
        from knowledge_graph_v2 import BlackHoleGraph
        kg = BlackHoleGraph()
        m  = kg.get_black_hole_metrics()
        kg.close()
        return m
    except Exception as e:
        return {"error": str(e)}


def _get_agent_status() -> dict:
    agents = {}
    if not PID_DIR.exists():
        return {"error": "PID-Verzeichnis nicht gefunden"}

    for pidfile in PID_DIR.glob("*.pid"):
        name = pidfile.stem
        try:
            pid  = int(pidfile.read_text().strip())
            Path(f"/proc/{pid}").stat()  # Wirft OSError wenn tot
            agents[name] = {"status": "running", "pid": pid}
        except (OSError, ValueError):
            agents[name] = {"status": "dead", "pid": None}

    return agents


def _get_last_log_lines(service: str, n: int = 20) -> list[str]:
    logfile = LOG_DIR / f"{service}.log"
    if not logfile.exists():
        return []
    try:
        with open(logfile, "r", errors="replace") as f:
            return f.readlines()[-n:]
    except OSError:
        return []


def _get_disk_usage() -> dict:
    try:
        import shutil
        total, used, free = shutil.disk_usage("/")
        return {
            "total_gb": round(total / 1e9, 1),
            "used_gb":  round(used  / 1e9, 1),
            "free_gb":  round(free  / 1e9, 1),
            "used_pct": round(used  / total * 100, 1),
        }
    except Exception:
        return {}


def _get_memory_usage() -> dict:
    try:
        with open("/proc/meminfo") as f:
            lines = {l.split(":")[0]: int(l.split()[1]) for l in f if ":" in l}
        total  = lines.get("MemTotal", 0)
        avail  = lines.get("MemAvailable", 0)
        swap_t = lines.get("SwapTotal", 0)
        swap_f = lines.get("SwapFree", 0)
        return {
            "ram_total_gb":  round(total  / 1e6, 1),
            "ram_avail_gb":  round(avail  / 1e6, 1),
            "ram_used_pct":  round((total - avail) / total * 100, 1) if total else 0,
            "swap_total_gb": round(swap_t / 1e6, 1),
            "swap_used_pct": round((swap_t - swap_f) / swap_t * 100, 1) if swap_t else 0,
        }
    except Exception:
        return {}


class HealthHandler(BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        pass  # Unterdrückt HTTP-Log-Spam

    def _json(self, data: dict, code: int = 200):
        body = json.dumps(data, indent=2, default=str).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]

        if path in ("/", "/health"):
            agents = _get_agent_status()
            all_ok = all(v.get("status") == "running" for v in agents.values()) if agents else False
            self._json({
                "status":    "ok" if all_ok else "degraded",
                "uptime_since": START_TS,
                "now":       datetime.now(timezone.utc).isoformat(),
                "agents":    agents,
                "memory":    _get_memory_usage(),
                "disk":      _get_disk_usage(),
            })

        elif path == "/metrics":
            self._json({
                "graph":   _get_graph_metrics(),
                "memory":  _get_memory_usage(),
                "disk":    _get_disk_usage(),
            })

        elif path == "/agents":
            self._json(_get_agent_status())

        elif path == "/logs":
            logs = {}
            for service in ["napoleon", "task_router", "intake", "meta_supervisor"]:
                lines = _get_last_log_lines(service)
                if lines:
                    logs[service] = [l.rstrip() for l in lines]
            self._json(logs)

        else:
            self._json({"error": f"Unbekannter Pfad: {path}"}, 404)


def run():
    server = HTTPServer(("0.0.0.0", PORT), HealthHandler)
    log.info(f"Health Check Server läuft auf http://0.0.0.0:{PORT}")
    log.info(f"Endpunkte: /health  /metrics  /agents  /logs")

    def _shutdown(sig, frame):
        log.info("Shutdown...")
        server.shutdown()

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT,  _shutdown)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    run()
