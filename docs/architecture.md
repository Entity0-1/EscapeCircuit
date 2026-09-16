# Architecture

## Design goals

- Keep gameplay responsive even when neural computation is slow.
- Make biological data, modeling assumptions, and game scaffolding distinguishable.
- Run entirely on the player's machine with no paid backend.
- Support deterministic recording and replay for testing and video production.
- Package the production controller inside a single-player build with no backend.

## Components

### Godot game

The game runs at the display frame rate. It instantiates the CC BY 4.0 Modern Apartment glTF, and owns first-person WASD movement and mouse look, fly body, swatter, animation, three-dimensional navigation volume, collision detection, round state, telemetry UI, and audio. It converts world state into a compact sensory message and consumes the most recent neural response without waiting for it. `ApartmentLayout` registers furniture bounds extracted from the imported scene; selected architectural meshes generate static collision bodies. Player and fly query those walls while sharing furniture footprints, and the fly follows doorway waypoints when changing rooms. Short movement substeps and swept ray checks prevent high-speed fly motion from tunneling through thin walls.

### In-process MaleCNS controllers

The escape provider receives modeled angular-size and expansion-speed features, visual sectors, proximity, and impact. It returns continuous descending activity and separate fast-takeoff, directional-takeoff, and airborne-saccade drives alongside steering and diagnostic signals. `ConnectomeBrain` reads the checked-in escape artifact. Independently, `FlightTurnBrain` reads the VES041/DNa15/DNb01 artifact and uses engineered spontaneous pulses and a straight-flight input to regulate cruising saccades. Both run in-process; neither replaces Godot navigation or physics.

`FallbackBrain` preserves the same contract and is used only if the artifact cannot be loaded. It remains visibly labeled whenever active.

### Optional Python reference service

The local Python process:

1. Validates version-locked MaleCNS inputs.
2. Imports the graph into a compact sparse representation.
3. Extracts a documented, reviewable runtime artifact.
4. Implements the same declared approximate neural dynamics independently.
5. Streams activity and performance telemetry to Godot over versioned JSON lines.

The game never blocks its render loop while waiting for the service. When the service is absent, disconnected, or late, the in-process escape provider continues immediately. The separate flight-turn circuit remains in-process in either case. The network socket is loopback-only.

## Runtime flow

```text
WASD + mouse look + swatter geometry
          |
          v
fly-relative looming sectors, proximity, impact
          |
          +------ optional local Python service ------+
          |                                            |
          v                                            v
in-process ConnectomeBrain <------ latest valid response
          |
          v
escape action + yaw + pitch + roll + power + landing
          |
          +---- FlightTurnBrain: modeled pulses + straight-flight state
          |
          v
3D biomechanics, fly state machine, cruising turns, collision, UI, audio
```

## Scientific boundary

MaleCNS is measured connectivity. Membrane dynamics, stimulus encoding, action decoding, learning rules, and body control are models or engineering decisions unless explicitly supported by cited experiments. Project copy and telemetry must preserve this distinction.
