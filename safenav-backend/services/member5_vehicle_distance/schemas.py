from enum import Enum
from typing import Optional

from pydantic import BaseModel


class DistanceSeverity(str, Enum):
    SAFE = "SAFE"
    CAUTION = "CAUTION"
    WARNING = "WARNING"
    CRITICAL = "CRITICAL"


class DistanceWarningEventRequest(BaseModel):
    trip_id: str
    timestamp: str
    distance_m: float
    safe_distance_m: float
    following_gap_ratio: float
    speed_kmh: float
    severity: DistanceSeverity
    ttc_seconds: Optional[float] = None
    duration_seconds: float


class DistanceWarningEvent(BaseModel):
    id: str
    trip_id: str
    timestamp: str
    distance_m: float
    safe_distance_m: float
    following_gap_ratio: float
    speed_kmh: float
    severity: DistanceSeverity
    ttc_seconds: Optional[float] = None
    duration_seconds: float


class TripDistanceStats(BaseModel):
    trip_id: str
    total_events: int
    critical_events: int
    warning_events: int
    caution_events: int
    closest_distance_m: Optional[float]
    avg_following_gap_ratio: float
    total_too_close_seconds: float
    safety_deduction: float
    coaching_tip: str