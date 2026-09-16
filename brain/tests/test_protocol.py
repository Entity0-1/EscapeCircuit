from __future__ import annotations

import json

import pytest

from escape_circuit_brain.protocol import BrainOutput, StepRequest, StepResponse


def test_request_round_trip_shape() -> None:
    request = StepRequest.from_json(
        json.dumps(
            {
                "protocol": 1,
                "sequence": 42,
                "dt_ms": 16.667,
                "sensors": {
                    "loom_left": 0.75,
                    "loom_right": 0.2,
                    "proximity": 0.6,
                    "impact": 0.0,
                },
            }
        ).encode()
    )
    assert request.sequence == 42
    assert request.sensors.loom_left == 0.75


def test_response_is_compact_json_line() -> None:
    response = StepResponse(
        sequence=2,
        brain=BrainOutput(0.4, -0.1, 0.7, False),
        activity={"visual_left": 0.2},
        mode="TEST",
        compute_ms=0.25,
    )
    encoded = response.to_json_line()
    assert encoded.endswith(b"\n")
    assert b" " not in encoded
    assert json.loads(encoded)["protocol"] == 1


def test_request_rejects_wrong_protocol() -> None:
    with pytest.raises(ValueError, match="protocol"):
        StepRequest.from_json(b'{"protocol":99,"sequence":0,"dt_ms":16,"sensors":{}}')

