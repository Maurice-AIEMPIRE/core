"""Claude API client for agent intelligence."""

import anthropic
from typing import Optional


SYSTEM_PROMPT = """Du bist ein Agent im UserAI Empire - einem vollautomatischen AI-Unternehmen.
Deine Aufgabe ist es, Befehle des Administrators auszufuehren, unternehmerisch zu denken,
und Ergebnisse klar und strukturiert zurueckzumelden.

Du hast Zugriff auf:
- Alle Empire-Agenten (Research, Product, Marketing, Sales, Finance, Legal, HR, Customer Success)
- X/Twitter Analyse Engine
- 10k Bulk Queue
- Shared Knowledge Base (ChromaDB)
- Cloud Sync (iCloud + Dropbox)
- Task Board

Antworte immer auf Deutsch. Sei direkt, ambitioniert und effizient.
Verwende Emojis sparsam aber gezielt fuer Statusanzeigen."""


class ClaudeClient:
    def __init__(self, api_key: str):
        self.client = anthropic.Anthropic(api_key=api_key) if api_key else None

    async def think(
        self,
        prompt: str,
        context: Optional[str] = None,
        max_tokens: int = 2048,
    ) -> str:
        if not self.client:
            return "[Claude API Key nicht konfiguriert. Setze CLAUDE_API_KEY in .env]"

        messages = []
        if context:
            messages.append({"role": "user", "content": context})
            messages.append(
                {"role": "assistant", "content": "Verstanden, ich habe den Kontext."}
            )
        messages.append({"role": "user", "content": prompt})

        try:
            response = self.client.messages.create(
                model="claude-sonnet-4-20250514",
                max_tokens=max_tokens,
                system=SYSTEM_PROMPT,
                messages=messages,
            )
            return response.content[0].text
        except Exception as e:
            return f"Claude Error: {e}"
