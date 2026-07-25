from pydantic import BaseModel


class TelemetryEvent(BaseModel):
    """One raw data point streamed from the phone every 2-3 seconds."""
    session_id: str
    latitude: float
    longitude: float
    speed_kmh: float
    heading_degrees: float = 0
    vehicle_type: str = "car"
    timestamp: str


class RollingFeatures(BaseModel):
    """Aggregated features computed from the sliding window buffer."""
    avg_speed_kmh: float
    speed_volatility: float       # standard deviation of speed in window
    harsh_brake_events: int
    heading_variance: float
    distance_covered_m: float
    sample_count: int
    window_seconds: float


class StreamRiskUpdate(BaseModel):
    """Pushed back to the client the moment new inference completes."""
    session_id: str
    risk_score: float
    risk_level: str
    rolling_features: RollingFeatures
    volatility_multiplier: float
    timestamp: str
