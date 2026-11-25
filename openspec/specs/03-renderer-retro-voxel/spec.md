# Renderer, Retro 3D Suite, Sprites, Voxels, Terrain & Text Specification

## Purpose
Defines the unified OpenGL 3.3 Core / GLES 3.0 (WebGL2) rendering architecture (`eng_shader`, `eng_asset`, `eng_render`, `eng_sprite`, `eng_voxel`, `eng_terrain`, `eng_particles`, `eng_text`).

## Requirements

### Requirement: Unified GL 3.3 Core and GLES 3.0 Shader Pipeline
The engine SHALL compile single-source shaders across Desktop OpenGL 3.3+ (including macOS GL 4.1) and WebGL2 (`#version 300 es`) via automatic preamble injection and `#include` expansion, supporting hot reload on file modification.

#### Scenario: Cross-platform shader compilation and hot reload
- **WHEN** a shader file in `shaders/` is loaded on Desktop or Web and later edited on disk
- **THEN** `eng_shader` injects the platform preamble, links the program, and swaps the live GPU program on modification without crashing if a syntax error occurs

### Requirement: Selectable Forward and Deferred PBR/Retro Pipelines
The engine SHALL support both Forward PBR/Retro (default) and G-Buffer Deferred pipelines with runtime-updatable directional/point/spot lights, shadows, analytic sky-gradient IBL for metals, HDR emissive glow feeding Dual-Kawase bloom, back-to-front Fresnel translucency composited in forward pass across both pipelines, tone mapping, and procedural skyboxes.

#### Scenario: Switching Forward and Deferred modes
- **WHEN** a scene configures `"pipeline": "deferred"` or toggles pipeline mode at runtime
- **THEN** opaque meshes render through the MRT G-Buffer + shadow-lit deferred pass while emissive/translucent meshes, sprites, particles, skybox, and UI composite cleanly in the forward pass with shared depth

#### Scenario: Metallic sky reflections and translucent emissive crystals
- **WHEN** a scene submits metallic materials (gold/chrome) alongside an emissive translucent mesh (`alpha < 0.99`)
- **THEN** `eng_render` reflects the pocket sky gradient along `reflect(-V, N)` weighted by roughness/Fresnel and renders the translucent mesh back-to-front with Fresnel edge highlights and bloom-feeding emission

### Requirement: Retro 3D Rendering Controls
The engine SHALL provide per-game/per-camera retro 3D controls including clip-space vertex snapping, nearest-neighbor texel filtering, ordered 4×4 Bayer dithering with color quantization, configurable distance and height fog (`fog_density`, `fog_color`, `fog_height`), bloom intensity, and CRT scanline post-processing.

#### Scenario: PS1-style retro preset activation
- **WHEN** a game enables vertex snapping, nearest filtering, and 16-bit Bayer dithering
- **THEN** `eng_render` applies quantized clip-space vertex positions and ordered dithered output in the post-processing pass

### Requirement: GPU Instancing, Frustum/Occlusion Culling, and Mesh LODs
The engine SHALL frustum-cull entity AABBs, select distance-based mesh LODs (`LOD0..LOD3`), batch identical mesh+material draws via `glDrawElementsInstanced`, and support hardware/BVH occlusion culling.

#### Scenario: Instanced crowd rendering with culling
- **WHEN** 1,000 identical asteroid or enemy meshes are spawned with 600 outside the camera frustum
- **THEN** `eng_render` culls the 600 off-screen instances and submits the remaining 400 in instanced draw batches per active LOD

### Requirement: First-Class 3D Objects, 8-Way Sprites, Greedy-Meshed Voxels, Terrain, Particles & SDF Text
The engine SHALL natively render glTF/OBJ/compound-CSG 3D meshes, depth-writing billboard and 8-directional sprites, greedy-meshed palette voxel chunks (`.vox` and `from_ascii` with 4-level vertex AO), splatted heightmap terrain, instanced alpha/additive particles (supporting fire, smoke, sparks, runtime emitter movement, and a built-in soft radial puff texture), and UTF-8 `stb_truetype` SDF text.

#### Scenario: Greedy voxel remeshing on block edit
- **WHEN** Lua or C modifies a voxel inside a `16x16x16` chunk
- **THEN** `eng_voxel` greedy-merges coplanar same-palette faces with per-vertex AO and updates only the dirty chunk mesh

### Requirement: Multi-Viewport Split-Screen Rendering
The engine SHALL render 1 to 4 independent camera viewports per frame (`eng_renderer_render_views`, `eng.camera.set_split`) across both Forward and Deferred pipelines with per-viewport aspect/FOV, isolated pocket portals and shadows, pixel-exact Deferred G-buffer sampling (`texelFetch`), divider bars, and viewport-relative HUD anchoring.

#### Scenario: Two-to-four player split-screen across different pockets
- **WHEN** a game enables 2-way or 4-way split-screen and players view different `pocket_id` spaces
- **THEN** each viewport renders its own camera, pocket lighting, portals, and viewport-anchored HUD cleanly clipped to its screen rectangle without bleeding across viewports
