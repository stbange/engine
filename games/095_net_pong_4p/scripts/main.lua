-- 095_net_pong_4p: 4-Wall Square Arena 4-Player Replicated Paddle Battle
local S = game.state


local LIMIT = 8.5
local PADDLE_HALF = 1.65

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_sky(0.03, 0.05, 0.12, 0.08, 0.16, 0.28)
    eng.render.add_light({ type = "dir", dir = {-0.3, -1.0, -0.4}, color = {2.0, 2.0, 2.1}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 8.0, 0.0}, color = {1.6, 2.2, 2.8}, range = 28.0 })

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.ball_mesh = eng.asset.sphere(0.42, 12, 16)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    local seed = math.floor(eng.math.range(100, 90000))
    local floor_tex = eng.procgen.texture("sci_fi_panel", seed, 64)

    -- Square arena floor + 4 corner bumpers
    local floor_e = eng.scene.spawn("pong_arena_floor")
    eng.scene.set_pos(floor_e, 0.0, -0.25, 0.0)
    eng.scene.set_scale(floor_e, 19.0, 0.5, 19.0)
    eng.scene.set_mesh(floor_e, S.box_mesh, { tex = floor_tex, color = {0.16, 0.22, 0.34, 1.0}, metallic = 0.5, roughness = 0.3 })

    for sx = -1, 1, 2 do
        for sz = -1, 1, 2 do
            local c = eng.scene.spawn("corner_bumper_" .. tostring(sx) .. "_" .. tostring(sz))
            eng.scene.set_pos(c, sx * 8.8, 0.55, sz * 8.8)
            eng.scene.set_scale(c, 1.6, 1.1, 1.6)
            eng.scene.set_mesh(c, S.box_mesh, { color = {0.65, 0.72, 0.85, 1.0}, roughness = 0.35 })
        end
    end

    -- 4 Peer Paddles: 1=South (Local Player), 2=North (Bot), 3=West (Bot), 4=East (Bot)
    local peer_defs = {
        { name = "peer1_south", axis = "x", fixed =  8.2, col = {0.20, 0.95, 1.00, 1.0}, spd = 14.5 },
        { name = "peer2_north", axis = "x", fixed = -8.2, col = {1.00, 0.28, 0.36, 1.0}, spd = 6.2  },
        { name = "peer3_west",  axis = "z", fixed = -8.2, col = {1.00, 0.78, 0.20, 1.0}, spd = 6.2  },
        { name = "peer4_east",  axis = "z", fixed =  8.2, col = {0.78, 0.35, 1.00, 1.0}, spd = 6.2  }
    }
    S.peers = {}
    for i = 1, 4 do
        local d = peer_defs[i]
        local pe = eng.scene.spawn(d.name)
        if d.axis == "x" then
            eng.scene.set_pos(pe, 0.0, 0.45, d.fixed)
            eng.scene.set_scale(pe, PADDLE_HALF * 2.0, 0.7, 0.55)
        else
            eng.scene.set_pos(pe, d.fixed, 0.45, 0.0)
            eng.scene.set_scale(pe, 0.55, 0.7, PADDLE_HALF * 2.0)
        end
        eng.scene.set_mesh(pe, S.box_mesh, { color = d.col, roughness = 0.2, cast_shadow = true })
        S.peers[i] = { ent = pe, axis = d.axis, fixed = d.fixed, pos = 0.0, hp = 2, spd = d.spd, pkt = 0 }
    end

    -- 3 Multi-Ball Chaos Spheres
    local bdirs = { {0.42, -0.91}, {-0.88, -0.47}, {0.86, 0.51} }
    S.balls = {}
    for i = 1, 3 do
        local be = eng.scene.spawn("pong_ball_" .. tostring(i))
        local bx, bz = (i - 2) * 1.4, 0.0
        eng.scene.set_pos(be, bx, 0.45, bz)
        eng.scene.set_mesh(be, S.ball_mesh, { color = {1.0, 0.95, 0.45, 1.0}, roughness = 0.1, cast_shadow = true })
        S.balls[i] = { ent = be, x = bx, z = bz, vx = bdirs[i][1] * 13.5, vz = bdirs[i][2] * 13.5 }
    end

    S.sfx_bounce = eng.audio.synth("square", 480, 0.07, 620)
    S.sfx_goal = eng.audio.synth("saw", 260, 0.18, 540)

    S.net_tick = 0
    S.replicated_packets = 0
    S.saves = 0
    S.goals_scored = 0
    S.bots_eliminated = 0
    S.won = false

    eng.camera.look_at(0.0, 16.5, 13.5, 0.0, 0.0, 0.0, 0)
    eng.mod.emit("post_init")
end

-- Quantize peer input (-1, 0, +1, smash) into a compact deterministic lockstep byte
local function pack_peer_cmd(move_dir, smash)
    local q = (move_dir < -0.1) and 1 or ((move_dir > 0.1) and 2 or 0)
    return bit.bor(q, smash and 4 or 0)
end

local function unpack_move(pkt)
    local q = bit.band(pkt, 3)
    if q == 1 then return -1.0 elseif q == 2 then return 1.0 else return 0.0 end
end

function update(dt)
    if S.won then return end
    S.net_tick = S.net_tick + 1

    -- 1. Build & replicate deterministic input packets for Local Peer 1 + Bot Peers 2..4
    local mx, _ = eng.input.axis2d("left", "right", "down", "up")
    local smash = eng.input.down("fire") or eng.input.pressed("fire")
    S.peers[1].pkt = pack_peer_cmd(mx, smash)

    for p = 2, 4 do
        local peer = S.peers[p]
        -- Bot tracks closest approaching ball on its wall axis
        local best_b, best_d = S.balls[1], 999.0
        for b = 1, #S.balls do
            local ball = S.balls[b]
            local d = (peer.axis == "x") and math.abs(ball.z - peer.fixed) or math.abs(ball.x - peer.fixed)
            if d < best_d then best_d = d; best_b = ball end
        end
        local target = (peer.axis == "x") and best_b.x or best_b.z
        local dir = (target > peer.pos + 0.35) and 1.0 or ((target < peer.pos - 0.35) and -1.0 or 0.0)
        peer.pkt = pack_peer_cmd(dir, false)
    end
    S.replicated_packets = S.replicated_packets + 4

    -- 2. Apply replicated peer inputs
    for p = 1, 4 do
        local peer = S.peers[p]
        if peer.hp > 0 then
            local mv = unpack_move(peer.pkt)
            peer.pos = eng.math.clamp(peer.pos + mv * peer.spd * dt, -6.2, 6.2)
            if peer.axis == "x" then
                eng.scene.set_pos(peer.ent, peer.pos, 0.45, peer.fixed)
            else
                eng.scene.set_pos(peer.ent, peer.fixed, 0.45, peer.pos)
            end
        end
    end

    -- 3. Step multi-ball arena collisions & goal scoring
    local smash_boost = (bit.band(S.peers[1].pkt, 4) ~= 0) and 1.12 or 1.02
    for i = 1, #S.balls do
        local b = S.balls[i]
        b.x = b.x + b.vx * dt
        b.z = b.z + b.vz * dt

        -- Corner bumper reflections
        if math.abs(b.x) > 7.4 and math.abs(b.z) > 7.4 then
            b.vx = -b.vx
            b.vz = -b.vz
            b.x = eng.math.clamp(b.x, -7.3, 7.3)
            b.z = eng.math.clamp(b.z, -7.3, 7.3)
        end

        -- South wall (Peer 1 - Local Player)
        if b.z > 7.75 and b.vz > 0.0 then
            if S.peers[1].hp <= 0 or math.abs(b.x - S.peers[1].pos) <= (PADDLE_HALF + 0.55) then
                b.z = 7.75
                b.vz = -math.abs(b.vz) * smash_boost
                b.vx = b.vx + (b.x - S.peers[1].pos) * 3.2
                S.saves = S.saves + 1
                eng.audio.play(S.sfx_bounce, b.x, 0.5, b.z, 0)
            elseif b.z > LIMIT then
                S.peers[1].hp = math.max(1, S.peers[1].hp - 1)
                b.x, b.z, b.vz = 0.0, 0.0, -13.5
            end
        end

        -- North wall (Peer 2)
        if b.z < -7.75 and b.vz < 0.0 then
            if S.peers[2].hp <= 0 or math.abs(b.x - S.peers[2].pos) <= PADDLE_HALF then
                b.z = -7.75
                b.vz = math.abs(b.vz)
                eng.audio.play(S.sfx_bounce, b.x, 0.5, b.z, 0)
            elseif b.z < -LIMIT then
                score_bot_goal(2, b, 0.0, 14.0)
            end
        end

        -- West wall (Peer 3)
        if b.x < -7.75 and b.vx < 0.0 then
            if S.peers[3].hp <= 0 or math.abs(b.z - S.peers[3].pos) <= PADDLE_HALF then
                b.x = -7.75
                b.vx = math.abs(b.vx)
                eng.audio.play(S.sfx_bounce, b.x, 0.5, b.z, 0)
            elseif b.x < -LIMIT then
                score_bot_goal(3, b, 14.0, -4.5)
            end
        end

        -- East wall (Peer 4)
        if b.x > 7.75 and b.vx > 0.0 then
            if S.peers[4].hp <= 0 or math.abs(b.z - S.peers[4].pos) <= PADDLE_HALF then
                b.x = 7.75
                b.vx = -math.abs(b.vx)
                eng.audio.play(S.sfx_bounce, b.x, 0.5, b.z, 0)
            elseif b.x > LIMIT then
                score_bot_goal(4, b, -14.0, -4.5)
            end
        end

        b.vx = eng.math.clamp(b.vx, -20.0, 20.0)
        b.vz = eng.math.clamp(b.vz, -20.0, 20.0)
        eng.scene.set_pos(b.ent, b.x, 0.45, b.z)
    end

    if S.bots_eliminated >= 3 or S.goals_scored >= 5 then
        S.won = true
        eng.save.write("net_pong_4p_win", tostring(S.goals_scored))
    end
end

function score_bot_goal(peer_idx, ball, rvx, rvz)
    local p = S.peers[peer_idx]
    S.goals_scored = S.goals_scored + 1
    eng.audio.play(S.sfx_goal, ball.x, 0.6, ball.z, 0)
    if p.hp > 0 then
        p.hp = p.hp - 1
        if p.hp == 0 then
            S.bots_eliminated = S.bots_eliminated + 1
            -- Seal eliminated peer's goal wall as a solid arena bumper
            if p.axis == "x" then
                eng.scene.set_pos(p.ent, 0.0, 0.45, p.fixed)
                eng.scene.set_scale(p.ent, 16.0, 0.7, 0.55)
            else
                eng.scene.set_pos(p.ent, p.fixed, 0.45, 0.0)
                eng.scene.set_scale(p.ent, 0.55, 0.7, 16.0)
            end
        end
    end
    ball.x, ball.z = 0.0, 0.0
    ball.vx, ball.vz = rvx, rvz
end

function draw()
    for i = 1, #S.balls do
        eng.render.draw_sprite(S.balls[i].x, 1.05, S.balls[i].z, 0.6, 0.6, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 560, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | TICK " .. S.net_tick .. " | GOALS " .. S.goals_scored .. "/5 | KO " .. S.bots_eliminated .. "/3", 1.0, {0.4, 0.98, 0.85, 1.0})
    eng.ui.bar(x, y + 26, 220, S.goals_scored / 5.0, "MATCH ")
end
