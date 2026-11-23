-- 029_voxel_snake_3d: 3D snake slithering seamlessly across all 6 faces of a mini voxel planetoid
local S = game.state

local APPLE_TOUR = {
    { c = { 2,  0,  2}, n = { 0,  0,  1} }, -- Face +Z
    { c = { 2,  1,  0}, n = { 1,  0,  0} }, -- Face +X
    { c = { 0,  2, -1}, n = { 0,  1,  0} }, -- Face +Y
    { c = {-2,  0, -1}, n = {-1,  0,  0} }, -- Face -X
    { c = { 0, -1, -2}, n = { 0,  0, -1} }, -- Face -Z
    { c = { 0, -2,  1}, n = { 0, -1,  0} }  -- Face -Y
}

local function surf_world(c, n)
    return c[1] + n[1] * 0.86, c[2] + n[2] * 0.86, c[3] + n[3] * 0.86
end

local function cross3(a, b)
    return {
        a[2] * b[3] - a[3] * b[2],
        a[3] * b[1] - a[1] * b[3],
        a[1] * b[2] - a[2] * b[1]
    }
end

local function face_id(n)
    return (n[1] + 2) * 100 + (n[2] + 2) * 10 + (n[3] + 2)
end

local function count_faces()
    local cnt = 0
    for _, v in pairs(S.face_map) do
        if v then cnt = cnt + 1 end
    end
    return cnt
end

local function sync_apple()
    local ap = APPLE_TOUR[((S.apples_eaten) % #APPLE_TOUR) + 1]
    S.apple = { c = {ap.c[1], ap.c[2], ap.c[3]}, n = {ap.n[1], ap.n[2], ap.n[3]} }
    local ax, ay, az = surf_world(S.apple.c, S.apple.n)
    eng.scene.set_pos(S.apple_ent, ax, ay, az)
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.010 })
    eng.render.set_sky(0.02, 0.03, 0.08, 0.08, 0.12, 0.24)
    eng.render.add_light({ type = "dir", dir = {-0.4, -0.8, -0.5}, color = {2.1, 2.05, 1.9}, shadow = true })
    eng.render.add_light({ type = "dir", dir = { 0.5,  0.7,  0.4}, color = {1.1, 1.25, 1.5}, shadow = false })

    -- 5x5x5 floating mini voxel planetoid (crust + core)
    local cap = "22222\n22222\n22722\n22222\n22222"
    local mid = "22222\n23332\n23632\n23332\n22222"
    local planet_vox = eng.asset.voxel_ascii({cap, mid, mid, mid, cap}, 5, 5, 5, 1.0)

    S.seg_vox = eng.asset.voxel_ascii({"22\n22", "22\n22"}, 2, 2, 2, 0.36)
    S.apple_mesh = eng.asset.sphere(0.42, 10, 12)

    S.sfx_eat = eng.audio.synth("triangle", 540, 0.10, 980)
    S.sfx_hit = eng.audio.synth("noise", 220, 0.18, 80)

    local planet = eng.scene.spawn("voxel_planetoid")
    eng.scene.set_pos(planet, -2.5, -2.5, -2.5)
    eng.scene.set_mesh(planet, planet_vox, { cast_shadow = true })
    eng.physics.add_body(planet, { shape = "aabb", motion = "static", half_extents = {2.5, 2.5, 2.5} })

    S.segs = {
        { c = { 0, 0, 2}, n = {0, 0, 1} },
        { c = {-1, 0, 2}, n = {0, 0, 1} },
        { c = {-2, 0, 2}, n = {0, 0, 1} }
    }
    S.dir = {1, 0, 0}
    S.seg_ents = {}
    for i = 1, #S.segs do
        local se = eng.scene.spawn("snake_seg_" .. i)
        local sx, sy, sz = surf_world(S.segs[i].c, S.segs[i].n)
        eng.scene.set_pos(se, sx - 0.36, sy - 0.36, sz - 0.36)
        eng.scene.set_mesh(se, S.seg_vox, {
            color = (i == 1) and {0.35, 1.0, 0.45, 1.0} or {0.20, 0.80, 0.55, 1.0},
            cast_shadow = true
        })
        S.seg_ents[i] = se
    end

    S.apple_ent = eng.scene.spawn("glowing_apple")
    eng.scene.set_mesh(S.apple_ent, S.apple_mesh, { color = {1.5, 0.25, 0.25, 1.0}, roughness = 0.2 })

    S.apples_eaten = 0
    S.target_apples = 5
    S.self_hits = 0
    S.face_map = { [face_id({0, 0, 1})] = true }
    S.faces_visited = 1
    S.turn_q = 0
    S.step_t = 0.0
    S.cam_x, S.cam_y, S.cam_z = 0.0, 2.5, 11.0
    S.won = false

    sync_apple()
    eng.camera.look_at(S.cam_x, S.cam_y, S.cam_z, 0.0, 0.0, 0.0, 0)
    eng.mod.emit("post_init")
end

local function step_snake()
    local head = S.segs[1]
    local n = head.n
    local d = S.dir

    if S.turn_q == -1 then
        d = cross3(n, d)
    elseif S.turn_q == 1 then
        d = cross3(d, n)
    end
    S.turn_q = 0

    local nc = { head.c[1] + d[1], head.c[2] + d[2], head.c[3] + d[3] }
    local nn = { n[1], n[2], n[3] }
    local nd = { d[1], d[2], d[3] }

    -- Seamless 90-degree wrap onto adjacent face of the 5x5x5 cube planetoid
    if math.abs(nc[1]) > 2 or math.abs(nc[2]) > 2 or math.abs(nc[3]) > 2 then
        nc = { head.c[1], head.c[2], head.c[3] }
        nn = { d[1], d[2], d[3] }
        nd = { -n[1], -n[2], -n[3] }
    end
    S.dir = nd
    S.face_map[face_id(nn)] = true
    S.faces_visited = count_faces()

    -- Self-collision check
    for i = 1, #S.segs - 1 do
        local sg = S.segs[i]
        if sg.c[1] == nc[1] and sg.c[2] == nc[2] and sg.c[3] == nc[3]
           and sg.n[1] == nn[1] and sg.n[2] == nn[2] and sg.n[3] == nn[3] then
            S.self_hits = S.self_hits + 1
            eng.audio.play(S.sfx_hit, 0, 0, 0, 0)
            return
        end
    end

    local ate = (nc[1] == S.apple.c[1] and nc[2] == S.apple.c[2] and nc[3] == S.apple.c[3]
                 and nn[1] == S.apple.n[1] and nn[2] == S.apple.n[2] and nn[3] == S.apple.n[3])

    table.insert(S.segs, 1, { c = nc, n = nn })
    if ate then
        S.apples_eaten = S.apples_eaten + 1
        local ne = eng.scene.spawn("snake_seg_" .. #S.segs)
        eng.scene.set_mesh(ne, S.seg_vox, { color = {0.20, 0.80, 0.55, 1.0}, cast_shadow = true })
        S.seg_ents[#S.seg_ents + 1] = ne
        local ax, ay, az = surf_world(nc, nn)
        eng.audio.play(S.sfx_eat, ax, ay, az, 0)
        if S.apples_eaten >= S.target_apples then
            S.won = true
            eng.save.write("voxel_snake_progress", "clear")
        else
            sync_apple()
        end
    else
        table.remove(S.segs)
    end

    for i = 1, #S.segs do
        local sx, sy, sz = surf_world(S.segs[i].c, S.segs[i].n)
        eng.scene.set_pos(S.seg_ents[i], sx - 0.36, sy - 0.36, sz - 0.36)
        eng.scene.set_mesh(S.seg_ents[i], S.seg_vox, {
            color = (i == 1) and {0.35, 1.0, 0.45, 1.0} or {0.20, 0.80, 0.55, 1.0},
            cast_shadow = true
        })
    end
end

function update(dt)
    if S.won then return end

    if eng.input.pressed("left") then S.turn_q = -1 end
    if eng.input.pressed("right") then S.turn_q = 1 end

    S.step_t = S.step_t + dt
    if S.step_t >= 0.08 then
        S.step_t = S.step_t - 0.08
        step_snake()
    end

    -- Smooth orbital camera tracking active planetoid face
    local hn = S.segs[1].n
    local tx = hn[1] * 10.5 + ((hn[2] ~= 0) and 2.5 or 0.0)
    local ty = hn[2] * 10.5 + ((hn[2] == 0) and 3.0 or 0.0)
    local tz = hn[3] * 10.5 + ((hn[2] ~= 0) and 2.5 or 0.0)
    local k = math.min(1.0, dt * 5.0)
    S.cam_x = S.cam_x + (tx - S.cam_x) * k
    S.cam_y = S.cam_y + (ty - S.cam_y) * k
    S.cam_z = S.cam_z + (tz - S.cam_z) * k
    eng.camera.look_at(S.cam_x, S.cam_y, S.cam_z, 0.0, 0.0, 0.0, 0)
end

function draw()
    local x, y = eng.ui.anchor("top_left", 16, 14, 560, 56, 1280, 720)
    eng.ui.label(x, y, string.format("%s | APPLES %d/%d | FACES %d/6 | LEN %d",
        eng.i18n.t("title"), S.apples_eaten, S.target_apples, S.faces_visited, #S.segs), 1.0, {0.45, 1.0, 0.55, 1.0})
    eng.ui.bar(x, y + 26, 220, S.apples_eaten / S.target_apples, "ORBIT ")
end
