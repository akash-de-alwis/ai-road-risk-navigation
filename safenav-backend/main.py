from __future__ import annotations

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

from shared.config import OPENWEATHER_API_KEY
from shared.models.schemas import (
    AlertResponse,
    HealthResponse,
    HotspotResponse,
    NearbyAlertRequest,
    RealTimeRiskRequest,
    RealTimeRiskResponse,
    RouteSafetyRequest,
    RouteSafetyResponse,
)
from member1_risk_prediction.part1 import hotspot_service, risk_service
from member2_route_engine.part1 import route_service
from member3_alert_system.part1 import nlp_alert_service
from member1_risk_prediction.part2.router import router as m1p2_router
from member2_route_engine.part2.router import router as m2p2_router
from member3_alert_system.part2.router import router as m3p2_router
from services.member4_part2.router import router as m4p2_router
from services.member1b_realtime_pipeline.router import router as m1b_router

app = FastAPI(
    title="SafeNav API",
    version="1.0.0",
    description="Road accident risk prediction API for Panadura, Sri Lanka",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(m1p2_router)
app.include_router(m2p2_router)
app.include_router(m3p2_router)
app.include_router(m4p2_router)
app.include_router(m1b_router)


# ── 1. Root ───────────────────────────────────────────────────────────────────

@app.get("/")
def root():
    return {"message": "SafeNav API is running", "docs": "/docs"}


# ── 2. Health ─────────────────────────────────────────────────────────────────

@app.get("/health", response_model=HealthResponse)
def health():
    return HealthResponse(
        status="ok",
        model_loaded=risk_service.MODEL is not None,
        hotspots_loaded=len(hotspot_service.HOTSPOTS),
    )


# ── 3. All hotspots ───────────────────────────────────────────────────────────

@app.get(
    "/hotspots",
    response_model=list[HotspotResponse],
    description="Returns all accident hotspots with risk scores for map display",
)
def list_hotspots(risk_level: str | None = Query(default=None)):
    hotspots = hotspot_service.get_all_hotspots()
    if risk_level:
        level = risk_level.upper()
        hotspots = [h for h in hotspots if h["risk_level"] == level]
    return hotspots


# ── 4. Hotspots near a GPS point (must come before /{hotspot_id}) ─────────────

@app.get("/hotspots/near", response_model=list[HotspotResponse])
def hotspots_near(
    lat: float = Query(...),
    lng: float = Query(...),
    radius_m: float = Query(default=300),
):
    return hotspot_service.get_hotspots_near_point(lat, lng, radius_m)


# ── 5. Single hotspot by ID ───────────────────────────────────────────────────

@app.get("/hotspots/{hotspot_id}", response_model=HotspotResponse)
def get_hotspot(hotspot_id: int):
    hotspot = hotspot_service.get_hotspot_by_id(hotspot_id)
    if hotspot is None:
        raise HTTPException(status_code=404, detail=f"Hotspot {hotspot_id} not found")
    return hotspot


# ── 6. Route safety ranking ───────────────────────────────────────────────────

@app.post("/route/safety", response_model=RouteSafetyResponse)
def route_safety(body: RouteSafetyRequest):
    result = route_service.rank_routes(
        origin=body.origin.model_dump(),
        destination=body.destination.model_dump(),
        destination_name=body.destination_name,
    )
    return result


# ── 7. Real-time risk prediction ──────────────────────────────────────────────

@app.post("/predict/realtime", response_model=RealTimeRiskResponse)
def predict_realtime(body: RealTimeRiskRequest):
    request_data = body.model_dump()

    prediction = risk_service.predict_risk(request_data)

    nearby = hotspot_service.get_hotspots_near_point(body.latitude, body.longitude, radius_m=300)
    nearest = nearby[0] if nearby else None

    alert_en, alert_si = nlp_alert_service.generate_alert(
        prediction["risk_level"],
        nearest,
        body.hour,
        body.vehicle_type,
    )

    return RealTimeRiskResponse(
        risk_probability=prediction["risk_probability"],
        risk_score=prediction["risk_score"],
        risk_level=prediction["risk_level"],
        nearest_hotspot_id=nearest["hotspot_id"] if nearest else None,
        nearest_hotspot_distance_m=nearest["distance_m"] if nearest else None,
        alert_message=alert_en,
        alert_message_si=alert_si,
        should_alert=prediction["risk_level"] in ("HIGH", "MEDIUM"),
    )


# ── 8. NLP-powered nearby alerts ─────────────────────────────────────────────

@app.post("/alerts/nearby", response_model=AlertResponse)
def alerts_nearby(body: NearbyAlertRequest):
    nearby = hotspot_service.get_hotspots_near_point(
        body.latitude, body.longitude, radius_m=500
    )

    # Filter already-alerted hotspots
    candidates = [
        h for h in nearby if h["hotspot_id"] not in body.alerted_hotspot_ids
    ]

    raw_alerts = [
        nlp_alert_service.build_alert(
            hotspot=h,
            distance_m=h["distance_m"],
            driver_score=body.driver_score,
            driver_events=body.driver_events,
            hour=body.hour,
            is_weekend=body.is_weekend,
            vehicle_type=body.vehicle_type,
        )
        for h in candidates
    ]

    alerts = nlp_alert_service.prioritize_alerts(raw_alerts)

    return AlertResponse(
        alerts=alerts,
        total_nearby_hotspots=len(nearby),
        checked_radius_m=500.0,
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
