import asyncio
import json
import websockets
from datetime import datetime


async def test():
    uri = "ws://localhost:8000/v2/pipeline/stream/test_session_1"
    async with websockets.connect(uri) as ws:
        base_lat, base_lng = 6.7133, 79.9063
        speeds = [40, 42, 45, 30, 65, 20, 70, 68, 66]  # includes harsh drops
        for i, spd in enumerate(speeds):
            payload = {
                "latitude": base_lat + i * 0.001,
                "longitude": base_lng + i * 0.001,
                "speed_kmh": spd,
                "heading_degrees": 90,
                "vehicle_type": "car",
                "timestamp": datetime.now().isoformat(),
            }
            await ws.send(json.dumps(payload))
            response = await ws.recv()
            print(f"Sent speed={spd} -> {response}")
            await asyncio.sleep(2)


asyncio.run(test())
