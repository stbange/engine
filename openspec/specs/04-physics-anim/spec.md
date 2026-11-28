# Pure-C Physics & Skeletal Animation Specification

## Purpose
Defines deterministic pure-C11 rigid-body/voxel collision and dynamics (`eng_physics`) and glTF skeletal animation skinning, blending, and inverse kinematics (`eng_anim`).

## Requirements

### Requirement: Deterministic Pure-C Rigid Body and Voxel Physics
The engine SHALL step physics at a fixed timestep using a dynamic AABB BVH broadphase, analytical + GJK/EPA + voxel-grid narrowphase, sequential-impulse rigid-body solver, sensor triggers, kinematic stair-stepping character controller, lateral wall-sliding collision queries (`eng_physics_slide_xz`, `eng.physics.slide_move`) against static AABB/voxel colliders (including procedural dungeons and pocket building walls), and raycasts/spherecasts.

#### Scenario: Raycast and rigid-body collision determinism
- **WHEN** identical scenes and inputs execute twice with `--seed 42` in `--headless` mode
- **THEN** `eng_physics` produces bit-identical contact events, raycast hits, and rigid-body transforms at frame 600

#### Scenario: Wall collision blocks and slides player movement
- **WHEN** a player moves diagonally into a static AABB or procedural dungeon voxel wall via `eng.physics.slide_move`
- **THEN** penetration into the wall is blocked while tangential velocity slides smoothly along the wall surface without snagging on floors or corners

### Requirement: Skeletal Skinning, Crossfade Blending, and IK
The engine SHALL evaluate glTF joint hierarchies, sample `step`/`linear`/`cubic` animation channels, blend/crossfade multiple clips with optional bone masks, upload GPU skinning matrices, and solve 2-bone analytical IK and multi-joint FABRIK chains.

#### Scenario: Foot placement via 2-bone IK
- **WHEN** a mech or character ankle target is adjusted onto uneven terrain via `eng_anim_ik_two_bone`
- **THEN** hip and knee joint rotations update smoothly to reach the target within limb-length bounds before GPU bone palette upload

### Requirement: Full 6-DOF Rotational Dynamics, Buoyancy, Joints & Voxel Island Fracture
The engine SHALL compute shape inertia tensors, off-center contact lever-arm angular impulses, quaternion angular velocity integration, velocity-threshold sleeping, material-density Archimedes fluid buoyancy + hydrodynamic drag, wind/radial-blast forces, breakable constraints (`distance`, `ball`, `hinge`, `spring` with `break_force`), and 6-connected floating voxel island extraction (`eng_voxel_extract_floating_islands`).

#### Scenario: Buoyant vs sinking rigid bodies, breakable joints, and severed voxel islands
- **WHEN** a wooden box (`density = 600`) and iron sphere (`density = 7800`) enter water (`density = 1000`), an off-center impulse strikes a dynamic crate, or a voxel pillar's base is removed
- **THEN** the wooden box floats at equilibrium while the iron sphere sinks, the struck crate tumbles in 6-DOF, overloaded joints break cleanly, and disconnected upper voxels detach as independent chunks

