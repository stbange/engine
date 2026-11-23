-- 064_shadow_silhouette: Rotate a compound 3D sculpture in front of a spotlight to align its projected wall shadow
local S = game.state

local SCULPTURES = {
    -- Stage 1: Royal Crown (scrambled pitch=45, yaw=-60)
    {
        start_rx = 45.0, start_ry = -60.0,
        parts = {
            { x =  0.0, y = -0.55, z =  0.3, sx = 1.6, sy = 0.35, sz = 0.35 },
            { x = -0.65, y = 0.05, z = -0.3, sx = 0.32, sy = 0.9, sz = 0.32 },
            { x =  0.0,  y = 0.25, z =  0.4, sx = 0.35, sy = 1.2, sz = 0.35 },
            { x =  0.65, y = 0.05, z = -0.2, sx = 0.32, sy = 0.9, sz = 0.32 },
            { x =  0.0,  y = 0.95, z = -0.4, sx = 0.35, sy = 0.35, sz = 0.35 },
        }
    },
    -- Stage 2: Astral Key (scrambled pitch=-54, yaw=72)
    {
        start_rx = -54.0, start_ry = 72.0,
        parts = {
            { x =  0.0, y =  0.65, z =  0.35, sx = 1.1,  sy = 0.85, sz = 0.32 },
            { x =  0.0, y = -0.25, z = -0.30, sx = 0.30, sy = 1.4,  sz = 0.30 },
            { x =  0.45, y = -0.55, z = 0.25, sx = 0.65, sy = 0.25, sz = 0.28 },
            { x =  0.45, y = -0.90, z = -0.2, sx = 0.65, sy = 0.25, sz = 0.28 },
            { x = -0.45, y =  0.65, z = -0.35, sx = 0.32, sy = 0.85, sz = 0.32 },
        }
    },
    -- Stage 3: Hourglass Spire (scrambled pitch=63, yaw=-81)
    {
        start_rx = 63.0, start_ry = -81.0,
        parts = {
            { x =  0.0,  y =  0.85, z =  0.3, sx = 1.4, sy = 0.28, sz = 0.32 },
            { x =  0.0,  y = -0.85, z = -0.3, sx = 1.4, sy = 0.28, sz = 0.32 },
            { x = -0.35, y =  0.35, z = -0.25, sx = 0.45, sy = 0.55, sz = 0.30 },
            { x =  0.35, y = -0.35, z =  0.25, sx = 0.45, sy = 0.55, sz = 0.30 },
            { x =  0.0,  y =  0.0,  z =  0.0, sx = 0.42, sy = 0.42, sz = 0.42 },
        }
    }
}

-- Spotlight at (0, 3.2, 5.5) projecting past pivot (0, 3.2, 0.0) onto screen z = -4.4
local LIGHT_Y, LIGHT_Z = 3.2, 5.5
local PIVOT_Y, PIVOT_Z = 3.2, 0.0
local WALL_Z = -4.4

local function project_local_pt(lx, ly, lz, rx_deg, ry_deg)
    -- Match engine Euler order: Ry(yaw) * Rx(pitch)
    local rx, ry = math.rad(rx_deg), math.rad(ry_deg)
    local cx, sx = math.cos(rx), math.sin(rx)
    local cy, sy = math.cos(ry), math.sin(ry)
    -- Rx first
    local y1 = ly * cx - lz * sx
    local z1 = ly * sx + lz * cx
    -- Ry second
    local wx = lx * cy + z1 * sy
    local wy = PIVOT_Y + y1
    local wz = PIVOT_Z - lx * sy + z1 * cy

    local t = (LIGHT_Z - WALL_Z) / math.max(1.0, (LIGHT_Z - wz))
    local px = wx * t
    local py = LIGHT_Y + (wy - LIGHT_Y) * t
    return px, py, t
end

local function clear_stage()
    if S.stage_ents then
        for i = 1, #S.stage_ents do eng.scene.despawn(S.stage_ents[i]) end
    end
    S.stage_ents = {}
    S.shadow_ents = {}
    S.target_pts = {}
end

local function update_sculpture_pose()
    eng.scene.set_rot_deg(S.pivot, S.rx, S.ry, 0.0)
    local sc = SCULPTURES[S.stage]
    local sq_sum = 0.0
    for i = 1, #sc.parts do
        local p = sc.parts[i]
        local sx, sy, mag = project_local_pt(p.x, p.y, p.z, S.rx, S.ry)
        eng.scene.set_pos(S.shadow_ents[i], sx, sy, WALL_Z + 0.05)
        eng.scene.set_scale(S.shadow_ents[i], p.sx * mag, p.sy * mag, 0.08)
        local tp = S.target_pts[i]
        local dx, dy = sx - tp.x, sy - tp.y
        sq_sum = sq_sum + dx * dx + dy * dy
    end
    local rms = math.sqrt(sq_sum / #sc.parts)
    S.rms_error = rms
    S.alignment = eng.math.clamp(1.0 - rms / 2.2, 0.0, 1.0)
end

local function build_stage(idx)
    clear_stage()
    S.stage = idx
    local sc = SCULPTURES[idx]
    S.rx = sc.start_rx
    S.ry = sc.start_ry

    S.pivot = eng.scene.spawn("sculpture_pivot")
    eng.scene.set_pos(S.pivot, 0.0, PIVOT_Y, PIVOT_Z)
    S.stage_ents[#S.stage_ents + 1] = S.pivot

    local seed_base = math.floor(eng.math.range(100, 6000)) + idx * 83
    local bronze_tex = eng.procgen.texture("wood_grain", seed_base, 64)

    for i = 1, #sc.parts do
        local p = sc.parts[i]
        local tx, ty, tmag = project_local_pt(p.x, p.y, p.z, 0.0, 0.0)
        S.target_pts[i] = { x = tx, y = ty }

        local te = eng.scene.spawn("silhouette_lock_" .. tostring(i))
        eng.scene.set_pos(te, tx, ty, WALL_Z + 0.02)
        eng.scene.set_scale(te, p.sx * tmag * 1.08, p.sy * tmag * 1.08, 0.06)
        eng.scene.set_mesh(te, S.box_mesh, { color = {0.95, 0.72, 0.22, 1.0} })
        S.stage_ents[#S.stage_ents + 1] = te

        local se = eng.scene.spawn("live_shadow_" .. tostring(i))
        eng.scene.set_mesh(se, S.box_mesh, { color = {0.10, 0.09, 0.14, 1.0} })
        S.stage_ents[#S.stage_ents + 1] = se
        S.shadow_ents[i] = se

        local pe = eng.scene.spawn("sculpt_part_" .. tostring(i))
        eng.scene.set_parent(pe, S.pivot)
        eng.scene.set_pos(pe, p.x, p.y, p.z)
        eng.scene.set_scale(pe, p.sx, p.sy, p.sz)
        eng.scene.set_mesh(pe, S.box_mesh, { tex = bronze_tex, color = {0.82, 0.58, 0.34, 1.0}, metallic = 0.6, roughness = 0.35, cast_shadow = true })
        S.stage_ents[#S.stage_ents + 1] = pe
    end

    update_sculpture_pose()
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.01 })
    eng.render.set_sky(0.08, 0.06, 0.12, 0.22, 0.16, 0.20)
    eng.render.add_light({ type = "spot", pos = {0.0, LIGHT_Y, LIGHT_Z}, dir = {0.0, 0.0, -1.0}, color = {3.2, 2.9, 2.4}, range = 24.0, shadow = true })
    eng.render.add_light({ type = "dir", dir = {-0.3, -1.0, -0.4}, color = {1.1, 1.05, 1.15}, shadow = false })

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.sfx_lock = eng.audio.synth("sine", 520, 0.24, 1040)

    local floor_tex = eng.procgen.texture("stone_brick", 404, 64)
    local floor_e = eng.scene.spawn("gallery_floor")
    eng.scene.set_pos(floor_e, 0.0, -0.25, 0.0)
    eng.scene.set_scale(floor_e, 14.0, 0.5, 14.0)
    eng.scene.set_mesh(floor_e, S.box_mesh, { tex = floor_tex, color = {0.36, 0.32, 0.34, 1.0} })
    eng.physics.add_body(floor_e, { shape = "aabb", motion = "static", half_extents = {7.0, 0.25, 7.0} })

    local wall_e = eng.scene.spawn("projection_screen")
    eng.scene.set_pos(wall_e, 0.0, 3.2, WALL_Z - 0.15)
    eng.scene.set_scale(wall_e, 9.5, 6.6, 0.3)
    eng.scene.set_mesh(wall_e, S.box_mesh, { color = {0.90, 0.86, 0.78, 1.0} })

    local ped_e = eng.scene.spawn("sculpt_pedestal")
    eng.scene.set_pos(ped_e, 0.0, 0.0, 0.0)
    eng.scene.set_scale(ped_e, 0.7, 0.55, 0.7)
    eng.scene.set_mesh(ped_e, S.pillar_mesh, { color = {0.45, 0.42, 0.40, 1.0}, cast_shadow = true })

    S.locked_stages = 0
    S.won = false
    build_stage(1)
    eng.camera.look_at(3.4, 4.2, 6.2, 0.0, 3.0, -2.5, 0)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end
    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    if math.abs(mx) > 0.01 or math.abs(my) > 0.01 then
        S.ry = S.ry + mx * 110.0 * dt
        S.rx = S.rx + my * 110.0 * dt
        update_sculpture_pose()
    end

    if S.rms_error < 0.14 then
        S.locked_stages = S.locked_stages + 1
        eng.audio.play(S.sfx_lock, 0.0, 3.2, WALL_Z, 0)
        if S.stage < 3 then
            eng.save.write("shadow_silhouette", "stage_" .. tostring(S.stage + 1))
            build_stage(S.stage + 1)
        else
            S.rx, S.ry = 0.0, 0.0
            update_sculpture_pose()
            S.won = true
            eng.save.write("shadow_silhouette", "clear")
        end
    end
end

function draw()
    local pct = math.floor(S.alignment * 100.0 + 0.5)
    local x, y = eng.ui.anchor("top_left", 16, 14, 480, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | SCULPTURE " .. S.stage .. "/3 | MATCH " .. pct .. "%", 1.0, {1.0, 0.90, 0.55, 1.0})
    eng.ui.bar(x, y + 26, 200, S.alignment, "MATCH ")
end
