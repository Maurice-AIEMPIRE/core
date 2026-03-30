#!/usr/bin/env python3
"""
QPTS - Quantitative Polymarket Trading System
Integrated into openclaw/core monorepo
"""
import os
import sys
import asyncio
import json
from datetime import datetime
from typing import Dict, Any, List, TypedDict

from dotenv import load_dotenv
from rich.console import Console
from rich.table import Table

load_dotenv()

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from tools.polymarket_client import PolymarketClient
from agents.research import research_markets
from agents.analyst import analyze_markets
from agents.risk_manager import risk_check

console = Console()

# ─── State Schema ───────────────────────────────────────────────────────────

class QPTSState(TypedDict):
    capital: float
    cycle: int
    client: Any
    paper_mode: bool
    kelly_fraction: float
    max_drawdown: float
    researched_markets: List[Dict]
    trade_candidates: List[Dict]
    approved_trades: List[Dict]
    rejected_trades: List[Dict]
    total_exposure: float
    cycle_log: List[str]
    trade_history: List[Dict]

# ─── Execution Node ──────────────────────────────────────────────────────────

def execute_trades(state: QPTSState) -> QPTSState:
    """Execute approved trades via CLOB or paper mode."""
    client = state["client"]
    approved = state.get("approved_trades", [])

    for trade in approved:
        token_id = trade.get("condition_id", "")
        size = trade["position_size"]
        side = trade.get("side", "YES")
        price = trade.get("token_price", 0.5)

        try:
            result = client.place_order(
                token_id=token_id,
                side=side,
                price=price,
                size=size,
            )

            trade["execution_result"] = result
            trade["executed_at"] = datetime.now().isoformat()
            state["trade_history"].append(trade)

            mode = "PAPER" if state["paper_mode"] else "LIVE"
            state["cycle_log"].append(
                f"[Execute/{mode}] {side} {trade['question'][:50]}... "
                f"size=${size:.2f} @ {price:.3f}"
            )
        except Exception as e:
            state["cycle_log"].append(f"[Execute/ERROR] {trade['question'][:40]}: {str(e)}")

    return state

def log_cycle(state: QPTSState) -> QPTSState:
    """Log cycle results."""
    cycle = state["cycle"]
    logs = state["cycle_log"]

    # Print rich table
    table = Table(title=f"QPTS Cycle #{cycle} — {datetime.now().strftime('%H:%M:%S')}")
    table.add_column("Step", style="cyan")
    table.add_column("Detail", style="green")

    for log in logs:
        step = log.split("]")[0].replace("[", "") if "]" in log else "INFO"
        detail = log.split("]", 1)[1].strip() if "]" in log else log
        table.add_row(step, detail)

    console.print(table)

    # Save to log file
    log_dir = os.path.join(os.path.dirname(__file__), "logs")
    os.makedirs(log_dir, exist_ok=True)
    log_file = os.path.join(log_dir, f"cycle_{datetime.now().strftime('%Y%m%d')}.jsonl")

    with open(log_file, "a") as f:
        f.write(json.dumps({
            "cycle": cycle,
            "timestamp": datetime.now().isoformat(),
            "capital": state["capital"],
            "logs": logs,
            "trades_executed": len(state.get("approved_trades", [])),
            "paper_mode": state["paper_mode"],
        }) + "\n")

    state["cycle"] += 1
    return state

# ─── LangGraph Setup ─────────────────────────────────────────────────────────

def build_graph():
    from langgraph.graph import StateGraph, END

    workflow = StateGraph(dict)
    workflow.add_node("research", research_markets)
    workflow.add_node("analyze", analyze_markets)
    workflow.add_node("risk_check", risk_check)
    workflow.add_node("execute", execute_trades)
    workflow.add_node("log", log_cycle)

    workflow.set_entry_point("research")
    workflow.add_edge("research", "analyze")
    workflow.add_edge("analyze", "risk_check")
    workflow.add_edge("risk_check", "execute")
    workflow.add_edge("execute", "log")
    workflow.add_edge("log", END)

    return workflow.compile()

# ─── Main Entry ──────────────────────────────────────────────────────────────

def run_cycle(app, initial_state: QPTSState):
    state = dict(initial_state)
    state["cycle_log"] = []
    state["researched_markets"] = []
    state["trade_candidates"] = []
    state["approved_trades"] = []
    state["rejected_trades"] = []
    state["total_exposure"] = 0.0

    result = app.invoke(state)
    return result

def main():
    paper_mode = os.getenv("PAPER_MODE", "true").lower() == "true"

    mode_label = "[PAPER MODE]" if paper_mode else "[LIVE TRADING]"
    console.print(f"\n[bold green]QPTS - Quantitative Polymarket Trading System[/]\n{mode_label}\n")

    if not paper_mode:
        console.print("[bold red]WARNING: LIVE TRADING ACTIVE. Ensure audit passed.[/]")

    client = PolymarketClient(paper_mode=paper_mode)

    initial_state: QPTSState = {
        "capital": float(os.getenv("START_CAPITAL", "600.0")),
        "cycle": 1,
        "client": client,
        "paper_mode": paper_mode,
        "kelly_fraction": float(os.getenv("KELLY_FRACTION", "0.25")),
        "max_drawdown": float(os.getenv("MAX_DRAWDOWN", "0.20")),
        "researched_markets": [],
        "trade_candidates": [],
        "approved_trades": [],
        "rejected_trades": [],
        "total_exposure": 0.0,
        "cycle_log": [],
        "trade_history": [],
    }

    interval_minutes = int(os.getenv("CYCLE_INTERVAL_MINUTES", "15"))

    try:
        app = build_graph()
    except ImportError:
        console.print("[yellow]LangGraph not available, running single cycle...[/]")
        # Fallback: run pipeline manually
        state = dict(initial_state)
        state["cycle_log"] = []
        state = research_markets(state)
        state = analyze_markets(state)
        state = risk_check(state)
        state = execute_trades(state)
        state = log_cycle(state)
        return

    # Single cycle mode (use APScheduler for continuous)
    single_run = os.getenv("SINGLE_CYCLE", "false").lower() == "true"

    if single_run:
        run_cycle(app, initial_state)
        return

    # Scheduled mode
    try:
        from apscheduler.schedulers.blocking import BlockingScheduler
        scheduler = BlockingScheduler()

        state_holder = {"state": initial_state}

        def scheduled_cycle():
            result = run_cycle(app, state_holder["state"])
            state_holder["state"]["capital"] = result.get("capital", state_holder["state"]["capital"])
            state_holder["state"]["cycle"] = result.get("cycle", state_holder["state"]["cycle"])
            state_holder["state"]["trade_history"] = result.get("trade_history", [])

        # Run immediately on start
        scheduled_cycle()

        scheduler.add_job(scheduled_cycle, 'interval', minutes=interval_minutes)
        console.print(f"[bold]Scheduler started: cycle every {interval_minutes} min[/]")
        scheduler.start()

    except ImportError:
        run_cycle(app, initial_state)

if __name__ == "__main__":
    main()
