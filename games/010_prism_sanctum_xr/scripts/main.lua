-- 010_prism_sanctum_xr: 3-Chamber 6DoF WebXR Cross-Portal Laser & Prism Puzzle
local S = game.state
local SQ = math.sqrt(0.5)

-- 4 discrete 45-degree 3D mirror/prism orientations (2 horizontal + 2 vertical 3D elevation prisms)
local MIRROR_MODES = {
    { nx = SQ,  ny = 0.0, nz = SQ,  rot = {0.0, 45.0, 0.0}   }, -- +X <-> -Z
    { nx = SQ,  ny = 0.0, nz = -SQ, rot = {0.0, 135.0, 0.0}  }, -- +X <-> +Z, -Z <-> -X
    { nx = SQ,  ny = -SQ, nz = 0.0, rot = {0.0, 0.0, -45.0}  }, -- +X -> +Y (upward refraction)
    { nx = 0.0, ny = SQ,  nz = SQ,  rot = {45.0, 0.0, 0.0}   }, -- +Y -> -Z (elevated portal beam)
}

local function clear_chamber_ents()
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
        local b = eng.scene.spawn("sanctum_beam_" .. tostring(idx))
        eng.scene.set_mesh(b, S.box_mesh, { color = {0.25, 0.95, 1.0, 1.0} })
        S.ents[#S.ents + 1] = b
        S.beams[idx] = b
    end
    return S.beams[idx]
end

local function set_beam_segment(idx, pocket_id, x0, y0, z0, x1, y1, z1)
    local b = ensure_beam_ent(idx)
    eng.scene.set_pocket(b, pocket_id)
    eng.scene.set_pos(b, (x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
    eng.scene.set_scale(b, math.max(0.10, math.abs(x1 - x0)), math.max(0.10, math.abs(y1 - y0)), math.max(0.10, math.abs(z1 - z0)))
end

local function trace_lasers()
    for i = 1, #S.crystals do S.crystals[i].lit = false end

    local cur_pk = 0
    local ox = S.emit.x + S.emit.dx * 0.55
    local oy = S.emit.y + S.emit.dy * 0.55
    local oz = S.emit.z + S.emit.dz * 0.55
    local dx, dy, dz = S.emit.dx, S.emit.dy, S.emit.dz
    local seg_count = 0

    for step = 1, 8 do
        local hit = eng.physics.raycast(cur_pk, ox, oy, oz, dx, dy, dz, 60.0)
        S.raycast_calls = S.raycast_calls + 1

        if hit and hit.portal_hops and hit.portal_hops >= 1 then
            -- Render outer beam entering portal threshold + inner beam inside pocket chamber(s)
            seg_count = seg_count + 1
            set_beam_segment(seg_count, cur_pk, ox, oy, oz, ox, oy, -3.8)
            if hit.portal_hops >= 2 then
                seg_count = seg_count + 1
                set_beam_segment(seg_count, S.shrine_3.pocket_id, 0.0, oy, 7.8, 0.0, oy, -2.8)
            end
            seg_count = seg_count + 1
            local entry_z = (hit.portal_hops >= 2) and 6.8 or 7.8
            set_beam_segment(seg_count, hit.pocket_id, 0.0, oy, entry_z, hit.point[1], hit.point[2], hit.point[3])
        else
            local hx = hit and hit.point[1] or (ox + dx * 10.0)
            local hy = hit and hit.point[2] or (oy + dy * 10.0)
            local hz = hit and hit.point[3] or (oz + dz * 10.0)
            seg_count = seg_count + 1
            set_beam_segment(seg_count, cur_pk, ox, oy, oz, hx, hy, hz)
        end

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
            if (hit.portal_hops or 0) >= 1 then
                S.portal_laser_hits = S.portal_laser_hits + 1
                if hit.portal_hops > S.max_portal_hops then S.max_portal_hops = hit.portal_hops end
            end
            break
        elseif hit_mirror then
            local md = MIRROR_MODES[hit_mirror.state + 1]
            local dot = dx * md.nx + dy * md.ny + dz * md.nz
            if math.abs(dot) < 0.15 then break end
            dx = dx - 2.0 * dot * md.nx
            dy = dy - 2.0 * dot * md.ny
            dz = dz - 2.0 * dot * md.nz
            cur_pk = hit.pocket_id
            ox = hit_mirror.x + dx * 0.58
            oy = hit_mirror.y + dy * 0.58
            oz = hit_mirror.z + dz * 0.58
        else
            break
        end
    end

    for i = seg_count + 1, #S.beams do
        eng.scene.set_pocket(S.beams[i], 0)
        eng.scene.set_pos(S.beams[i], 0.0, -8.0, 0.0)
        eng.scene.set_scale(S.beams[i], 0.1, 0.1, 0.1)
    end

    local lit_n = 0
    for i = 1, #S.crystals do
        local c = S.crystals[i]
        if c.lit then
            lit_n = lit_n + 1
            eng.scene.set_mesh(c.ent, S.crystal_mesh, { color = {0.25, 1.0, 0.78, 1.0} })
        else
            eng.scene.set_mesh(c.ent, S.crystal_mesh, { color = {0.42, 0.48, 0.72, 1.0} })
        end
    end
    S.lit_crystals = lit_n

    local sel = S.mirrors[S.sel_idx]
    if sel and S.cursor_ent then
        eng.scene.set_pos(S.cursor_ent, sel.x, sel.y + 0.85, sel.z)
    end
end

local function build_chamber(idx)
    clear_chamber_ents()
    S.chamber = idx
    S.sel_idx = 1

    local m_cfg, c_cfg
    if idx == 1 then
        -- Chamber 1: Single mirror pedestal -> Shrine 1 ("amber_vault", 1 portal hop)
        S.emit = { x = -6.8, y = 1.0, z = 1.5, dx = 1.0, dy = 0.0, dz = 0.0 }
        m_cfg = {
            { x = -4.0, y = 1.0, z = 1.5, state = 3 }, -- 1 press -> state 0 (+X -> -Z through Shrine 1)
        }
        c_cfg = {
            { pocket = S.shrine_1.pocket_id, x = 0.0, y = 1.0, z = -3.0 },
        }
    elseif idx == 2 then
        -- Chamber 2: 3-pedestal horizontal S-bend -> Shrine 2 ("cyan_vault", 1 portal hop)
        S.emit = { x = -6.8, y = 1.0, z = 2.8, dx = 1.0, dy = 0.0, dz = 0.0 }
        m_cfg = {
            { x = -2.0, y = 1.0, z = 2.8, state = 3 }, -- 1 press -> state 0 (+X -> -Z)
            { x = -2.0, y = 1.0, z = 0.2, state = 3 }, -- 1 press -> state 0 (-Z -> +X)
            { x =  0.0, y = 1.0, z = 0.2, state = 3 }, -- 1 press -> state 0 (+X -> -Z through Shrine 2)
        }
        c_cfg = {
            { pocket = S.shrine_2.pocket_id, x = 0.0, y = 1.0, z = -3.0 },
        }
    else
        -- Chamber 3: 3D vertical prism elevation -> Shrine 3 -> Nested Inner Core (2 portal hops!)
        S.emit = { x = 0.5, y = 0.65, z = 1.5, dx = 1.0, dy = 0.0, dz = 0.0 }
        m_cfg = {
            { x = 4.0, y = 0.65, z = 1.5, state = 1 }, -- 1 press -> state 2 (+X -> +Y upward)
            { x = 4.0, y = 1.65, z = 1.5, state = 2 }, -- 1 press -> state 3 (+Y -> -Z through 2 nested portals!)
        }
        c_cfg = {
            { pocket = S.inner_core.pocket_id, x = 0.0, y = 1.45, z = -2.5 },
        }
    end

    local em = eng.scene.spawn("prism_emitter")
    eng.scene.set_pocket(em, 0)
    eng.scene.set_pos(em, S.emit.x, S.emit.y, S.emit.z)
    eng.scene.set_scale(em, 0.85, 1.1, 0.85)
    eng.scene.set_mesh(em, S.box_mesh, { color = {0.25, 0.85, 1.0, 1.0}, cast_shadow = true })
    S.ents[#S.ents + 1] = em

    for i = 1, #m_cfg do
        local mc = m_cfg[i]
        if mc.y <= 1.1 then
            local ped = eng.scene.spawn("mirror_pedestal_" .. tostring(i))
            eng.scene.set_pocket(ped, 0)
            eng.scene.set_pos(ped, mc.x, 0.0, mc.z)
            eng.scene.set_scale(ped, 0.55, math.max(0.15, (mc.y - 0.35) / 3.0), 0.55)
            eng.scene.set_mesh(ped, S.pillar_mesh, { color = {0.65, 0.68, 0.78, 1.0} })
            S.ents[#S.ents + 1] = ped
        end

        local me = eng.scene.spawn("prism_mirror_" .. tostring(i))
        eng.scene.set_pocket(me, 0)
        eng.scene.set_pos(me, mc.x, mc.y, mc.z)
        eng.scene.set_scale(me, 0.82, 0.82, 0.18)
        eng.scene.set_mesh(me, S.box_mesh, { color = {0.86, 0.94, 1.0, 1.0}, metallic = 0.95, roughness = 0.08, cast_shadow = true })
        eng.physics.add_body(me, { shape = "sphere", motion = "static", pocket = 0, radius = 0.44 })
        S.ents[#S.ents + 1] = me

        local m = { ent = me, x = mc.x, y = mc.y, z = mc.z, state = mc.state }
        apply_mirror_rot(m)
        S.mirrors[#S.mirrors + 1] = m
    end

    for i = 1, #c_cfg do
        local cc = c_cfg[i]
        local ce = eng.scene.spawn("pocket_receptor_" .. tostring(i))
        eng.scene.set_pocket(ce, cc.pocket)
        eng.scene.set_pos(ce, cc.x, cc.y - 0.35, cc.z)
        eng.scene.set_scale(ce, 1.1, 1.1, 1.1)
        eng.scene.set_mesh(ce, S.crystal_mesh, { color = {0.42, 0.48, 0.72, 1.0}, cast_shadow = true })
        eng.physics.add_body(ce, { shape = "aabb", motion = "static", pocket = cc.pocket, half_extents = {0.5, 0.65, 0.5} })
        S.ents[#S.ents + 1] = ce
        S.crystals[#S.crystals + 1] = { ent = ce, pocket = cc.pocket, x = cc.x, y = cc.y, z = cc.z, lit = false }
    end

    S.cursor_ent = eng.scene.spawn("pedestal_cursor")
    eng.scene.set_pocket(S.cursor_ent, 0)
    eng.scene.set_scale(S.cursor_ent, 0.34, 0.34, 0.34)
    eng.scene.set_mesh(S.cursor_ent, S.sphere_mesh, { color = {1.0, 0.92, 0.30, 1.0} })
    S.ents[#S.ents + 1] = S.cursor_ent

    trace_lasers()
    eng.camera.look_at(S.px, S.py, S.pz, 0.0, 1.3, -4.2, 0)
end

function init()
    eng.xr.set_mode("6dof")
    eng.render.set_sky(0.04, 0.08, 0.20, 0.16, 0.22, 0.38)

    eng.render.add_light({ type = "dir", pocket = "world", dir = {-0.3, -1.0, -0.4}, color = {2.0, 2.05, 2.2}, shadow = true })
    eng.render.add_light({ type = "point", pocket = "world", pos = {0.0, 5.5, 1.0}, color = {1.6, 2.0, 2.6}, range = 26.0 })
    eng.render.add_light({ type = "point", pocket = "amber_vault", pos = {0.0, 4.5, 0.0}, color = {2.6, 1.9, 1.1}, range = 22.0 })
    eng.render.add_light({ type = "point", pocket = "cyan_vault", pos = {0.0, 4.5, 0.0}, color = {1.1, 2.3, 2.8}, range = 22.0 })
    eng.render.add_light({ type = "point", pocket = "violet_vault", pos = {0.0, 4.5, 0.0}, color = {2.2, 1.3, 2.8}, range = 22.0 })
    eng.render.add_light({ type = "point", pocket = "inner_core", pos = {0.0, 4.0, 0.0}, color = {1.4, 2.8, 2.2}, range = 20.0 })

    S.seed = math.floor(eng.math.range(100, 90000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.sphere_mesh = eng.asset.sphere(0.5, 10, 14)
    S.pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    local marble_tex = eng.procgen.texture("marble", S.seed, 64)

    S.sfx_rot = eng.audio.synth("triangle", 480, 0.08, 680)
    S.sfx_clear = eng.audio.synth("sine", 560, 0.24, 1120)

    -- Central 6DoF WebXR Sanctum Platform
    local floor_e = eng.scene.spawn("sanctum_plaza")
    eng.scene.set_pocket(floor_e, "world")
    eng.scene.set_pos(floor_e, 0.0, -0.25, 0.0)
    eng.scene.set_scale(floor_e, 22.0, 0.5, 18.0)
    eng.scene.set_mesh(floor_e, S.box_mesh, { tex = marble_tex, color = {0.34, 0.38, 0.48, 1.0} })
    eng.physics.add_body(floor_e, { shape = "aabb", motion = "static", pocket = 0, half_extents = {11.0, 0.25, 9.0} })

    -- 3 Bigger-on-the-Inside Pocket Portal Shrines + 1 Nested Inner Core Portal
    S.shrine_1 = eng.space.create_pocket_building(eng, {
        outer_pocket = "world", pocket = "amber_vault",
        exterior_pos = {-4.0, 0.0, -5.0}, exterior_size = {2.4, 2.8, 2.4},
        interior_size = {14.0, 6.0, 16.0}, door_size = {1.4, 2.2},
        exterior_color = {0.72, 0.52, 0.24, 1.0}, interior_color = {0.42, 0.32, 0.20, 1.0},
        mesh_id = S.box_mesh
    })
    S.shrine_2 = eng.space.create_pocket_building(eng, {
        outer_pocket = "world", pocket = "cyan_vault",
        exterior_pos = {0.0, 0.0, -5.0}, exterior_size = {2.4, 2.8, 2.4},
        interior_size = {14.0, 6.0, 16.0}, door_size = {1.4, 2.2},
        exterior_color = {0.22, 0.56, 0.76, 1.0}, interior_color = {0.18, 0.34, 0.46, 1.0},
        mesh_id = S.box_mesh
    })
    S.shrine_3 = eng.space.create_pocket_building(eng, {
        outer_pocket = "world", pocket = "violet_vault",
        exterior_pos = {4.0, 0.0, -5.0}, exterior_size = {2.4, 2.8, 2.4},
        interior_size = {14.0, 6.0, 16.0}, door_size = {1.4, 2.2},
        exterior_color = {0.54, 0.28, 0.76, 1.0}, interior_color = {0.32, 0.20, 0.46, 1.0},
        mesh_id = S.box_mesh
    })
    S.inner_core = eng.space.create_pocket_building(eng, {
        outer_pocket = "violet_vault", pocket = "inner_core",
        exterior_pos = {0.0, 0.0, -4.0}, exterior_size = {2.4, 2.8, 2.4},
        interior_size = {12.0, 5.5, 14.0}, door_size = {1.4, 2.2},
        exterior_color = {0.25, 0.75, 0.62, 1.0}, interior_color = {0.18, 0.42, 0.38, 1.0},
        mesh_id = S.box_mesh
    })

    S.px, S.py, S.pz = 0.0, 2.8, 6.8
    S.rotations = 0
    S.raycast_calls = 0
    S.portal_laser_hits = 0
    S.max_portal_hops = 0
    S.won = false

    build_chamber(1)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end

    -- Optional 6DoF / desktop forward-back inspection walk
    local _, iy = eng.input.axis2d("left", "right", "down", "up")
    if math.abs(iy) > 0.01 then
        S.pz = eng.math.clamp(S.pz - iy * 5.0 * dt, 3.8, 8.2)
        eng.camera.look_at(S.px, S.py, S.pz, 0.0, 1.3, -4.2, 0)
    end

    local changed = false
    if eng.input.pressed("left") then
        S.sel_idx = ((S.sel_idx - 2) % #S.mirrors) + 1
        changed = true
    elseif eng.input.pressed("right") then
        S.sel_idx = (S.sel_idx % #S.mirrors) + 1
        changed = true
    elseif eng.input.pressed("fire") or eng.input.pressed("interact") then
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
            eng.audio.play(S.sfx_clear, 0.0, 2.0, -3.5, 0)
            if S.chamber < 3 then
                eng.save.write("prism_sanctum_xr", "chamber_" .. tostring(S.chamber + 1))
                build_chamber(S.chamber + 1)
            else
                S.won = true
                eng.save.write("prism_sanctum_xr", "clear")
            end
        end
    end
end

function draw()
    local x, y = eng.ui.anchor("top_left", 16, 14, 580, 56, 1280, 720)
    local msg = S.won and eng.i18n.t("victory") or
        (eng.i18n.t("title") .. " | " .. eng.i18n.t("chamber") .. " " .. S.chamber .. "/3 | PORTAL HOPS " .. S.max_portal_hops)
    eng.ui.label(x, y, msg, 1.0, {0.55, 0.95, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 220, S.won and 1.0 or ((S.chamber - 1) / 3.0), "PRISM ")
end
