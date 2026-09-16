"""Loopback-only asynchronous neural controller service."""

from __future__ import annotations

import argparse
import asyncio
import logging
import time
from collections.abc import Sequence

from .controller import load_best_available_controller
from .protocol import MAX_MESSAGE_BYTES, StepRequest, StepResponse

LOGGER = logging.getLogger("escape_circuit_brain")
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8765


async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    peer = writer.get_extra_info("peername")
    controller, controller_mode = load_best_available_controller()
    LOGGER.info("client_connected peer=%s", peer)
    try:
        while line := await reader.readline():
            if len(line) > MAX_MESSAGE_BYTES:
                raise ValueError("request exceeds maximum message size")
            started_at = time.perf_counter()
            request = StepRequest.from_json(line)
            output, activity = controller.step(request.dt_ms / 1000.0, request.sensors)
            elapsed_ms = (time.perf_counter() - started_at) * 1000.0
            response = StepResponse(
                sequence=request.sequence,
                brain=output,
                activity=activity,
                mode=controller_mode,
                compute_ms=elapsed_ms,
            )
            writer.write(response.to_json_line())
            await writer.drain()
    except (ValueError, KeyError, TypeError) as error:
        LOGGER.warning("client_protocol_error peer=%s error=%s", peer, error)
    except (ConnectionError, asyncio.CancelledError):
        pass
    finally:
        writer.close()
        await writer.wait_closed()
        LOGGER.info("client_disconnected peer=%s", peer)


async def serve(host: str = DEFAULT_HOST, port: int = DEFAULT_PORT) -> None:
    if host not in {"127.0.0.1", "::1", "localhost"}:
        raise ValueError("The brain service may bind to loopback only")
    server = await asyncio.start_server(handle_client, host, port, limit=MAX_MESSAGE_BYTES)
    addresses = ", ".join(str(socket.getsockname()) for socket in (server.sockets or []))
    LOGGER.info("brain_service_started addresses=%s", addresses)
    async with server:
        await server.serve_forever()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default=DEFAULT_HOST, choices=("127.0.0.1", "::1", "localhost"))
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--verbose", action="store_true")
    return parser


def main(argv: Sequence[str] | None = None) -> None:
    arguments = build_parser().parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if arguments.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    try:
        asyncio.run(serve(arguments.host, arguments.port))
    except KeyboardInterrupt:
        LOGGER.info("brain_service_stopped")


if __name__ == "__main__":
    main()
