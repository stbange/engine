# 3D Spatial Audio, AI & Pluggable Networking Specification

## Purpose
Defines SDL3 3D audio mixing/decoding/synthesis (`eng_audio`), NavMesh A* pathfinding and Behavior Trees (`eng_ai`), and cross-platform UDP/WebSocket/Loopback networking with state replication (`eng_net`).

## Requirements

### Requirement: SDL3 3D Spatial Audio Streaming, Decoding, and Retro Synth
The engine SHALL mix master/SFX/music/UI buses over `SDL_AudioStream` with 3D distance attenuation, stereo panning, and Doppler shift, supporting WAV, streaming Ogg Vorbis (`stb_vorbis`), and procedural retro ADSR waveform synthesis.

#### Scenario: Spatialized SFX panning and attenuation
- **WHEN** an audio source plays `10m` to the right of the active listener camera (or nearest of up to 4 split-screen listeners across pockets)
- **THEN** `eng_audio` attenuates gain by distance and pans output toward the right stereo channel

### Requirement: NavMesh/Grid A* Pathfinding and Lua Behavior Trees
The engine SHALL compute 3D NavMesh and walkable voxel/grid paths in C using A* with funnel string-pulling and SHALL execute Behavior Trees (`selector`, `sequence`, `decorator`, `action` + entity blackboard) driven from Lua.

#### Scenario: Obstacle avoidance via NavMesh A*
- **WHEN** an AI agent requests a path around a wall blocking direct line-of-sight
- **THEN** `eng_ai_find_path` returns a valid string-pulled waypoint sequence reaching the goal without intersecting blocked cells

### Requirement: Cross-Platform Multi-Client WebSocket, UDP, and Loopback Networking with Dedicated Server Mode
The engine SHALL support multi-client networking (up to 16 peers) over RFC 6455 Binary WebSockets (`SDL3_net` on Windows/macOS/Linux and `<emscripten/websocket.h>` on Web so all platforms play together), multi-client UDP (`SDL3_net` on Desktop), and multi-client in-memory loopback, plus pocket-aware scene snapshots and a headless `--server` dedicated server CLI mode.

#### Scenario: Cross-platform client-server session over WebSocket and loopback
- **WHEN** an authoritative `--server` hosts a room and Desktop and Browser clients connect via WebSocket (or virtual clients connect via loopback)
- **THEN** `eng_net` emits `connect`/`message`/`disconnect` events with per-client IDs, broadcasts binary packets and pocket-aware scene snapshots, and converges entity state across all connected clients
