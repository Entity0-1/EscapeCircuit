# Escape Circuit

**A first-person fly-swatting game whose escape actions and some cruising turns are influenced by circuits derived from a real fruit-fly connectome.**

Escape Circuit is an open-source game and software-engineering portfolio project. The player has sixty seconds to track and catch a fly moving freely through a furnished modern apartment: an open-plan living/dining/kitchen area, workspace, corridor, bathroom, and bedroom. One compact circuit receives modeled visual threats and helps select distinct escape actions; another regulates modeled spontaneous flight turns. Godot handles three-dimensional movement, navigation, and biomechanics.

The downloadable game is self-contained: both compact MaleCNS-derived circuits run inside Godot, so players do not need Python, a server, an account, or an internet connection. A matching Python escape implementation and reproducible data pipeline are included for software verification and scientific inspection, not biological validation.

> Scientific boundary: these are compact game controllers weighted by observed MaleCNS v1.0 connections. Stimulus encoding, spontaneous pulses, dynamics, thresholds, action decoding, and body motion are engineered. This is **not** a whole-brain simulation or a reconstruction of a fly's mind.

## Controls

- Use WASD to walk around the apartment.
- Move the mouse to look and track the fly in three dimensions.
- Hold the left mouse button or Space to charge.
- Release to swing.
- Press R after a round to restart.
- Press Escape to pause or resume.
- Press T to show or hide the modeled-threat and circuit-response display.
- Press V after a round to view a looping split-screen replay of the last twelve seconds. Press V or Escape to close it. Screen-record this view to make video footage; the game does not export a movie file.

## Play locally

For the already-built Windows game, double-click `build/windows/EscapeCircuit.exe`. It is a standalone export with the game data embedded; PowerShell and a separate Godot installation are not required.

If you are running the source project instead, install the pinned portable Godot version with:


```powershell
powershell -ExecutionPolicy Bypass -File scripts/bootstrap.ps1
```

Then double-click `scripts/play.ps1` or run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/play.ps1
```

The bootstrap archive and executable are verified against pinned SHA-256 digests and kept out of Git.

## Development

The project targets Godot 4.7.2 and uses GDScript. Open `project.godot` in the Godot editor, or run it from the command line:

```powershell
godot --path . --editor
```

The imported apartment is instantiated from `scenes/apartment.tscn`, which inherits the supplied `scene.gltf`. Open that scene in Godot to inspect the model and make local scene overrides. Its source textures and geometry live under `assets/models/apartment/modern_apartment/`. Spawn positions, fly perches, room waypoints, and furniture footprints are in `scripts/apartment_layout.gd`; the architectural collision is generated from selected low-poly meshes in `scripts/main.gd`. If you move walls or furniture, update those gameplay coordinates as well.

This is a detailed architectural-visualization asset (about three million triangles), not a low-poly game level. Collision uses only selected structural surfaces, but the full art still renders. Benchmark target hardware and consider mesh simplification, texture downsizing, and LODs before presenting a public browser build as optimized.

Run every Godot and Python quality check with:

```powershell
scripts/check.ps1
```

The optional loopback service runs the independent Python implementation through the same versioned protocol:

```powershell
scripts/play-with-brain.ps1
```

## Build a public Windows release

Install the pinned Godot 4.7.2 export templates once, then run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/bootstrap.ps1 -WithExportTemplates
scripts/build-release.ps1
```

The script tests the project and creates:

- `dist/Escape-Circuit-web.zip` — upload to itch.io as an HTML project for free and select “This file will be played in the browser.”
- `dist/Escape-Circuit-windows-x86_64.zip` — offer as a Windows download on itch.io or use its executable for a future Steam build.

The shipped fly is “Housefly” by schmoldt.art under CC BY 4.0. Its original wings are separated and animated in Godot; the earlier Personal Use License fly is not shipped. The apartment, “Fly Swatter” model by reconpeanut, and MaleCNS-derived circuit also remain CC BY 4.0. Before publishing a game page or video description, credit all four sources with their model/data and license links and note the gameplay adaptations; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The release script copies the notices into both builds.

Use the ready-to-copy credit text and release checklist in [docs/publishing.md](docs/publishing.md). The web export is large, even after preserving apartment texture resolution with high-quality lossy import; test its loading time and frame rate in a real browser before making the page public.

Steam Direct requires a per-product fee; itch.io hosting and browser play do not require a paid backend for this game.

## Architecture

The game is deliberately split into three concerns:

1. `ApartmentLayout` holds shared bounds, imported-furniture footprints, perch points, and room-to-room fly routes. Selected architectural surfaces generate static collision bodies from the source model.
2. Godot owns rendering, input, collision detection, movement, animation, the short in-memory replay, and user experience.
3. A neural provider consumes sensory values and produces high-level action values.

The shipped game loads two compact MaleCNS v1.0 artifacts: visual-to-descending escape contacts and a six-neuron spontaneous-flight-turn motif. `FallbackBrain` is retained as a visibly labeled escape recovery mode. The optional Python loopback service implements the escape equations independently; the flight-turn motif always runs locally in Godot.

See [docs/architecture.md](docs/architecture.md) for the intended production design.

## Data and scientific claims

Large connectome files are downloaded separately and never committed to Git. The data tools pin source URLs, release identifiers, byte counts, licenses, and SHA-256 hashes, then extract the direct LPLC2/LC4-to-descending-neuron escape circuit and a small VES041/DNa15/DNb01 turn motif. Every connection between observed data and engineered behavior is documented in [docs/neuroscience.md](docs/neuroscience.md).

The primary data comes from the [official MaleCNS v1.0 download](https://male-cns.janelia.org/download/). The companion [flyconnectome/2025malecns GitHub repository](https://github.com/flyconnectome/2025malecns) contains the paper's supplemental derived data; it is not the full connectome download.

For a concise system tour and portfolio talking points, see [docs/architecture.md](docs/architecture.md) and [docs/portfolio-guide.md](docs/portfolio-guide.md).

## License

Original project code is licensed under the MIT License. Third-party assets and scientific datasets are not covered by that grant; they retain their own licenses and attribution requirements.
