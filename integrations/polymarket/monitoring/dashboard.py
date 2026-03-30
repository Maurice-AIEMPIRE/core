#!/usr/bin/env python3
"""
QPTS Live Trading Dashboard
Flask + SSE for real-time updates
Run: python monitoring/dashboard.py
Access: http://localhost:8765
"""
import os
import sys
import json
import time
from datetime import datetime
from pathlib import Path
from flask import Flask, Response, render_template_string, jsonify

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

app = Flask(__name__)
LOG_DIR = Path(__file__).parent.parent / "logs"

DASHBOARD_HTML = '''<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>QPTS — Harvey Trading Dashboard</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { background: #0a0e1a; color: #e0e6f0; font-family: 'JetBrains Mono', 'Courier New', monospace; }
  .header { background: #0d1225; border-bottom: 1px solid #1e3a5f; padding: 16px 24px; display: flex; align-items: center; justify-content: space-between; }
  .header h1 { font-size: 18px; color: #4fc3f7; letter-spacing: 2px; }
  .status-dot { width: 10px; height: 10px; border-radius: 50%; background: #4caf50; box-shadow: 0 0 8px #4caf50; animation: pulse 2s infinite; display: inline-block; margin-right: 8px; }
  @keyframes pulse { 0%,100%{opacity:1} 50%{opacity:0.5} }
  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 16px; padding: 24px; }
  .card { background: #0d1225; border: 1px solid #1e3a5f; border-radius: 8px; padding: 20px; }
  .card .label { font-size: 11px; color: #7a90b0; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px; }
  .card .value { font-size: 28px; font-weight: bold; color: #4fc3f7; }
  .card .value.green { color: #4caf50; }
  .card .value.red { color: #f44336; }
  .card .value.yellow { color: #ffc107; }
  .section { padding: 0 24px 24px; }
  .section h2 { font-size: 13px; color: #7a90b0; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 12px; padding-bottom: 8px; border-bottom: 1px solid #1e3a5f; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; }
  th { color: #7a90b0; text-align: left; padding: 8px 12px; font-weight: normal; font-size: 11px; text-transform: uppercase; border-bottom: 1px solid #1e3a5f; }
  td { padding: 10px 12px; border-bottom: 1px solid #0f1930; color: #c0cce0; }
  tr:hover td { background: #111827; }
  .badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 11px; font-weight: bold; }
  .badge.paper { background: #1a3a5c; color: #4fc3f7; }
  .badge.live { background: #3a1a1a; color: #f44336; }
  .badge.yes { background: #1a3a2a; color: #4caf50; }
  .badge.no { background: #3a1a1a; color: #f44336; }
  .equity-bar { height: 4px; background: #1e3a5f; border-radius: 2px; margin-top: 8px; }
  .equity-fill { height: 4px; background: linear-gradient(90deg, #1565c0, #4fc3f7); border-radius: 2px; transition: width 0.5s; }
  #log-container { background: #060a14; border: 1px solid #1e3a5f; border-radius: 8px; padding: 16px; font-size: 12px; max-height: 200px; overflow-y: auto; font-family: monospace; }
  .log-line { padding: 2px 0; color: #7a90b0; }
  .log-line.info { color: #4fc3f7; }
  .log-line.trade { color: #4caf50; }
  .log-line.risk { color: #ffc107; }
  .log-line.error { color: #f44336; }
  .mode-indicator { font-size: 12px; padding: 4px 12px; border-radius: 4px; }
  .update-time { font-size: 11px; color: #7a90b0; }
</style>
</head>
<body>
<div class="header">
  <div>
    <span class="status-dot" id="status-dot"></span>
    <span class="header h1" style="display:inline;font-size:18px;color:#4fc3f7;letter-spacing:2px;">QPTS — HARVEY TRADING</span>
  </div>
  <div style="display:flex;align-items:center;gap:16px;">
    <span id="mode-badge" class="badge paper">PAPER</span>
    <span class="update-time" id="update-time">—</span>
  </div>
</div>

<div class="grid">
  <div class="card">
    <div class="label">Capital</div>
    <div class="value" id="capital">$600.00</div>
    <div class="equity-bar"><div class="equity-fill" id="equity-bar" style="width:100%"></div></div>
  </div>
  <div class="card">
    <div class="label">Total Return</div>
    <div class="value green" id="total-return">+0.00%</div>
  </div>
  <div class="card">
    <div class="label">Cycles Run</div>
    <div class="value" id="cycles">0</div>
  </div>
  <div class="card">
    <div class="label">Trades Executed</div>
    <div class="value" id="trades">0</div>
  </div>
  <div class="card">
    <div class="label">Last Exposure</div>
    <div class="value yellow" id="exposure">$0.00</div>
  </div>
  <div class="card">
    <div class="label">Win Rate</div>
    <div class="value" id="win-rate">—</div>
  </div>
</div>

<div class="section">
  <h2>Recent Cycles</h2>
  <table>
    <thead><tr><th>Cycle</th><th>Time</th><th>Capital</th><th>Trades</th><th>Mode</th><th>Log</th></tr></thead>
    <tbody id="cycles-table"></tbody>
  </table>
</div>

<div class="section">
  <h2>Live Log</h2>
  <div id="log-container"></div>
</div>

<script>
const startCapital = 600.0;
let allCycles = [];

function formatCurrency(v) { return '$' + parseFloat(v).toFixed(2); }
function formatPct(v) { const p = ((v - startCapital) / startCapital * 100).toFixed(2); return (p >= 0 ? '+' : '') + p + '%'; }

function updateUI(data) {
  const capital = data.capital || startCapital;
  const ret = (capital - startCapital) / startCapital * 100;

  document.getElementById('capital').textContent = formatCurrency(capital);
  document.getElementById('capital').className = 'value ' + (capital >= startCapital ? 'green' : 'red');
  document.getElementById('total-return').textContent = (ret >= 0 ? '+' : '') + ret.toFixed(2) + '%';
  document.getElementById('total-return').className = 'value ' + (ret >= 0 ? 'green' : 'red');
  document.getElementById('cycles').textContent = data.cycle || 0;
  document.getElementById('trades').textContent = data.total_trades || 0;
  document.getElementById('exposure').textContent = formatCurrency(data.last_exposure || 0);
  document.getElementById('update-time').textContent = 'Updated: ' + new Date().toLocaleTimeString();

  const barPct = Math.min(100, Math.max(10, (capital / startCapital) * 100));
  document.getElementById('equity-bar').style.width = barPct + '%';
  document.getElementById('equity-bar').style.background = capital >= startCapital ? 'linear-gradient(90deg,#1b5e20,#4caf50)' : 'linear-gradient(90deg,#b71c1c,#f44336)';

  const mode = data.paper_mode ? 'PAPER' : 'LIVE';
  document.getElementById('mode-badge').textContent = mode;
  document.getElementById('mode-badge').className = 'badge ' + (data.paper_mode ? 'paper' : 'live');

  if (data.cycles) {
    const tbody = document.getElementById('cycles-table');
    tbody.innerHTML = '';
    [...data.cycles].reverse().slice(0, 10).forEach(c => {
      const tr = document.createElement('tr');
      const capDiff = c.capital - startCapital;
      tr.innerHTML = `
        <td>#${c.cycle}</td>
        <td>${new Date(c.timestamp).toLocaleTimeString()}</td>
        <td style="color:${capDiff >= 0 ? '#4caf50' : '#f44336'}">${formatCurrency(c.capital)}</td>
        <td>${c.trades_executed}</td>
        <td><span class="badge ${c.paper_mode ? 'paper' : 'live'}">${c.paper_mode ? 'PAPER' : 'LIVE'}</span></td>
        <td style="color:#7a90b0;font-size:11px">${(c.logs || []).slice(-1)[0] || '—'}</td>
      `;
      tbody.appendChild(tr);
    });
  }

  if (data.recent_logs) {
    const container = document.getElementById('log-container');
    container.innerHTML = '';
    data.recent_logs.forEach(line => {
      const div = document.createElement('div');
      div.className = 'log-line ' + (
        line.includes('[Trade') || line.includes('Execute') ? 'trade' :
        line.includes('[Risk') ? 'risk' :
        line.includes('ERROR') ? 'error' : 'info'
      );
      div.textContent = line;
      container.appendChild(div);
    });
    container.scrollTop = container.scrollHeight;
  }
}

// SSE for live updates
const es = new EventSource('/stream');
es.onmessage = e => { try { updateUI(JSON.parse(e.data)); } catch(err) {} };
es.onerror = () => { document.getElementById('status-dot').style.background = '#f44336'; };
es.onopen = () => { document.getElementById('status-dot').style.background = '#4caf50'; };

// Also poll every 10s as fallback
setInterval(() => fetch('/api/state').then(r=>r.json()).then(updateUI), 10000);
fetch('/api/state').then(r=>r.json()).then(updateUI);
</script>
</body>
</html>'''

def read_logs():
    """Read all JSONL log files and return parsed entries."""
    entries = []
    if not LOG_DIR.exists():
        return entries
    for f in sorted(LOG_DIR.glob("cycle_*.jsonl")):
        try:
            for line in f.read_text().strip().split("\n"):
                if line:
                    entries.append(json.loads(line))
        except Exception:
            pass
    return entries

def get_state():
    entries = read_logs()
    if not entries:
        return {
            "capital": 600.0,
            "cycle": 0,
            "total_trades": 0,
            "last_exposure": 0,
            "paper_mode": True,
            "cycles": [],
            "recent_logs": ["Waiting for first cycle..."],
        }

    latest = entries[-1]
    total_trades = sum(e.get("trades_executed", 0) for e in entries)
    all_logs = []
    for e in entries[-5:]:
        all_logs.extend(e.get("logs", []))

    return {
        "capital": latest.get("capital", 600.0),
        "cycle": latest.get("cycle", 0),
        "total_trades": total_trades,
        "last_exposure": latest.get("total_exposure", 0),
        "paper_mode": latest.get("paper_mode", True),
        "cycles": entries,
        "recent_logs": all_logs[-20:],
    }

@app.route("/")
def index():
    return render_template_string(DASHBOARD_HTML)

@app.route("/api/state")
def api_state():
    return jsonify(get_state())

@app.route("/stream")
def stream():
    def event_stream():
        while True:
            state = get_state()
            yield f"data: {json.dumps(state)}\n\n"
            time.sleep(5)
    return Response(event_stream(), mimetype="text/event-stream",
                    headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})

if __name__ == "__main__":
    port = int(os.getenv("DASHBOARD_PORT", "8766"))
    print(f"QPTS Dashboard: http://localhost:{port}")
    app.run(host="0.0.0.0", port=port, debug=False, threaded=True)
