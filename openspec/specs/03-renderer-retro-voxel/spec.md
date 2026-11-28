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

### Requirement: Enhanced Skyboxes, Per-Pocket Skies, and Retro Parallax Backgrounds
The engine SHALL render far-plane skyboxes supporting 3-color gradients, equirectangular panorama textures, 6-face cubemaps (`eng_asset_load_cubemap`), light-synced or retro banded sun/moon discs, procedural clouds and twinkling stars, retro pixel snapping, up to 4 multi-layer parallax horizon bands (procedural silhouettes or alpha textures scrolled by yaw, XZ movement, and time), and per-pocket sky overrides (`eng_renderer_set_pocket_sky`).

#### Scenario: Per-pocket skybox with retro parallax visible across a portal
- **WHEN** an exterior pocket uses a daylight mountain parallax sky and a linked interior pocket sets a per-pocket synthwave city sky override
- **THEN** looking through the portal reveals the interior pocket's skybox, parallax layers, and matching metallic IBL without affecting the exterior sky

### Requirement: Decoupled Low-Resolution Realism Lens and Sharp Upscaling
The engine SHALL support decoupled internal 3D rendering resolution (`render_scale`, `pixel_height`, `sharp_upscale`, and `eng_retro_lowres_realism_preset`) so full HDR PBR, shadows, water, fire, and volumetrics render into a low-resolution `RGBA16F` target (e.g. `640x360`) and upscale cleanly to native window or 4K capture resolutions while keeping HUD/UI crisp.

#### Scenario: Low-resolution 360p realism lens upscaled to output framebuffer
- **WHEN** a game activates `eng_retro_lowres_realism_preset()` or `pixel_height = 360` on a `1280x720` or `1920x1080` target
- **THEN** `eng_render` sizes internal HDR/G-buffer/scene-snapshot targets to `360p` without PS1 vertex wobble, applies dithered ACES tonemapping + sharp pixel upscaling, and renders UI overlays at full output resolution

### Requirement: Physical Inverse-Square Lighting, Soft PCF Shadows, Normal/Wetness Maps & SSAO
The engine SHALL evaluate physical inverse-square point/spot attenuation across Forward and Deferred pipelines, zero direct-light leak in shadow (`0.0`), slope-scaled bias with rotated Poisson PCF soft shadows, screen-space cotangent normal/roughness mapping (including procedural textures) with surface `wetness` darkening/gloss, and depth-buffer SSAO.

#### Scenario: Wet stone normal-mapped surface under soft directional shadow and SSAO
- **WHEN** a mesh with procedural normal/roughness maps and `wetness = 0.8` is partially occluded from a directional shadow-casting light
- **THEN** shadowed texels receive zero direct sun radiance with soft PCF penumbras, crevices darken via SSAO, and lit wet surfaces exhibit darkened diffuse albedo with sharp specular highlights

### Requirement: Ray-Integrated Mie Fog, Volumetric God-Rays, Gerstner Water & Blackbody Fire
The engine SHALL render closed-form ray-integrated exponential height fog with Henyey-Greenstein sun in-scattering, Bayer-jittered shadow-mapped volumetric light shafts (`volumetric_fog`), Gerstner wave water with Beer-Lambert RGB depth absorption, screen-space refraction, shoreline/crest foam, underwater camera post-processing, and Planck blackbody curl-turbulence soft-depth particles.

#### Scenario: Refractive Beer-Lambert water and soft blackbody fire in volumetric mist
- **WHEN** a pocket configures water (`eng_renderer_set_water`), volumetric fog, and a blackbody fire emitter
- **THEN** `eng_render` snapshots scene color/depth via `BlitFramebuffer`, renders depth-attenuated refractive water with shore foam, depth-fades blackbody flames/smoke without hard geometry seams, and marches shadowed volumetric god-rays

