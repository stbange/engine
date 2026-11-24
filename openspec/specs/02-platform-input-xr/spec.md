# Platform, Windowing, Rebindable Input, Mobile Touch & WebXR Specification

## Purpose
Defines SDL3 window/context management (`eng_platform`), OpenGL function loading (`eng_gl`), unified action-mapped input (`eng_input`), automatic mobile web touch controls, and stereo WebXR (`eng_xr`).

## Requirements

### Requirement: Cross-Platform SDL3 Windowing and Headless Dummy Mode
The engine SHALL manage OpenGL 3.3 Core (Desktop) and WebGL2 / GLES 3.0 (Web) contexts via SDL3, supporting resizing, fullscreen/borderless toggles, multi-monitor placement, VSync, HiDPI scaling, and GPU-less `--headless` execution.

#### Scenario: Headless initialization in CI
- **WHEN** `engine` starts with `--headless` on a machine without a physical display or audio card
- **THEN** `eng_platform` initializes `SDL_VIDEODRIVER=dummy` and `SDL_AUDIODRIVER=dummy` with a software/offscreen GL target and runs deterministically

### Requirement: Rebindable Logical Action and Axis Mapping
The engine SHALL map keyboard, mouse, SDL3 gamepad, touch, and WebXR controller inputs onto named actions and axes persisted in JSON, including configurable input buffering, coyote-time helpers, and relative mouse/pointer lock (`eng_platform_set_mouse_lock`, `eng_platform_is_mouse_lock`, `eng.input.set_mouse_lock`, `eng.input.mouse_delta`, `eng.camera.fps_steer`).

#### Scenario: Runtime action rebinding
- **WHEN** a player or Lua script rebinds action `"jump"` from `Space` to `GamepadSouth` and saves bindings
- **THEN** `eng_input_pressed("jump")` triggers on `GamepadSouth` and persists cleanly to JSON

#### Scenario: Pointer-locked mouse look and camera-relative WASD strafing
- **WHEN** a first-person or free-roam game requests mouse lock (`eng.input.set_mouse_lock(true)` or `eng.camera.fps_steer`) and the player clicks the canvas on Web or Desktop
- **THEN** pointer lock engages (`ESC` releases), mouse movement rotates camera yaw/pitch freely, and `W`/`S`/`A`/`D` steer forward/backward and strafe left/right relative to camera yaw without orbiting a fixed point

### Requirement: Automatic Mobile Web Touch Controls
The engine SHALL detect touch-primary mobile browsers on Web builds and automatically activate a skinnable virtual thumbstick/button overlay matching the game's `touch_preset`.

#### Scenario: Mobile browser touch activation
- **WHEN** a game loads in a mobile touch browser (`maxTouchPoints > 0` / touch event detected)
- **THEN** `eng_input` enables the configured virtual touch overlay (`dual_stick`, `dpad_buttons`, `tap_drag`, or `steering`) and feeds virtual inputs directly into standard `eng_input` actions

### Requirement: Full Stereo WebXR Immersive-VR Support
The engine SHALL support WebXR `immersive-vr` sessions (`XRWebGLLayer`), rendering left and right eye viewports with per-eye view/projection matrices and mapping headset + dual 6DoF hand-controller poses into `eng_xr` and `eng_input`.

#### Scenario: Stereo WebXR frame submission
- **WHEN** a user enters VR via `"Enter VR"` in any game (`diorama`, `cockpit`, `first_person`, or `6dof` mode)
- **THEN** `eng_xr` binds `XRWebGLLayer.framebuffer` and renders both stereo eye views without overwriting FBO `0`
