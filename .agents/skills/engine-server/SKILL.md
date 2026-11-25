---
name: engine-server
description: >
  Create, test, and deploy authoritative cross-platform multiplayer servers for
  stbange/engine games so Browser (WebGL2), Windows, macOS, and Linux clients
  play together over WebSockets (ws:// / wss://) using --server, eng.mp, and Docker+Caddy.
license: MIT
---

# Engine Dedicated Server & Cross-Play Skill (`stbange/engine`)

Use this skill whenever adding online multiplayer, creating a dedicated server, or deploying a cross-platform (Browser + Windows + macOS + Linux) game server on `stbange/engine`.

## 1. Cross-Platform Transport Architecture
- **Same binary wire protocol everywhere**: Every packet over WebSocket is a binary frame `[uint8_t channel][payload...]`.
- **Desktop (Windows / macOS / Linux)**: Uses `SDL3_net` (`NET_Server` / `NET_StreamSocket`) with the engine's built-in RFC 6455 Binary WebSocket server & client, plus **verified TLS 1.2 (`wss://`)** via BearSSL (MIT) validating X.509 certificates and SNI hostnames against the OS root CA store (`ENG_TLS_CA_FILE` / `SSL_CERT_FILE` overrides for private CAs), and multi-client UDP for Desktop-only LAN.
- **Browser (Emscripten WebGL2)**: Uses `<emscripten/websocket.h>` speaking the exact same binary protocol (`ws://` for local dev, `wss://` for HTTPS sites such as GitHub Pages).
- **One server & one `wss://` invite URL for all platforms**: A single `./engine --server` behind Caddy (`wss://...`) accepts Browser, Windows, macOS, and Linux clients simultaneously with the exact same URL.

## 2. Server Script Architecture (Two Options)
When launched with `--server`, the engine automatically boots in headless fixed-tick mode, hosts a multi-client WebSocket listener on `--bind`/`--port`, and sets `eng.net.is_server() == true`.

1. **Unified single-script game (`scripts/main.lua`)** — best for small/medium games sharing procedural map generation & physics:
   ```lua
   function init()
       if eng.net.is_server() then
           game.state.srv = eng.mp.create_server(eng, {
               seed = 42,
               snapshot_hz = 20,
               on_join = function(cid, p) p.x, p.y, p.z = 0, 1.4, 4 end,
               on_input = function(cid, p, pkt, dt)
                   -- Authoritative movement + physics wall sliding
                   local nx, nz = eng.physics.slide_move(p.pk, p.x, p.y, p.z, (pkt.dx or 0), (pkt.dz or 0), 0.38)
                   p.x, p.z = nx, nz
                   p.yaw = pkt.yaw or p.yaw
               end
           })
       else
           game.state.cli = eng.mp.create_client(eng, {
               on_welcome = function(id, seed) eng.log.info("Joined as #" .. id .. " seed=" .. seed) end
           })
           if game.state.cli.url then game.state.cli:connect() end
       end
   end

   function update(dt)
       if game.state.srv then
           game.state.srv:step(dt)
           return
       end
       -- Client simulation + remote avatar interpolation via eng.mp.lerp(...)
   end
   ```
2. **Dedicated server entrypoint (`scripts/server.lua`)** — optional separation: if `games/<slug>/scripts/server.lua` exists, `--server` automatically loads `scripts/server.lua` instead of `scripts/main.lua` while normal clients continue loading `scripts/main.lua`.

## 3. Low-Level & High-Level Lua Networking APIs
- **High-level (`eng.mp.*`, `lua/eng/mp.lua`)**:
  - `eng.mp.pack(tbl)` / `eng.mp.unpack(str)` — safe, deterministic flat-table serializer (numbers, booleans, escaped strings; never uses `loadstring`).
  - `eng.mp.create_server(eng, opts)` — tracks `players[cid]`, sends `welcome` (`id`, `seed`), dispatches `on_join` / `on_input` / `on_leave` / `on_snapshot`, and broadcasts compact player state at `snapshot_hz`.
  - `eng.mp.create_client(eng, opts)` — reads `eng.net.launch_url()` (populated by `--connect` on Desktop or `?server=`/`?join=` in the browser URL), handles `welcome`/`leave`/`p` packets, and sends local inputs at `input_hz`.
  - `eng.mp.lerp(cur, tgt, dt, rate)` — smooth exponential interpolation for remote avatars.
- **Low-level (`eng.net.*`)**:
  - `eng.net.is_server()`, `eng.net.launch_url()`, `eng.net.is_connected(role?)`
  - `eng.net.host(transport?, port?, bind_ip?)`, `eng.net.connect("ws://host:7777" | "wss://host")`
  - `eng.net.poll_event(role?)` -> `{ type = "connect"|"disconnect"|"message", client_id = N, reliable = bool, data = string }`
  - `eng.net.send_to(client_id, data, reliable?)`, `eng.net.broadcast(data, reliable?)`, `eng.net.clients()`, `eng.net.kick(client_id)`
  - `eng.net.broadcast_snapshot(client_id?)` / `eng.net.apply_snapshot(data)` for built-in pocket-aware entity transform replication.

## 4. Authoritative Server Rules (Never Trust the Client)
- **Deterministic worlds**: Send only the integer `seed` in the `welcome` packet so server and every client generate identical dungeons/terrain/props via `eng.procgen.*` and `eng.math.seed(seed)`.
- **Validate inputs on the server**: Clamp movement speeds, positions, and action cooldowns server-side; run `eng.physics.slide_move` and `eng.portal.check_crossing` on the server so clients cannot walk through walls or teleport.
- **Safe deserialization**: Only use `eng.mp.unpack` (or fixed string parsing); never execute client strings. Kick misbehaving peers with `eng.net.kick(cid)`.
- **Pocket sync**: Replicate each player's `pk` (`pocket_id`) so remote avatars appear in the right "Bigger on the Inside" pocket space.

## 5. Local Cross-Play Testing Workflow
1. **Start dedicated server** (30 Hz fixed tick, WebSocket on port `7777`):
   ```bash
   ./build/engine --server --game games/<slug> --port 7777 --tick-rate 30
   ```
2. **Connect Native Desktop client(s)** (Windows / macOS / Linux):
   ```bash
   ./build/engine --game games/<slug> --connect ws://127.0.0.1:7777
   ```
3. **Connect Browser client(s)** (same match as Desktop clients!):
   Open `http://127.0.0.1:8080/play.html?game=<slug>&server=ws://127.0.0.1:7777`.
4. **Automated CI playtest (zero sockets required)**:
   In `tests/playtest.lua`, call `eng.net.start_loopback()` to test both `eng.mp.create_server` and `eng.mp.create_client` deterministically inside `--headless --test tests/playtest.lua`.

## 6. Production Deployment (`wss://` for HTTPS Browsers + Desktop)
Browsers served over HTTPS (such as GitHub Pages) require secure WebSockets (`wss://`). Use the ready-made templates in `server/`:
- `server/Dockerfile` — multi-stage Ubuntu image building the headless `engine` server binary.
- `server/Caddyfile` — automatic Let's Encrypt TLS reverse proxy (`wss://<domain>:443 -> ws://game-server:7777`).
- `server/docker-compose.yml` — runs both `game-server` and `caddy` together.

Deploy on any VPS / cloud VM:
```bash
cd server
GAME_DIR=games/<slug> SERVER_DOMAIN=play.yourdomain.com docker compose up -d --build
```
Players then join from **any platform** using the same URL:
- **Browser**: `https://<user>.github.io/<repo>/play.html?game=<slug>&server=wss://play.yourdomain.com`
- **Desktop**: `./engine --game games/<slug> --connect wss://play.yourdomain.com` (or `ws://<host>:7777` on LAN).
