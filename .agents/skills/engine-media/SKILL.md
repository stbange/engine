---
name: engine-media
description: >
  Record deterministic gameplay replays (.engrep), capture high-resolution screenshots,
  and export synchronized 60 fps video + 48 kHz 3D spatial audio for YouTube (16:9 / 4K),
  Reels/Shorts/TikTok (9:16), Instagram Square (1:1), and palette GIFs — including
  clean-feed, highlight clips, slow-motion, director cameras, and automated playtest trailers.
license: MIT
---

# Engine Media Capture, Deterministic Replay & Social Export Skill (`stbange/engine`)

Use this skill whenever capturing screenshots, trailers, YouTube longform videos, vertical Reels/Shorts/TikToks, social GIFs, or deterministic gameplay replays (`.engrep`) from any `stbange/engine` game.

## 1. The "Play Once -> Export Everywhere" Workflow

Because `stbange/engine` runs deterministic fixed-timestep simulation + seeded RNG (`eng.math` & `math.random`) + 48 kHz stereo audio mixing, record your gameplay **once** as a tiny `.engrep` file (only ~1–2 KB/s) and re-render it offline into every social format at locked 60 fps with zero dropped frames and sample-accurate sound:

```bash
# 1. Play once and record actions + highlight bookmarks (press F10 during hype moments!)
./engine --game games/001_catacomb_blitz --record-replay captures/run.engrep

# 2. Export 16:9 1080p60 YouTube video + synced 48 kHz stereo audio (clean feed)
./engine --game games/001_catacomb_blitz --replay captures/run.engrep \
  --record-video captures/yt_1080p.mp4 --preset youtube --clean-feed

# 3. Export 9:16 1080x1920 60fps Reel/Short/TikTok around a bookmarked moment
./engine --game games/001_catacomb_blitz --replay captures/run.engrep \
  --record-video captures/reel.mp4 --preset reel --clip bookmark:highlight:4:3

# 4. Export 4K YouTube master, 1:1 Square clip, and palette-dithered GIF
./engine --game games/001_catacomb_blitz --replay captures/run.engrep \
  --record-video captures/yt_4k.mp4 --preset youtube4k --clean-feed
./engine --game games/001_catacomb_blitz --replay captures/run.engrep \
  --record-video captures/loop.gif --preset gif --clip 5:10

# 5. Batch-capture clean PNG thumbnails at every bookmark (or custom timestamps)
./engine --game games/001_catacomb_blitz --replay captures/run.engrep \
  --preset youtube4k --screenshot-at bookmarks --out-dir captures/thumbs --clean-feed
```

> **Portrait 9:16 Framing**: The renderer automatically applies Hor+ portrait FOV compensation when `aspect < 1.0`, and offscreen capture FBOs render at full target resolution (`1080x1920` or `3840x2160`) regardless of monitor size.

## 2. Social Media Export Presets (`--preset`)

| Preset | Aliases | Resolution | Default FPS | Best For |
|---|---|---|---|---|
| `youtube` | `landscape` | `1920x1080` | `60` | YouTube, Steam, itch.io, X/Twitter |
| `youtube4k` | `4k` | `3840x2160` | `60` | 4K YouTube masters & crisp press-kit PNGs |
| `reel` | `shorts`, `tiktok`, `vertical` | `1080x1920` | `60` | Instagram Reels, YouTube Shorts, TikTok |
| `square` | `instagram` | `1080x1080` | `60` | Instagram feed posts & Mastodon/Bluesky |
| `gif` | — | `640x360` | `24` | Discord embeds, README demos, store pages |

Output container is selected automatically from `--record-video` extension: `.mp4` (H.264 `yuv420p` + AAC `+faststart`), `.webm` (VP9 + Opus), or `.gif` (palettegen/paletteuse Bayer dither).

> **MIT License & Zero-Dependency Fallback**: `ffmpeg` is never linked into the engine binary — it is invoked purely as an optional external CLI subprocess (shell-free `execvp` / `CreateProcessA`). If `ffmpeg` is not installed on `PATH`, the engine automatically writes lossless PNG frames + a 48 kHz 16-bit stereo `audio.wav` into `<out_path>_frames/`.

## 3. Live In-Game Hotkeys & Browser Controls

- **Desktop**:
  - `F12` — Instant PNG screenshot (`captures/<game>_shot_NNN.png`)
  - `F9` — Start/stop live video + audio capture (`captures/<game>_vid_NNN.mp4`)
  - `Shift+F9` — Start/stop `.engrep` replay capture (`captures/<game>_rep_NNN.engrep`)
  - `F10` — Drop a `"highlight"` bookmark at the exact current replay frame
  - `F11` — Toggle Clean Feed (hides HUD/help/editor in saved shots & videos; the subtle `[REC]` corner badge renders *after* capture readback so it never pollutes recordings)
- **Browser WebGL2 (`play.html`)**:
  - Topbar **`Shot`** button (or `F12`) downloads a post-frame PNG without blank frames.
  - Topbar **`Rec` / `Stop`** button records WebGL2 canvas + tapped WebAudio into a downloadable `.webm` video.

## 4. Slow-Motion (`--speed`) & Director Camera Scripts (`--director`)

- **Cinematic Slow-Mo / Timelapse**: Pass `--speed 0.5` (2× slow-motion) or `--speed 2.0` (2× timelapse). Video frame timing and `ffmpeg` `atempo` audio pitch-preserving time-stretch stay locked in sync across `[0.25 .. 4.0]`.
- **Director Camera Override (`--director orbit.lua`)**: Re-shoot any recorded `.engrep` replay from a dramatic trailer angle without touching the game's simulation or physics:
  ```lua
  -- captures/orbit.lua: runs every frame after update(dt) during replay export
  function director_camera(t, frame, cam)
      local a = t * 0.7
      eng.camera.look_at(
          cam.x + math.sin(a) * 6.0, cam.y + 3.2, cam.z + math.cos(a) * 6.0,
          cam.x, cam.y + 0.5, cam.z,
          cam.pocket
      )
  end
  ```

## 5. Lua Scripting API (`eng.capture.*`)

Games and playtest bots can drop automatic bookmarks on boss kills/combos or trigger sandboxed captures (strictly jailed to `captures/`):

```lua
eng.capture.bookmark("boss_kill")              -- Mark hype moment in active .engrep
eng.capture.screenshot("hero_pose.png")        -- Save captures/hero_pose.png
eng.capture.set_clean_feed(true)               -- Hide HUD for clean trailer shot
eng.capture.start_video("intro.mp4", { preset = "youtube", fps = 60, speed = 1.0 })
eng.capture.stop_video()
```

## 6. Automated Zero-Human Press Kit Pipeline (Bot Playtest -> Trailer)

Combine `--test tests/playtest.lua --record-replay` with offline export to generate fresh thumbnails and Reels automatically in CI (under `xvfb-run -a` on Linux servers for full GPU/Mesa GL 3.3 rendering):

```bash
# Step 1: Run deterministic bot playtest and save its inputs as a replay
./engine --game games/102_portal_arena_mp --headless \
  --test tests/playtest.lua --max-frames 360 --record-replay captures/bot.engrep

# Step 2: Render full-GL 16:9 trailer + 9:16 Reel + screenshots from the bot replay
xvfb-run -a ./engine --game games/102_portal_arena_mp \
  --replay captures/bot.engrep --record-video captures/trailer_16x9.mp4 \
  --preset youtube --screenshot-at 1.0,3.0,5.0 --out-dir captures/presskit --clean-feed
```
