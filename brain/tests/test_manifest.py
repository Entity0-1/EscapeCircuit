from __future__ import annotations

import json
from pathlib import Path

import pytest

from escape_circuit_brain.manifest import DEFAULT_MANIFEST, load_manifest


def test_checked_in_manifest_is_valid() -> None:
    manifest = load_manifest(DEFAULT_MANIFEST)
    assert manifest.dataset_id == "malecns-v1.0"
    assert manifest.license == "CC-BY-4.0"
    assert set(manifest.files) == {"annotations", "neurotransmitters", "edges"}


def test_manifest_rejects_path_traversal(tmp_path: Path) -> None:
    value = json.loads(DEFAULT_MANIFEST.read_text(encoding="utf-8"))
    value["files"]["annotations"]["filename"] = "../annotations.feather"
    path = tmp_path / "invalid.json"
    path.write_text(json.dumps(value), encoding="utf-8")
    with pytest.raises(ValueError, match="basename"):
        load_manifest(path)

