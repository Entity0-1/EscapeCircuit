from __future__ import annotations

import json
from pathlib import Path

import pyarrow as pa
import pyarrow.feather as feather

from escape_circuit_brain.turn_circuit import (
    DEFAULT_RUNTIME_OUTPUT,
    extract_turn_circuit,
)


def test_extracts_only_observed_six_neuron_motif(tmp_path: Path) -> None:
    labels = [
        ("VES041", "L"),
        ("VES041", "R"),
        ("DNa15", "L"),
        ("DNa15", "R"),
        ("DNb01", "L"),
        ("DNb01", "R"),
        ("other", "L"),
    ]
    annotations = pa.table(
        {
            "bodyId": pa.array(range(1, 8), type=pa.int64()),
            "instance": [f"{name}_{side}" for name, side in labels],
            "type": [name for name, _ in labels],
            "superclass": ["central"] * 7,
            "rootSide": [side for _, side in labels],
            "somaSide": [None] * 7,
            "status": ["Traced"] * 7,
        }
    )
    edges = pa.table(
        {
            "body_pre": pa.array([1, 2, 5, 7, 1], type=pa.int64()),
            "body_post": pa.array([3, 6, 4, 3, 7], type=pa.int64()),
            "weight": pa.array([8, 11, 5, 90, 30], type=pa.int64()),
        }
    )
    annotation_path = tmp_path / "annotations.feather"
    edge_path = tmp_path / "edges.feather"
    feather.write_feather(annotations, annotation_path)
    feather.write_feather(edges, edge_path)

    circuit = extract_turn_circuit(annotation_path, edge_path)

    assert circuit["selection"]["observed_connection_rows"] == 3
    assert circuit["selection"]["observed_synaptic_contacts"] == 24
    assert circuit["observed_aggregates"][0]["synaptic_contacts"] == 5


def test_checked_in_turn_artifact_has_observed_ves041_contacts() -> None:
    circuit = json.loads(DEFAULT_RUNTIME_OUTPUT.read_text(encoding="utf-8"))
    assert circuit["selection"]["observed_connection_rows"] == 13
    assert circuit["selection"]["observed_synaptic_contacts"] == 138
    assert any(
        row["source_type"] == "VES041" and row["target_type"] == "DNb01"
        for row in circuit["observed_aggregates"]
    )
