"""
QPTS Telegram Alerts
Integrates with existing openclaw Telegram bot
"""
import os
import json
import requests
from typing import Optional
from dotenv import load_dotenv

load_dotenv()

TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_ADMIN_ID = os.getenv("TELEGRAM_ADMIN_ID", "8531161985")

def send_alert(message: str, level: str = "info") -> bool:
    """Send alert to Telegram."""
    if not TELEGRAM_BOT_TOKEN:
        print(f"[Telegram] No token configured. Message: {message}")
        return False

    emoji_map = {
        "info": "ℹ️",
        "success": "✅",
        "warning": "⚠️",
        "error": "🚨",
        "trade": "💰",
    }

    emoji = emoji_map.get(level, "ℹ️")
    formatted = f"{emoji} *QPTS Harvey*\n\n{message}"

    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    payload = {
        "chat_id": TELEGRAM_ADMIN_ID,
        "text": formatted,
        "parse_mode": "Markdown",
    }

    try:
        resp = requests.post(url, json=payload, timeout=5)
        return resp.status_code == 200
    except Exception as e:
        print(f"[Telegram] Failed: {e}")
        return False

def alert_trade_executed(trade: dict, paper_mode: bool = True) -> None:
    mode = "PAPER" if paper_mode else "🔴 LIVE"
    msg = (
        f"*Trade Executed [{mode}]*\n"
        f"Market: {trade.get('question', 'N/A')[:60]}\n"
        f"Side: {trade.get('side', 'N/A')}\n"
        f"Size: ${trade.get('position_size', 0):.2f}\n"
        f"Price: {trade.get('token_price', 0):.3f}\n"
        f"EV: {trade.get('expected_value', 0):.4f}\n"
        f"Kelly: {trade.get('kelly_fraction', 0):.3f}"
    )
    send_alert(msg, "trade" if not paper_mode else "info")

def alert_drawdown(current_capital: float, start_capital: float, threshold: float = 0.10) -> None:
    drawdown = (start_capital - current_capital) / start_capital
    if drawdown >= threshold:
        msg = (
            f"*Drawdown Alert*\n"
            f"Capital: ${current_capital:.2f} (started ${start_capital:.2f})\n"
            f"Drawdown: {drawdown:.1%}\n"
            f"Action: Review strategy before next cycle"
        )
        send_alert(msg, "warning")

def alert_cycle_summary(cycle: int, capital: float, trades: int, paper_mode: bool) -> None:
    mode = "Paper" if paper_mode else "Live"
    msg = (
        f"*Cycle #{cycle} Complete [{mode}]*\n"
        f"Capital: ${capital:.2f}\n"
        f"Trades: {trades}"
    )
    send_alert(msg, "info")

def alert_backtest_result(go: bool, sharpe: float, drawdown: float, ruin_prob: float) -> None:
    status = "✅ GO" if go else "❌ NO-GO"
    msg = (
        f"*Backtest Result: {status}*\n"
        f"Sharpe: {sharpe:.2f}\n"
        f"Max Drawdown: {drawdown:.1f}%\n"
        f"Ruin Probability: {ruin_prob:.1%}"
    )
    send_alert(msg, "success" if go else "warning")
