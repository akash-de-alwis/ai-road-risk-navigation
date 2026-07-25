from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from .schemas import TelemetryEvent
from .stream_buffer import buffer_manager
from .feature_extractor import extract_features
from .stream_risk_service import compute_stream_risk
from .connection_manager import manager

router = APIRouter(
    prefix='/v2/pipeline',
    tags=['Member 1b - Real-Time Data Pipeline'])


@router.websocket('/stream/{session_id}')
async def stream_endpoint(websocket: WebSocket, session_id: str):
    await manager.connect(session_id, websocket)
    buffer = buffer_manager.get_or_create(session_id)

    try:
        while True:
            raw = await websocket.receive_json()
            event = TelemetryEvent(**raw, session_id=session_id)
            buffer.add(event)

            features = extract_features(buffer.get_events())
            update = await compute_stream_risk(session_id, event, features)

            await manager.send_update(session_id, update.model_dump())

    except WebSocketDisconnect:
        manager.disconnect(session_id)
        buffer_manager.remove(session_id)
    except Exception as e:
        print(f"[pipeline] stream error for {session_id}: {e}")
        manager.disconnect(session_id)
        buffer_manager.remove(session_id)


@router.get('/health')
async def health():
    return {'status': 'ok', 'module': 'member1b_realtime_pipeline'}
