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
The engine SHALL support multi-client networking (up to 16 peers) over RFC 6455 Binary WebSockets (`SDL3_net` on Desktop and `<emscripten/websocket.h>` on Web so Browser and Desktop clients join the same room), multi-client UDP (`SDL3_net` on Desktop), and multi-client in-memory loopback, plus pocket-aware scene snapshots and a headless `--server` dedicated server CLI mode.

#### Scenario: Cross-platform client-server session over WebSocket and loopback
- **WHEN** an authoritative `--server` hosts a room and Desktop and Browser clients connect via WebSocket (or virtual clients connect via loopback)
- **THEN** `eng_net` emits `connect`/`message`/`disconnect` events with per-client IDs, broadcasts binary packets and pocket-aware scene snapshots, and converges entity state across all connected clients

### Requirement: Verified Native TLS (wss://) WebSocket Client
Native Desktop clients SHALL support `wss://` WebSocket URLs over TLS 1.2 (via MIT-licensed BearSSL) with SNI and strict X.509 certificate verification against the OS root CA trust store or explicit PEM CA overrides (`eng_net_set_ca_pem`, `ENG_TLS_CA_FILE`, `SSL_CERT_FILE`), failing closed when no trusted CAs are available.

#### Scenario: Verified native TLS (wss://) client connection and untrusted certificate rejection
- **WHEN** a native Desktop client connects to a `wss://` WebSocket endpoint
- **THEN** `eng_net` completes the verified TLS 1.2 handshake and exchanges encrypted binary frames when trusted, and rejects untrusted or mismatched certificates with a disconnect event
