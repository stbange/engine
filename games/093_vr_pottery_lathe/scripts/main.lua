-- 093_vr_pottery_lathe: 6DoF WebXR Ceramic Lathe Sculpting & Procedural Glazes
local S = game.state

local PROFILES = {
    -- 1: Classic Amphora
    { 0.34, 0.48, 0.72, 0.78, 0.66, 0.40, 0.32, 0.46 },
    -- 2: Gourd Bottle
    { 0.42, 0.74, 0.70, 0.44, 0.58, 0.56, 0.30, 0.28 },
    -- 3: Royal Chalice
    { 0.56, 0.28, 0.28, 0.34, 0.62, 0.74, 0.78, 0.80 }
}
local GLAZE_RECIPES = { "marble", "water_caustics", "stone_brick" }

local function calc_match()
    local tgt = PROFILES[S.stage]
    local err = 0.0
    for i = 1, 8 do
        err = err + math.abs(S.radii[i] - tgt[i])
    end
    return eng.math.clamp(1.0 - (err / 8.0) * 2.2, 0.0, 1.0)
end

local function refresh_vase_visuals()
    local tgt = PROFILES[S.stage]
    local tex = S.glaze_tex[S.glaze_idx]
    for i = 1, 8 do
        local r = S.radii[i]
        eng.scene.set_scale(S.rings[i], r, 1.0, r)
        local hi = (i == S.sel_ring) and 1.15 or 1.0
        eng.scene.set_mesh(S.rings[i], S.ring_mesh, {
            tex = tex,
            color = {0.86 * hi, 0.74 * hi, 0.64 * hi, 1.0},
            roughness = S.glazed and 0.16 or 0.62,
            metallic = S.glazed and 0.15 or 0.0,
            cast_shadow = true
        })
        local tr = tgt[i]
        eng.scene.set_scale(S.target_rings[i], tr, 1.0, tr)
    end
    local y = 0.94 + (S.sel_ring - 1) * 0.14
    local r = S.radii[S.sel_ring]
    eng.scene.set_pos(S.hand_l, -r - 0.16, y, -2.5)
    eng.scene.set_pos(S.hand_r,  r + 0.16, y, -2.5)
    S.match = calc_match()
end

local function load_commission(idx)
    S.stage = idx
    S.sel_ring = 1
    S.glazed = false
    S.glaze_idx = ((idx - 1) % #GLAZE_RECIPES) + 1
    for i = 1, 8 do S.radii[i] = 0.52 end
    refresh_vase_visuals()
end

function init()
    eng.xr.set_mode("6dof")
    eng.render.set_sky(0.18, 0.14, 0.12, 0.36, 0.28, 0.22)
    eng.render.add_light({ type = "dir", dir = {-0.35, -1.0, -0.45}, color = {2.1, 1.95, 1.75}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.2, 2.6, -1.5}, color = {2.0, 1.7, 1.3}, range = 14.0 })

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.ring_mesh = eng.asset.cylinder(1.0, 1.0, 0.135, 24)
    S.wheel_mesh = eng.asset.cylinder(1.05, 1.05, 0.12, 24)
    S.hand_mesh = eng.asset.sphere(0.09, 10, 12)

    local seed = math.floor(eng.math.range(100, 90000))
    local wood_tex = eng.procgen.texture("wood_planks", seed, 64)
    S.glaze_tex = {}
    for i = 1, #GLAZE_RECIPES do
        S.glaze_tex[i] = eng.procgen.texture(GLAZE_RECIPES[i], seed + i * 37, 64)
    end

    -- Studio workbench & spinning wheel platter
    local bench = eng.scene.spawn("pottery_bench")
    eng.scene.set_pos(bench, 0.65, 0.38, -2.5)
    eng.scene.set_scale(bench, 3.8, 0.76, 1.8)
    eng.scene.set_mesh(bench, S.box_mesh, { tex = wood_tex, roughness = 0.75 })

    S.wheel_ent = eng.scene.spawn("lathe_wheel")
    eng.scene.set_pos(S.wheel_ent, 0.0, 0.82, -2.5)
    eng.scene.set_mesh(S.wheel_ent, S.wheel_mesh, { color = {0.35, 0.36, 0.40, 1.0}, metallic = 0.6, roughness = 0.35 })

    S.rings = {}
    S.target_rings = {}
    S.radii = {}
    for i = 1, 8 do
        local y = 0.94 + (i - 1) * 0.14
        local re = eng.scene.spawn("clay_ring_" .. tostring(i))
        eng.scene.set_pos(re, 0.0, y, -2.5)
        S.rings[i] = re

        local te = eng.scene.spawn("target_ring_" .. tostring(i))
        eng.scene.set_pos(te, 1.45, y, -2.5)
        eng.scene.set_mesh(te, S.ring_mesh, { color = {0.30, 0.90, 0.95, 1.0}, roughness = 0.25 })
        S.target_rings[i] = te
    end

    -- 6DoF sculpting tool spheres flanking active clay ring
    S.hand_l = eng.scene.spawn("xr_sculpt_hand_l")
    eng.scene.set_mesh(S.hand_l, S.hand_mesh, { color = {1.0, 0.65, 0.25, 1.0}, roughness = 0.3 })
    S.hand_r = eng.scene.spawn("xr_sculpt_hand_r")
    eng.scene.set_mesh(S.hand_r, S.hand_mesh, { color = {1.0, 0.65, 0.25, 1.0}, roughness = 0.3 })

    S.sfx_shaper = eng.audio.synth("sine", 340, 0.06, 420)
    S.sfx_kiln = eng.audio.synth("triangle", 520, 0.22, 880)

    S.spin_deg = 0.0
    S.vases_completed = 0
    S.glazes_applied = 0
    S.step_cd = 0.0
    S.won = false
    load_commission(1)

    eng.camera.look_at(0.55, 1.78, 0.25, 0.55, 1.35, -2.5, 0)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end
    S.step_cd = math.max(0.0, S.step_cd - dt)
    S.spin_deg = (S.spin_deg + 260.0 * dt) % 360.0
    eng.scene.set_rot_deg(S.wheel_ent, 0.0, S.spin_deg, 0.0)
    for i = 1, 8 do
        eng.scene.set_rot_deg(S.rings[i], 0.0, S.spin_deg, 0.0)
    end

    if S.step_cd <= 0.0 then
        if eng.input.pressed("up") or eng.input.down("up") then
            S.sel_ring = (S.sel_ring % 8) + 1
            S.step_cd = 0.06
            refresh_vase_visuals()
        elseif eng.input.pressed("down") or eng.input.down("down") then
            S.sel_ring = ((S.sel_ring - 2) % 8) + 1
            S.step_cd = 0.06
            refresh_vase_visuals()
        end
    end

    local mx, _ = eng.input.axis2d("left", "right", "down", "up")
    if math.abs(mx) > 0.01 then
        S.radii[S.sel_ring] = eng.math.clamp(S.radii[S.sel_ring] + mx * 1.8 * dt, 0.20, 0.90)
        refresh_vase_visuals()
    end

    if eng.input.pressed("interact") then
        S.glaze_idx = (S.glaze_idx % #GLAZE_RECIPES) + 1
        S.glazes_applied = S.glazes_applied + 1
        eng.audio.play(S.sfx_shaper, 0.0, 1.3, -2.5, 0)
        refresh_vase_visuals()
    end

    if eng.input.pressed("fire") and S.match >= 0.88 then
        S.glazed = true
        S.glazes_applied = S.glazes_applied + 1
        S.vases_completed = S.vases_completed + 1
        eng.audio.play(S.sfx_kiln, 0.0, 1.4, -2.5, 0)
        refresh_vase_visuals()
        if S.vases_completed >= 3 then
            S.won = true
            eng.save.write("pottery_master", "3_commissions")
        else
            load_commission(S.vases_completed + 1)
        end
    end
end

function draw()
    local x, y = eng.ui.anchor("top_left", 16, 14, 520, 28, 1280, 720)
    local pct = math.floor(S.match * 100 + 0.5)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | VASE " .. S.stage .. "/3 | RING " .. S.sel_ring .. " | MATCH " .. pct .. "%", 1.0, {1.0, 0.9, 0.65, 1.0})
    eng.ui.bar(x, y + 26, 220, S.match, "FIT ")
end
