"""
Vision processor — handles video frame analysis via GPT-4 Vision API.
"""

import base64
import io
import logging
import os
import time

from PIL import Image

logger = logging.getLogger(__name__)

# Resize dimension for frames before sending to API (saves tokens)
FRAME_RESIZE = int(os.getenv("FRAME_RESIZE", "512"))


def _resize_image(image_data: bytes, max_size: int = FRAME_RESIZE) -> bytes:
    """Resize image to max_size while preserving aspect ratio."""
    img = Image.open(io.BytesIO(image_data))
    w, h = img.size
    if max(w, h) <= max_size:
        return image_data
    ratio = max_size / max(w, h)
    new_size = (int(w * ratio), int(h * ratio))
    img = img.resize(new_size, Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=70)
    return buf.getvalue()


async def analyze_frame(
    openai_client,
    base64_jpeg: str,
    frame_resize: int = FRAME_RESIZE,
) -> str | None:
    """
    Send a video frame to GPT-4 Vision and return a text description.
    Returns None if analysis is skipped (e.g. frame too small).
    """
    try:
        # Decode, resize, re-encode
        raw_bytes = base64.b64decode(base64_jpeg)
        resized = _resize_image(raw_bytes, frame_resize)
        resized_b64 = base64.b64encode(resized).decode("utf-8")

        # Cost: resize reduces image tokens ~4x
        response = await openai_client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": "Describe what you see in this camera frame in 1-2 short sentences. "
                                    "Focus on visible objects, people, actions, and the environment.",
                        },
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/jpeg;base64,{resized_b64}",
                                "detail": "low",  # low detail = 85 tokens per image vs 170+ for high
                            },
                        },
                    ],
                }
            ],
            max_tokens=150,
        )

        description = response.choices[0].message.content.strip()
        logger.info("Frame analyzed: %.100s", description)

        # Store description for use by the agent loop
        try:
            from cost_controller import frame_controller
            frame_controller.set_latest_description(session_id, description)
        except Exception:
            pass

        return description

    except Exception as e:
        logger.error("Vision analysis failed: %s", e, exc_info=True)
        return None


async def process_frame(session_id: str, base64_jpeg: str) -> str | None:
    """Entry point called from websocket_handler."""
    from cost_controller import frame_controller
    from main import state

    if not frame_controller.should_sample(session_id, base64_jpeg):
        return None

    # Demo mode: skip real API call if no key configured
    if not state.api_key_available or not state.openai_client:
        logger.info("Demo mode: returning mock vision analysis")
        mock_desc = "我看到一个用户在摄像头前（演示模式 — 未配置 API Key）"
        frame_controller.set_latest_description(session_id, mock_desc)
        # Still forward the frame to keep UI informed
        return mock_desc

    return await analyze_frame(state.openai_client, base64_jpeg)
