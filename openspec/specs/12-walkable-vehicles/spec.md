# Steerable Walkable Moving Vehicles Specification

## Purpose
Defines first-class engine support for steerable, moving, and rotating vehicles whose interiors are isolated pocket spaces (`pocket_id`) where multiple players/NPCs can walk, operate stations, look out stencil window portals, and board/exit across moving thresholds with Galilean momentum preservation.

## Requirements

### Requirement: Moving-Portal Threshold Sweep and Galilean Momentum Transfer
The portal and physics subsystems (`eng_portal`, `eng_physics`) SHALL track per-portal world kinematic transforms across frames (`eng_portal_step_kinematics`) so stationary external entities swept by a moving vehicle portal cross cleanly, and SHALL transform linear velocities across portals using Galilean relative frame velocity ($\mathbf{v}' = \mathbf{W}_{3\times 3}(\mathbf{v} - \mathbf{v}_{\text{src}}(\mathbf{x})) + \mathbf{v}_{\text{dst}}(\mathbf{x}')$).

#### Scenario: Exiting and boarding a moving vehicle preserves world/deck momentum
- **WHEN** a dynamic body or player exits an interior pocket doorway (`v_src = 0`) onto an exterior vehicle hatch moving at `(0, 0, -20)` m/s
- **THEN** the exited body inherits the vehicle's `-20 m/s` world velocity plus its rotated local exit velocity, and a stationary external body swept by an advancing vehicle ramp crosses into the interior pocket at relative deck speed

### Requirement: Multi-Window, Multi-Station Steerable Vehicle Builder
The `eng.space` Lua standard library SHALL provide `eng.space.create_steerable_vehicle(eng, vehicle_ent, cfg)` constructing an isolated walkable interior pocket, a passable boarding hatch portal, non-passable cockpit windshield/window stencil portals parented to the exterior hull, multi-crew interactive stations (helm + auxiliary stations), persistent cruise steering while crew walk freely, and clamped inertial deck sway coupled to hull acceleration and gait cadence.

#### Scenario: Three crew members steering and operating stations inside a moving bipedal vehicle
- **WHEN** one crew member sets cruise/steering at the helm while two other crew members walk inside the swaying interior deck to operate auxiliary stations
- **THEN** the exterior vehicle moves and turns in world space, windshield portals track the live exterior view, and interior crew walk without physics jitter
