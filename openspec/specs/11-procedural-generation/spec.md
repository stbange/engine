# Deterministic Random & Procedural Content Generation Specification

## Purpose
Defines deterministic seed-driven procedural generation (`eng_procgen` in C11 and `lua/eng/procgen.lua`) for multi-dimensional noise, PBR/retro textures, solvable dungeons/caves/WFC layouts, 3D spherical planets, articulated DNA animals, modular people/NPCs, L-system flora, Poisson-disk scatter, and multi-seed Spatial Doctor fuzzing.

## Requirements

### Requirement: Cross-Platform Deterministic Noise and Procedural Texture Synthesis
The engine SHALL provide seeded 2D/3D Value, Perlin, Simplex-style, and Worley/Voronoi noise (with fBm, Ridged, and Domain Warp modifiers) and SHALL synthesize tileable `RGBA8` albedo, Sobel normal, and roughness textures from compact seed/recipe descriptors.

#### Scenario: Bit-consistent procedural texture generation from seed
- **WHEN** `eng.procgen.texture("stone_brick", 1337, 128)` runs on Desktop or WebAssembly
- **THEN** `eng_procgen` generates deterministic `128x128` albedo and normal maps without external image files

### Requirement: Solvability-Guaranteed Dungeons, Caves, and WFC Layouts
The engine SHALL generate BSP room-and-corridor dungeons, 2D/3D cellular-automata caves, and tiled WFC layouts from a seed, automatically repairing disconnected regions and guaranteeing `key_depth < lock_depth` progression before emitting meshes/voxels, colliders, and NavMeshes.

#### Scenario: Guaranteed entrance-to-exit path in cellular cave
- **WHEN** a cave or dungeon is generated for any 64-bit seed
- **THEN** `eng_procgen` verifies path connectivity between `"entrance"` and `"exit"` (carving connecting tunnels if isolated) so zero unwinnable layouts occur

### Requirement: Seamless 3D Cube-Sphere Planets with Whittaker Biomes and Radial Gravity
The engine SHALL generate 3D spherical planets using cube-sphere/icosphere subdivision (free of polar UV pinching) with ridged continents, oceans, craters, latitude/moisture/elevation biome coloring, LOD chunks, and radial spherical gravity helpers.

#### Scenario: Walking full circle around a procedural 3D planet
- **WHEN** a procedural planet is spawned via `eng.procgen.planet({ seed = 99, radius = 40.0 })` with radial gravity enabled
- **THEN** character and rigid-body physics align `up` to `normalize(pos - planet_center)` smoothly across poles and equator

### Requirement: Procedural Articulated Animals and Modular People with Auto-Rigged Gaits
The engine SHALL generate 3D/voxel animals from seed or DNA descriptors (`quadruped`, `biped`, `avian`, `insectoid`, `aquatic`, `serpentine`) with lofted spines, symmetrical limbs, head features, coat patterns, auto-skeletons, and procedural phase-shifted IK gaits, and SHALL generate modular humanoid NPCs (`eng.procgen.person`) with varied proportions, harmonious palettes, gear, rigs, and Markov names/traits.

#### Scenario: Immediate locomotion of seed-generated quadruped animal
- **WHEN** a game spawns `eng.procgen.animal({ seed = 7, archetype = "quadruped" })` and sets velocity forward
- **THEN** the generated creature mesh, coat texture, 4-leg skeleton, and procedural IK gait animate smoothly without external `.glb` files

### Requirement: L-System Flora, Poisson Scatter, and Multi-Seed Fuzz Doctor
The engine SHALL provide 3D L-system flora builders, overlap-free 2D/spherical Poisson-disk scatter, and `--doctor --fuzz-seeds <N>` to verify procedural scenes across `N` seeds in headless CI.

#### Scenario: Multi-seed procedural scene validation
- **WHEN** `./engine --headless --doctor --fuzz-seeds 10 --game <dir>` runs on a procedural game
- **THEN** `--doctor` initializes and audits 10 distinct seeds, failing non-zero if any seed produces collider spawn overlaps, empty camera frustums, or unreachable exits
