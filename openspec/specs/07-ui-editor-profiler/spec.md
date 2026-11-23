# Immediate-Mode UI, In-Game HUD, Console, Profiler & Level Editor Specification

## Purpose
Defines the pure-C Nuklear immediate-mode debug UI and Lua-accessible In-Game HUD (`eng_ui`), Quake-style console (`eng_log`), CPU/GPU profiler and 3D debug draw (`eng_profiler`), and built-in scene/level editor (`eng_editor`).

## Requirements

### Requirement: Pure-C Nuklear Debug UI and Skinnable In-Game HUD
The engine SHALL render Nuklear debug/editor panels over OpenGL 3.3 / GLES 3.0 and SHALL expose anchored, resolution-independent In-Game UI widgets (labels, buttons, bars, menus, touch joysticks) to C and Lua.

#### Scenario: Resolution-anchored HUD scaling
- **WHEN** the window resizes from `1280x720` to `1920x1080` or HiDPI scale changes
- **THEN** anchored HUD widgets reposition proportionally without clipping off-screen

### Requirement: Drop-Down Console, Profiler, and 3D Debug Draw
The engine SHALL provide a toggleable `~` console with log filtering, CVars, and live sandboxed Lua REPL, alongside scoped CPU/GPU frame timings, memory arena meters, and 3D debug wireframe/collider/skeleton/navmesh drawing.

#### Scenario: Live Lua REPL inspection in console
- **WHEN** a developer or test executes a Lua expression in the console command handler
- **THEN** the sandboxed expression evaluates against the active scene and prints formatted output to the console buffer

### Requirement: Built-In Scene and Level Editor with Play-In-Editor
The engine SHALL include a toggleable `F1` editor featuring entity hierarchy, ECS component inspector, 3D translate/rotate/scale gizmos, voxel/prefab brushes, `F5` Play-in-Editor snapshot/restore, and JSON scene saving.

#### Scenario: Edit, Play-in-Editor, and restore scene state
- **WHEN** an entity is moved via gizmo in `F1` editor mode, `F5` starts Play-in-Editor, and `F5` stops Play-in-Editor
- **THEN** the scene restores cleanly to the pre-play edited snapshot and saves valid JSON to `scenes/*.json`
