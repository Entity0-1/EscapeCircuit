"""Versioned JSON-lines protocol shared with the Godot client."""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from typing import Any

PROTOCOL_VERSION = 1
MAX_MESSAGE_BYTES = 64 * 1024


def _bounded(value: Any, field: str) -> float:
    number = float(value)
    if not 0.0 <= number <= 1.0:
        raise ValueError(f"{field} must be between 0 and 1")
    return number


@dataclass(frozen=True, slots=True)
class Sensors:
    loom_left: float
    loom_right: float
    proximity: float
    impact: float
    loom_up: float = 0.0
    loom_down: float = 0.0
    lc4_left: float | None = None
    lc4_right: float | None = None
    lplc2_left: float | None = None
    lplc2_right: float | None = None

    @classmethod
    def from_mapping(cls, value: dict[str, Any]) -> Sensors:
        return cls(
            loom_left=_bounded(value.get("loom_left", 0.0), "loom_left"),
            loom_right=_bounded(value.get("loom_right", 0.0), "loom_right"),
            proximity=_bounded(value.get("proximity", 0.0), "proximity"),
            impact=_bounded(value.get("impact", 0.0), "impact"),
            loom_up=_bounded(value.get("loom_up", 0.0), "loom_up"),
            loom_down=_bounded(value.get("loom_down", 0.0), "loom_down"),
            lc4_left=_bounded(value["lc4_left"], "lc4_left") if "lc4_left" in value else None,
            lc4_right=_bounded(value["lc4_right"], "lc4_right") if "lc4_right" in value else None,
            lplc2_left=(
                _bounded(value["lplc2_left"], "lplc2_left") if "lplc2_left" in value else None
            ),
            lplc2_right=(
                _bounded(value["lplc2_right"], "lplc2_right") if "lplc2_right" in value else None
            ),
        )


@dataclass(frozen=True, slots=True)
class StepRequest:
    sequence: int
    dt_ms: float
    sensors: Sensors

    @classmethod
    def from_json(cls, payload: bytes) -> StepRequest:
        if len(payload) > MAX_MESSAGE_BYTES:
            raise ValueError("request exceeds maximum message size")
        value = json.loads(payload)
        if int(value.get("protocol", -1)) != PROTOCOL_VERSION:
            raise ValueError("unsupported protocol version")
        sequence = int(value["sequence"])
        if sequence < 0:
            raise ValueError("sequence must be nonnegative")
        dt_ms = float(value["dt_ms"])
        if not 0.0 < dt_ms <= 250.0:
            raise ValueError("dt_ms must be greater than 0 and at most 250")
        return cls(sequence=sequence, dt_ms=dt_ms, sensors=Sensors.from_mapping(value["sensors"]))


@dataclass(frozen=True, slots=True)
class BrainOutput:
    escape_drive: float
    turn_bias: float
    forward_drive: float
    trigger_escape: bool
    takeoff_drive: float = 0.0
    yaw_drive: float = 0.0
    pitch_drive: float = 0.0
    roll_drive: float = 0.0
    flight_power: float = 0.5
    landing_drive: float = 0.0
    fast_takeoff_drive: float = 0.0
    backward_takeoff_drive: float = 0.0
    forward_takeoff_drive: float = 0.0
    flight_saccade_drive: float = 0.0
    saccade_side: float = 0.0


@dataclass(frozen=True, slots=True)
class StepResponse:
    sequence: int
    brain: BrainOutput
    activity: dict[str, float]
    mode: str
    compute_ms: float

    def to_json_line(self) -> bytes:
        payload = {"protocol": PROTOCOL_VERSION, **asdict(self)}
        return json.dumps(payload, separators=(",", ":"), allow_nan=False).encode("utf-8") + b"\n"
