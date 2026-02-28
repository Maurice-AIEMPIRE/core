import os
from dataclasses import dataclass


@dataclass
class Config:
    telegram_token: str
    admin_chat_id: int
    claude_api_key: str
    redis_url: str
    chroma_host: str
    chroma_port: int
    x_bearer_token: str
    empire_data_dir: str

    @classmethod
    def from_env(cls) -> "Config":
        return cls(
            telegram_token=os.environ["TELEGRAM_BOT_TOKEN"],
            admin_chat_id=int(os.environ["TELEGRAM_ADMIN_CHAT_ID"]),
            claude_api_key=os.environ.get("CLAUDE_API_KEY", ""),
            redis_url=os.environ.get("REDIS_URL", "redis://redis:6379"),
            chroma_host=os.environ.get("CHROMA_HOST", "chromadb"),
            chroma_port=int(os.environ.get("CHROMA_PORT", "8000")),
            x_bearer_token=os.environ.get("X_BEARER_TOKEN", ""),
            empire_data_dir=os.environ.get("EMPIRE_DATA_DIR", "/empire"),
        )
