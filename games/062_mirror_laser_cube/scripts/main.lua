-- 062_mirror_laser_cube: Rotate 45-degree 3D mirror cubes so eng.physics.raycast beams energize crystal receivers
local S = game.state
local SQ = math.sqrt(0.5)

-- 4 discrete 45-degree 3D mirror planes (2 horizontal + 2 vertical 45-deg elevation prisms)
local MIRROR_MODES = {
    { nx = SQ,  ny = 0.0, nz = SQ,  rot = {0.0, 45.0, 0.0}  }, -- +X <-> -Z
    { nx = SQ,  ny = 0.0, nz = -SQ, rot = {0.0, 135.0, 0.0} }, -- -Z <-> -X
    { nx = 0.0, ny = SQ,  nz = SQ,  rot = {45.0, 0.0, 0.0}  }, -- -Z <-> +Y (vertical upward bounce)
    { nx = SQ,  ny = SQ,  nz = 0.0, rot = {0.0, 0.0, 45.0}  }, -- +Y <-> -X (elevated lateral bounce)
}

local function clear_stage()
    if S.ents then
        for i = 1, #S.ents do eng.scene.despawn(S.ents[i]) end
    end
    S.ents = {}
    S.mirrors = {}
    S.crystals = {}
    S.beams = {}
end

local function apply_mirror_rot(m)
    local md = MIRROR_MODES[m.state + 1]
    eng.scene.set_rot_deg(m.ent, md.rot[1], md.rot[2], md.rot[3])
end

local function ensure_beam_ent(idx)
    if not S.beams[idx] then
        local b = eng.scene.spawn("laser_seg_" .. tostring(idx))
        eng.scene.set_mesh(b, S.box_mesh, { color = {1.0, 0.18, 0.35, 1.0} })
        S.ents[#S.ents + 1] = b
        S.beams[idx] = b
    end
    return S.beams[idx]
end

local function set_beam_segment(idx, x0, y0, z0, x1, y1, z1)
    local b = ensure_beam_ent(idx)
    local cx, cy, cz = (x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5
    local sx = math.max(0.10, math.abs(x1 - x0))
    local sy = math.max(0.10, math.abs(y1 - y0))
    local sz = math.max(0.10, math.abs(z1 - z0))
    eng.scene.set_pos(b, cx, cy, cz)
    eng.scene.set_scale(b, sx, sy, sz)
end

local function trace_lasers()
    for i = 1, #S.crystals do S.crystals[i].lit = false end

    local ox, oy, oz = S.emit.x + S.emit.dx * 0.6, S.emit.y + S.emit.dy * 0.6, S.emit.z + S.emit.dz * 0.6
    local dx, dy, dz = S.emit.dx, S.emit.dy, S.emit.dz
    local seg_count = 0
    local bounces = 0

    for step = 1, 8 do
        local hit = eng.physics.raycast(0, ox, oy, oz, dx, dy, dz, 24.0)
        S.raycast_calls = S.raycast_calls + 1
        local hx, hy, hz
        if hit then
            hx, hy, hz = hit.point[1], hit.point[2], hit.point[3]
        else
            hx, hy, hz = ox + dx * 12.0, oy + dy * 12.0, oz + dz * 12.0
        end
        seg_count = seg_count + 1
        set_beam_segment(seg_count, ox, oy, oz, hx, hy, hz)
        if not hit then break end

        local hit_mirror = nil
        for i = 1, #S.mirrors do
            if S.mirrors[i].ent == hit.entity then hit_mirror = S.mirrors[i]; break end
        end
        local hit_crystal = nil
        for i = 1, #S.crystals do
            if S.crystals[i].ent == hit.entity then hit_crystal = S.crystals[i]; break end
        end

        if hit_crystal then
            hit_crystal.lit = true
            ox = hit_crystal.x + dx * 0.58
            oy = hit_crystal.y + dy * 0.58
            oz = hit_crystal.z + dz * 0.58
        elseif hit_mirror then
            local md = MIRROR_MODES[hit_mirror.state + 1]
            local dot = dx * md.nx + dy * md.ny + dz * md.nz
            if math.abs(dot) < 0.15 then break end
            dx = dx - 2.0 * dot * md.nx
            dy = dy - 2.0 * dot * md.ny
            dz = dz - 2.0 * dot * md.nz
            ox = hit_mirror.x + dx * 0.58
            oy = hit_mirror.y + dy * 0.58
            oz = hit_mirror.z + dz * 0.58
            bounces = bounces + 1
        else
            break
        end
    end

    S.last_bounces = bounces
    for i = seg_count + 1, #S.beams do
        eng.scene.set_pos(S.beams[i], 0.0, -8.0, 0.0)
        eng.scene.set_scale(S.beams[i], 0.1, 0.1, 0.1)
    end

    local lit_n = 0
    for i = 1, #S.crystals do
        local c = S.crystals[i]
        if c.lit then
            lit_n = lit_n + 1
            eng.scene.set_mesh(c.ent, S.crystal_mesh, { color = {0.25, 1.0, 0.75, 1.0} })
        else
            eng.scene.set_mesh(c.ent, S.crystal_mesh, { color = {0.35, 0.45, 0.65, 1.0} })
        end
    end
    S.lit_crystals = lit_n

    local sel = S.mirrors[S.sel_idx]
    if sel and S.cursor_ent then
        eng.scene.set_pos(S.cursor_ent, sel.x, sel.y + 0.85, sel.z)
    end
end

local function build_stage(idx)
    clear_stage()
    S.stage = idx
    S.sel_idx = 1
    local seed_base = math.floor(eng.math.range(100, 5000)) + idx * 53
    local tile_tex = eng.procgen.texture("metal_rivets", seed_base, 64)

    local floor_e = eng.scene.spawn("optical_floor")
    eng.scene.set_pos(floor_e, 0.0, -0.25, 0.0)
    eng.scene.set_scale(floor_e, 16.0, 0.5, 16.0)
    eng.scene.set_mesh(floor_e, S.box_mesh, { tex = tile_tex, color = {0.26, 0.28, 0.36, 1.0} })
    eng.physics.add_body(floor_e, { shape = "aabb", motion = "static", half_extents = {8.0, 0.25, 8.0} })
    S.ents[#S.ents + 1] = floor_e

    S.emit = { x = -4.0, y = 1.0, z = 2.0, dx = 1.0, dy = 0.0, dz = 0.0 }
    local em = eng.scene.spawn("laser_emitter")
    eng.scene.set_pos(em, S.emit.x, S.emit.y, S.emit.z)
    eng.scene.set_scale(em, 0.9, 1.2, 0.9)
    eng.scene.set_mesh(em, S.box_mesh, { color = {0.95, 0.25, 0.30, 1.0}, cast_shadow = true })
    S.ents[#S.ents + 1] = em

    local m_cfg, c_cfg, blk_cfg
    if idx == 1 then
        m_cfg = {
            { x = 0.0, y = 1.0, z = 2.0,  state = 3 }, -- 1 press -> state 0 (+X -> -Z)
            { x = 0.0, y = 1.0, z = -4.0, state = 0 }, -- 1 press -> state 1 (-Z -> -X)
        }
        c_cfg = {
            { x = 0.0,  y = 1.0, z = -1.0 },
            { x = -4.0, y = 1.0, z = -4.0 },
        }
        blk_cfg = { { x = 4.0, y = 1.0, z = 2.0 } }
    else
        m_cfg = {
            { x = 2.0, y = 1.0, z = 2.0,  state = 2 }, -- 2 presses -> state 0 (+X -> -Z)
            { x = 2.0, y = 1.0, z = -3.0, state = 1 }, -- 1 press   -> state 2 (-Z -> +Y vertical!)
            { x = 2.0, y = 4.0, z = -3.0, state = 1 }, -- 2 presses -> state 3 (+Y -> -X elevated!)
        }
        c_cfg = {
            { x = 2.0,  y = 1.0, z = -0.5 },
            { x = -2.0, y = 4.0, z = -3.0 },
        }
        blk_cfg = { { x = 5.0, y = 1.0, z = 2.0 } }
    end

    for i = 1, #blk_cfg do
        local b = eng.scene.spawn("obsidian_blocker_" .. tostring(i))
        eng.scene.set_pos(b, blk_cfg[i].x, 0.0, blk_cfg[i].z)
        eng.scene.set_scale(b, 1.0, 0.85, 1.0)
        eng.scene.set_mesh(b, S.pillar_mesh, { color = {0.22, 0.20, 0.28, 1.0}, cast_shadow = true })
        eng.physics.add_body(b, { shape = "aabb", motion = "static", half_extents = {0.5, 1.2, 0.5} })
        S.ents[#S.ents + 1] = b
    end

    for i = 1, #m_cfg do
        local mc = m_cfg[i]
        local me = eng.scene.spawn("mirror_cube_" .. tostring(i))
        eng.scene.set_pos(me, mc.x, mc.y, mc.z)
        eng.scene.set_scale(me, 0.85, 0.85, 0.18)
        eng.scene.set_mesh(me, S.box_mesh, { color = {0.82, 0.92, 1.0, 1.0}, metallic = 0.95, roughness = 0.1, cast_shadow = true })
        eng.physics.add_body(me, { shape = "sphere", motion = "static", radius = 0.45 })
        S.ents[#S.ents + 1] = me
        local m = { ent = me, x = mc.x, y = mc.y, z = mc.z, state = mc.state }
        apply_mirror_rot(m)
        S.mirrors[#S.mirrors + 1] = m
    end

    for i = 1, #c_cfg do
        local cc = c_cfg[i]
        local ce = eng.scene.spawn("crystal_recv_" .. tostring(i))
        eng.scene.set_pos(ce, cc.x, cc.y - 0.3, cc.z)
        eng.scene.set_scale(ce, 1.0, 1.0, 1.0)
        eng.scene.set_mesh(ce, S.crystal_mesh, { color = {0.35, 0.45, 0.65, 1.0}, cast_shadow = true })
        eng.physics.add_body(ce, { shape = "aabb", motion = "static", half_extents = {0.45, 0.55, 0.45} })
        S.ents[#S.ents + 1] = ce
        S.crystals[#S.crystals + 1] = { ent = ce, x = cc.x, y = cc.y, z = cc.z, lit = false }
    end

    S.cursor_ent = eng.scene.spawn("mirror_cursor")
    eng.scene.set_scale(S.cursor_ent, 0.35, 0.35, 0.35)
    eng.scene.set_mesh(S.cursor_ent, S.sphere_mesh, { color = {1.0, 0.9, 0.25, 1.0} })
    S.ents[#S.ents + 1] = S.cursor_ent

    trace_lasers()
    eng.camera.look_at(-1.0, 10.5, 9.5, 0.0, 1.8, -1.0, 0)
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.012 })
    eng.render.set_sky(0.05, 0.07, 0.16, 0.16, 0.12, 0.26)
    eng.render.add_light({ type = "dir", dir = {-0.3, -1.0, -0.4}, color = {1.9, 1.95, 2.1}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 5.5, -1.0}, color = {2.2, 0.8, 1.4}, range = 26.0 })

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.sphere_mesh = eng.asset.sphere(0.5, 10, 14)
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.sfx_rot = eng.audio.synth("square", 420, 0.07, 560)
    S.sfx_clear = eng.audio.synth("sine", 540, 0.24, 980)

    S.rotations = 0
    S.raycast_calls = 0
    S.last_bounces = 0
    S.won = false
    build_stage(1)
    eng.mod.emit("post_init")
end

function update(dt)
    (void_dt_noop or function() end)(dt)
    if S.won then return end

    local changed = false
    if eng.input.pressed("left") then
        S.sel_idx = ((S.sel_idx - 2) % #S.mirrors) + 1
        changed = true
    elseif eng.input.pressed("right") then
        S.sel_idx = (S.sel_idx % #S.mirrors) + 1
        changed = true
    elseif eng.input.pressed("fire") then
        local m = S.mirrors[S.sel_idx]
        m.state = (m.state + 1) % 4
        apply_mirror_rot(m)
        S.rotations = S.rotations + 1
        eng.audio.play(S.sfx_rot, m.x, m.y, m.z, 0)
        changed = true
    end

    if changed then
        trace_lasers()
        if S.lit_crystals == #S.crystals then
            eng.audio.play(S.sfx_clear, 0.0, 2.0, 0.0, 0)
            if S.stage < 2 then
                eng.save.write("mirror_laser_cube", "stage_2")
                build_stage(S.stage + 1)
            else
                S.won = true
                eng.save.write("mirror_laser_cube", "clear")
            end
        end
    end
end

function draw()
    local x, y = eng.ui.anchor("top_left", 16, 14, 480, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | CHAMBER " .. S.stage .. "/2 | CRYSTALS " .. S.lit_crystals .. "/" .. #S.crystals, 1.0, {0.5, 0.95, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 200, S.lit_crystals / math.max(1, #S.crystals), "BEAM  ")
end
