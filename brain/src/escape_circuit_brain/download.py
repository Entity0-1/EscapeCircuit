"""Reproducible downloader for version-locked MaleCNS source files."""

from __future__ import annotations

import argparse
import hashlib
import os
import sys
import time
import urllib.request
from collections.abc import Iterable
from pathlib import Path

from .manifest import DEFAULT_MANIFEST, DatasetFile, load_manifest

PROJECT_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_OUTPUT = PROJECT_ROOT / "data" / "connectome" / "malecns-v1.0"
CHUNK_SIZE = 8 * 1024 * 1024


def file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(CHUNK_SIZE):
            digest.update(chunk)
    return digest.hexdigest()


def verify_file(path: Path, expected: DatasetFile) -> tuple[bool, str]:
    if not path.is_file():
        return False, "missing"
    actual_size = path.stat().st_size
    if actual_size != expected.bytes:
        return False, f"size mismatch ({actual_size} != {expected.bytes})"
    actual_digest = file_digest(path)
    if actual_digest != expected.sha256:
        return False, f"SHA-256 mismatch ({actual_digest})"
    return True, "verified"


def _progress(downloaded: int, total: int, started_at: float) -> str:
    elapsed = max(time.monotonic() - started_at, 0.001)
    percent = downloaded / total * 100.0 if total else 0.0
    rate_mib = downloaded / elapsed / (1024 * 1024)
    return f"{percent:6.2f}%  {downloaded / (1024 * 1024):8.1f} MiB  {rate_mib:6.1f} MiB/s"


def download_file(entry: DatasetFile, output_dir: Path) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    destination = output_dir / entry.filename
    valid, reason = verify_file(destination, entry)
    if valid:
        print(f"{entry.key}: already {reason} ({destination.name})")
        return destination
    if destination.exists():
        raise ValueError(
            f"Refusing to overwrite unverified dataset file {destination}: {reason}. "
            "Move it aside or delete that exact file before retrying."
        )

    partial = destination.with_suffix(destination.suffix + ".partial")
    if partial.exists():
        partial.unlink()

    request = urllib.request.Request(
        entry.url,
        headers={"User-Agent": "Escape-Circuit/0.1 (+https://github.com/)"},
    )
    started_at = time.monotonic()
    downloaded = 0
    print(f"{entry.key}: downloading {entry.bytes / (1024 * 1024):.1f} MiB")
    try:
        with urllib.request.urlopen(request, timeout=60) as response, partial.open("xb") as stream:
            while chunk := response.read(CHUNK_SIZE):
                stream.write(chunk)
                downloaded += len(chunk)
                print(f"\r  {_progress(downloaded, entry.bytes, started_at)}", end="", flush=True)
        print()
        valid, reason = verify_file(partial, entry)
        if not valid:
            raise ValueError(f"Downloaded file failed verification: {reason}")
        os.replace(partial, destination)
    except BaseException:
        if partial.exists():
            partial.unlink()
        raise
    print(f"{entry.key}: verified SHA-256 {entry.sha256}")
    return destination


def download_selected(keys: Iterable[str], manifest_path: Path, output_dir: Path) -> list[Path]:
    manifest = load_manifest(manifest_path)
    requested = list(keys)
    unknown = sorted(set(requested) - manifest.files.keys())
    if unknown:
        raise ValueError(f"Unknown dataset file key(s): {', '.join(unknown)}")
    return [download_file(manifest.files[key], output_dir) for key in requested]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--files",
        nargs="+",
        choices=("annotations", "neurotransmitters", "edges"),
        default=("annotations", "neurotransmitters"),
        help="Versioned source files to fetch (the edge table is approximately 1.1 GB).",
    )
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    return parser


def main() -> None:
    arguments = build_parser().parse_args()
    try:
        download_selected(arguments.files, arguments.manifest, arguments.output)
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()

