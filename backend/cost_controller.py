"""
Cost control layer — manages token budgets, frame sampling, and silence detection.
"""

import time
import logging
from collections import deque

import numpy as np

logger = logging.getLogger(__name__)


class FrameRateController:
    """
    Controls frame sampling rate with adaptive down-scaling.
    Drops frames when scene is static to save API costs.
    """

    def __init__(self, max_fps: float = 1.0, min_fps: float = 0.2):
        self.max_fps = max_fps
        self.min_fps = min_fps
        self._last_frame_time: dict[str, float] = {}
        self._last_frame_data: dict[str, str] = {}
        self._static_count: dict[str, int] = {}
        self._last_descriptions: dict[str, str] = {}

    def should_sample(self, session_id: str, frame_data: str) -> bool:
        """Return True if this frame should be processed (sent to Vision API)."""
        now = time.time()
        last_time = self._last_frame_time.get(session_id, 0.0)

        # Enforce minimum interval
        min_interval = 1.0 / self.max_fps
        if now - last_time < min_interval:
            return False

        # Detect static scene: if frame is identical (or very similar) to last one
        last_frame = self._last_frame_data.get(session_id)
        if last_frame == frame_data:
            self._static_count[session_id] = self._static_count.get(session_id, 0) + 1
        else:
            self._static_count[session_id] = 0

        # If scene is static for >3 consecutive checks, down-sample
        static_count = self._static_count.get(session_id, 0)
        if static_count > 3:
            slow_interval = 1.0 / self.min_fps
            if now - last_time < slow_interval:
                # Still in slow mode — skip
                return False
            # Allow through at slow rate
            self._last_frame_time[session_id] = now
            self._last_frame_data[session_id] = frame_data
            return True

        self._last_frame_time[session_id] = now
        self._last_frame_data[session_id] = frame_data
        return True


    def get_latest_description(self, session_id: str) -> str | None:
        """Return the description of the last analyzed frame for this session."""
        return self._last_descriptions.get(session_id)

    def set_latest_description(self, session_id: str, description: str):
        """Store the description from the latest analyzed frame."""
        self._last_descriptions[session_id] = description



class SilenceDetector:
    """
    Detects silence in audio PCM data.
    Used to skip STT API calls when the user isn't speaking.
    """

    def __init__(self, threshold: float = 500.0):
        self.threshold = threshold

    def is_silence(self, pcm_bytes: bytes) -> bool:
        """Return True if audio chunk is below energy threshold."""
        if len(pcm_bytes) < 2:
            return True
        # Convert bytes to int16 samples
        samples = np.frombuffer(pcm_bytes, dtype=np.int16)
        if len(samples) == 0:
            return True
        rms = np.sqrt(np.mean(samples.astype(np.float32) ** 2))
        return rms < self.threshold


class ConversationBudget:
    """
    Manages conversation token budgets.
    When the history grows too large, triggers summarization.
    """

    def __init__(self, max_tokens: int = 4096):
        self.max_tokens = max_tokens
        self._history: dict[str, list[dict]] = {}
        self._token_counts: dict[str, int] = {}

    def add_message(self, session_id: str, role: str, content: str, token_count: int):
        if session_id not in self._history:
            self._history[session_id] = []
            self._token_counts[session_id] = 0

        self._history[session_id].append({"role": role, "content": content})
        self._token_counts[session_id] += token_count

        # Check if we need to trigger summarization
        if self._token_counts[session_id] > self.max_tokens:
            logger.info("Token budget exceeded for session=%s, triggering summarization", session_id)
            return True  # Signal that summarization is needed

        return False

    def needs_summary(self, session_id: str) -> bool:
        return self._token_counts.get(session_id, 0) > self.max_tokens

    def get_recent_context(self, session_id: str, max_messages: int = 10) -> list[dict]:
        history = self._history.get(session_id, [])
        return history[-max_messages:]

    def replace_with_summary(self, session_id: str, summary: str, summary_tokens: int):
        """Replace conversation history with a summary."""
        self._history[session_id] = [
            {"role": "system", "content": f"Previous conversation summary: {summary}"}
        ]
        self._token_counts[session_id] = summary_tokens


# Global instances
frame_controller = FrameRateController()
silence_detector = SilenceDetector()
conversation_budget = ConversationBudget()
