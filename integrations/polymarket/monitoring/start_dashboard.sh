#!/bin/bash
# Start QPTS Dashboard
cd "$(dirname "$0")/.."
source venv/bin/activate 2>/dev/null || true
pip install flask --quiet
python monitoring/dashboard.py
