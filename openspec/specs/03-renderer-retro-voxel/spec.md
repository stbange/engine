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
The engine SHALL support both a Forward PBR/Retro pipeline (default) and a G-Buffer Deferred pipeline with dynamic directional/point/spot lights, shadow-map cascades/atlas, HDR FBO, Dual-Kawase bloom, tone mapping, and cubemap/procedural skyboxes.

#### Scenario: Switching Forward and Deferred modes
- **WHEN** a scene configures `"pipeline": "deferred"` or toggles pipeline mode at runtime
- **THEN** opaque meshes render through the MRT G-Buffer + shadow-lit deferred pass while sprites, particles, skybox, and UI composite cleanly in the forward pass

### Requirement: Retro 3D Rendering Controls
The engine SHALL provide per-game/per-camera retro 3D controls including clip-space vertex snapping, nearest-neighbor texel filtering, ordered 4×4 Bayer dithering with color quantization, distance/height fog, and CRT scanline post-processing.

#### Scenario: PS1-style retro preset activation
- **WHEN** a game enables vertex snapping, nearest filtering, and 16-bit Bayer dithering
- **THEN** `eng_render` applies quantized clip-space vertex positions and ordered dithered output in the post-processing pass

### Requirement: GPU Instancing, Frustum/Occlusion Culling, and Mesh LODs
The engine SHALL frustum-cull entity AABBs, select distance-based mesh LODs (`LOD0..LOD3`), batch identical mesh+material draws via `glDrawElementsInstanced`, and support hardware/BVH occlusion culling.

#### Scenario: Instanced crowd rendering with culling
- **WHEN** 1,000 identical asteroid or enemy meshes are spawned with 600 outside the camera frustum
- **THEN** `eng_render` culls the 600 off-screen instances and submits the remaining 400 in instanced draw batches per active LOD

### Requirement: First-Class 3D Objects, 8-Way Sprites, Greedy-Meshed Voxels, Terrain, Particles & SDF Text
The engine SHALL natively render glTF/OBJ/compound-CSG 3D meshes, depth-writing billboard and 8-directional sprites, greedy-meshed palette voxel chunks (`.vox` and `from_ascii` with 4-level vertex AO), splatted heightmap terrain, instanced particles, and UTF-8 `stb_truetype` SDF text.

#### Scenario: Greedy voxel remeshing on block edit
- **WHEN** Lua or C modifies a voxel inside a `16x16x16` chunk
- **THEN** `eng_voxel` greedy-merges coplanar same-palette faces with per-vertex AO and updates only the dirty chunk mesh
