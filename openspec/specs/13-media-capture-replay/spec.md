# Media Capture, Deterministic Replay & Social Export Specification

## Purpose
Defines screenshot capture, synchronized video + 48 kHz stereo 3D audio recording (`eng_capture`), deterministic user-action recording/playback (`.engrep`, `eng_replay`), social media aspect presets, and browser capture controls.

## Requirements

### Requirement: Deterministic User Action Capture and Replay
The engine SHALL record per-frame simulation deltas, logical actions, sparse axes, mouse deltas, 4-player split-screen/gamepad states, RNG seed, and highlight bookmarks into binary `.engrep` files (`eng_replay`) and replay them deterministically into `eng_input_t` across interactive and headless sessions.

#### Scenario: Bit-identical gameplay replay across repeated runs
- **WHEN** a gameplay session with movement, mouse look, SFX, and bookmarks is recorded to `.engrep` and replayed twice from the same seed
- **THEN** final entity positions, RNG state, and bookmark timestamps match identically on both playback runs

### Requirement: Offscreen High-Resolution Screenshots and Clean Feed
The engine SHALL capture PNG screenshots (`F12`, `eng.capture.screenshot`, `--screenshot-at`) at arbitrary target resolutions via an optional offscreen RGBA8 capture FBO (`eng_renderer_set_capture_target`), supporting both HUD-inclusive and clean-feed (`F11`, `--clean-feed`) captures.

#### Scenario: Portrait 9:16 and landscape 16:9 offscreen screenshots
- **WHEN** a session requests offscreen screenshots at `180x320` (9:16) and `320x180` (16:9)
- **THEN** `eng_capture` writes valid non-empty PNG files matching each requested resolution without clamping to monitor size

### Requirement: Synchronized Video and 48 kHz Stereo Audio Capture
The engine SHALL tap mixed 48 kHz stereo PCM audio (`eng_audio_set_capture_cb`) and framebuffer pixels into either MIT-pure lossless PNG+WAV sequences or an external `ffmpeg` CLI subprocess (zero GPL/LGPL linking, zero shell injection) producing upload-ready MP4, WebM, or palette GIF files across social media presets (`youtube`, `youtube4k`, `reel`, `shorts`, `tiktok`, `square`, `gif`), optional time clips (`--clip`), slow-motion (`--speed`), and director camera overrides (`--director`).

#### Scenario: Offline replay export with synced audio and fallback
- **WHEN** a `.engrep` replay is exported with `--record-video` and a social preset
- **THEN** fixed-timestep video frames and 48 kHz stereo WAV audio stay locked in sync, muxing cleanly via `ffmpeg` when installed or falling back to a lossless PNG+WAV directory when `ffmpeg` is absent

### Requirement: Browser WebGL2 Screenshot and Video Recording
The Emscripten Web player (`web/shell_play.html`) SHALL expose compact `Shot` (post-frame PNG download) and `Rec` (canvas `captureStream` + WebAudio `MediaRecorder` WebM download) controls without blocking gameplay.

#### Scenario: Browser capture controls present and non-blocking
- **WHEN** a game loads in `play.html`
- **THEN** the toolbar provides `Shot` and `Rec` triggers that capture frames after WebGL2 rendering without freezing the main loop
