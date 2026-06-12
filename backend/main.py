"""
AI 视觉对话助手 — Backend Entry Point
FastAPI + deepagents
"""

import os
import logging
from contextlib import asynccontextmanager

from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from openai import AsyncOpenAI

from websocket_handler import router as ws_router

load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
logger = logging.getLogger(__name__)


# --- Global state ---
class AppState:
    def __init__(self):
        self.openai_client: AsyncOpenAI | None = None
        self.api_key_available: bool = False


state = AppState()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize OpenAI client on startup."""
    api_key = os.getenv("OPENAI_API_KEY")
    base_url = os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1")

    if api_key and api_key != "sk-your-api-key-here":
        state.openai_client = AsyncOpenAI(api_key=api_key, base_url=base_url)
        state.api_key_available = True
        logger.info("OpenAI client initialized (base_url=%s)", base_url)
    else:
        logger.warning("OPENAI_API_KEY not set or still default. Running in DEMO MODE.")
        logger.warning("Vision analysis, STT, and TTS will use mock responses.")
        logger.warning("Set OPENAI_API_KEY in .env file for full functionality.")
        state.api_key_available = False

    yield

    if state.openai_client:
        await state.openai_client.aclose()
        logger.info("OpenAI client closed")


app = FastAPI(
    title="AI Vision Chat Assistant",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(ws_router)

# Serve static files (web test client) at /app
static_dir = os.path.join(os.path.dirname(__file__), "static")
os.makedirs(static_dir, exist_ok=True)
app.mount("/app", StaticFiles(directory=static_dir, html=True), name="static")


@app.get("/")
async def root():
    return {
        "service": "AI Vision Chat Assistant",
        "version": "1.0.0",
        "mode": "full" if state.api_key_available else "demo",
        "docs": "/docs",
        "web_client": "/app",
        "websocket": "/ws?session_id=<your-session-id>",
    }


@app.get("/api/health")
async def health():
    return {
        "status": "ok",
        "service": "ai-vision-chat",
        "mode": "full" if state.api_key_available else "demo",
        "version": "1.0.0",
    }


if __name__ == "__main__":
    import uvicorn
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8000"))
    uvicorn.run("main:app", host=host, port=port, reload=True)
