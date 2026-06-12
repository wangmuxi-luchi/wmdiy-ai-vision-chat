"""
Audio processor — handles speech-to-text (Whisper) and text-to-speech (TTS) via OpenAI API.
"""

import base64
import io
import logging
import os
import time

logger = logging.getLogger(__name__)


async def transcribe_audio(openai_client, audio_bytes: bytes) -> str | None:
    """
    Transcribe audio using OpenAI Whisper API.
    """
    try:
        # Whisper accepts file-like objects
        audio_file = io.BytesIO(audio_bytes)
        audio_file.name = "audio.wav"

        response = await openai_client.audio.transcriptions.create(
            model="whisper-1",
            file=audio_file,
            language="zh",  # Support Chinese; adjust as needed
        )
        text = response.text.strip()
        logger.info("Audio transcribed: %.100s", text)
        return text if text else None

    except Exception as e:
        logger.error("Whisper transcription failed: %s", e, exc_info=True)
        return None


async def synthesize_speech(openai_client, text: str) -> bytes | None:
    """
    Synthesize speech from text using OpenAI TTS API.
    Returns MP3 audio bytes.
    """
    try:
        response = await openai_client.audio.speech.create(
            model="tts-1",
            voice="alloy",
            input=text,
            response_format="mp3",
        )
        # OpenAI v2 API: response.content is the binary data
        audio_bytes = response.content
        logger.info("TTS synthesized: %d bytes for text: %.60s", len(audio_bytes), text)
        return audio_bytes

    except Exception as e:
        logger.error("TTS synthesis failed: %s", e, exc_info=True)
        return None


async def process_audio_chunk(session_id: str, base64_audio: str):
    """
    Entry point called from websocket_handler.
    Decodes audio -> silence check -> Whisper STT -> agent loop -> TTS -> send back.
    """
    from main import state
    from cost_controller import silence_detector, conversation_budget, frame_controller
    from websocket_handler import manager

    if not state.api_key_available:
        logger.debug("Demo mode: skipping audio processing")
        return

    # Decode
    try:
        audio_bytes = base64.b64decode(base64_audio)
    except Exception:
        logger.warning("Invalid base64 audio from session=%s", session_id)
        return

    # Silence check (cost control)
    if silence_detector.is_silence(audio_bytes):
        logger.debug("Silence detected, skipping STT for session=%s", session_id)
        return

    # Transcribe (or mock in demo mode)
    if state.api_key_available:
        text = await transcribe_audio(state.openai_client, audio_bytes)
    else:
        # Demo mode: mock transcription
        logger.info("Demo mode: skipping Whisper STT")
        text = None  # We'll handle this below

    if not text:
        # In demo mode, don't try to process audio chunks since we can't STT
        logger.debug("No text from audio (silence or demo mode)")
        return

    # Send user message to frontend for display
    await manager.send_json(session_id, {
        "type": "user_message",
        "text": text,
    })

    # Get latest frame description (from vision analysis)
    latest_description = frame_controller.get_latest_description(session_id)

    # Route through deepagents agent
    from agent_orchestrator import process_user_input
    try:
        reply = await process_user_input(session_id, text, latest_description)
    except Exception as e:
        logger.error("Agent failed for session=%s: %s", session_id, e)
        reply = "抱歉，我遇到了一些问题，请稍后再试。"

    if not reply:
        return

    # Send text reply to frontend
    await manager.send_json(session_id, {
        "type": "assistant_message",
        "text": reply,
    })

    # Synthesize and send TTS audio (skip in demo mode)
    if state.api_key_available:
        tts_bytes = await synthesize_speech(state.openai_client, reply)
        if tts_bytes:
            await manager.send_bytes(session_id, tts_bytes)
    else:
        logger.debug("Demo mode: skipping TTS synthesis")
