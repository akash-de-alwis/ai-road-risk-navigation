"""
Per-session sliding window buffer. Each active trip gets its own
buffer holding the last WINDOW_SECONDS of telemetry events.
"""
from collections import deque
from datetime import datetime, timedelta
from typing import Dict, List
from .schemas import TelemetryEvent
from .config import WINDOW_SECONDS, MAX_BUFFER_EVENTS


class SessionBuffer:
    def __init__(self, session_id: str):
        self.session_id = session_id
        self.events: deque = deque(maxlen=MAX_BUFFER_EVENTS)

    def add(self, event: TelemetryEvent):
        self.events.append(event)
        self._trim_old()

    def _trim_old(self):
        cutoff = datetime.now() - timedelta(seconds=WINDOW_SECONDS)
        while self.events and self._parse_ts(self.events[0].timestamp) < cutoff:
            self.events.popleft()

    def _parse_ts(self, ts: str) -> datetime:
        try:
            return datetime.fromisoformat(ts)
        except Exception:
            return datetime.now()

    def get_events(self) -> List[TelemetryEvent]:
        return list(self.events)


class StreamBufferManager:
    """Holds one SessionBuffer per active WebSocket connection."""
    def __init__(self):
        self._buffers: Dict[str, SessionBuffer] = {}

    def get_or_create(self, session_id: str) -> SessionBuffer:
        if session_id not in self._buffers:
            self._buffers[session_id] = SessionBuffer(session_id)
        return self._buffers[session_id]

    def remove(self, session_id: str):
        self._buffers.pop(session_id, None)


# Singleton instance shared across the router
buffer_manager = StreamBufferManager()
