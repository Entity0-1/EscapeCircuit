from __future__ import annotations

import asyncio
import json

from escape_circuit_brain.server import handle_client


def test_server_handles_a_step_without_blocking() -> None:
    async def scenario() -> None:
        server = await asyncio.start_server(handle_client, "127.0.0.1", 0)
        socket = (server.sockets or [])[0]
        port = int(socket.getsockname()[1])
        async with server:
            reader, writer = await asyncio.open_connection("127.0.0.1", port)
            request = {
                "protocol": 1,
                "sequence": 7,
                "dt_ms": 16.667,
                "sensors": {
                    "loom_left": 0.9,
                    "loom_right": 0.1,
                    "loom_up": 0.9,
                    "loom_down": 0.0,
                    "proximity": 0.8,
                    "impact": 0.0,
                },
            }
            writer.write(json.dumps(request).encode() + b"\n")
            await writer.drain()
            response = json.loads(await asyncio.wait_for(reader.readline(), timeout=1.0))
            assert response["protocol"] == 1
            assert response["sequence"] == 7
            assert response["mode"] in {"PROTOTYPE SERVICE", "MALECNS SENSORIMOTOR"}
            assert response["brain"]["escape_drive"] > 0.0
            assert "yaw_drive" in response["brain"]
            writer.close()
            await writer.wait_closed()

    asyncio.run(scenario())
