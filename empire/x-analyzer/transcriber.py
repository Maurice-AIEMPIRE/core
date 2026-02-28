"""
Video/Audio Transcriber
========================
Uses OpenAI Whisper (local, free) to transcribe video/audio content.
"""

import logging
import os

logger = logging.getLogger("transcriber")

# Lazy load whisper to avoid import time on startup
_model = None


def _get_model():
    """Load whisper model (lazy, cached)."""
    global _model
    if _model is None:
        import whisper
        model_size = os.environ.get("WHISPER_MODEL", "base")
        logger.info(f"Loading Whisper model: {model_size}")
        _model = whisper.load_model(model_size)
        logger.info("Whisper model loaded.")
    return _model


async def transcribe_video(video_path: str) -> str:
    """
    Transcribe a video file to text using Whisper.

    Args:
        video_path: Path to the video/audio file.

    Returns:
        Transcribed text.
    """
    if not os.path.exists(video_path):
        logger.error(f"Video file not found: {video_path}")
        return ""

    try:
        model = _get_model()
        logger.info(f"Transcribing: {video_path}")

        result = model.transcribe(
            video_path,
            language=None,  # Auto-detect language
            verbose=False,
        )

        text = result.get("text", "").strip()
        language = result.get("language", "unknown")
        logger.info(f"Transcription complete. Language: {language}, Length: {len(text)} chars")

        return text

    except Exception as e:
        logger.error(f"Transcription error: {e}", exc_info=True)
        return f"[Transcription failed: {e}]"


async def transcribe_audio(audio_path: str) -> str:
    """Alias for transcribe_video - works with audio files too."""
    return await transcribe_video(audio_path)
