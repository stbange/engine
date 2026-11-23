# Non-Euclidean Pocket Spaces ("Bigger on the Inside") & Seamless Portals Specification

## Purpose
Defines first-class pocket-space spatial isolation (`pocket_id`), stencil + oblique near-plane recursive portal rendering (`eng_portal`, `eng_render`), cross-portal physics/raycast/audio/NavMesh traversal, and 1-call LLM building/vehicle helpers (`lua/eng/space.lua`).

## Requirements

### Requirement: Isolated Pocket Spaces Without Geometry or Physics Bleed
The engine SHALL partition entities by `pocket_id` (`0` = default exterior world, `1..N` = named pocket interiors) so rendering, frustum culling, shadow casting, and physics collisions inside an oversized interior room never bleed through a smaller exterior building or moving vehicle.

#### Scenario: Oversized interior centered at origin inside tiny hut
- **WHEN** a `3m x 3m x 3m` exterior hut in `pocket "world"` links to a `30m x 12m x 30m` room in `pocket "hut_inside"` centered at `(0, 0, 0)`
- **THEN** exterior views show only `pocket "world"` outside the doorway while the doorway aperture renders `pocket "hut_inside"` with zero exterior wall poke-through

### Requirement: Stencil and Lengyel Oblique Near-Plane Portal Rendering Across Desktop, Web, and WebXR
The engine SHALL render visible portals using hardware stencil masking, 2D screen-space scissor bounds, Lengyel oblique near-plane projection clipping, and an inverted doorway near-plane cap, supporting moving vehicle portals, scale ratios, and per-eye Stereo WebXR views.

#### Scenario: Stereo WebXR view and walkthrough without near-plane flash
- **WHEN** a player looks through or walks across an open portal threshold on Desktop, Mobile Web, or Stereo WebXR
- **THEN** objects behind the destination portal plane are clipped cleanly by the oblique projection matrix and camera near-plane intersection produces zero 1-frame clipping flicker

### Requirement: Seamless Cross-Portal Physics, Raycasts, Spatial Audio, and AI Pathing
The engine SHALL teleport crossing entities smoothly (transforming pose and linear/angular velocity), project ghost proxy colliders for bodies straddling a portal, continue raycasts across hit portals, route 3D audio attenuation/panning through open doorways, and connect portals with bi-directional NavMesh links.

#### Scenario: Projectile raycast and NPC pathing into a bigger-on-the-inside vehicle
- **WHEN** a raycast is fired from `pocket "world"` through an open vehicle hatch or an AI agent paths toward a target inside `pocket "cabin"`
- **THEN** `eng_physics_raycast` hits targets inside `"cabin"` at the transformed ray trajectory and `eng_ai_find_path` traverses the portal link into `"cabin"`

### Requirement: One-Call LLM Pocket Builders and Portal Spatial Doctor Lint
The engine SHALL provide `eng.space.create_pocket_building`, `eng.space.attach_vehicle_interior`, and `eng.space.cut_wall_with_door` in Lua, and `--doctor` SHALL warn whenever a portal aperture is blocked by a solid collider or mismatched in dimensions.

#### Scenario: Detecting accidentally blocked doorway collider
- **WHEN** `--doctor` audits a scene where a solid wall collider overlaps an active passable portal aperture
- **THEN** `--doctor` emits a structured warning identifying the blocking collider and suggesting `eng.space.cut_wall_with_door`
