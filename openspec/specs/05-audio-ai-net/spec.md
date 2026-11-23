# 3D Spatial Audio, AI & Pluggable Networking Specification

## Purpose
Defines SDL3 3D audio mixing/decoding/synthesis (`eng_audio`), NavMesh A* pathfinding and Behavior Trees (`eng_ai`), and cross-platform UDP/WebSocket/Loopback networking with state replication (`eng_net`).

## Requirements

### Requirement: SDL3 3D Spatial Audio Streaming, Decoding, and Retro Synth
The engine SHALL mix master/SFX/music/UI buses over `SDL_AudioStream` with 3D distance attenuation, stereo panning, and Doppler shift, supporting WAV, streaming Ogg Vorbis (`stb_vorbis`), and procedural retro ADSR waveform synthesis.

#### Scenario: Spatialized SFX panning and attenuation
- **WHEN** an audio source plays `10m` to the right of the active listener camera
- **THEN** `eng_audio` attenuates gain by distance and pans output toward the right stereo channel

### Requirement: NavMesh/Grid A* Pathfinding and Lua Behavior Trees
The engine SHALL compute 3D NavMesh and walkable voxel/grid paths in C using A* with funnel string-pulling and SHALL execute Behavior Trees (`selector`, `sequence`, `decorator`, `action` + entity blackboard) driven from Lua.

#### Scenario: Obstacle avoidance via NavMesh A*
- **WHEN** an AI agent requests a path around a wall blocking direct line-of-sight
- **THEN** `eng_ai_find_path` returns a valid string-pulled waypoint sequence reaching the goal without intersecting blocked cells

### Requirement: Pluggable UDP, WebSocket, and Loopback State Replication
The engine SHALL abstract networking over native non-blocking UDP (Desktop), WebSocket client (Web), and deterministic in-memory loopback (Web & headless tests), providing reliable/unreliable channels and ECS component snapshot/delta replication.

#### Scenario: Client-server entity replication over loopback
- **WHEN** a server world spawns and moves a `NetReplicated` entity connected to a client via loopback or UDP
- **THEN** `eng_net` replicates spawn and transform deltas so client state converges within the configured tick interval
