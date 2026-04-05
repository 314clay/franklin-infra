"""__SERVICE_NAME__ — chainable microservice server.

Generic FastAPI server that connects to an upstream WebSocket or SSE source,
delegates processing to the `process` module, and exposes results via REST + SSE.
"""

import asyncio
import json
import logging
import os
import time
from collections import defaultdict
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path

import httpx
import websockets
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse

import process

# --- Config ---

PORT = int(os.environ.get("PORT", "__PORT__"))
CHUNK_INTERVAL = float(os.environ.get("CHUNK_INTERVAL", "5"))  # seconds between chunk flushes
OUTPUT_DIR = Path(os.environ.get("OUTPUT_DIR", "output"))
START_TIME = time.time()

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(message)s")
log = logging.getLogger(process.SERVICE_NAME)

# --- State ---

# Active sessions: session_id -> session info
sessions: dict[str, dict] = {}

# Processing results: session_id -> list of result dicts
results: dict[str, list[dict]] = defaultdict(list)

# SSE listeners for live updates
sse_listeners: dict[str, set[asyncio.Queue]] = defaultdict(set)


async def broadcast_result(session_id: str, result: dict):
    """Push a result to all SSE listeners for this session."""
    message = f"event: result\ndata: {json.dumps(result, default=str)}\n\n"
    dead = set()
    for queue in sse_listeners.get(session_id, set()):
        try:
            queue.put_nowait(message)
        except asyncio.QueueFull:
            dead.add(queue)
    if dead:
        sse_listeners[session_id] -= dead


# --- WebSocket Consumer ---

async def ws_consumer(ws_url: str, session_id: str):
    """Connect to an upstream WebSocket, accumulate binary chunks, and process them."""
    log.info(f"[{session_id}] WS connecting to {ws_url}")
    audio_buffer = bytearray()
    mime_type = "audio/webm"
    last_flush = time.time()
    chunk_index = 0

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    try:
        async with websockets.connect(ws_url) as ws:
            await ws.send(json.dumps({
                "type": "session_start",
                "service": process.SERVICE_NAME,
                "session_id": session_id,
                "mime_type": mime_type,
                "timestamp": datetime.now(timezone.utc).isoformat(),
            }))

            sessions[session_id]["status"] = "connected"
            log.info(f"[{session_id}] Connected, accumulating chunks...")

            async for message in ws:
                if isinstance(message, bytes):
                    audio_buffer.extend(message)

                    now = time.time()
                    if now - last_flush >= CHUNK_INTERVAL and len(audio_buffer) > 1000:
                        chunk_bytes = bytes(audio_buffer)
                        audio_buffer.clear()
                        last_flush = now
                        chunk_index += 1

                        asyncio.create_task(
                            _process_chunk(session_id, chunk_bytes, chunk_index, mime_type)
                        )

                elif isinstance(message, str):
                    try:
                        msg = json.loads(message)
                        if msg.get("type") == "ack":
                            log.info(f"[{session_id}] Server ack: {msg.get('session_id')}")
                        elif msg.get("type") == "pong":
                            pass
                    except json.JSONDecodeError:
                        pass

    except websockets.ConnectionClosed:
        log.info(f"[{session_id}] WebSocket closed")
    except Exception as e:
        log.error(f"[{session_id}] WS error: {e}")
    finally:
        # Flush remaining buffer
        if len(audio_buffer) > 1000:
            chunk_index += 1
            await _process_chunk(session_id, bytes(audio_buffer), chunk_index, mime_type)

        sessions[session_id]["status"] = "disconnected"
        sessions[session_id]["ended_at"] = datetime.now(timezone.utc).isoformat()
        log.info(f"[{session_id}] WS session ended, {chunk_index} chunks processed")


async def _process_chunk(session_id: str, chunk_bytes: bytes, chunk_index: int, mime_type: str):
    """Delegate a binary chunk to process.handle_chunk and store the result."""
    log.info(f"[{session_id}] Processing chunk {chunk_index} ({len(chunk_bytes)} bytes)...")

    try:
        result = await process.handle_chunk(session_id, chunk_bytes, chunk_index, mime_type)
    except Exception as e:
        log.error(f"[{session_id}] Chunk {chunk_index} failed: {e}")
        return

    if result:
        result.setdefault("chunk", chunk_index)
        result.setdefault("timestamp", datetime.now(timezone.utc).isoformat())
        results[session_id].append(result)
        log.info(f"[{session_id}] Chunk {chunk_index}: {result.get('text', '(no text)')}")

        await broadcast_result(session_id, result)

        out_file = OUTPUT_DIR / f"{session_id}.jsonl"
        with open(out_file, "a") as f:
            f.write(json.dumps(result, default=str) + "\n")
    else:
        log.warning(f"[{session_id}] Chunk {chunk_index}: no result returned")


# --- SSE Consumer ---

async def sse_consumer(sse_url: str, session_id: str):
    """Connect to an upstream SSE endpoint and process each event."""
    log.info(f"[{session_id}] SSE connecting to {sse_url}")
    event_index = 0

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    try:
        async with httpx.AsyncClient(timeout=None) as client:
            async with client.stream("GET", sse_url) as resp:
                if resp.status_code != 200:
                    log.error(f"[{session_id}] SSE upstream returned {resp.status_code}")
                    sessions[session_id]["status"] = "error"
                    return

                sessions[session_id]["status"] = "connected"
                log.info(f"[{session_id}] SSE connected")

                event_type = None
                data_lines: list[str] = []

                async for line in resp.aiter_lines():
                    if line.startswith("event:"):
                        event_type = line[6:].strip()
                    elif line.startswith("data:"):
                        data_lines.append(line[5:].strip())
                    elif line == "":
                        # Empty line = end of SSE event
                        if data_lines:
                            raw_data = "\n".join(data_lines)
                            data_lines.clear()

                            # Skip heartbeats
                            if event_type == "heartbeat":
                                event_type = None
                                continue

                            try:
                                event_data = json.loads(raw_data)
                            except json.JSONDecodeError:
                                event_data = {"raw": raw_data}

                            event_index += 1
                            asyncio.create_task(
                                _process_event(session_id, event_data, event_index, event_type)
                            )

                        event_type = None

    except httpx.RemoteProtocolError:
        log.info(f"[{session_id}] SSE stream closed by server")
    except Exception as e:
        log.error(f"[{session_id}] SSE error: {e}")
    finally:
        sessions[session_id]["status"] = "disconnected"
        sessions[session_id]["ended_at"] = datetime.now(timezone.utc).isoformat()
        log.info(f"[{session_id}] SSE session ended, {event_index} events processed")


async def _process_event(session_id: str, event_data: dict, event_index: int, event_type: str | None):
    """Delegate an SSE event to process.handle_event and store the result."""
    log.info(f"[{session_id}] Processing event {event_index} (type={event_type})...")

    try:
        result = await process.handle_event(session_id, event_data, event_index)
    except Exception as e:
        log.error(f"[{session_id}] Event {event_index} failed: {e}")
        return

    if result:
        result.setdefault("event_index", event_index)
        result.setdefault("event_type", event_type)
        result.setdefault("timestamp", datetime.now(timezone.utc).isoformat())
        results[session_id].append(result)
        log.info(f"[{session_id}] Event {event_index}: {result.get('text', '(no text)')}")

        await broadcast_result(session_id, result)

        out_file = OUTPUT_DIR / f"{session_id}.jsonl"
        with open(out_file, "a") as f:
            f.write(json.dumps(result, default=str) + "\n")
    else:
        log.debug(f"[{session_id}] Event {event_index}: skipped (no result)")


# --- App ---

@asynccontextmanager
async def lifespan(app: FastAPI):
    log.info(f"{process.SERVICE_NAME} starting on port {PORT}")
    await process.setup()
    yield
    for sid, info in sessions.items():
        if "task" in info and not info["task"].done():
            info["task"].cancel()


app = FastAPI(lifespan=lifespan)


@app.get("/api/state")
async def health():
    return {
        "status": "ok",
        "service": process.SERVICE_NAME,
        "active_sessions": len([s for s in sessions.values() if s.get("status") == "connected"]),
        "uptime_seconds": int(time.time() - START_TIME),
    }


@app.post("/api/connect")
async def connect_upstream(request: Request):
    """Subscribe to an upstream source.

    Body: { "ws_url": "ws://..." } OR { "sse_url": "http://..." }
    Optional: { "session_id": "custom_id" }
    """
    body = await request.json()
    ws_url = body.get("ws_url")
    sse_url = body.get("sse_url")

    if ws_url and sse_url:
        return JSONResponse({"error": "provide ws_url or sse_url, not both"}, 400)
    if not ws_url and not sse_url:
        return JSONResponse({"error": "ws_url or sse_url required"}, 400)

    session_id = body.get("session_id") or f"s_{int(time.time())}"
    upstream_url = ws_url or sse_url
    upstream_type = "ws" if ws_url else "sse"

    if session_id in sessions and sessions[session_id].get("status") == "connected":
        return JSONResponse({"error": "session already active"}, 409)

    if ws_url:
        task = asyncio.create_task(ws_consumer(ws_url, session_id))
    else:
        task = asyncio.create_task(sse_consumer(sse_url, session_id))

    sessions[session_id] = {
        "session_id": session_id,
        "upstream_url": upstream_url,
        "upstream_type": upstream_type,
        "status": "connecting",
        "started_at": datetime.now(timezone.utc).isoformat(),
        "task": task,
    }

    return JSONResponse({
        "session_id": session_id,
        "upstream_url": upstream_url,
        "upstream_type": upstream_type,
        "status": "connecting",
        "transcript_url": f"/api/transcript/{session_id}",
        "live_url": f"/api/live/{session_id}",
    }, 201)


@app.delete("/api/session/{session_id}")
async def stop_session(session_id: str):
    """Stop an active session."""
    if session_id not in sessions:
        return JSONResponse({"error": "not found"}, 404)

    info = sessions[session_id]
    if "task" in info and not info["task"].done():
        info["task"].cancel()

    info["status"] = "stopped"
    return {"session_id": session_id, "status": "stopped"}


@app.get("/api/sessions")
async def list_sessions():
    """List all sessions."""
    return {
        "sessions": [
            {k: v for k, v in info.items() if k != "task"}
            for info in sessions.values()
        ]
    }


@app.get("/api/topology")
async def topology():
    """Report this service's upstream connections and downstream listeners."""
    upstreams = []
    for sid, info in sessions.items():
        upstreams.append({
            "session_id": sid,
            "upstream_url": info.get("upstream_url"),
            "upstream_type": info.get("upstream_type"),
            "status": info.get("status"),
        })

    downstreams = {}
    for sid, listeners in sse_listeners.items():
        downstreams[sid] = len(listeners)

    return {
        "service": process.SERVICE_NAME,
        "url": f"http://localhost:{PORT}",
        "upstreams": upstreams,
        "downstreams": downstreams,
        "active_sessions": len([u for u in upstreams if u["status"] == "connected"]),
    }


@app.get("/api/transcript/{session_id}")
async def get_transcript(session_id: str):
    """Get full processing history for a session."""
    segments = results.get(session_id, [])
    return {
        "session_id": session_id,
        "segments": segments,
        "full_text": " ".join(s.get("text", "") for s in segments if s.get("text")),
    }


@app.get("/api/live/{session_id}")
async def live_stream(session_id: str, request: Request):
    """SSE stream of live results with replay and heartbeat."""
    queue: asyncio.Queue = asyncio.Queue(maxsize=256)
    sse_listeners[session_id].add(queue)

    async def event_generator():
        try:
            # Replay existing results
            for seg in results.get(session_id, []):
                yield f"event: result\ndata: {json.dumps(seg, default=str)}\n\n"

            while True:
                try:
                    message = await asyncio.wait_for(queue.get(), timeout=15.0)
                    yield message
                except asyncio.TimeoutError:
                    yield f"event: heartbeat\ndata: {json.dumps({'time': datetime.now(timezone.utc).isoformat()})}\n\n"

                if await request.is_disconnected():
                    break
        finally:
            sse_listeners[session_id].discard(queue)
            if not sse_listeners[session_id]:
                del sse_listeners[session_id]

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "Connection": "keep-alive"},
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=PORT)
