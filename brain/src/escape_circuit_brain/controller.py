"""Neural-provider implementations."""

from __future__ import annotations

import json
import math
from collections import defaultdict
from pathlib import Path
from typing import Any

from .protocol import BrainOutput, Sensors


class PrototypeController:
    """Deterministic transport scaffold, not a biological model."""

    response_rate = 9.0
    adaptation_rate = 0.7

    def __init__(self) -> None:
        self.reset()

    def reset(self) -> None:
        self.visual_left = 0.0
        self.visual_right = 0.0
        self.escape_drive = 0.0
        self.motor_bias = 0.0
        self.adaptation = 0.0

    def step(self, dt_seconds: float, sensors: Sensors) -> tuple[BrainOutput, dict[str, float]]:
        alpha = 1.0 - math.exp(-self.response_rate * dt_seconds)
        self.visual_left = _lerp(self.visual_left, sensors.loom_left, alpha)
        self.visual_right = _lerp(self.visual_right, sensors.loom_right, alpha)
        combined_loom = max(self.visual_left, self.visual_right)
        target_escape = min(1.0, combined_loom * 0.92 + sensors.proximity * 0.22 + sensors.impact)
        self.escape_drive = _lerp(self.escape_drive, target_escape, alpha)
        self.motor_bias = _lerp(
            self.motor_bias,
            self.visual_left - self.visual_right,
            alpha,
        )
        self.adaptation = max(0.0, self.adaptation - self.adaptation_rate * dt_seconds)
        triggered = self.escape_drive > 0.45 + self.adaptation * 0.15
        if triggered:
            self.adaptation = 1.0

        output = BrainOutput(
            escape_drive=self.escape_drive,
            turn_bias=max(-1.0, min(1.0, self.motor_bias)),
            forward_drive=min(1.0, 0.58 + (0.46 + self.escape_drive * 0.54) * 0.42),
            trigger_escape=triggered,
            takeoff_drive=self.escape_drive,
            yaw_drive=max(-1.0, min(1.0, self.motor_bias)),
            pitch_drive=max(
                -1.0,
                min(
                    1.0,
                    (sensors.loom_down - sensors.loom_up) * self.escape_drive * 1.25,
                ),
            ),
            roll_drive=max(-1.0, min(1.0, -self.motor_bias * 0.75)),
            flight_power=min(1.0, 0.46 + self.escape_drive * 0.54),
            landing_drive=max(
                0.0,
                1.0 - max(self.escape_drive, sensors.proximity * 0.72),
            ),
        )
        activity = {
            "visual_left": self.visual_left,
            "visual_right": self.visual_right,
            "escape": self.escape_drive,
            "motor": abs(self.motor_bias),
        }
        return output, activity


DEFAULT_CIRCUIT_PATH = (
    Path(__file__).resolve().parents[2] / "circuits" / "malecns-v1.0-looming-escape.json"
)


class ConnectomeCircuitController:
    """Population-rate model weighted by observed direct MaleCNS contacts."""

    response_rate = 11.0
    adaptation_rate = 0.58

    def __init__(self, circuit_path: Path = DEFAULT_CIRCUIT_PATH) -> None:
        raw: dict[str, Any] = json.loads(circuit_path.read_text(encoding="utf-8"))
        if int(raw.get("schema_version", -1)) != 1:
            raise ValueError("Unsupported circuit schema")
        self.contacts: defaultdict[tuple[str, str], dict[str, int]] = defaultdict(dict)
        for row in raw["observed_aggregates"]:
            target_key = (str(row["target_type"]), str(row["target_side"]))
            source_key = f"{row['source_type']}:{row['source_side']}"
            self.contacts[target_key][source_key] = (
                self.contacts[target_key].get(source_key, 0)
                + int(row["synaptic_contacts"])
            )
        if not self.contacts:
            raise ValueError("Circuit contains no observed connections")
        self.reset()

    def reset(self) -> None:
        self.target_activity = {key: 0.0 for key in self.contacts}
        self.escape_drive = 0.0
        self.motor_bias = 0.0
        self.pitch_drive = 0.0
        self.adaptation = 0.0

    def step(self, dt_seconds: float, sensors: Sensors) -> tuple[BrainOutput, dict[str, float]]:
        alpha = 1.0 - math.exp(-self.response_rate * dt_seconds)
        lc4_left = sensors.lc4_left if sensors.lc4_left is not None else sensors.loom_left
        lc4_right = sensors.lc4_right if sensors.lc4_right is not None else sensors.loom_right
        lplc2_left = (
            sensors.lplc2_left
            if sensors.lplc2_left is not None
            else sensors.loom_left * (0.72 + sensors.proximity * 0.28)
        )
        lplc2_right = (
            sensors.lplc2_right
            if sensors.lplc2_right is not None
            else sensors.loom_right * (0.72 + sensors.proximity * 0.28)
        )
        source_activity = {
            "LC4:L": lc4_left,
            "LC4:R": lc4_right,
            "LPLC2:L": lplc2_left,
            "LPLC2:R": lplc2_right,
        }
        for target_key, incoming in self.contacts.items():
            total_contacts = sum(incoming.values())
            drive = (
                sum(
                    source_activity.get(source, 0.0) * weight
                    for source, weight in incoming.items()
                )
                / total_contacts
                if total_contacts
                else 0.0
            )
            self.target_activity[target_key] = _lerp(
                self.target_activity[target_key], drive, alpha
            )

        left_fast = self.target_activity.get(("DNp01", "L"), 0.0)
        right_fast = self.target_activity.get(("DNp01", "R"), 0.0)
        left_directional = max(
            self.target_activity.get((target, "L"), 0.0)
            for target in ("DNp02", "DNp04", "DNp11")
        )
        right_directional = max(
            self.target_activity.get((target, "R"), 0.0)
            for target in ("DNp02", "DNp04", "DNp11")
        )
        left_collision = max(
            self.target_activity.get((target, "L"), 0.0)
            for target in ("DNp03", "DNp06")
        )
        right_collision = max(
            self.target_activity.get((target, "R"), 0.0)
            for target in ("DNp03", "DNp06")
        )
        evasive = max(left_collision, right_collision)
        backward_takeoff = max(
            (self.target_activity.get(("DNp02", side), 0.0)
             + self.target_activity.get(("DNp04", side), 0.0)) * 0.5
            for side in ("L", "R")
        )
        forward_takeoff = max(
            self.target_activity.get(("DNp11", side), 0.0) for side in ("L", "R")
        )
        left_saccade = self.target_activity.get(("DNp03", "L"), 0.0)
        right_saccade = self.target_activity.get(("DNp03", "R"), 0.0)
        flight_saccade = max(left_saccade, right_saccade)
        fast = max(left_fast, right_fast)
        directional = max(left_directional, right_directional)
        target_escape = min(
            1.0,
            fast * 0.48
            + directional * 0.30
            + evasive * 0.22
            + sensors.proximity * 0.10
            + sensors.impact,
        )
        self.escape_drive = _lerp(self.escape_drive, target_escape, alpha)
        target_bias = (
            left_directional
            + left_fast
            + left_collision * 0.75
            - right_directional
            - right_fast
            - right_collision * 0.75
        ) / 2.75
        self.motor_bias = _lerp(self.motor_bias, target_bias, alpha)
        vertical_threat = sensors.loom_down - sensors.loom_up
        self.pitch_drive = _lerp(
            self.pitch_drive,
            vertical_threat * max(evasive, self.escape_drive) * 1.25,
            alpha,
        )
        self.adaptation = max(0.0, self.adaptation - self.adaptation_rate * dt_seconds)
        triggered = self.escape_drive > 0.36 + self.adaptation * 0.16
        if triggered:
            self.adaptation = 1.0

        takeoff_drive = min(
            1.0,
            fast * 0.66 + directional * 0.19 + evasive * 0.15 + sensors.impact,
        )
        flight_power = min(1.0, 0.48 + max(self.escape_drive, evasive) * 0.52)
        landing_drive = max(
            0.0,
            1.0 - max(self.escape_drive, sensors.proximity * 0.72),
        )
        yaw_drive = max(-1.0, min(1.0, self.motor_bias))
        roll_drive = max(-1.0, min(1.0, -yaw_drive * (0.62 + evasive * 0.30)))
        output = BrainOutput(
            escape_drive=self.escape_drive,
            turn_bias=yaw_drive,
            forward_drive=min(1.0, 0.58 + flight_power * 0.42),
            trigger_escape=triggered,
            takeoff_drive=takeoff_drive,
            yaw_drive=yaw_drive,
            pitch_drive=max(-1.0, min(1.0, self.pitch_drive)),
            roll_drive=roll_drive,
            flight_power=flight_power,
            landing_drive=landing_drive,
            fast_takeoff_drive=fast,
            backward_takeoff_drive=backward_takeoff,
            forward_takeoff_drive=forward_takeoff,
            flight_saccade_drive=flight_saccade,
            saccade_side=max(-1.0, min(1.0, left_saccade - right_saccade)),
        )
        return output, {
            "visual_left": max(sensors.loom_left, left_fast),
            "visual_right": max(sensors.loom_right, right_fast),
            "lc4": max(lc4_left, lc4_right),
            "lplc2": max(lplc2_left, lplc2_right),
            "dn_takeoff": fast,
            "dn_backward": backward_takeoff,
            "dn_forward": forward_takeoff,
            "dn_saccade": flight_saccade,
            "escape": self.escape_drive,
            "motor": min(1.0, abs(self.motor_bias)),
        }


def load_best_available_controller() -> tuple[
    PrototypeController | ConnectomeCircuitController, str
]:
    if DEFAULT_CIRCUIT_PATH.is_file():
        return ConnectomeCircuitController(DEFAULT_CIRCUIT_PATH), "MALECNS SENSORIMOTOR"
    return PrototypeController(), "PROTOTYPE SERVICE"


def _lerp(start: float, end: float, weight: float) -> float:
    return start + (end - start) * weight
