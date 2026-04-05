"""__SERVICE_NAME__ — custom processing logic.

Edit this file. Implement handle_chunk (for audio/binary upstream)
and/or handle_event (for text/JSON upstream via SSE).
"""

SERVICE_NAME = "__SERVICE_NAME__"
SERVICE_DESCRIPTION = "TODO: describe what this service does"


async def setup():
    """Called once at startup. Initialize clients, load models, etc."""
    pass


async def handle_chunk(
    session_id: str, chunk_bytes: bytes, chunk_index: int, mime_type: str
) -> dict | None:
    """Process a binary audio chunk from a WebSocket upstream.

    Return a dict to broadcast as an SSE event, or None to skip.
    The dict should contain a "text" key for downstream chaining.
    Example: {"text": "hello world", "confidence": 0.95}
    """
    raise NotImplementedError(
        "Implement handle_chunk for WS upstream, or remove if using SSE only"
    )


async def handle_event(
    session_id: str, event_data: dict, event_index: int
) -> dict | None:
    """Process a JSON event from an SSE upstream.

    event_data is the parsed JSON from the upstream service's SSE stream.
    Return a dict to broadcast, or None to skip.
    """
    raise NotImplementedError(
        "Implement handle_event for SSE upstream, or remove if using WS only"
    )
