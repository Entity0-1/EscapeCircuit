# Escape Circuit brain service

This package owns the versioned MaleCNS data pipeline and the optional reference neural-controller service used by the Godot game. The public game runs the equivalent controller in-process and does not require Python.

The service binds to loopback only. It does not upload connectome data, gameplay data, or telemetry.

## Development setup

```powershell
uv sync --project brain --extra dev
uv run --project brain pytest
```

## Run the local service

```powershell
uv run --project brain escape-circuit-brain
```

When the generated circuit artifact is present, the service loads its observed MaleCNS connection weights and emits the same continuous 3D motor channels as the in-process controller. It falls back to the visibly labeled prototype only when the artifact is unavailable.

## Download MaleCNS inputs

Download the two small metadata files first:

```powershell
uv run --project brain escape-circuit-data --files annotations neurotransmitters
```

The complete edge table is approximately 1.1 GB and is intentionally explicit:

```powershell
uv run --project brain escape-circuit-data --files edges
```

Every completed file is checked against a pinned byte count and SHA-256 digest before it is accepted.

## Discover the direct looming-to-descending circuit

After downloading annotations and edges, scan the versioned graph and write a compact report:

```powershell
uv run --project brain escape-circuit-extract
```

The command writes both a complete ignored report and the small tracked runtime artifact. They list observed direct connections from the looming-sensitive LPLC2 and LC4 populations to annotated descending neurons. Extraction does not infer neural dynamics or behavior.
