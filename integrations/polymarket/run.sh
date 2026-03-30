#!/bin/bash
# QPTS Quick Start Script
# Usage: ./run.sh [paper|backtest|live|docker]

set -e
cd "$(dirname "$0")"

MODE=${1:-paper}

check_env() {
    if [ ! -f ".env" ]; then
        echo "ERROR: .env not found. Copy .env.example and fill in keys."
        cp .env.example .env
        echo "Created .env from .env.example. Edit it first!"
        exit 1
    fi
}

case "$MODE" in
    paper)
        echo "Starting QPTS in PAPER MODE..."
        check_env
        PAPER_MODE=true SINGLE_CYCLE=true python main.py
        ;;
    backtest)
        echo "Running QPTS Backtest..."
        python -c "
import sys; sys.path.insert(0,'.')
from core.backtester import run_backtest, monte_carlo_simulation
# Simulated trade history
trades = [{'pnl': 8.5}, {'pnl': -4.0}, {'pnl': 12.0}, {'pnl': -3.5}, {'pnl': 9.0}]
result = run_backtest(trades, 600.0)
mc = monte_carlo_simulation(0.65, 8.0, 4.5, 600.0)
print('=== Backtest Results ===')
for k,v in result.items():
    if k != 'equity_curve':
        print(f'  {k}: {v}')
print('=== Monte Carlo (1000 sims) ===')
for k,v in mc.items():
    print(f'  {k}: {v}')
"
        ;;
    live)
        echo "LIVE TRADING MODE - Are you sure? (yes/no)"
        read -r confirm
        if [ "$confirm" = "yes" ]; then
            check_env
            PAPER_MODE=false python main.py
        else
            echo "Aborted."
        fi
        ;;
    docker)
        echo "Starting QPTS via Docker..."
        check_env
        docker compose up --build -d
        echo "Logs: docker compose logs -f"
        ;;
    *)
        echo "Usage: ./run.sh [paper|backtest|live|docker]"
        exit 1
        ;;
esac
