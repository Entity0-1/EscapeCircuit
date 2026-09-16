from __future__ import annotations

import pytest

from escape_circuit_brain.controller import PrototypeController
from escape_circuit_brain.protocol import Sensors


def test_controller_is_deterministic() -> None:
    first = PrototypeController()
    second = PrototypeController()
    sensors = Sensors(loom_left=0.8, loom_right=0.1, proximity=0.7, impact=0.0)

    for _ in range(12):
        first_output, first_activity = first.step(1 / 60, sensors)
        second_output, second_activity = second.step(1 / 60, sensors)

    assert first_output == second_output
    assert first_activity == second_activity


def test_lateral_inputs_produce_opposing_bias() -> None:
    left = PrototypeController()
    right = PrototypeController()
    for _ in range(30):
        left_output, _ = left.step(1 / 60, Sensors(1.0, 0.0, 0.0, 0.0))
        right_output, _ = right.step(1 / 60, Sensors(0.0, 1.0, 0.0, 0.0))

    assert left_output.turn_bias > 0.0
    assert right_output.turn_bias < 0.0


def test_strong_looming_eventually_triggers_escape() -> None:
    controller = PrototypeController()
    triggered = False
    for _ in range(30):
        output, _ = controller.step(1 / 60, Sensors(1.0, 1.0, 1.0, 0.0))
        triggered |= output.trigger_escape
    assert triggered


def test_sensor_values_are_bounded() -> None:
    with pytest.raises(ValueError, match="loom_left"):
        Sensors.from_mapping({"loom_left": 1.1})

