"""Generic AI Chat Bot for Telegram.

Each instance connects to one AI model via LiteLLM.
Supports conversation history, streaming, and auto-recovery.
"""

from __future__ import annotations

import asyncio
import logging
import time
from collections import defaultdict
from dataclasses import dataclass, field

import aiohttp
from telegram import Update
from telegram.constants import ChatAction, ParseMode
from telegram.ext import (
    Application,
    CommandHandler,
    ContextTypes,
    MessageHandler,
    filters,
)

logger = logging.getLogger(__name__)

MAX_HISTORY = 20  # messages per user
MAX_MESSAGE_LENGTH = 4096  # Telegram limit


@dataclass
class BotConfig:
    """Configuration for a single bot instance."""

    name: str
    token: str
    model: str
    litellm_url: str = "http://litellm:4000"
    litellm_api_key: str = "sk-galaxia-local"
    system_prompt: str = ""
    max_tokens: int = 2048
    temperature: float = 0.7


@dataclass
class ConversationHistory:
    """Per-user conversation history."""

    messages: list = field(default_factory=list)
    last_active: float = field(default_factory=time.time)

    def add(self, role: str, content: str) -> None:
        self.messages.append({"role": role, "content": content})
        if len(self.messages) > MAX_HISTORY:
            self.messages = self.messages[-MAX_HISTORY:]
        self.last_active = time.time()

    def clear(self) -> None:
        self.messages.clear()

    def get_messages(self, system_prompt: str) -> list[dict]:
        msgs = []
        if system_prompt:
            msgs.append({"role": "system", "content": system_prompt})
        msgs.extend(self.messages)
        return msgs


class AIChatBot:
    """A Telegram bot powered by a specific AI model."""

    def __init__(self, config: BotConfig):
        self.config = config
        self._app: Application | None = None
        self._conversations: dict[int, ConversationHistory] = defaultdict(
            ConversationHistory
        )
        self._request_count = 0
        self._error_count = 0
        self._start_time = time.time()

    @property
    def uptime_seconds(self) -> float:
        return time.time() - self._start_time

    async def start(self) -> None:
        """Start the bot."""
        self._app = Application.builder().token(self.config.token).build()

        self._app.add_handler(CommandHandler("start", self._cmd_start))
        self._app.add_handler(CommandHandler("help", self._cmd_help))
        self._app.add_handler(CommandHandler("model", self._cmd_model))
        self._app.add_handler(CommandHandler("clear", self._cmd_clear))
        self._app.add_handler(CommandHandler("stats", self._cmd_stats))
        self._app.add_handler(
            MessageHandler(filters.TEXT & ~filters.COMMAND, self._handle_message)
        )

        await self._app.initialize()
        await self._app.start()
        await self._app.updater.start_polling(
            drop_pending_updates=True,
            allowed_updates=["message"],
        )
        logger.info("[%s] Bot gestartet mit Modell: %s", self.config.name, self.config.model)

    async def stop(self) -> None:
        """Stop the bot gracefully."""
        if self._app:
            await self._app.updater.stop()
            await self._app.stop()
            await self._app.shutdown()
            logger.info("[%s] Bot gestoppt", self.config.name)

    async def _call_llm(self, messages: list[dict]) -> str:
        """Call LiteLLM API with the conversation."""
        url = f"{self.config.litellm_url}/v1/chat/completions"
        headers = {
            "Authorization": f"Bearer {self.config.litellm_api_key}",
            "Content-Type": "application/json",
        }
        payload = {
            "model": self.config.model,
            "messages": messages,
            "max_tokens": self.config.max_tokens,
            "temperature": self.config.temperature,
        }

        async with aiohttp.ClientSession() as session:
            async with session.post(url, json=payload, headers=headers, timeout=aiohttp.ClientTimeout(total=120)) as resp:
                if resp.status != 200:
                    error_text = await resp.text()
                    raise RuntimeError(f"LiteLLM error {resp.status}: {error_text[:200]}")
                data = await resp.json()
                return data["choices"][0]["message"]["content"]

    async def _cmd_start(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
        name = self.config.name
        model = self.config.model
        await update.message.reply_text(
            f"*{name}*\n\n"
            f"Modell: `{model}`\n\n"
            f"Schreib mir einfach eine Nachricht und ich antworte dir!\n\n"
            f"*Befehle:*\n"
            f"/model - Welches Modell nutze ich?\n"
            f"/clear - Konversation zurucksetzen\n"
            f"/stats - Bot-Statistiken\n"
            f"/help - Diese Hilfe",
            parse_mode=ParseMode.MARKDOWN,
        )

    async def _cmd_help(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
        await self._cmd_start(update, ctx)

    async def _cmd_model(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
        await update.message.reply_text(
            f"*Modell-Info*\n\n"
            f"Bot: {self.config.name}\n"
            f"Modell: `{self.config.model}`\n"
            f"Max Tokens: {self.config.max_tokens}\n"
            f"Temperature: {self.config.temperature}",
            parse_mode=ParseMode.MARKDOWN,
        )

    async def _cmd_clear(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
        user_id = update.effective_user.id
        self._conversations[user_id].clear()
        await update.message.reply_text("Konversation geloscht. Frischer Start!")

    async def _cmd_stats(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
        uptime_h = int(self.uptime_seconds // 3600)
        uptime_m = int((self.uptime_seconds % 3600) // 60)
        await update.message.reply_text(
            f"*{self.config.name} Stats*\n\n"
            f"Uptime: {uptime_h}h {uptime_m}m\n"
            f"Requests: {self._request_count}\n"
            f"Errors: {self._error_count}\n"
            f"Aktive User: {len(self._conversations)}\n"
            f"Modell: `{self.config.model}`",
            parse_mode=ParseMode.MARKDOWN,
        )

    async def _handle_message(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
        """Handle incoming text messages."""
        user_id = update.effective_user.id
        text = update.message.text.strip()
        if not text:
            return

        # Show typing indicator
        await update.message.chat.send_action(ChatAction.TYPING)

        conv = self._conversations[user_id]
        conv.add("user", text)
        messages = conv.get_messages(self.config.system_prompt)

        self._request_count += 1

        try:
            response = await self._call_llm(messages)
            conv.add("assistant", response)

            # Split long messages
            if len(response) <= MAX_MESSAGE_LENGTH:
                await update.message.reply_text(response)
            else:
                chunks = [
                    response[i : i + MAX_MESSAGE_LENGTH]
                    for i in range(0, len(response), MAX_MESSAGE_LENGTH)
                ]
                for chunk in chunks:
                    await update.message.reply_text(chunk)

        except Exception as e:
            self._error_count += 1
            logger.error("[%s] LLM error: %s", self.config.name, e)
            await update.message.reply_text(
                f"Fehler bei der Anfrage an `{self.config.model}`:\n"
                f"`{str(e)[:200]}`\n\n"
                f"Versuche es nochmal oder /clear zum Zurucksetzen.",
                parse_mode=ParseMode.MARKDOWN,
            )
