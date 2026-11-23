-- 052_hex_archipelago: Procedural 3D island conquest & coastal watchtowers (diorama)
local S = game.state

local HEX_R = 1.95
local SQRT3 = 1.7320508

local function axial_to_world(q, r)
    local x = HEX_R * SQRT3 * (q + r * 0.5)
    local z = HEX_R * 1.5 * r
    return x, z
end

local function hex_dist(q1, r1, q2, r2)
    local dq = q1 - q2
    local dr = r1 - r2
    local ds = (-q1 - r1) - (-q2 - r2)
    return (math.abs(dq) + math.abs(dr) + math.abs(ds)) * 0.5
end

local function refresh_hex_visual(h)
    local col
    if h.owner == 1 then
        col = h.is_land and {0.20, 0.72, 0.98, 1.0} or {0.16, 0.52, 0.88, 1.0}
    elseif h.owner == 2 then
        col = {0.92, 0.28, 0.25, 1.0}
    else
        col = h.is_land and {0.42, 0.78, 0.36, 1.0} or {0.22, 0.58, 0.66, 1.0}
    end
    eng.scene.set_mesh(h.ent, S.hex_mesh, { tex = h.is_land and S.grass_tex or S.water_tex, color = col, cast_shadow = true })
end

local function count_owned(owner_id)
    local n = 0
    for i = 1, #S.hexes do
        if S.hexes[i].owner == owner_id then n = n + 1 end
    end
    return n
end

local function has_adjacent_owner(q, r, owner_id)
    for i = 1, #S.hexes do
        local o = S.hexes[i]
        if o.owner == owner_id and hex_dist(q, r, o.q, o.r) == 1 then return true end
    end
    return false
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.010 })
    eng.render.set_sky(0.12, 0.42, 0.78, 0.62, 0.82, 0.95)
    eng.render.add_light({ type = "dir", dir = {-0.4, -1.0, -0.35}, color = {2.2, 2.1, 1.9}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 9.0, 0.0}, color = {0.9, 1.4, 2.0}, range = 34.0 })

    local seed_base = math.floor(eng.math.range(100, 900000))
    S.hex_mesh = eng.asset.cylinder(HEX_R * 0.94, HEX_R * 0.98, 1.0, 6)
    S.ring_mesh = eng.asset.cylinder(HEX_R * 1.06, HEX_R * 1.06, 0.22, 6)
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.tree_mesh = eng.procgen.tree(seed_base + 19, 2, 2.2, 0.18)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.water_tex = eng.procgen.texture("water_caustics", seed_base, 64)
    S.grass_tex = eng.procgen.texture("grass", seed_base + 5, 64)
    S.sfx_claim = eng.audio.synth("triangle", 440, 0.14, 720)
    S.sfx_tower = eng.audio.synth("square", 300, 0.18, 620)
    S.sfx_cannon = eng.audio.synth("noise", 240, 0.10, 90)

    local sea = eng.scene.spawn("ocean_basin")
    eng.scene.set_pos(sea, 0.0, -0.45, 0.0)
    eng.scene.set_scale(sea, 34.0, 0.4, 34.0)
    eng.scene.set_mesh(sea, S.box_mesh, { tex = S.water_tex, color = {0.10, 0.38, 0.68, 1.0} })

    S.hexes = {}
    for q = -2, 2 do
        for r = -2, 2 do
            if math.abs(q + r) <= 2 then
                local wx, wz = axial_to_world(q, r)
                local n = eng.procgen.noise2d(q * 0.65 + 3.1, r * 0.65 + 1.7, seed_base)
                local is_home = (q == -2 and r == 1) or (q == 2 and r == -1) or (q == 0 and r == 0)
                local is_land = is_home or (n > -0.15)
                local hgt = is_land and (0.85 + math.max(0.0, n) * 0.9) or 0.35

                local ent = eng.scene.spawn("hex_" .. tostring(q) .. "_" .. tostring(r))
                eng.scene.set_pos(ent, wx, hgt * 0.5 - 0.15, wz)
                eng.scene.set_scale(ent, 1.0, hgt, 1.0)

                local owner = 0
                if q == -2 and r == 1 then owner = 1 end
                if q == 2 and r == -1 then owner = 2 end

                local hex = {
                    ent = ent, q = q, r = r, x = wx, z = wz, h = hgt,
                    is_land = is_land, owner = owner, tower = false, tower_ent = nil
                }
                refresh_hex_visual(hex)

                if is_land and owner == 0 and n > 0.12 then
                    local tr = eng.scene.spawn("palm_" .. tostring(#S.hexes + 1))
                    eng.scene.set_pos(tr, wx + 0.35, hgt - 0.15, wz - 0.25)
                    eng.scene.set_scale(tr, 0.75, 0.75, 0.75)
                    eng.scene.set_mesh(tr, S.tree_mesh, { color = {0.28, 0.78, 0.32, 1.0}, cast_shadow = true })
                end

                S.hexes[#S.hexes + 1] = hex
            end
        end
    end

    S.sel_idx = 1
    for i = 1, #S.hexes do
        if S.hexes[i].q == -1 and S.hexes[i].r == 1 then S.sel_idx = i break end
    end

    S.cursor_ent = eng.scene.spawn("hex_selector")
    local sh = S.hexes[S.sel_idx]
    eng.scene.set_pos(S.cursor_ent, sh.x, sh.h + 0.05, sh.z)
    eng.scene.set_mesh(S.cursor_ent, S.ring_mesh, { color = {1.0, 0.92, 0.25, 1.0} })

    S.cx, S.cz = sh.x, sh.z
    S.gold = 55.0
    S.towers_built = 0
    S.captures = 0
    S.income_acc = 0.0
    S.tower_cd = 0.7
    S.ai_cd = 1.9
    S.act_cd = 0.0
    S.target_hexes = 12
    S.won = false
    S.lost = false

    eng.camera.look_at(0.0, 17.5, 15.5, 0.0, 0.4, 0.0, 0)
    eng.mod.emit("post_init")
end

local function build_tower_on(h)
    if h.tower then return false end
    h.tower = true
    local te = eng.scene.spawn("coastal_tower_" .. tostring(h.q) .. "_" .. tostring(h.r))
    eng.scene.set_pos(te, h.x, h.h - 0.15, h.z)
    eng.scene.set_scale(te, 0.65, 0.72, 0.65)
    eng.scene.set_mesh(te, S.pillar_mesh, { color = {0.92, 0.95, 1.0, 1.0}, cast_shadow = true })
    h.tower_ent = te
    S.towers_built = S.towers_built + 1
    eng.audio.play(S.sfx_tower, h.x, h.h + 1.0, h.z, 0)
    return true
end

function update(dt)
    if S.won or S.lost then return end
    S.act_cd = math.max(0.0, S.act_cd - dt)

    -- Move selector smoothly across archipelago
    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    if math.abs(mx) > 0.01 or math.abs(my) > 0.01 then
        S.cx = eng.math.clamp(S.cx + mx * 12.0 * dt, -9.5, 9.5)
        S.cz = eng.math.clamp(S.cz - my * 12.0 * dt, -9.5, 9.5)
        local best_i, best_d = S.sel_idx, 999.0
        for i = 1, #S.hexes do
            local d = eng.math.dist3(S.cx, 0, S.cz, S.hexes[i].x, 0, S.hexes[i].z)
            if d < best_d then best_d = d; best_i = i end
        end
        S.sel_idx = best_i
    end
    local sel = S.hexes[S.sel_idx]
    eng.scene.set_pos(S.cursor_ent, sel.x, sel.h + 0.05, sel.z)

    -- Gold income from owned islands & towers
    local p_owned = count_owned(1)
    S.gold = S.gold + (4.5 + p_owned * 2.2 + S.towers_built * 3.5) * dt

    -- Fire: Claim adjacent neutral/rival hex
    if (eng.input.pressed("fire") or eng.input.down("fire")) and S.act_cd <= 0.0 then
        local cost = (sel.owner == 2) and 14.0 or 8.0
        if sel.owner ~= 1 and has_adjacent_owner(sel.q, sel.r, 1) and S.gold >= cost then
            S.act_cd = 0.16
            S.gold = S.gold - cost
            sel.owner = 1
            S.captures = S.captures + 1
            refresh_hex_visual(sel)
            eng.audio.play(S.sfx_claim, sel.x, sel.h + 0.5, sel.z, 0)
        end
    end

    -- Interact: Build Coastal Watchtower on owned hex
    if (eng.input.pressed("interact") or eng.input.down("interact")) and S.act_cd <= 0.0 then
        if sel.owner == 1 and not sel.tower and S.gold >= 12.0 then
            S.act_cd = 0.22
            S.gold = S.gold - 12.0
            build_tower_on(sel)
        end
    end

    -- Coastal Watchtowers bombard & convert adjacent enemy/neutral sea hexes
    S.tower_cd = S.tower_cd - dt
    if S.tower_cd <= 0.0 then
        S.tower_cd = 0.75
        for i = 1, #S.hexes do
            local th = S.hexes[i]
            if th.owner == 1 and th.tower then
                for j = 1, #S.hexes do
                    local nh = S.hexes[j]
                    if nh.owner ~= 1 and hex_dist(th.q, th.r, nh.q, nh.r) == 1 then
                        nh.owner = 1
                        S.captures = S.captures + 1
                        refresh_hex_visual(nh)
                        eng.audio.play(S.sfx_cannon, nh.x, nh.h + 0.5, nh.z, 0)
                        break
                    end
                end
            end
        end
    end

    -- Rival pirate fleet expands slowly from owned crimson hexes
    S.ai_cd = S.ai_cd - dt
    if S.ai_cd <= 0.0 then
        S.ai_cd = 2.1
        for i = 1, #S.hexes do
            local eh = S.hexes[i]
            if eh.owner == 0 and has_adjacent_owner(eh.q, eh.r, 2) then
                eh.owner = 2
                refresh_hex_visual(eh)
                break
            end
        end
    end

    p_owned = count_owned(1)
    if p_owned >= S.target_hexes then
        S.won = true
        eng.save.write("hex_archipelago_clear", tostring(p_owned))
    elseif p_owned == 0 then
        S.lost = true
    end
end

function draw()
    for i = 1, #S.hexes do
        local h = S.hexes[i]
        if h.tower then
            eng.render.draw_sprite(h.x, h.h + 2.3, h.z, 0.65, 0.65, S.orb_tex)
        end
    end
    local owned = count_owned(1)
    local x, y = eng.ui.anchor("top_left", 16, 14, 520, 52, 1280, 720)
    local status = S.won and (" | " .. eng.i18n.t("victory")) or ""
    eng.ui.label(x, y, eng.i18n.t("title") .. string.format(" | GOLD: %d | TOWERS: %d%s", math.floor(S.gold), S.towers_built, status), 1.0, {0.95, 0.95, 0.55, 1.0})
    eng.ui.bar(x, y + 24, 240, owned / S.target_hexes, "ISLANDS " .. owned .. "/" .. S.target_hexes .. " ")
end
