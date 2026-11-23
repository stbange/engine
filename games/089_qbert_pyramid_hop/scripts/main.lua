-- 089_qbert_pyramid_hop: Diagonal Hops on a 4-Tier 3D Cube Pyramid Flipping Tiles to Gold
local S = game.state

local TIERS = 4
local STEP_X = 1.85
local STEP_Y = 1.25
local STEP_Z = 1.55
local HOP_DUR = 0.16

local function tile_top_pos(r, c)
    local cx = (c - (r + 1) * 0.5) * STEP_X
    local cy = (TIERS - r) * STEP_Y + 1.32
    local cz = (r - 2.5) * STEP_Z
    return cx, cy, cz
end

local function valid_rc(r, c)
    return r >= 1 and r <= TIERS and c >= 1 and c <= r
end

local function flip_tile(r, c)
    local t = S.grid[r] and S.grid[r][c]
    if t and not t.gold then
        t.gold = true
        S.gold_count = S.gold_count + 1
        S.score = S.score + 100
        eng.scene.set_mesh(t.cap_ent, S.box_mesh, {
            tex = S.gold_tex,
            color = {1.00, 0.85, 0.18, 1.0},
            metallic = 0.65,
            roughness = 0.22
        })
        local tx, ty, tz = tile_top_pos(r, c)
        eng.audio.play(S.sfx_gold, tx, ty, tz, 0)
    end
end

local function start_enemy_hop(sp, nr, nc)
    sp.r0, sp.c0 = sp.r, sp.c
    sp.x0, sp.y0, sp.z0 = tile_top_pos(sp.r, sp.c)
    sp.nr, sp.nc = nr, nc
    sp.x1, sp.y1, sp.z1 = tile_top_pos(nr, nc)
    sp.hop_t = 0.0
    sp.hopping = true
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.010 })
    eng.render.set_sky(0.04, 0.03, 0.14, 0.14, 0.08, 0.28)
    eng.render.add_light({ type = "dir", dir = {-0.35, -0.90, -0.45}, color = {2.2, 2.1, 1.95}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 8.5, 2.0}, color = {1.5, 1.7, 2.4}, range = 30.0 })

    local seed_base = math.floor(eng.math.range(100, 90000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.sphere_mesh = eng.asset.sphere(0.44, 12, 16)
    S.disc_mesh = eng.asset.cylinder(0.66, 0.66, 0.14, 14)
    S.cube_tex = eng.procgen.texture("stone_brick", seed_base, 64)
    S.gold_tex = eng.procgen.texture("marble", seed_base + 13, 64)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    S.sfx_hop = eng.audio.synth("triangle", 380, 0.08, 620)
    S.sfx_gold = eng.audio.synth("square", 560, 0.14, 940)
    S.sfx_hit = eng.audio.synth("noise", 220, 0.15, 75)

    -- Voxel Q-Hopper character with snout
    S.vox_hopper = eng.asset.voxel_ascii({
        "1..1\n1111\n1111\n....",
        "1111\n1111\n1111\n.22.",
        ".11.\n1221\n.11.\n.22."
    }, 4, 3, 4, 0.24)

    -- Build 4-tier stepped cube pyramid (1 + 2 + 3 + 4 = 10 cubes + 10 flippable top tiles)
    S.grid = {}
    S.total_tiles = 0
    for r = 1, TIERS do
        S.grid[r] = {}
        for c = 1, r do
            local tx, ty, tz = tile_top_pos(r, c)
            local block_e = eng.scene.spawn("pyr_cube_" .. r .. "_" .. c)
            eng.scene.set_pos(block_e, tx, ty - 0.69, tz)
            eng.scene.set_scale(block_e, 1.70, 1.24, 1.44)
            eng.scene.set_mesh(block_e, S.box_mesh, {
                tex = S.cube_tex,
                color = {0.32, 0.36, 0.58, 1.0},
                roughness = 0.78,
                cast_shadow = true
            })

            local cap_e = eng.scene.spawn("pyr_tile_" .. r .. "_" .. c)
            eng.scene.set_pos(cap_e, tx, ty - 0.04, tz)
            eng.scene.set_scale(cap_e, 1.62, 0.12, 1.36)
            eng.scene.set_mesh(cap_e, S.box_mesh, {
                tex = S.gold_tex,
                color = {0.18, 0.58, 0.98, 1.0},
                roughness = 0.35
            })

            S.grid[r][c] = { cube_ent = block_e, cap_ent = cap_e, r = r, c = c, gold = false }
            S.total_tiles = S.total_tiles + 1
        end
    end

    -- 2 Flanking Escape Lift Discs beside Row 2: (2, 0) and (2, 3)
    S.discs = {}
    local disc_cols = { 0, 3 }
    for i = 1, 2 do
        local dc = disc_cols[i]
        local dx, dy, dz = tile_top_pos(2, dc)
        local de = eng.scene.spawn("lift_disc_" .. tostring(i))
        eng.scene.set_pos(de, dx, dy, dz)
        eng.scene.set_mesh(de, S.disc_mesh, { color = {0.30, 0.98, 0.85, 1.0}, metallic = 0.5 })
        S.discs[i] = { ent = de, r = 2, c = dc, x = dx, y = dy, z = dz, active = true }
    end

    -- Spawn Q-Hopper at apex (1, 1)
    S.hopper = eng.scene.spawn("q_hopper")
    local hx, hy, hz = tile_top_pos(1, 1)
    eng.scene.set_pos(S.hopper, hx - 0.48, hy + 0.02, hz - 0.48)
    eng.scene.set_mesh(S.hopper, S.vox_hopper, { color = {1.0, 0.52, 0.14, 1.0}, cast_shadow = true })

    -- Spawn Pursuing Coily Sphere (violet) + Tumbling Hazard Sphere (crimson)
    S.spheres = {}
    local sp_specs = {
        { kind = "coily",  r = 4, c = 4, col = {0.82, 0.22, 0.98, 1.0}, cd = 0.44 },
        { kind = "hazard", r = 3, c = 1, col = {1.00, 0.22, 0.26, 1.0}, cd = 0.50 }
    }
    for i = 1, #sp_specs do
        local sp = sp_specs[i]
        local sx, sy, sz = tile_top_pos(sp.r, sp.c)
        local se = eng.scene.spawn("sphere_" .. sp.kind)
        eng.scene.set_pos(se, sx, sy + 0.42, sz)
        eng.scene.set_mesh(se, S.sphere_mesh, { color = sp.col, roughness = 0.18, metallic = 0.25, cast_shadow = true })
        S.spheres[i] = {
            ent = se, kind = sp.kind,
            r = sp.r, c = sp.c, nr = sp.r, nc = sp.c,
            x = sx, y = sy + 0.42, z = sz,
            x0 = sx, y0 = sy, z0 = sz, x1 = sx, y1 = sy, z1 = sz,
            hopping = false, hop_t = 0.0, wait = sp.cd, base_cd = sp.cd
        }
    end

    S.pr, S.pc = 1, 1
    S.nr, S.nc = 1, 1
    S.px, S.py, S.pz = hx, hy, hz
    S.x0, S.y0, S.z0 = hx, hy, hz
    S.x1, S.y1, S.z1 = hx, hy, hz
    S.hopping = false
    S.hop_t = 0.0
    S.yaw = 0.0
    S.lives = 3
    S.invuln = 0.0
    S.score = 0
    S.gold_count = 0
    S.hops_made = 0
    S.dodges = 0
    S.won = false

    eng.camera.look_at(0.0, 10.2, 9.8, 0.0, 2.3, 0.0, 0)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end
    S.invuln = math.max(0.0, S.invuln - dt)

    for i = 1, #S.discs do
        local d = S.discs[i]
        if d.active then
            eng.scene.set_rot_deg(d.ent, 0.0, (S.hops_made * 45.0 + i * 90.0) + S.invuln * 180.0, 0.0)
        end
    end

    -- Player diagonal hop input:
    -- "left" = Up-Left (r-1, c-1), "up" = Up-Right (r-1, c), "down" = Down-Left (r+1, c), "right" = Down-Right (r+1, c+1)
    if not S.hopping then
        local dr, dc, yaw = 0, 0, S.yaw
        if eng.input.pressed("left") or eng.input.down("left") then
            dr, dc, yaw = -1, -1, 135.0
        elseif eng.input.pressed("up") or eng.input.down("up") then
            dr, dc, yaw = -1, 0, -135.0
        elseif eng.input.pressed("down") or eng.input.down("down") then
            dr, dc, yaw = 1, 0, 45.0
        elseif eng.input.pressed("right") or eng.input.down("right") then
            dr, dc, yaw = 1, 1, -45.0
        end

        if dr ~= 0 then
            S.nr, S.nc = S.pr + dr, S.pc + dc
            S.x0, S.y0, S.z0 = tile_top_pos(S.pr, S.pc)
            S.x1, S.y1, S.z1 = tile_top_pos(S.nr, S.nc)
            S.hopping = true
            S.hop_t = 0.0
            S.yaw = yaw
            S.hops_made = S.hops_made + 1
            eng.audio.play(S.sfx_hop, S.x0, S.y0 + 0.4, S.z0, 0)
        end
    else
        S.hop_t = S.hop_t + dt / HOP_DUR
        if S.hop_t >= 1.0 then
            S.hopping = false
            S.hop_t = 0.0

            -- Check Lift Disc landing
            local used_disc = nil
            for i = 1, #S.discs do
                local d = S.discs[i]
                if d.active and d.r == S.nr and d.c == S.nc then
                    used_disc = d
                    break
                end
            end

            if used_disc then
                used_disc.active = false
                eng.scene.despawn(used_disc.ent)
                S.pr, S.pc = 1, 1
                S.nr, S.nc = 1, 1
                flip_tile(1, 1)
                S.dodges = S.dodges + 1
                S.score = S.score + 200
            elseif valid_rc(S.nr, S.nc) then
                S.pr, S.pc = S.nr, S.nc
                flip_tile(S.pr, S.pc)
                -- Count close dodge when hopping near a sphere
                for i = 1, #S.spheres do
                    local sp = S.spheres[i]
                    if math.abs(sp.r - S.pr) + math.abs(sp.c - S.pc) <= 2 then
                        S.dodges = S.dodges + 1
                    end
                end
            else
                -- Hopped off pyramid edge: lose a life & respawn at apex
                S.lives = math.max(1, S.lives - 1)
                S.invuln = 0.9
                S.pr, S.pc = 1, 1
                S.nr, S.nc = 1, 1
                eng.audio.play(S.sfx_hit, S.x0, S.y0, S.z0, 0)
            end
            S.px, S.py, S.pz = tile_top_pos(S.pr, S.pc)
        else
            local t = S.hop_t
            local arc = math.sin(t * math.pi) * 0.92
            S.px = S.x0 + (S.x1 - S.x0) * t
            S.py = S.y0 + (S.y1 - S.y0) * t + arc
            S.pz = S.z0 + (S.z1 - S.z0) * t
        end
    end

    eng.scene.set_pos(S.hopper, S.px - 0.48, S.py + 0.02, S.pz - 0.48)

    -- Step Coily & Hazard Spheres
    for i = 1, #S.spheres do
        local sp = S.spheres[i]
        if not sp.hopping then
            sp.wait = sp.wait - dt
            if sp.wait <= 0.0 then
                sp.wait = sp.base_cd
                if sp.kind == "coily" then
                    -- Coily chases player diagonally up or down the pyramid
                    local opts = {
                        { sp.r - 1, sp.c - 1 },
                        { sp.r - 1, sp.c     },
                        { sp.r + 1, sp.c     },
                        { sp.r + 1, sp.c + 1 }
                    }
                    local best_r, best_c, best_d = sp.r, sp.c, 999
                    for k = 1, #opts do
                        local cr, cc = opts[k][1], opts[k][2]
                        if valid_rc(cr, cc) then
                            local d = math.abs(cr - S.pr) + math.abs(cc - S.pc)
                            if d < best_d then best_d = d; best_r, best_c = cr, cc end
                        end
                    end
                    start_enemy_hop(sp, best_r, best_c)
                else
                    -- Red Hazard Sphere tumbles down-left or down-right, wrapping back to Row 1/2
                    local dc = (eng.math.rand() < 0.5) and 0 or 1
                    local nr, nc = sp.r + 1, sp.c + dc
                    if nr > TIERS then
                        sp.r = 2
                        sp.c = (eng.math.rand() < 0.5) and 1 or 2
                        sp.nr, sp.nc = sp.r, sp.c
                        local rx, ry, rz = tile_top_pos(sp.r, sp.c)
                        sp.x, sp.y, sp.z = rx, ry + 0.42, rz
                    else
                        start_enemy_hop(sp, nr, nc)
                    end
                end
            end
        else
            sp.hop_t = sp.hop_t + dt / 0.24
            if sp.hop_t >= 1.0 then
                sp.hopping = false
                sp.r, sp.c = sp.nr, sp.nc
                local sx, sy, sz = tile_top_pos(sp.r, sp.c)
                sp.x, sp.y, sp.z = sx, sy + 0.42, sz
            else
                local t = sp.hop_t
                local arc = math.sin(t * math.pi) * 0.78
                sp.x = sp.x0 + (sp.x1 - sp.x0) * t
                sp.y = sp.y0 + (sp.y1 - sp.y0) * t + 0.42 + arc
                sp.z = sp.z0 + (sp.z1 - sp.z0) * t
            end
        end
        eng.scene.set_pos(sp.ent, sp.x, sp.y, sp.z)

        -- Sphere collision check with Q-Hopper
        if S.invuln <= 0.0 and eng.math.dist3(S.px, S.py + 0.35, S.pz, sp.x, sp.y, sp.z) < 0.62 then
            S.lives = math.max(1, S.lives - 1)
            S.invuln = 1.0
            eng.audio.play(S.sfx_hit, S.px, S.py, S.pz, 0)
            -- Push sphere back to far corner so player isn't chain-hit
            sp.hopping = false
            sp.r, sp.c = 4, (i == 1) and 4 or 1
            sp.nr, sp.nc = sp.r, sp.c
            sp.wait = 0.65
            local rx, ry, rz = tile_top_pos(sp.r, sp.c)
            sp.x, sp.y, sp.z = rx, ry + 0.42, rz
            eng.scene.set_pos(sp.ent, sp.x, sp.y, sp.z)
        end
    end

    if S.gold_count >= S.total_tiles then
        S.won = true
        S.score = S.score + 500
    end

    eng.camera.look_at(S.px * 0.14, 10.2, 9.8, S.px * 0.08, 2.3, 0.0, 0)
end

function draw()
    for i = 1, #S.spheres do
        local sp = S.spheres[i]
        eng.render.draw_sprite(sp.x, sp.y + 0.55, sp.z, 0.45, 0.45, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 480, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | GOLD " .. S.gold_count .. "/" .. S.total_tiles .. " | SCORE " .. S.score, 1.0, {1.0, 0.88, 0.30, 1.0})
    eng.ui.bar(x, y + 26, 180, S.lives / 3.0, "LIVES ")
end
