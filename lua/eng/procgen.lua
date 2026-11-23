-- High-level deterministic Procedural Generation helpers (eng.procgen_ext)
local M = {}

function M.spawn_dungeon_entity(eng_root, cfg)
    local d = eng_root.procgen.dungeon(cfg.width or 24, cfg.height or 24, cfg.seed or 42, cfg.style or "bsp", cfg.tile_size or 2.0, cfg.wall_height or 3.0)
    local ent = eng_root.scene.spawn(cfg.name or "proc_dungeon")
    if cfg.pocket then eng_root.scene.set_pocket(ent, eng_root.scene.register_pocket(cfg.pocket)) end
    local tex = eng_root.procgen.texture(cfg.texture or "stone_brick", cfg.seed or 42, 64)
    eng_root.scene.set_mesh(ent, d.mesh_id, { tex = tex })
    d.entity = ent
    return d
end

function M.spawn_planet_entity(eng_root, cfg)
    local radius = cfg.radius or 30.0
    local pid = eng_root.scene.register_pocket(cfg.pocket or "world")
    local mesh_id = eng_root.procgen.planet(cfg.seed or 99, radius, cfg.subdivisions or 20, cfg.sea_level or 0.0)
    local ent = eng_root.scene.spawn(cfg.name or "proc_planet")
    eng_root.scene.set_pocket(ent, pid)
    eng_root.scene.set_mesh(ent, mesh_id, { roughness = 0.85 })
    eng_root.physics.set_planet_gravity(pid, 0.0, 0.0, 0.0, cfg.gravity or 9.81, cfg.seed or 99, radius)
    return { entity = ent, mesh_id = mesh_id, radius = radius, pocket_id = pid }
end

function M.spawn_creature(eng_root, cfg)
    local pos = cfg.pos or {0, 0, -4}
    local pid = eng_root.scene.register_pocket(cfg.pocket or "world")
    local ent = eng_root.scene.spawn(cfg.name or "creature")
    eng_root.scene.set_pocket(ent, pid)
    eng_root.scene.set_pos(ent, pos[1], pos[2], pos[3])
    local info = eng_root.procgen.animal(ent, cfg.seed or 7, cfg.archetype or "quadruped")
    info.entity = ent
    return info
end

function M.spawn_npc(eng_root, cfg)
    local pos = cfg.pos or {0, 0, -3}
    local pid = eng_root.scene.register_pocket(cfg.pocket or "world")
    local ent = eng_root.scene.spawn(cfg.name or "npc")
    eng_root.scene.set_pocket(ent, pid)
    eng_root.scene.set_pos(ent, pos[1], pos[2], pos[3])
    local info = eng_root.procgen.person(ent, cfg.seed or 11)
    info.entity = ent
    return info
end

return M
