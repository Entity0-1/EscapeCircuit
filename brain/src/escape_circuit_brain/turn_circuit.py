"""Extract the small spontaneous-flight-turn motif from verified MaleCNS edges."""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import defaultdict
from pathlib import Path
from typing import Any

import pyarrow as pa
import pyarrow.compute as pc
import pyarrow.ipc as ipc

from .circuit import load_annotation_index
from .download import DEFAULT_OUTPUT, verify_file
from .manifest import DEFAULT_MANIFEST, load_manifest

PROJECT_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_RUNTIME_OUTPUT = PROJECT_ROOT / "brain" / "circuits" / "malecns-v1.0-flight-turn.json"
NODE_TYPES = ("VES041", "DNa15", "DNb01")
SIDES = ("L", "R")


def extract_turn_circuit(annotations_path: Path, edges_path: Path) -> dict[str, Any]:
    """Keep only observed contacts among the six annotated circuit neurons."""
    annotations = load_annotation_index(annotations_path)
    node_index: dict[int, tuple[str, str]] = {}
    for body_id, row in annotations.items():
        if row["type"] in NODE_TYPES and row["side"] in SIDES and row["status"] != "Glia":
            node_index[body_id] = (row["type"], row["side"])
    for node_type in NODE_TYPES:
        for side in SIDES:
            matches = [
                body_id for body_id, label in node_index.items() if label == (node_type, side)
            ]
            if len(matches) != 1:
                raise ValueError(f"Expected exactly one {node_type}:{side}, found {len(matches)}")

    ids = pa.array(sorted(node_index), type=pa.int64())
    reader = ipc.open_file(pa.memory_map(str(edges_path), "r"))
    aggregates: defaultdict[tuple[str, str, str, str], list[int]] = defaultdict(
        lambda: [0, 0]
    )
    for batch_index in range(reader.num_record_batches):
        batch = reader.get_batch(batch_index)
        source_mask = pc.is_in(batch.column("body_pre"), value_set=ids)
        target_mask = pc.is_in(batch.column("body_post"), value_set=ids)
        filtered = batch.filter(pc.and_(source_mask, target_mask))
        if not filtered.num_rows:
            continue
        for source_id, target_id, weight in zip(
            filtered.column("body_pre").to_pylist(),
            filtered.column("body_post").to_pylist(),
            filtered.column("weight").to_pylist(),
            strict=True,
        ):
            source_type, source_side = node_index[int(source_id)]
            target_type, target_side = node_index[int(target_id)]
            key = (source_type, source_side, target_type, target_side)
            aggregates[key][0] += 1
            aggregates[key][1] += int(weight)

    rows = [
        {
            "source_type": key[0],
            "source_side": key[1],
            "target_type": key[2],
            "target_side": key[3],
            "connection_rows": counts[0],
            "synaptic_contacts": counts[1],
        }
        for key, counts in sorted(aggregates.items())
    ]
    if not any(row["source_type"] == "VES041" for row in rows):
        raise ValueError("No observed VES041 output to the turn motif")
    return {
        "schema_version": 1,
        "name": "MaleCNS v1.0 spontaneous-flight-turn motif",
        "selection": {
            "node_types": list(NODE_TYPES),
            "node_ids": [
                {"type": label[0], "side": label[1], "body_id": body_id}
                for body_id, label in sorted(node_index.items())
            ],
            "observed_connection_rows": sum(int(str(row["connection_rows"])) for row in rows),
            "observed_synaptic_contacts": sum(int(str(row["synaptic_contacts"])) for row in rows),
        },
        "observed_aggregates": rows,
        "model_boundary": {
            "observed": "Annotated neuron identities and direct synaptic contact counts.",
            "engineered": (
                "Game-state inputs, tonic activity, inhibitory signs, rate dynamics, "
                "thresholds, and flight movement."
            ),
            "claim": "Connectome-weighted turn regulation, not a biological flight simulation.",
        },
        "references": [
            "https://male-cns.janelia.org/download/",
            "https://pubmed.ncbi.nlm.nih.gov/38228148/",
        ],
    }


def build_turn_circuit(
    data_dir: Path = DEFAULT_OUTPUT,
    output_path: Path = DEFAULT_RUNTIME_OUTPUT,
) -> dict[str, Any]:
    manifest = load_manifest(DEFAULT_MANIFEST)
    annotations_entry = manifest.files["annotations"]
    edges_entry = manifest.files["edges"]
    annotations_path = data_dir / annotations_entry.filename
    edges_path = data_dir / edges_entry.filename
    for path, entry in ((annotations_path, annotations_entry), (edges_path, edges_entry)):
        verified, reason = verify_file(path, entry)
        if not verified:
            raise ValueError(f"Source file failed manifest verification: {path} ({reason})")

    circuit = extract_turn_circuit(annotations_path, edges_path)
    circuit["dataset"] = {
        "id": manifest.dataset_id,
        "release": manifest.release,
        "license": manifest.license,
        "source_page": manifest.source_page,
        "annotations_sha256": annotations_entry.sha256,
        "edges_sha256": edges_entry.sha256,
    }
    canonical = json.dumps(circuit, indent=2, sort_keys=True) + "\n"
    circuit["report_sha256"] = hashlib.sha256(canonical.encode()).hexdigest()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(circuit, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return circuit


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--output", type=Path, default=DEFAULT_RUNTIME_OUTPUT)
    arguments = parser.parse_args()
    circuit = build_turn_circuit(arguments.data_dir, arguments.output)
    print(
        json.dumps(
            {
                "output": str(arguments.output),
                **circuit["selection"],
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
