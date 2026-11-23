-- One-call "Bigger on the Inside" Pocket Space & Doorway builders (eng.space)
local M = {}

function M.cut_wall_with_door(eng_root, pocket_name, wall_pos, wall_size, door_size, mesh_id, color)
    local parts = eng_root.portal.cut_doorway(wall_size[1], wall_size[2], wall_size[3], door_size[1], door_size[2])
    local pid = eng_root.scene.register_pocket(pocket_name or "world")
    local spawned = {}
    for i = 1, #parts do
        local b = parts[i]
        local cx = wall_pos[1] + (b.min[1] + b.max[1]) * 0.5
        local cy = wall_pos[2] + (b.min[2] + b.max[2]) * 0.5
        local cz = wall_pos[3] + (b.min[3] + b.max[3]) * 0.5
        local sx = b.max[1] - b.min[1]
        local sy = b.max[2] - b.min[2]
        local sz = b.max[3] - b.min[3]
        local e = eng_root.scene.spawn("door_wall_" .. tostring(i))
        eng_root.scene.set_pocket(e, pid)
        eng_root.scene.set_pos(e, cx, cy, cz)
        eng_root.scene.set_scale(e, sx, sy, sz)
        eng_root.scene.set_mesh(e, mesh_id, { color = color or {0.65, 0.62, 0.58, 1.0}, cast_shadow = true })
        eng_root.physics.add_body(e, { shape = "aabb", motion = "static", pocket = pid, half_extents = {sx * 0.5, sy * 0.5, sz * 0.5} })
        spawned[#spawned + 1] = e
    end
    return spawned
end

function M.create_pocket_building(eng_root, cfg)
    local ext_p = cfg.exterior_pos or {0, 0, -6}
    local ext_s = cfg.exterior_size or {3.0, 3.0, 3.0}
    local int_s = cfg.interior_size or {20.0, 8.0, 24.0}
    local door_s = cfg.door_size or {1.2, 2.2}
    local p_out = eng_root.scene.register_pocket(cfg.outer_pocket or "world")
    local p_in = eng_root.scene.register_pocket(cfg.pocket or "inside")
    local box_mesh = cfg.mesh_id or eng_root.asset.box(1, 1, 1)

    -- Exterior front wall split cleanly around doorway
    local front_z = ext_p[3] + ext_s[3] * 0.5
    M.cut_wall_with_door(eng_root, cfg.outer_pocket or "world",
                         {ext_p[1], ext_p[2], front_z}, {ext_s[1], ext_s[2], 0.2}, door_s, box_mesh, cfg.exterior_color)

    -- Exterior back/roof shell
    local shell = eng_root.scene.spawn((cfg.pocket or "hut") .. "_shell")
    eng_root.scene.set_pocket(shell, p_out)
    eng_root.scene.set_pos(shell, ext_p[1], ext_p[2] + ext_s[2] * 0.5, ext_p[3] - 0.15)
    eng_root.scene.set_scale(shell, ext_s[1], ext_s[2], ext_s[3] - 0.3)
    eng_root.scene.set_mesh(shell, box_mesh, { color = cfg.exterior_color or {0.6, 0.35, 0.22, 1.0}, cast_shadow = true })

    -- Oversized interior floor centered around (0, 0, 0) in isolated pocket
    local floor_e = eng_root.scene.spawn((cfg.pocket or "hut") .. "_floor")
    eng_root.scene.set_pocket(floor_e, p_in)
    eng_root.scene.set_pos(floor_e, 0.0, -0.25, 0.0)
    eng_root.scene.set_scale(floor_e, int_s[1], 0.5, int_s[3])
    eng_root.scene.set_mesh(floor_e, box_mesh, { color = cfg.interior_color or {0.35, 0.42, 0.52, 1.0} })
    eng_root.physics.add_body(floor_e, { shape = "aabb", motion = "static", pocket = p_in, half_extents = {int_s[1] * 0.5, 0.25, int_s[3] * 0.5} })

    -- Link exterior & interior portal entities
    local d_ext = eng_root.scene.spawn((cfg.pocket or "hut") .. "_door_ext")
    eng_root.scene.set_pocket(d_ext, p_out)
    eng_root.scene.set_pos(d_ext, ext_p[1], ext_p[2] + door_s[2] * 0.5, front_z)

    local d_int = eng_root.scene.spawn((cfg.pocket or "hut") .. "_door_int")
    eng_root.scene.set_pocket(d_int, p_in)
    eng_root.scene.set_pos(d_int, 0.0, door_s[2] * 0.5, int_s[3] * 0.5 - 0.2)
    eng_root.scene.set_rot_deg(d_int, 0.0, 180.0, 0.0)

    local portal_idx = eng_root.portal.link(d_ext, d_int, door_s[1], door_s[2], cfg.scale_ratio or 1.0, true, true)
    return { pocket_id = p_in, door_ext = d_ext, door_int = d_int, portal = portal_idx }
end

function M.attach_vehicle_interior(eng_root, vehicle_ent, cfg)
    local p_out = eng_root.scene.get_pocket(vehicle_ent)
    local p_in = eng_root.scene.register_pocket(cfg.pocket or "vehicle_cabin")
    local door_s = cfg.door_size or {1.1, 2.0}
    local int_s = cfg.interior_size or {12.0, 5.0, 18.0}
    local dlp = cfg.door_local_pos or {0.0, 1.0, 1.5}
    local box_mesh = cfg.mesh_id or eng_root.asset.box(1, 1, 1)

    local d_ext = eng_root.scene.spawn((cfg.pocket or "veh") .. "_hatch_ext")
    eng_root.scene.set_pocket(d_ext, p_out)
    eng_root.scene.set_parent(d_ext, vehicle_ent)
    eng_root.scene.set_pos(d_ext, dlp[1], dlp[2], dlp[3])

    local deck = eng_root.scene.spawn((cfg.pocket or "veh") .. "_deck")
    eng_root.scene.set_pocket(deck, p_in)
    eng_root.scene.set_pos(deck, 0.0, -0.25, 0.0)
    eng_root.scene.set_scale(deck, int_s[1], 0.5, int_s[3])
    eng_root.scene.set_mesh(deck, box_mesh, { color = {0.28, 0.32, 0.38, 1.0} })
    eng_root.physics.add_body(deck, { shape = "aabb", motion = "static", pocket = p_in, half_extents = {int_s[1] * 0.5, 0.25, int_s[3] * 0.5} })

    local d_int = eng_root.scene.spawn((cfg.pocket or "veh") .. "_hatch_int")
    eng_root.scene.set_pocket(d_int, p_in)
    eng_root.scene.set_pos(d_int, 0.0, door_s[2] * 0.5, int_s[3] * 0.5 - 0.2)
    eng_root.scene.set_rot_deg(d_int, 0.0, 180.0, 0.0)

    local pidx = eng_root.portal.link(d_ext, d_int, door_s[1], door_s[2], 1.0, true, true)
    return { pocket_id = p_in, door_ext = d_ext, door_int = d_int, portal = pidx }
end

return M
