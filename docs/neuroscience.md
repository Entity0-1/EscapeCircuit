# Neuroscience scope and claims

## What the data provides

MaleCNS v1.0 provides reconstructed neurons, annotations, predicted neurotransmitter information, and measured synaptic connectivity for an adult male fruit-fly brain and ventral nerve cord.

## What the data does not provide by itself

A wiring diagram is not a complete dynamical brain model. The release does not uniquely specify membrane time constants, receptor-dependent synaptic effects, complete sensory transduction, neuromodulation, plasticity, muscle dynamics, or a mapping from game pixels to biological experience.

## Project claim boundary

The intended defensible description is:

> An interactive game in which compact controllers derived from measured fruit-fly connectivity receive engineered inputs and influence escape actions and spontaneous flight turns.

The project must not describe the result as an uploaded mind, conscious fly, exact reproduction of a biological individual, or validated model of natural learning.

## Current implementation

The shipped in-process `ConnectomeBrain` and the optional service-side `ConnectomeCircuitController` load the same generated MaleCNS circuit artifact. Their independent implementations are tested against the same known connection count and behavioral cases. `FallbackBrain` remains deterministic interface scaffolding and is labeled `PROTOTYPE` if used.

The generated `malecns-v1.0-looming-escape.json` artifact contains 1,343 observed connection rows and 39,549 synaptic contacts from LPLC2 and LC4 visual-projection neurons to selected descending neuron types. LPLC2 and LC4 are looming-sensitive; DNp01 is the Giant Fiber associated with rapid escape takeoff. DNp02, DNp04, and DNp11 are among documented LC4 downstream pathways associated with directional escape, DNp06 has been associated with evasive maneuvers, and DNp03 is a collision-avoidance flight-saccade pathway.

The runtime controller is a compact population-rate model weighted by those observed contacts. It continuously decodes descending-population activity into takeoff, yaw, pitch, roll, flight-power, and landing signals. Those signals now steer the trajectory and banking angle throughout an escape instead of merely selecting a pre-authored dodge direction.

The escape decoder now exposes separate DNp01 fast-takeoff, DNp02/DNp04 backward-takeoff, DNp11 forward-takeoff, and DNp03 airborne-saccade drives. The fly chooses an action from their relative modeled activity and its perched/airborne state. Fast takeoff, directional takeoff, and flight saccade have different trajectories and speed curves. The [directional-takeoff experiments](https://www.nature.com/articles/s41586-022-05562-8) and [DNp03 flight-saccade study](https://pubmed.ncbi.nlm.nih.gov/41389794/) motivate these distinctions. The game's action mappings and thresholds are engineered interpretations, not a reconstruction of exact fly motor commands. In particular, this compact artifact pools visual contacts by neuron type and body side, so it does not preserve the retinotopic gradients needed to reproduce the experimentally measured front-versus-back takeoff choice.

An independent `FlightTurnBrain` loads `malecns-v1.0-flight-turn.json`, extracted from the complete MaleCNS edge table and annotations. Its six annotated neurons (bilateral VES041, DNa15, and DNb01) have **13 observed connection rows and 138 synaptic contacts** within this selected motif. DNa15 corresponds to the DNae014 name used in [Ros et al. (2024)](https://pubmed.ncbi.nlm.nih.gov/38228148/). The paper associates DNa15/DNb01 units with spontaneous flight saccades and VES041 with turn suppression. During ordinary cruising, seeded game-generated left/right turn pulses and a game-state straight-flight input enter this contact-weighted model; its output steers sharp turns or suppresses them during room-to-room transit. Pulse timing, tonic input, contact normalization, inhibitory signs, and steering strength remain modeling choices. The optional Python service implements the escape circuit only; the separate spontaneous-turn motif always runs locally in Godot.

The mapping from swatter geometry and player approach velocity to visual sectors, neural rate dynamics, normalization, motor-channel equations, landing permission, navigation targets, and Godot biomechanics are engineered. Swatter charge and windup are intentionally excluded from sensory input; only the actual descending strike contributes swatter looming, matching the distinction between a stationary object and an expanding visual threat. In particular, the landing channel is a modeled threat-inhibition signal rather than a reconstruction of a complete biological landing pathway. The result is a connectome-derived sensorimotor controller, not a whole-brain emulation.

The visual encoder now estimates each approaching object's apparent angular diameter and angular expansion rate from its game-world size, distance, and radial closing speed. An engineered log-Gaussian size response feeds LPLC2; an engineered saturating expansion-speed response feeds LC4. This follows the experimentally identified feature distinction in [Ache et al. (2019)](https://pubmed.ncbi.nlm.nih.gov/30827912/) but does **not** import their fitted parameters, reproduce their stimulus apparatus, or validate real-fly reaction times. Left/right feature values flow separately through the observed MaleCNS contact counts to descending outputs. Both the in-process Godot brain and optional Python brain service accept the same additional feature fields; old protocol callers retain their legacy input behavior.

For a reproducible *model* timing check, `tests/test_runner.gd` holds apparent size and distance fixed, changes only radial closing speed, and reports the first 60 Hz frame at which the connectome-weighted takeoff drive exceeds the gameplay threshold. `brain/tests/test_connectome_controller.py` checks the equivalent service-side behavior. These timings are simulated controller outputs in milliseconds, **not** biological latency measurements. A perched fly with a loaded MaleCNS circuit now uses its descending response for takeoff timing; only the prototype fallback retains a fixed-delay looming trigger.

During ordinary cruising, a periodically changing altitude target and waypoint destinations remain game-only behavior. They do not change either circuit's contact weights. The flight-turn motif influences horizontal saccades versus straight segments, not destination choice or wing-flap animation; takeoff, dodging, and recovery do not use the cruise altitude target.

## Reproducibility

The manifest pins the MaleCNS release URL, byte size, and SHA-256 digest for every source file. The extractor verifies those files before scanning the complete edge table. The checked-in runtime artifact records the source digests, selection criteria, observed row and synaptic-contact totals, references, and its generated report digest.

The second artifact is regenerated with `uv run --project brain python -m escape_circuit_brain.turn_circuit` after the annotations and full edge table are downloaded. Its extractor verifies both source files against the manifest before scanning. The neural tests compare intact turn regulation to a VES041-contact ablation under identical modeled inputs; this demonstrates a contribution of the selected graph to the *game model*, not biological validation.

## Primary dataset citation

Berg, S. et al. “Sexual dimorphism in the complete Drosophila male central nervous system connectome.” *Cell* 189(18), 5504–5526.e15 (2026). https://doi.org/10.1016/j.cell.2026.08.015

- Official data and license: https://male-cns.janelia.org/download/
- Official supplemental GitHub repository: https://github.com/flyconnectome/2025malecns
