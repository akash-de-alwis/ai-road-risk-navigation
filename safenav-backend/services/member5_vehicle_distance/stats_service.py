from .event_store import events_for_trip
from .schemas import DistanceSeverity, TripDistanceStats


def _coaching_tip(critical: int, warning: int, avg_ratio: float) -> str:
    if critical > 3:
        return (
            "You followed vehicles very closely several times. Try "
            "counting '1-Mississippi, 2-Mississippi, 3-Mississippi' "
            "from when the car ahead passes a sign — you shouldn't "
            "reach it before you finish counting."
        )
    if warning > 3:
        return (
            "Your following distance was tight in a few moments. "
            "Aim to leave at least a 3-second gap from the vehicle "
            "ahead, especially at higher speeds."
        )
    if avg_ratio < 1.2:
        return (
            "Your average following gap was close to the minimum "
            "recommended distance. Leaving a bit more space gives "
            "you more time to react."
        )
    return "Good job maintaining a safe following distance during this trip."


def compute_trip_stats(trip_id: str) -> TripDistanceStats:
    events = events_for_trip(trip_id)

    if not events:
        return TripDistanceStats(
            trip_id=trip_id,
            total_events=0,
            critical_events=0,
            warning_events=0,
            caution_events=0,
            closest_distance_m=None,
            avg_following_gap_ratio=0,
            total_too_close_seconds=0,
            safety_deduction=0,
            coaching_tip="No close-following events detected — nice work.",
        )

    critical = [e for e in events if e.severity == DistanceSeverity.CRITICAL]
    warning = [e for e in events if e.severity == DistanceSeverity.WARNING]
    caution = [e for e in events if e.severity == DistanceSeverity.CAUTION]

    too_close_seconds = sum(
        e.duration_seconds
        for e in events
        if e.severity in [DistanceSeverity.WARNING, DistanceSeverity.CRITICAL]
    )

    avg_ratio = sum(e.following_gap_ratio for e in events) / len(events)
    closest = min(e.distance_m for e in events)

    deduction = min(40, len(critical) * 8 + len(warning) * 3 + len(caution) * 1)

    return TripDistanceStats(
        trip_id=trip_id,
        total_events=len(events),
        critical_events=len(critical),
        warning_events=len(warning),
        caution_events=len(caution),
        closest_distance_m=round(closest, 1),
        avg_following_gap_ratio=round(avg_ratio, 2),
        total_too_close_seconds=round(too_close_seconds, 1),
        safety_deduction=deduction,
        coaching_tip=_coaching_tip(len(critical), len(warning), avg_ratio),
    )