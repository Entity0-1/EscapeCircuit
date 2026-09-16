"""Strict loading and validation for versioned scientific-data manifests."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

PACKAGE_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST = PACKAGE_ROOT / "datasets" / "malecns-v1.0.json"


@dataclass(frozen=True, slots=True)
class DatasetFile:
    key: str
    filename: str
    url: str
    bytes: int
    sha256: str


@dataclass(frozen=True, slots=True)
class DatasetManifest:
    dataset_id: str
    display_name: str
    release: str
    sex: str
    coverage: str
    license: str
    source_page: str
    files: dict[str, DatasetFile]


def load_manifest(path: Path = DEFAULT_MANIFEST) -> DatasetManifest:
    """Load a manifest, rejecting ambiguous paths and malformed digests."""
    raw: dict[str, Any] = json.loads(path.read_text(encoding="utf-8"))
    file_entries: dict[str, DatasetFile] = {}
    for key, value in raw["files"].items():
        filename = str(value["filename"])
        if Path(filename).name != filename:
            raise ValueError(f"Dataset filename must be a basename: {filename!r}")
        url = str(value["url"])
        parsed = urlparse(url)
        if parsed.scheme != "https" or not parsed.netloc:
            raise ValueError(f"Dataset URL must use HTTPS: {url!r}")
        digest = str(value["sha256"]).lower()
        if len(digest) != 64 or any(character not in "0123456789abcdef" for character in digest):
            raise ValueError(f"Invalid SHA-256 for {key!r}")
        byte_count = int(value["bytes"])
        if byte_count <= 0:
            raise ValueError(f"Invalid byte count for {key!r}")
        file_entries[key] = DatasetFile(key, filename, url, byte_count, digest)

    return DatasetManifest(
        dataset_id=str(raw["dataset_id"]),
        display_name=str(raw["display_name"]),
        release=str(raw["release"]),
        sex=str(raw["sex"]),
        coverage=str(raw["coverage"]),
        license=str(raw["license"]),
        source_page=str(raw["source_page"]),
        files=file_entries,
    )

