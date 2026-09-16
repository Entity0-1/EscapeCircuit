from __future__ import annotations

from pathlib import Path

import pyarrow as pa
import pyarrow.feather as feather

from escape_circuit_brain.circuit import derive_runtime_circuit, extract_direct_descending_report


def test_extracts_only_configured_visual_to_descending_edges(tmp_path: Path) -> None:
    annotations = pa.table(
        {
            "bodyId": pa.array([1, 2, 3, 4, 5], type=pa.int64()),
            "instance": ["LPLC2_L", "LC4_R", "DNp01_L", "interneuron", "glia"],
            "type": ["LPLC2", "LC4", "DNp01", "IN001", "DNp01"],
            "superclass": [
                "visual_projection",
                "visual_projection",
                "descending_neuron",
                "central",
                "descending_neuron",
            ],
            "rootSide": ["L", "R", "L", None, "R"],
            "somaSide": [None, None, None, None, None],
            "status": ["Traced", "Traced", "Traced", "Traced", "Glia"],
        }
    )
    edges = pa.table(
        {
            "body_pre": pa.array([1, 2, 1, 4, 1], type=pa.int64()),
            "body_post": pa.array([3, 3, 4, 3, 5], type=pa.int64()),
            "weight": pa.array([8, 3, 99, 77, 66], type=pa.int64()),
        }
    )
    annotation_path = tmp_path / "annotations.feather"
    edge_path = tmp_path / "edges.feather"
    feather.write_feather(annotations, annotation_path)
    feather.write_feather(edges, edge_path)

    report = extract_direct_descending_report(annotation_path, edge_path)

    assert report["matched_connection_rows"] == 2
    assert report["matched_synaptic_contacts"] == 11
    assert report["top_target_types"] == [{"type": "DNp01", "synaptic_contacts": 11}]
    assert {row["source_type"] for row in report["aggregates"]} == {"LPLC2", "LC4"}


def test_minimum_weight_is_applied(tmp_path: Path) -> None:
    annotations = pa.table(
        {
            "bodyId": pa.array([1, 2], type=pa.int64()),
            "instance": ["LC4_L", "DNp01_L"],
            "type": ["LC4", "DNp01"],
            "superclass": ["visual_projection", "descending_neuron"],
            "rootSide": ["L", "L"],
            "somaSide": [None, None],
            "status": ["Traced", "Traced"],
        }
    )
    edges = pa.table(
        {
            "body_pre": pa.array([1], type=pa.int64()),
            "body_post": pa.array([2], type=pa.int64()),
            "weight": pa.array([2], type=pa.int64()),
        }
    )
    annotation_path = tmp_path / "annotations.feather"
    edge_path = tmp_path / "edges.feather"
    feather.write_feather(annotations, annotation_path)
    feather.write_feather(edges, edge_path)

    report = extract_direct_descending_report(
        annotation_path, edge_path, minimum_weight=3
    )

    assert report["matched_connection_rows"] == 0


def test_runtime_circuit_selects_documented_targets() -> None:
    report = {
        "dataset": {"id": "test"},
        "report_sha256": "abc",
        "source_types": ["LPLC2", "LC4"],
        "target_superclass": "descending_neuron",
        "minimum_edge_weight": 1,
        "source_neuron_counts": [],
        "aggregates": [
            {
                "source_type": "LC4",
                "source_side": "L",
                "target_type": "DNp01",
                "target_side": "L",
                "connection_rows": 2,
                "synaptic_contacts": 11,
            },
            {
                "source_type": "LC4",
                "source_side": "L",
                "target_type": "DNp99",
                "target_side": "L",
                "connection_rows": 5,
                "synaptic_contacts": 500,
            },
        ],
    }

    circuit = derive_runtime_circuit(report)

    assert circuit["selection"]["observed_synaptic_contacts"] == 11
    assert len(circuit["observed_aggregates"]) == 1
    assert circuit["observed_aggregates"][0]["target_type"] == "DNp01"
