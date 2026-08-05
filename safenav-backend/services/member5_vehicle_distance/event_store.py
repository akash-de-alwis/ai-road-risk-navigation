import uuid
from datetime import datetime, timedelta
from typing import List

from .schemas import DistanceWarningEvent, DistanceWarningEventRequest

_events: List[DistanceWarningEvent] = []
EVENT_TTL_DAYS = 7


def _cleanup_expired():
    global _events
    cutoff = datetime.now() - timedelta(days=EVENT_TTL_DAYS)
    _events = [e for e in _events if datetime.fromisoformat(e.timestamp) > cutoff]


def log_event(req: DistanceWarningEventRequest) -> DistanceWarningEvent:
    _cleanup_expired()
    event = DistanceWarningEvent(
        id=str(uuid.uuid4())[:12],
        trip_id=req.trip_id,
        timestamp=req.timestamp,
        distance_m=req.distance_m,
        safe_distance_m=req.safe_distance_m,
        following_gap_ratio=req.following_gap_ratio,
        speed_kmh=req.speed_kmh,
        severity=req.severity,
        ttc_seconds=req.ttc_seconds,
        duration_seconds=req.duration_seconds,
    )
    _events.append(event)
    return event


def events_for_trip(trip_id: str) -> List[DistanceWarningEvent]:
    _cleanup_expired()
    return [e for e in _events if e.trip_id == trip_id]