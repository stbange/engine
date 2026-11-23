-- 055_orbital_station_sim: Bigger-on-the-inside orbital habitat pods, solar/O2 balance & crew
local S = game.state

local function spawn_astronaut(pocket_name, x, z, seed)
    local pid = eng.scene.register_pocket(pocket_name)
    local ent = eng.scene.spawn("astronaut_" .. tostring(#S.crew + 1))
    eng.scene.set_pocket(ent, pid)
    eng.scene.set_pos(ent, x, 0.0, z)
    local info = eng.procgen.person(ent, seed)
    S.crew[#S.crew + 1] = { ent = ent, pocket = pid, x = x, z = z, phase = seed * 0.7, name = info.name }
    return info
end

local function add_station_module()
    local idx = S.modules_built + 1
    S.modules_built = idx
    if (idx % 2) == 1 then
        -- Deploy exterior 3D Solar Array Wing along orbital truss
        S.solar_lvl = S.solar_lvl + 1
        local side = ((S.solar_lvl % 2) == 1) and -1.0 or 1.0
        local wing = eng.scene.spawn("solar_wing_" .. tostring(idx))
        eng.scene.set_pocket(wing, 0)
        eng.scene.set_pos(wing, side * (8.5 + S.solar_lvl * 1.4), 1.2, -1.0 + (S.solar_lvl % 3) * 2.2)
        eng.scene.set_scale(wing, 2.4, 0.12, 4.6)
        eng.scene.set_mesh(wing, S.box_mesh, { tex = S.panel_tex, color = {0.18, 0.52, 0.98, 1.0}, metallic = 0.8, roughness = 0.25 })
    else
        -- Deploy Hydroponic Bio-Scrubber inside Bigger-on-the-Inside Hydroponics Pod
        S.hydro_lvl = S.hydro_lvl + 1
        local vat = eng.scene.spawn("hydro_scrubber_" .. tostring(idx))
        eng.scene.set_pocket(vat, S.pods[1].pocket_id)
        eng.scene.set_pos(vat, -6.0 + S.hydro_lvl * 2.8, 0.0, -4.5)
        eng.scene.set_mesh(vat, S.tree_mesh, { color = {0.25, 0.95, 0.48, 1.0}, cast_shadow = true })
    end
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.006 })
    eng.render.set_sky(0.02, 0.03, 0.08, 0.06, 0.12, 0.24)
    eng.render.add_light({ type = "dir", dir = {-0.45, -0.9, -0.35}, color = {2.3, 2.2, 2.05}, shadow = true })
    eng.render.add_light({ type = "point", pocket = "world", pos = {0.0, 6.0, 0.0}, color = {1.3, 1.8, 2.4}, range = 28.0 })

    local seed_base = math.floor(eng.math.range(100, 900000))
    S.seed_base = seed_base
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.tree_mesh = eng.procgen.tree(seed_base + 31, 2, 2.8, 0.20)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    S.panel_tex = eng.procgen.texture("sci_fi_panel", seed_base, 64)

    S.sfx_build = eng.audio.synth("square", 340, 0.14, 680)
    S.sfx_crew = eng.audio.synth("triangle", 520, 0.16, 860)
    S.sfx_portal = eng.audio.synth("sine", 300, 0.20, 540)

    -- Exterior Orbital Spine Walk-Deck
    local spine = eng.scene.spawn("orbital_spine_deck")
    eng.scene.set_pos(spine, 0.0, -0.25, 0.0)
    eng.scene.set_scale(spine, 22.0, 0.5, 16.0)
    eng.scene.set_mesh(spine, S.box_mesh, { tex = S.panel_tex, color = {0.55, 0.62, 0.72, 1.0} })

    -- Distant Earth-like planet below orbital deck
    local planet_mesh = eng.procgen.planet(seed_base + 3, 9.0, 14, 0.0)
    local earth = eng.scene.spawn("planet_below")
    eng.scene.set_pos(earth, 0.0, -16.0, -18.0)
    eng.scene.set_mesh(earth, planet_mesh, { roughness = 0.8 })

    -- 3 Bigger-on-the-Inside Habitat Pods (3m exterior airlocks -> 22m x 8m x 24m pocket decks!)
    local pod_defs = {
        { name = "pod_hydro", pos = {-6.0, 0.0, -5.5}, ext_col = {0.25, 0.75, 0.48, 1.0}, int_col = {0.20, 0.42, 0.30, 1.0}, lcol = {1.4, 2.4, 1.6} },
        { name = "pod_solar", pos = { 0.0, 0.0, -6.0}, ext_col = {0.28, 0.58, 0.92, 1.0}, int_col = {0.22, 0.34, 0.52, 1.0}, lcol = {1.5, 2.0, 2.6} },
        { name = "pod_crew",  pos = { 6.0, 0.0, -5.5}, ext_col = {0.88, 0.68, 0.26, 1.0}, int_col = {0.42, 0.36, 0.28, 1.0}, lcol = {2.4, 2.0, 1.5} }
    }
    S.pods = {}
    for i = 1, #pod_defs do
        local pd = pod_defs[i]
        eng.render.add_light({ type = "point", pocket = pd.name, pos = {0.0, 5.5, 0.0}, color = pd.lcol, range = 32.0 })
        local built = eng.space.create_pocket_building(eng, {
            exterior_pos = pd.pos,
            exterior_size = {3.2, 3.0, 3.2},
            interior_size = {22.0, 8.0, 24.0},
            door_size = {1.5, 2.3},
            pocket = pd.name,
            mesh_id = S.box_mesh,
            exterior_color = pd.ext_col,
            interior_color = pd.int_col
        })
        -- Interior centerpiece well away from doorway (z = -3.5 vs doorway z = +11.8)
        local core = eng.scene.spawn(pd.name .. "_core")
        eng.scene.set_pocket(core, built.pocket_id)
        eng.scene.set_pos(core, 0.0, 0.0, -3.5)
        eng.scene.set_scale(core, 1.6, 1.8, 1.6)
        eng.scene.set_mesh(core, (i == 1) and S.tree_mesh or S.crystal_mesh, { color = pd.ext_col, cast_shadow = true })
        S.pods[i] = built
    end

    -- Player Commander Avatar + Initial Crew via eng.procgen.person
    S.crew = {}
    spawn_astronaut("pod_hydro", -2.5, -2.0, seed_base + 101)
    spawn_astronaut("pod_solar",  2.5, -2.0, seed_base + 102)
    spawn_astronaut("world",     -3.0,  2.0, seed_base + 103)

    S.px, S.py, S.pz = 0.0, 0.0, 3.5
    S.pocket = 0
    S.cmd_ent = eng.scene.spawn("commander")
    eng.scene.set_pos(S.cmd_ent, S.px, 0.0, S.pz)
    eng.procgen.person(S.cmd_ent, seed_base + 77)

    S.oxygen = 62.0
    S.power = 62.0
    S.readiness = 20.0
    S.solar_lvl = 1
    S.hydro_lvl = 1
    S.modules_built = 0
    S.pods_visited = 0
    S.act_cd = 0.0
    S.won = false
    S.lost = false

    add_station_module()
    eng.camera.look_at(0.0, 12.5, 13.0, 0.0, 1.2, -4.0, 0)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won or S.lost then return end
    S.act_cd = math.max(0.0, S.act_cd - dt)

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    if math.abs(mx) > 0.01 or math.abs(my) > 0.01 then
        local nx = eng.math.clamp(S.px + mx * 9.5 * dt, -9.5, 9.5)
        local nz = eng.math.clamp(S.pz - my * 9.5 * dt, -9.5, 11.2)
        local dst_pk, wx, _, wz = eng.portal.check_crossing(S.pocket, S.px, 1.1, S.pz, nx, 1.1, nz)
        if dst_pk then
            S.pocket = dst_pk
            S.px, S.pz = wx, wz
            if dst_pk ~= 0 then S.pods_visited = S.pods_visited + 1 end
            eng.scene.set_pocket(S.cmd_ent, S.pocket)
            eng.audio.play(S.sfx_portal, S.px, 1.2, S.pz, S.pocket)
        else
            S.px, S.pz = nx, nz
        end
        eng.scene.set_pos(S.cmd_ent, S.px, 0.0, S.pz)
        eng.scene.set_rot_deg(S.cmd_ent, 0.0, math.deg(math.atan2(-mx, my)), 0.0)
    end

    -- Fire: Construct Solar Array / Hydroponic O2 Scrubber module
    if (eng.input.pressed("fire") or eng.input.down("fire")) and S.act_cd <= 0.0 and S.modules_built < 8 then
        S.act_cd = 0.22
        add_station_module()
        S.readiness = math.min(100.0, S.readiness + 12.0)
        eng.audio.play(S.sfx_build, S.px, 1.2, S.pz, S.pocket)
    end

    -- Interact: Recruit & assign procedural Astronaut to habitat pod + boost readiness
    if (eng.input.pressed("interact") or eng.input.down("interact")) and S.act_cd <= 0.0 then
        S.act_cd = 0.26
        if #S.crew < 6 then
            local pod_names = { "pod_hydro", "pod_solar", "pod_crew" }
            local p_name = pod_names[(#S.crew % 3) + 1]
            spawn_astronaut(p_name, -3.5 + (#S.crew % 3) * 3.5, -1.5, S.seed_base + 200 + #S.crew)
        end
        S.oxygen = math.min(100.0, S.oxygen + 8.0)
        S.power = math.min(100.0, S.power + 8.0)
        S.readiness = math.min(100.0, S.readiness + 14.0)
        eng.audio.play(S.sfx_crew, S.px, 1.2, S.pz, S.pocket)
    end

    --Gentle patrol movement for crew NPCs inside their pockets
    for i = 1, #S.crew do
        local c = S.crew[i]
        c.phase = c.phase + dt * 1.8
        eng.scene.set_pos(c.ent, c.x + math.sin(c.phase) * 0.8, 0.0, c.z + math.cos(c.phase) * 0.5)
    end

    -- Life support & power simulation balance
    local o2_net = S.hydro_lvl * 6.5 - #S.crew * 2.1
    local pwr_net = S.solar_lvl * 7.0 - (2.5 + S.hydro_lvl * 1.6)
    S.oxygen = eng.math.clamp(S.oxygen + o2_net * dt, 0.0, 100.0)
    S.power = eng.math.clamp(S.power + pwr_net * dt, 0.0, 100.0)

    if S.oxygen >= 70.0 and S.power >= 70.0 and #S.crew >= 5 then
        S.readiness = math.min(100.0, S.readiness + 18.0 * dt)
    end

    if S.oxygen <= 0.0 or S.power <= 0.0 then
        S.lost = true
        eng.save.write("orbital_station_status", "failure")
    elseif S.readiness >= 100.0 and S.oxygen >= 75.0 and S.power >= 75.0 and #S.crew >= 5 and S.pods_visited >= 1 then
        S.won = true
        eng.save.write("orbital_station_status", "operational")
    end

    if S.pocket == 0 then
        eng.camera.look_at(0.0, 12.5, 13.0, 0.0, 1.2, -4.0, 0)
    else
        eng.camera.look_at(S.px * 0.4, 5.8, S.pz + 7.5, 0.0, 1.2, -3.5, S.pocket)
    end
end

function draw()
    if S.pocket == 0 then
        eng.render.draw_sprite(-6.0, 3.8, -5.5, 0.7, 0.7, S.orb_tex)
        eng.render.draw_sprite( 0.0, 3.8, -6.0, 0.7, 0.7, S.orb_tex)
        eng.render.draw_sprite( 6.0, 3.8, -5.5, 0.7, 0.7, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 560, 88, 1280, 720)
    local loc = (S.pocket == 0) and "EXTERIOR SPINE" or ("HABITAT POD #" .. tostring(S.pocket))
    local status = S.won and (" | " .. eng.i18n.t("victory")) or ""
    eng.ui.label(x, y, eng.i18n.t("title") .. " | " .. loc .. " | CREW: " .. #S.crew .. status, 1.0, {0.80, 0.95, 1.0, 1.0})
    eng.ui.bar(x, y + 22, 220, S.oxygen / 100.0,    "OXYGEN ")
    eng.ui.bar(x, y + 42, 220, S.power / 100.0,     "SOLAR  ")
    eng.ui.bar(x, y + 62, 220, S.readiness / 100.0, "READY  ")
end
