"""
Converts a window of raw telemetry events into rolling features
that describe HOW the driver has been driving over the last
WINDOW_SECONDS — not just their instantaneous speed.
"""
import statistics
from datetime import datetime
from typing import List
from .schemas import TelemetryEvent, RollingFeatures
from .config import MIN_EVENTS_FOR_FEATURES, HARSH_BRAKE_THRESHOLD_KMH
from member3_alert_system.part2.bend_detector import haversine_m


def extract_features(events: List[TelemetryEvent]) -> RollingFeatures:
    if len(events) < MIN_EVENTS_FOR_FEATURES:
        return RollingFeatures(
            avg_speed_kmh=events[-1].speed_kmh if events else 0,
            speed_volatility=0, harsh_brake_events=0,
            heading_variance=0, distance_covered_m=0,
            sample_count=len(events), window_seconds=0)

    speeds = [e.speed_kmh for e in events]
    headings = [e.heading_degrees for e in events]

    avg_speed = statistics.mean(speeds)
    volatility = statistics.pstdev(speeds) if len(speeds) > 1 else 0

    # Harsh braking = speed drop >= threshold between consecutive events
    harsh_events = 0
    for i in range(1, len(speeds)):
        drop = speeds[i - 1] - speeds[i]
        if drop >= HARSH_BRAKE_THRESHOLD_KMH:
            harsh_events += 1

    heading_variance = statistics.pstdev(headings) if len(headings) > 1 else 0

    # Distance covered across the window (sum of consecutive haversine deltas)
    distance_m = 0.0
    for i in range(1, len(events)):
        distance_m += haversine_m(
            events[i - 1].latitude, events[i - 1].longitude,
            events[i].latitude, events[i].longitude)

    try:
        t0 = datetime.fromisoformat(events[0].timestamp)
        t1 = datetime.fromisoformat(events[-1].timestamp)
        window_secs = max(0.0, (t1 - t0).total_seconds())
    except Exception:
        window_secs = 0.0

    return RollingFeatures(
        avg_speed_kmh=round(avg_speed, 1),
        speed_volatility=round(volatility, 2),
        harsh_brake_events=harsh_events,
        heading_variance=round(heading_variance, 1),
        distance_covered_m=round(distance_m, 1),
        sample_count=len(events),
        window_seconds=round(window_secs, 1))
