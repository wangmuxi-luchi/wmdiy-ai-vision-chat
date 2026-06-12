"""
WebSocket handler — manages real-time bidirectional communication with Flutter clients.
Uses proper FastAPI WebSocket patterns.
"""

import json
import logging
import uuid
from typing import Any

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

logger = logging.getLogger(__name__)

router = APIRouter()


class ConnectionManager:
    """Manage WebSocket connections per session."""

    def __init__(self):
        self._connections: dict[str, WebSocket] = {}

    async def connect(self, session_id: str, ws: WebSocket):
        await ws.accept()
        self._connections[session_id] = ws
        logger.info("Client connected: session=%s", session_id)

    def disconnect(self, session_id: str):
        self._connections.pop(session_id, None)
        logger.info("Client disconnected: session=%s", session_id)

    async def send_json(self, session_id: str, data: dict[str, Any]):
        ws = self._connections.get(session_id)
        if ws:
            await ws.send_json(data)

    async def send_bytes(self, session_id: str, data: bytes):
        ws = self._connections.get(session_id)
        if ws:
            await ws.send_bytes(data)

    def is_connected(self, session_id: str) -> bool:
        return session_id in self._connections


manager = ConnectionManager()


@router.websocket("/ws")
async def websocket_endpoint(ws: WebSocket, session_id: str | None = None):
    if not session_id:
        session_id = str(uuid.uuid4())

    await manager.connect(session_id, ws)
    try:
        # Send welcome message
        await manager.send_json(session_id, {
            "type": "connected",
            "session_id": session_id,
            "message": "AI Vision Chat connected",
        })

        while True:
            # Use receive_text() for JSON messages (frames, audio, control)
            # and receive_bytes() for binary data (future use)
            try:
                text = await ws.receive_text()
                await handle_text_message(session_id, text)
            except WebSocketDisconnect:
                break
            except Exception as e:
                logger.warning("Receive error (session=%s): %s", session_id, e)
                break

    except WebSocketDisconnect:
        pass
    except Exception as e:
        logger.error("WebSocket error (session=%s): %s", session_id, e, exc_info=True)
    finally:
        manager.disconnect(session_id)


async def handle_text_message(session_id: str, text: str):
    """Route JSON text messages to the appropriate handler."""
    try:
        msg = json.loads(text)
    except json.JSONDecodeError:
        logger.warning("Invalid JSON from session=%s", session_id)
        return

    msg_type = msg.get("type")
    data = msg.get("data")

    if msg_type == "frame":
        # Video frame (Base64 JPEG) — handled by vision processor
        from vision_processor import process_frame
        description = await process_frame(session_id, data)
        if description:
            await manager.send_json(session_id, {
                "type": "frame_analyzed",
                "description": description,
            })

    elif msg_type == "audio":
        # Audio chunk (Base64 encoded) — handled by audio processor
        from audio_processor import process_audio_chunk
        await process_audio_chunk(session_id, data)

    elif msg_type == "control":
        # Control commands
        cmd = data.get("command") if isinstance(data, dict) else data
        logger.info("Control command from session=%s: %s", session_id, cmd)
        await manager.send_json(session_id, {
            "type": "control_ack",
            "command": cmd,
        })

    elif msg_type == "ping":
        await manager.send_json(session_id, {"type": "pong"})

    elif msg_type == "test_chat":
        # Direct text chat (for web test client)
        from agent_orchestrator import process_user_input
        from cost_controller import frame_controller, conversation_budget

        # Try to get latest frame description
        description = frame_controller.get_latest_description(session_id)

        # Send user message to frontend
        await manager.send_json(session_id, {
            "type": "user_message",
            "text": data if isinstance(data, str) else str(data),
        })

        # Process through agent
        try:
            reply = await process_user_input(session_id, str(data), description)
        except Exception as e:
            logger.error("Agent failed: %s", e)
            reply = f"抱歉，处理出错: {str(e)[:100]}"

        # Send reply
        if reply:
            await manager.send_json(session_id, {
                "type": "assistant_message",
                "text": reply,
            })
