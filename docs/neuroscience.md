# Neuroscience scope and claims

## What the data provides

MaleCNS v1.0 provides reconstructed neurons, annotations, predicted neurotransmitter information, and measured synaptic connectivity for an adult male fruit-fly brain and ventral nerve cord.

## What the data does not provide by itself

A wiring diagram is not a complete dynamical brain model. The release does not uniquely specify membrane time constants, receptor-dependent synaptic effects, complete sensory transduction, neuromodulation, plasticity, muscle dynamics, or a mapping from game pixels to biological experience.

## Project claim boundary

The intended defensible description is:

> An interactive game in which a controller derived from measured fruit-fly connectivity receives engineered threat stimuli and influences a simulated fly's escape behavior.

The project must not describe the result as an uploaded mind, conscious fly, exact reproduction of a biological individual, or validated model of natural learning.

## Current implementation

The shipped in-process `ConnectomeBrain` and the optional service-side `ConnectomeCircuitController` load the same generated MaleCNS circuit artifact. Their independent implementations are tested against the same known connection count and behavioral cases. `FallbackBrain` remains deterministic interface scaffolding and is labeled `PROTOTYPE` if used.

The generated `malecns-v1.0-looming-escape.json` artifact contains 1,343 observed connection rows and 39,549 synaptic contacts from LPLC2 and LC4 visual-projection neurons to selected descending neuron types. LPLC2 and LC4 are looming-sensitive; DNp01 is the Giant Fiber associated with rapid escape takeoff. DNp02, DNp04, and DNp11 are among documented LC4 downstream pathways associated with directional escape, DNp06 has been associated with evasive maneuvers, and DNp03 is a collision-avoidance flight-saccade pathway.

The runtime controller is a compact population-rate model weighted by those observed contacts. It continuously decodes descending-population activity into takeoff, yaw, pitch, roll, flight-power, and landing signals. Those signals now steer the trajectory and banking angle throughout an escape instead of merely selecting a pre-authored dodge direction.

The mapping from swatter geometry and player approach velocity to visual sectors, neural rate dynamics, normalization, motor-channel equations, landing permission, navigation targets, and Godot biomechanics are engineered. Swatter charge and windup are intentionally excluded from sensory input; only the actual descending strike contributes swatter looming, matching the distinction between a stationary object and an expanding visual threat. In particular, the landing channel is a modeled threat-inhibition signal rather than a reconstruction of a complete biological landing pathway. The result is a connectome-derived sensorimotor controller, not a whole-brain emulation.

## Reproducibility

The manifest pins the MaleCNS release URL, byte size, and SHA-256 digest for every source file. The extractor verifies those files before scanning the complete edge table. The checked-in runtime artifact records the source digests, selection criteria, observed row and synaptic-contact totals, references, and its generated report digest.

## Primary dataset citation

Berg, S. et al. “Sexual dimorphism in the complete Drosophila male central nervous system connectome.” *Cell* 189(18), 5504–5526.e15 (2026). https://doi.org/10.1016/j.cell.2026.08.015

- Official data and license: https://male-cns.janelia.org/download/
- Official supplemental GitHub repository: https://github.com/flyconnectome/2025malecns
