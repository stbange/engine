-- 063_gravity_flip_rooms: Rotate room gravity along all 6 cardinal axes (eng.physics.set_gravity)
local S = game.state
local G_MAG = 30.0

local AXES = {
    left  = { id = "-X", gx = -G_MAG, gy = 0.0,    gz = 0.0    },
    right = { id = "+X", gx =  G_MAG, gy = 0.0,    gz = 0.0    },
    down  = { id = "-Y", gx = 0.0,    gy = -G_MAG, gz = 0.0    },
    up    = { id = "+Y", gx = 0.0,    gy =  G_MAG, gz = 0.0    },
    fire  = { id = "-Z", gx = 0.0,    gy = 0.0,    gz = -G_MAG },
    jump  = { id = "+Z", gx = 0.0,    gy = 0.0,    gz =  G_MAG },
}

local function clear_stage()
    if S.ents then
        for i = 1, #S.ents do eng.scene.despawn(S.ents[i]) end
    end
    S.ents = {}
end

local function spawn_wall(name, px, py, pz, hx, hy, hz, visible, color, tex)
    local e = eng.scene.spawn(name)
    eng.scene.set_pos(e, px, py, pz)
    eng.scene.set_scale(e, hx * 2.0, hy * 2.0, hz * 2.0)
    if visible then
        eng.scene.set_mesh(e, S.box_mesh, { tex = tex, color = color, cast_shadow = true })
    end
    eng.physics.add_body(e, { shape = "aabb", motion = "static", half_extents = {hx, hy, hz} })
    S.ents[#S.ents + 1] = e
    return e
end

local function apply_gravity(ax)
    S.cur_axis = ax.id
    if not S.axes_seen[ax.id] then
        S.axes_seen[ax.id] = true
        S.axes_count = S.axes_count + 1
    end
    S.flips = S.flips + 1
    eng.physics.set_vel(S.cube_body, 0.0, 0.0, 0.0)
    eng.physics.set_gravity(0, ax.gx, ax.gy, ax.gz)
    eng.audio.play(S.sfx_flip, 0.0, 5.0, 0.0, 0)
end

local function build_stage(idx)
    clear_stage()
    S.stage = idx
    S.cur_axis = "-Y"
    eng.physics.set_gravity(0, 0.0, -G_MAG, 0.0)

    local seed_base = math.floor(eng.math.range(100, 7000)) + idx * 71
    local panel_tex = eng.procgen.texture("metal_rivets", seed_base, 64)

    -- 8x8x8 interior cube: x in [-4, 4], y in [1, 9], z in [-4, 4] (South +Z wall invisible glass for diorama camera)
    spawn_wall("room_floor",   0.0,  0.5,  0.0, 4.5, 0.5, 4.5, true,  {0.28, 0.34, 0.44, 1.0}, panel_tex)
    spawn_wall("room_ceiling", 0.0,  9.5,  0.0, 4.5, 0.5, 4.5, true,  {0.34, 0.30, 0.46, 1.0}, panel_tex)
    spawn_wall("room_west",   -4.5,  5.0,  0.0, 0.5, 4.5, 4.5, true,  {0.38, 0.28, 0.34, 1.0}, panel_tex)
    spawn_wall("room_east",    4.5,  5.0,  0.0, 0.5, 4.5, 4.5, true,  {0.28, 0.38, 0.36, 1.0}, panel_tex)
    spawn_wall("room_north",   0.0,  5.0, -4.5, 4.5, 4.5, 0.5, true,  {0.30, 0.32, 0.42, 1.0}, panel_tex)
    spawn_wall("room_south",   0.0,  5.0,  4.5, 4.5, 4.5, 0.5, false, nil, nil)

    local start_pos
    if idx == 1 then
        start_pos = {2.0, 1.50, 0.0}
        spawn_wall("baffle_1", -1.5,  1.5, 0.0, 0.5, 0.5, 1.0, true, {0.65, 0.58, 0.42, 1.0}, panel_tex)
        spawn_wall("baffle_2", -0.55, 7.5, 0.0, 0.6, 0.5, 1.0, true, {0.65, 0.58, 0.42, 1.0}, panel_tex)
        S.latch = nil
        S.socket = { x = 3.55, y = 6.55, z = 0.0 }
    else
        start_pos = {0.0, 1.50, 0.0}
        spawn_wall("baffle_3", 0.0, 3.0, 3.55, 0.8, 0.5, 0.8, true, {0.65, 0.58, 0.42, 1.0}, panel_tex)
        S.latch = { x = 0.0, y = 8.55, z = -3.55, unlocked = false }
        local le = eng.scene.spawn("ceiling_latch")
        eng.scene.set_pos(le, S.latch.x, S.latch.y - 0.35, S.latch.z)
        eng.scene.set_scale(le, 0.9, 0.9, 0.9)
        eng.scene.set_mesh(le, S.crystal_mesh, { color = {1.0, 0.35, 0.75, 1.0} })
        S.ents[#S.ents + 1] = le
        S.latch.ent = le
        S.socket = { x = 0.0, y = 3.95, z = 3.55 }
    end

    local sk = eng.scene.spawn("wall_socket")
    eng.scene.set_pos(sk, S.socket.x, S.socket.y, S.socket.z)
    eng.scene.set_scale(sk, 1.15, 0.25, 1.15)
    eng.scene.set_mesh(sk, S.box_mesh, { color = {0.25, 1.0, 0.55, 1.0} })
    S.ents[#S.ents + 1] = sk
    S.socket.ent = sk

    S.cube_ent = eng.scene.spawn("gravity_key_cube")
    eng.scene.set_pos(S.cube_ent, start_pos[1], start_pos[2], start_pos[3])
    eng.scene.set_scale(S.cube_ent, 0.9, 0.9, 0.9)
    eng.scene.set_mesh(S.cube_ent, S.crate_mesh, { color = {1.0, 0.82, 0.22, 1.0}, cast_shadow = true })
    S.cube_body = eng.physics.add_body(S.cube_ent, {
        shape = "aabb", motion = "dynamic", half_extents = {0.45, 0.45, 0.45}, restitution = 0.0
    })
    S.ents[#S.ents + 1] = S.cube_ent

    eng.camera.look_at(0.0, 5.2, 12.2, 0.0, 5.0, 0.0, 0)
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.01 })
    eng.render.set_sky(0.06, 0.08, 0.16, 0.14, 0.18, 0.28)
    eng.render.add_light({ type = "dir", dir = {-0.25, -0.7, -0.8}, color = {1.8, 1.85, 2.0}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 5.0, 2.0}, color = {2.2, 1.9, 1.4}, range = 24.0 })

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.crate_mesh = eng.asset.load_mesh("assets/shared/meshes/crate.obj")
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.sfx_flip = eng.audio.synth("saw", 260, 0.10, 420)
    S.sfx_lock = eng.audio.synth("triangle", 520, 0.22, 960)

    S.axes_seen = {}
    S.axes_count = 0
    S.flips = 0
    S.won = false
    build_stage(1)
    eng.mod.emit("post_init")
end

function update(dt)
    (void_dt_noop or function() end)(dt)
    if S.won then return end

    for act, ax in pairs(AXES) do
        if eng.input.pressed(act) then
            apply_gravity(ax)
            break
        end
    end

    local cx, cy, cz = eng.scene.get_pos(S.cube_ent)
    if S.latch and not S.latch.unlocked then
        if eng.math.dist3(cx, cy, cz, S.latch.x, S.latch.y, S.latch.z) < 0.70 then
            S.latch.unlocked = true
            eng.scene.set_mesh(S.latch.ent, S.crystal_mesh, { color = {0.25, 1.0, 0.9, 1.0} })
            eng.audio.play(S.sfx_lock, cx, cy, cz, 0)
        end
    end

    local latch_ok = (S.latch == nil) or S.latch.unlocked
    if latch_ok and eng.math.dist3(cx, cy, cz, S.socket.x, S.socket.y, S.socket.z) < 0.65 then
        local vx, vy, vz = eng.physics.get_vel(S.cube_body)
        if (vx * vx + vy * vy + vz * vz) < 4.0 then
            eng.audio.play(S.sfx_lock, cx, cy, cz, 0)
            if S.stage < 2 then
                eng.save.write("gravity_flip_rooms", "stage_2")
                build_stage(S.stage + 1)
            else
                S.won = true
                eng.save.write("gravity_flip_rooms", "clear")
            end
        end
    end
end

function draw()
    local x, y = eng.ui.anchor("top_left", 16, 14, 480, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | ROOM " .. S.stage .. "/2 | GRAVITY " .. S.cur_axis .. " | AXES " .. S.axes_count .. "/6", 1.0, {1.0, 0.88, 0.45, 1.0})
    eng.ui.bar(x, y + 26, 200, S.axes_count / 6.0, "6-AXIS ")
end
