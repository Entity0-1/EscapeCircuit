from __future__ import annotations

import json
from pathlib import Path

from escape_circuit_brain.controller import (
    DEFAULT_CIRCUIT_PATH,
    ConnectomeCircuitController,
)
from escape_circuit_brain.protocol import Sensors


def _write_circuit(path: Path) -> None:
    rows = []
    for target in ("DNp01", "DNp02", "DNp03", "DNp04", "DNp06", "DNp11"):
        for side in ("L", "R"):
            rows.append(
                {
                    "source_type": "LC4",
                    "source_side": side,
                    "target_type": target,
                    "target_side": side,
                    "synaptic_contacts": 100,
                }
            )
            rows.append(
                {
                    "source_type": "LPLC2",
                    "source_side": side,
                    "target_type": target,
                    "target_side": side,
                    "synaptic_contacts": 50,
                }
            )
    path.write_text(json.dumps({"schema_version": 1, "observed_aggregates": rows}))


def test_connectome_controller_uses_observed_lateral_weights(tmp_path: Path) -> None:
    circuit_path = tmp_path / "circuit.json"
    _write_circuit(circuit_path)
    controller = ConnectomeCircuitController(circuit_path)

    triggered = False
    for _ in range(60):
        output, activity = controller.step(1 / 60, Sensors(1.0, 0.0, 0.9, 0.0))
        triggered |= output.trigger_escape

    assert triggered
    assert output.turn_bias > 0.0
    assert output.yaw_drive > 0.0
    assert output.flight_power > 0.48
    assert output.landing_drive < 0.4
    assert activity["visual_left"] > activity["visual_right"]
    assert activity["dn_takeoff"] > 0.0


def test_checked_in_malecns_circuit_is_loadable() -> None:
    controller = ConnectomeCircuitController(DEFAULT_CIRCUIT_PATH)
    triggered = False
    for _ in range(90):
        output, _ = controller.step(1 / 60, Sensors(1.0, 0.25, 0.95, 0.0, 1.0, 0.0))
        triggered |= output.trigger_escape
    assert triggered
    assert output.pitch_drive < 0.0


def test_distinct_visual_channels_change_takeoff_latency() -> None:
    def first_takeoff_tick(lc4: float, lplc2: float = 0.5) -> int:
        controller = ConnectomeCircuitController(DEFAULT_CIRCUIT_PATH)
        sensors = Sensors(
            loom_left=0.0,
            loom_right=0.0,
            proximity=0.55,
            impact=0.0,
            lc4_left=lc4 * 0.5,
            lc4_right=lc4 * 0.5,
            lplc2_left=lplc2,
            lplc2_right=lplc2,
        )
        for tick in range(1, 121):
            output, activity = controller.step(1 / 60, sensors)
            assert activity["lc4"] == lc4 * 0.5
            assert activity["lplc2"] == lplc2
            if output.takeoff_drive > 0.24:
                return tick
        return 121

    slow_tick = first_takeoff_tick(0.25)
    fast_tick = first_takeoff_tick(0.5)
    assert fast_tick < slow_tick < 121
    assert fast_tick < first_takeoff_tick(0.5, 0.35) < 121
