"""Extract a compact, reproducible looming-to-descending circuit from MaleCNS."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
from collections import Counter, defaultdict
from collections.abc import Sequence
from pathlib import Path
from typing import Any

import pyarrow as pa
import pyarrow.compute as pc
import pyarrow.feather as feather
import pyarrow.ipc as ipc

from .download import DEFAULT_OUTPUT, file_digest
from .manifest import DEFAULT_MANIFEST, load_manifest

PROJECT_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_CIRCUIT_OUTPUT = PROJECT_ROOT / "build" / "malecns-direct-descending-report.json"
DEFAULT_RUNTIME_OUTPUT = (
    PROJECT_ROOT / "brain" / "circuits" / "malecns-v1.0-looming-escape.json"
)
DEFAULT_SOURCE_TYPES = ("LPLC2", "LC4")
TARGET_SUPERCLASS = "descending_neuron"
RUNTIME_TARGETS = {
    "DNp01": "fast_escape_takeoff",
    "DNp02": "directional_escape",
    "DNp03": "collision_avoidance_flight_saccade",
    "DNp04": "directional_escape",
    "DNp06": "evasive_maneuver",
    "DNp11": "directional_escape",
}


def _text(value: Any) -> str:
    return "" if value is None else str(value)


def _side(row: dict[str, Any]) -> str:
    for field in ("rootSide", "somaSide"):
        value = _text(row.get(field)).upper()
        if value in {"L", "R"}:
            return value
    instance = _text(row.get("instance"))
    if instance.endswith("_L"):
        return "L"
    if instance.endswith("_R"):
        return "R"
    return "U"


def load_annotation_index(path: Path) -> dict[int, dict[str, str]]:
    columns = ["bodyId", "instance", "type", "superclass", "rootSide", "somaSide", "status"]
    table = feather.read_table(path, columns=columns)
    raw = table.to_pylist()
    index: dict[int, dict[str, str]] = {}
    for row in raw:
        body_id = int(row["bodyId"])
        if body_id < 0:
            raise ValueError(f"Negative neuron ID: {body_id}")
        if body_id in index:
            raise ValueError(f"Duplicate annotation ID: {body_id}")
        index[body_id] = {
            "instance": _text(row.get("instance")),
            "type": _text(row.get("type")),
            "superclass": _text(row.get("superclass")),
            "side": _side(row),
            "status": _text(row.get("status")),
        }
    return index


def extract_direct_descending_report(
    annotations_path: Path,
    edges_path: Path,
    source_types: Sequence[str] = DEFAULT_SOURCE_TYPES,
    minimum_weight: int = 1,
    progress: bool = False,
) -> dict[str, Any]:
    if minimum_weight < 1:
        raise ValueError("minimum_weight must be at least 1")
    annotations = load_annotation_index(annotations_path)
    source_type_set = set(source_types)
    source_ids = sorted(
        body_id
        for body_id, row in annotations.items()
        if row["type"] in source_type_set and row["status"] != "Glia"
    )
    target_ids = sorted(
        body_id
        for body_id, row in annotations.items()
        if row["superclass"] == TARGET_SUPERCLASS and row["status"] != "Glia"
    )
    if not source_ids:
        raise ValueError(f"No source neurons found for types: {', '.join(source_types)}")
    if not target_ids:
        raise ValueError(f"No target neurons found for superclass: {TARGET_SUPERCLASS}")

    source_id_set = set(source_ids)
    source_values = pa.array(source_ids, type=pa.int64())
    target_values = pa.array(target_ids, type=pa.int64())
    reader = ipc.open_file(pa.memory_map(str(edges_path), "r"))
    aggregates: defaultdict[tuple[str, str, str, str], list[int]] = defaultdict(
        lambda: [0, 0]
    )
    target_totals: Counter[str] = Counter()
    retained_rows = 0
    retained_contacts = 0
    started_at = time.monotonic()

    for batch_number in range(reader.num_record_batches):
        batch = reader.get_batch(batch_number)
        pre_column = batch.column(batch.schema.get_field_index("body_pre"))
        post_column = batch.column(batch.schema.get_field_index("body_post"))
        weight_column = batch.column(batch.schema.get_field_index("weight"))
        source_mask = pc.is_in(pre_column, value_set=source_values)
        target_mask = pc.is_in(post_column, value_set=target_values)
        weight_mask = pc.greater_equal(weight_column, pa.scalar(minimum_weight))
        mask = pc.and_(pc.and_(source_mask, target_mask), weight_mask)
        filtered = batch.filter(mask)
        if filtered.num_rows:
            pre_values = filtered.column("body_pre").to_pylist()
            post_values = filtered.column("body_post").to_pylist()
            weight_values = filtered.column("weight").to_pylist()
            for pre_value, post_value, weight_value in zip(
                pre_values, post_values, weight_values, strict=True
            ):
                pre = annotations[int(pre_value)]
                post = annotations[int(post_value)]
                weight = int(weight_value)
                key = (pre["type"], pre["side"], post["type"], post["side"])
                aggregates[key][0] += 1
                aggregates[key][1] += weight
                target_name = post["type"] or post["instance"] or str(post_value)
                target_totals[target_name] += weight
                retained_rows += 1
                retained_contacts += weight
        if progress and (batch_number + 1) % 250 == 0:
            elapsed = time.monotonic() - started_at
            percent = (batch_number + 1) / reader.num_record_batches * 100.0
            print(
                f"\rScanning edges: {percent:5.1f}%  matches={retained_rows:,}  {elapsed:5.1f}s",
                end="",
                flush=True,
            )
    if progress:
        print()

    source_counts = Counter(
        (row["type"], row["side"])
        for body_id, row in annotations.items()
        if body_id in source_id_set
    )
    aggregate_rows = [
        {
            "source_type": key[0],
            "source_side": key[1],
            "target_type": key[2],
            "target_side": key[3],
            "connection_rows": values[0],
            "synaptic_contacts": values[1],
        }
        for key, values in aggregates.items()
    ]
    aggregate_rows.sort(
        key=lambda row: (-int(str(row["synaptic_contacts"])), str(row["target_type"]))
    )
    return {
        "schema_version": 1,
        "description": (
            "Observed direct connections from looming-sensitive visual projection types "
            "to descending neurons."
        ),
        "source_types": list(source_types),
        "target_superclass": TARGET_SUPERCLASS,
        "minimum_edge_weight": minimum_weight,
        "source_neuron_counts": [
            {"type": key[0], "side": key[1], "count": value}
            for key, value in sorted(source_counts.items())
        ],
        "target_neuron_count": len(target_ids),
        "matched_connection_rows": retained_rows,
        "matched_synaptic_contacts": retained_contacts,
        "top_target_types": [
            {"type": target_type, "synaptic_contacts": contacts}
            for target_type, contacts in target_totals.most_common(40)
        ],
        "aggregates": aggregate_rows,
    }


def build_report(
    data_dir: Path = DEFAULT_OUTPUT,
    output_path: Path = DEFAULT_CIRCUIT_OUTPUT,
    minimum_weight: int = 1,
    progress: bool = True,
) -> dict[str, Any]:
    manifest = load_manifest(DEFAULT_MANIFEST)
    annotations_entry = manifest.files["annotations"]
    edges_entry = manifest.files["edges"]
    annotations_path = data_dir / annotations_entry.filename
    edges_path = data_dir / edges_entry.filename
    for path, entry in ((annotations_path, annotations_entry), (edges_path, edges_entry)):
        if not path.is_file():
            raise FileNotFoundError(f"Missing source file: {path}")
        if path.stat().st_size != entry.bytes or file_digest(path) != entry.sha256:
            raise ValueError(f"Source file does not match the versioned manifest: {path}")

    report = extract_direct_descending_report(
        annotations_path,
        edges_path,
        minimum_weight=minimum_weight,
        progress=progress,
    )
    report["dataset"] = {
        "id": manifest.dataset_id,
        "release": manifest.release,
        "license": manifest.license,
        "source_page": manifest.source_page,
        "annotations_sha256": annotations_entry.sha256,
        "edges_sha256": edges_entry.sha256,
    }
    canonical = json.dumps(report, indent=2, sort_keys=True) + "\n"
    report["report_sha256"] = hashlib.sha256(canonical.encode()).hexdigest()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return report


def derive_runtime_circuit(report: dict[str, Any]) -> dict[str, Any]:
    """Select documented escape-related targets without inventing missing edges."""
    selected = [
        row for row in report["aggregates"] if row["target_type"] in RUNTIME_TARGETS
    ]
    selected.sort(
        key=lambda row: (
            str(row["target_type"]),
            str(row["target_side"]),
            str(row["source_type"]),
            str(row["source_side"]),
        )
    )
    target_contacts: Counter[str] = Counter()
    for row in selected:
        target_contacts[str(row["target_type"])] += int(str(row["synaptic_contacts"]))
    return {
        "schema_version": 1,
        "name": "MaleCNS v1.0 looming-to-escape direct circuit",
        "dataset": report["dataset"],
        "source_report_sha256": report["report_sha256"],
        "selection": {
            "source_types": report["source_types"],
            "target_types": [
                {"type": target_type, "modeled_role": role}
                for target_type, role in RUNTIME_TARGETS.items()
            ],
            "target_superclass": report["target_superclass"],
            "minimum_edge_weight": report["minimum_edge_weight"],
            "observed_connection_rows": sum(
                int(str(row["connection_rows"])) for row in selected
            ),
            "observed_synaptic_contacts": sum(target_contacts.values()),
        },
        "source_neuron_counts": report["source_neuron_counts"],
        "target_contact_totals": [
            {"type": target_type, "synaptic_contacts": target_contacts[target_type]}
            for target_type in RUNTIME_TARGETS
        ],
        "observed_aggregates": selected,
        "model_boundary": {
            "observed": (
                "Neuron identities, sides, direct connections, and synaptic contact counts."
            ),
            "engineered": (
                "Game-to-neuron stimulus encoding, rate dynamics, normalization, thresholds, "
                "action decoding, and body motion."
            ),
            "claim": (
                "A compact game controller weighted by observed MaleCNS looming-to-descending "
                "connectivity; not a whole-brain emulation."
            ),
        },
        "references": [
            "https://male-cns.janelia.org/download/",
            "https://github.com/flyconnectome/2025malecns",
            "https://doi.org/10.1016/j.cell.2026.08.015",
            "https://doi.org/10.1038/s41586-022-05562-8",
            "https://doi.org/10.1038/s41586-025-09037-4",
        ],
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--output", type=Path, default=DEFAULT_CIRCUIT_OUTPUT)
    parser.add_argument("--runtime-output", type=Path, default=DEFAULT_RUNTIME_OUTPUT)
    parser.add_argument("--minimum-weight", type=int, default=1)
    parser.add_argument("--quiet", action="store_true")
    return parser


def main() -> None:
    arguments = build_parser().parse_args()
    try:
        report = build_report(
            arguments.data_dir,
            arguments.output,
            arguments.minimum_weight,
            progress=not arguments.quiet,
        )
        runtime_circuit = derive_runtime_circuit(report)
        arguments.runtime_output.parent.mkdir(parents=True, exist_ok=True)
        arguments.runtime_output.write_text(
            json.dumps(runtime_circuit, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
    print(
        json.dumps(
            {
                "output": str(arguments.output),
                "runtime_output": str(arguments.runtime_output),
                "matched_connection_rows": report["matched_connection_rows"],
                "matched_synaptic_contacts": report["matched_synaptic_contacts"],
                "top_target_types": report["top_target_types"][:12],
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
