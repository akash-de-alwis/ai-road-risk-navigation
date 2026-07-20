"""
Feeds the rolling stream features into Member 1's EXISTING risk
model and formula (imported, never modified) plus a NEW behavior
volatility multiplier that only the streaming pipeline can compute
(it requires a window of history, not a single snapshot).
"""
from datetime import datetime
from .schemas import RollingFeatures, StreamRiskUpdate, TelemetryEvent
from .config import VOLATILITY_WEIGHT_PER_HARSH_EVENT, VOLATILITY_MULTIPLIER_CAP

# Reuse Member 1's existing services — DO NOT COPY, just import
from member1_risk_prediction.part2.weather_service import get_current_weather
from member1_risk_prediction.part2.road_condition_service import infer_road_condition
from member1_risk_prediction.part2.schemas import VehicleType
from member1_risk_prediction.part2.realtime_risk_service import (
    speed_multiplier,
    WEATHER_MULTIPLIERS,
    ROAD_CONDITION_MULTIPLIERS,
    VEHICLE_BASE_MULTIPLIERS,
    hotspot_proximity_multiplier,
    base_model_probability,
)


def _resolve_vehicle_type(raw: str) -> VehicleType:
    """Map a loosely-formatted client string ("car", "three_wheeler") onto
    Member 1's VehicleType enum, defaulting to CAR when it doesn't match."""
    normalized = raw.replace('_', ' ').strip().title()
    try:
        return VehicleType(normalized)
    except ValueError:
        return VehicleType.CAR


def classify_risk_level(score: float) -> str:
    """Mirrors the thresholds used in Member 1 Part 2's realtime_risk_service
    (no standalone function exists there to import, so the same cut points
    are reproduced here rather than duplicating the whole formula)."""
    if score >= 70:
        return 'CRITICAL'
    if score >= 50:
        return 'HIGH'
    if score >= 25:
        return 'MODERATE'
    return 'LOW'


def compute_volatility_multiplier(features: RollingFeatures) -> float:
    """
    Behavior-based multiplier derived PURELY from the streamed
    window — this does not exist in the original Member 1 Part 2
    single-request formula, since it requires historical context.
    """
    raw = 1.0 + (features.harsh_brake_events * VOLATILITY_WEIGHT_PER_HARSH_EVENT)
    return round(min(raw, VOLATILITY_MULTIPLIER_CAP), 3)


async def compute_stream_risk(
    session_id: str,
    latest_event: TelemetryEvent,
    features: RollingFeatures,
) -> StreamRiskUpdate:
    vehicle_type = _resolve_vehicle_type(latest_event.vehicle_type)

    base_proba = base_model_probability(
        latest_event.latitude, latest_event.longitude, vehicle_type.value)

    weather = await get_current_weather(latest_event.latitude, latest_event.longitude)
    road = infer_road_condition(weather)

    weather_mult = WEATHER_MULTIPLIERS[weather.condition]
    road_mult = ROAD_CONDITION_MULTIPLIERS[road]
    speed_mult = speed_multiplier(features.avg_speed_kmh)  # use SMOOTHED speed
    vehicle_mult = VEHICLE_BASE_MULTIPLIERS[vehicle_type]
    hotspot_mult, _nearest_dist = hotspot_proximity_multiplier(
        latest_event.latitude, latest_event.longitude)
    volatility_mult = compute_volatility_multiplier(features)

    calibrated_base = base_proba * 0.4
    score = min(100, calibrated_base * speed_mult * weather_mult *
                road_mult * vehicle_mult * hotspot_mult *
                volatility_mult * 100)

    return StreamRiskUpdate(
        session_id=session_id,
        risk_score=round(score, 1),
        risk_level=classify_risk_level(score),
        rolling_features=features,
        volatility_multiplier=volatility_mult,
        timestamp=datetime.now().isoformat())
