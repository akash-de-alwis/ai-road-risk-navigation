from typing import List

from fastapi import APIRouter, HTTPException

from .event_store import events_for_trip, log_event
from .schemas import DistanceWarningEvent, DistanceWarningEventRequest, TripDistanceStats
from .stats_service import compute_trip_stats

router = APIRouter(prefix="/v3/distance", tags=["Member 5 - Vehicle Distance Estimator"])


@router.post("/event", response_model=DistanceWarningEvent)
async def log_distance_event(req: DistanceWarningEventRequest):
    try:
        return log_event(req)
    except Exception as e:
        raise HTTPException(500, f"Event log failed: {str(e)}")


@router.get("/trip/{trip_id}/events", response_model=List[DistanceWarningEvent])
async def get_trip_events(trip_id: str):
    return events_for_trip(trip_id)


@router.get("/trip/{trip_id}/stats", response_model=TripDistanceStats)
async def get_trip_stats(trip_id: str):
    return compute_trip_stats(trip_id)


@router.get("/health")
async def health():
    return {"status": "ok", "module": "member5_vehicle_distance"}