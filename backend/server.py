"""
Local HTTP API for the Swift client. Loads one Quaynor Chat session (see
https://www.quaynor.site/python/ and https://www.quaynor.site/python/chat/).
Streaming tokens via ChatAsync: https://www.quaynor.site/python/streaming-and-async-api/
"""

from __future__ import annotations

import asyncio
import json
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from quaynor import ChatAsync

DEFAULT_MODEL = (
    "huggingface:bartowski/Qwen_Qwen3-0.6B-GGUF/Qwen_Qwen3-0.6B-Q4_K_M.gguf"
)

_chat: ChatAsync | None = None
_chat_lock = asyncio.Lock()


def _model_path() -> str:
    return os.environ.get("QUAYNOR_MODEL", DEFAULT_MODEL)


SYSTEM_PROMPT = """You are a clear, helpful assistant.

Write in short paragraphs. Put a blank line between separate ideas so the reply is easy to scan.

Use plain punctuation: commas and periods. Do not use em dashes (—) or en dashes (–) as punctuation. If you need a break in a sentence, use a comma or split into two sentences. For compound words or ranges, a simple hyphen (-) is fine.

Keep a natural, conversational tone without sounding stiff or over-formatted."""


def _create_chat() -> ChatAsync:
    return ChatAsync(
        _model_path(),
        n_ctx=2048,
        template_variables={"enable_thinking": False},
        system_prompt=SYSTEM_PROMPT,
    )


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _chat
    _chat = await asyncio.to_thread(_create_chat)
    yield


app = FastAPI(title="Quaynor Swift Backend", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class ChatIn(BaseModel):
    message: str = Field(..., min_length=1, max_length=8000)


class ChatOut(BaseModel):
    reply: str


@app.get("/health")
def health() -> dict:
    return {"ok": True, "model": _model_path()}


@app.post("/chat", response_model=ChatOut)
async def chat_endpoint(body: ChatIn) -> ChatOut:
    if _chat is None:
        raise RuntimeError("Chat not initialized")

    async with _chat_lock:
        reply = await _chat.ask(body.message.strip()).completed()

    return ChatOut(reply=reply)


@app.post("/chat/stream")
async def chat_stream(body: ChatIn):
    """Newline-delimited JSON: `{"t":"<token>"}\\n` … `{"done":true}\\n`"""

    if _chat is None:
        raise RuntimeError("Chat not initialized")

    async def ndjson_chunks():
        async with _chat_lock:
            response = _chat.ask(body.message.strip())
            async for token in response:
                line = json.dumps({"t": str(token)}) + "\n"
                yield line.encode("utf-8")
            yield (json.dumps({"done": True}) + "\n").encode("utf-8")

    return StreamingResponse(
        ndjson_chunks(),
        media_type="application/x-ndjson",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@app.post("/reset")
async def reset() -> dict:
    """Start a fresh conversation (same model, empty history)."""
    if _chat is None:
        raise RuntimeError("Chat not initialized")

    async with _chat_lock:
        _chat.reset_history()

    return {"ok": True}
