# Portfolio guide

## One-sentence pitch

Escape Circuit turns a version-locked fruit-fly connectome circuit into the evasive controller of a polished, self-contained 3D game.

## What this demonstrates

- Product engineering: a complete interaction loop, visual hierarchy, procedural animation and audio, pause/restart states, and release packaging.
- Systems design: a stable provider interface with in-process, fallback, and non-blocking loopback implementations.
- Data engineering: checksummed 1.1 GB source data is streamed into a compact, reviewable runtime artifact.
- Simulation engineering: observed connectivity is decoded into continuous takeoff, yaw, pitch, roll, flight-power, and landing channels that drive Godot biomechanics.
- Scientific integrity: measured connectivity and engineered simulation choices are separated in code, telemetry, and documentation.
- Quality engineering: deterministic controller tests, scene-level integration tests, Python unit tests, linting, type checking, and CI.

## Suggested repository screenshots

1. Title screen framing the furnished apartment and `MALECNS SENSORIMOTOR` label.
2. Mid-swing gameplay with modeled-threat and descending-circuit telemetry active.
3. The synchronized player/fly split-screen replay, with the recorded circuit response beneath it.
4. A small architecture diagram from `docs/architecture.md`.
5. A code excerpt from `circuit.py` beside the generated JSON artifact.

## Suggested two-minute demo structure

1. State the challenge: can a controller derived from a fly connectome escape a human player?
2. Show one clean gameplay round and the live modeled-threat/circuit-response display, then press V for the last-twelve-seconds replay.
3. Explain the scientific boundary in one sentence; avoid calling it a whole fly brain.
4. Show that the original 1.1 GB graph becomes a tiny checked artifact with exact provenance.
5. End on the architecture, tests, and public download link.

## Resume bullet template

Built a fully 3D Godot 4 game set in a furnished apartment, with an in-process neural controller derived from version-pinned MaleCNS connectome data; created a reproducible Python/Arrow extraction pipeline, non-blocking TCP protocol, deterministic tests, CI configuration, and one-command Windows/Web packaging. Add “released” and cite a public link only after actually publishing it.
