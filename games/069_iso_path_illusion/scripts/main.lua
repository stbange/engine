-- 069_iso_path_illusion: Monument-Valley-inspired rotating bridge arch & perspective sightline connections
local S = game.state

local CAM_X, CAM_Y, CAM_Z = 11.0, 13.0, 11.0
local BRIDGE_L = 2.6
local LOW_Y = 0.8

local function tip_for_yaw(yaw_deg)
    local r = math.rad(yaw_deg)
    return -math.sin(r) * BRIDGE_L, LOW_Y, -math.cos(r) * BRIDGE_L
end

-- Exact point at elevation target_y that shares the same camera sightline ray as (tx, ty, tz)
local function project_sightline(tx, ty, tz, target_y)
    local s = (target_y - CAM_Y) / (ty - CAM_Y)
    return CAM_X + s * (tx - CAM_X), target_y, CAM_Z + s * (tz - CAM_Z)
end

-- Angular separation in degrees between two 3D world points as viewed from the camera eye
local function sightline_angle_deg(x1, y1, z1, x2, y2, z2)
    local vx1, vy1, vz1 = x1 - CAM_X, y1 - CAM_Y, z1 - CAM_Z
    local vx2, vy2, vz2 = x2 - CAM_X, y2 - CAM_Y, z2 - CAM_Z
    local l1 = math.max(1e-4, math.sqrt(vx1 * vx1 + vy1 * vy1 + vz1 * vz1))
    local l2 = math.max(1e-4, math.sqrt(vx2 * vx2 + vy2 * vy2 + vz2 * vz2))
    local dot = eng.math.clamp((vx1 * vx2 + vy1 * vy2 + vz1 * vz2) / (l1 * l2), -1.0, 1.0)
    return math.deg(math.acos(dot))
end

local function clear_stage()
    if S.ents then
        for i = 1, #S.ents do eng.scene.despawn(S.ents[i]) end
    end
    S.ents = {}
end

local function spawn_block(name, x, y, z, sx, sy, sz, yaw, col, mesh)
    local e = eng.scene.spawn(name)
    eng.scene.set_pos(e, x, y, z)
    eng.scene.set_rot_deg(e, 0.0, yaw or 0.0, 0.0)
    eng.scene.set_scale(e, sx, sy, sz)
    eng.scene.set_mesh(e, mesh or S.box_mesh, { tex = S.stone_tex, color = col, cast_shadow = true })
    S.ents[#S.ents + 1] = e
    return e
end

local function evaluate_links()
    local tx, ty, tz = tip_for_yaw(S.arch_yaw)
    S.tip_x, S.tip_y, S.tip_z = tx, ty, tz
    S.lower_linked = (eng.math.dist3(tx, ty, tz, S.low_lip_x, LOW_Y, S.low_lip_z) < 0.48)
    S.upper_ray_err = sightline_angle_deg(tx, ty, tz, S.up_lip_x, S.high_y, S.up_lip_z)
    S.illusion_linked = (S.upper_ray_err < 2.4)

    eng.scene.set_rot_deg(S.arch_pivot, 0.0, S.arch_yaw, 0.0)
    local deck_col = S.illusion_linked and {1.0, 0.92, 0.46, 1.0}
        or (S.lower_linked and {0.95, 0.72, 0.58, 1.0} or {0.88, 0.56, 0.50, 1.0})
    eng.scene.set_mesh(S.bridge_deck, S.box_mesh, { tex = S.stone_tex, color = deck_col, cast_shadow = true })
end

local function sync_pilgrim()
    local px, py, pz
    if S.phase == 1 then
        -- Walking along Lower Walkway toward the bridge gap (t in [0, 1])
        px = S.start_x + (S.low_lip_x - S.start_x) * S.prog
        py = LOW_Y + 0.15
        pz = S.start_z + (S.low_lip_z - S.start_z) * S.prog
    elseif S.phase == 2 then
        -- Riding / walking onto the Central Rotating Bridge Arch Pavilion (t in [0, 1])
        px = S.tip_x * (1.0 - S.prog)
        py = LOW_Y + 0.15
        pz = S.tip_z * (1.0 - S.prog)
    else
        -- Crossing the impossible perspective bridge onto the Upper Citadel Walkway (t in [0, 1])
        px = S.up_lip_x + (S.goal_x - S.up_lip_x) * S.prog
        py = S.high_y + 0.15
        pz = S.up_lip_z + (S.goal_z - S.up_lip_z) * S.prog
    end
    S.px, S.py, S.pz = px, py, pz
    eng.scene.set_pos(S.pilgrim_ent, px, py, pz)
end

local function build_stage(idx)
    clear_stage()
    S.stage = idx
    S.phase = 1
    S.prog = 0.0

    local low_yaw, up_yaw
    if idx == 1 then
        S.arch_yaw = 180.0
        low_yaw = 90.0
        up_yaw = 0.0
        S.high_y = 3.8
    else
        S.arch_yaw = 45.0
        low_yaw = 135.0
        up_yaw = 315.0
        S.high_y = 4.4
    end
    S.want_low_yaw = low_yaw
    S.want_up_yaw = up_yaw

    -- Lower Walkway geometry ending at tip_for_yaw(low_yaw)
    local lx, _, lz = tip_for_yaw(low_yaw)
    S.low_lip_x, S.low_lip_z = lx, lz
    local lr = math.rad(low_yaw)
    local dir_lx, dir_lz = -math.sin(lr), -math.cos(lr)
    S.start_x = lx + dir_lx * 2.6
    S.start_z = lz + dir_lz * 2.6

    spawn_block("lower_walkway", (lx + S.start_x) * 0.5, LOW_Y - 0.15, (lz + S.start_z) * 0.5,
                1.15, 0.30, 2.8, low_yaw, {0.92, 0.62, 0.58, 1.0})
    spawn_block("lower_column", S.start_x, (LOW_Y - 0.3) * 0.5 - 0.9, S.start_z,
                0.85, 2.4, 0.85, 0.0, {0.78, 0.52, 0.54, 1.0}, S.pillar_mesh)

    -- Central Turntable Pillar + Rotating Bridge Arch
    spawn_block("central_turntable_pillar", 0.0, -1.6, 0.0, 1.05, 2.3, 1.05, 0.0, {0.84, 0.68, 0.56, 1.0}, S.pillar_mesh)
    S.arch_pivot = eng.scene.spawn("rotating_bridge_pivot")
    eng.scene.set_pos(S.arch_pivot, 0.0, LOW_Y, 0.0)
    S.ents[#S.ents + 1] = S.arch_pivot

    S.bridge_deck = eng.scene.spawn("rotating_bridge_span")
    eng.scene.set_parent(S.bridge_deck, S.arch_pivot)
    eng.scene.set_pos(S.bridge_deck, 0.0, -0.15, -BRIDGE_L * 0.5)
    eng.scene.set_scale(S.bridge_deck, 1.10, 0.30, BRIDGE_L + 0.7)
    eng.scene.set_mesh(S.bridge_deck, S.box_mesh, { tex = S.stone_tex, color = {0.88, 0.56, 0.50, 1.0}, cast_shadow = true })
    S.ents[#S.ents + 1] = S.bridge_deck

    local arch_top = eng.scene.spawn("rotating_bridge_archway")
    eng.scene.set_parent(arch_top, S.arch_pivot)
    eng.scene.set_pos(arch_top, 0.0, 0.0, -BRIDGE_L * 0.55)
    eng.scene.set_scale(arch_top, 0.65, 0.75, 0.90)
    eng.scene.set_mesh(arch_top, S.arch_mesh, { color = {0.98, 0.86, 0.72, 1.0}, cast_shadow = true })
    S.ents[#S.ents + 1] = arch_top

    -- Upper Citadel Walkway placed at the EXACT sightline projection of tip_for_yaw(up_yaw) at y = S.high_y!
    local utx, uty, utz = tip_for_yaw(up_yaw)
    local ux, uy, uz = project_sightline(utx, uty, utz, S.high_y)
    S.up_lip_x, S.up_lip_z = ux, uz
    local ur = math.rad(up_yaw)
    local dir_ux, dir_uz = -math.sin(ur), -math.cos(ur)
    S.goal_x = ux + dir_ux * 2.6
    S.goal_z = uz + dir_uz * 2.6

    spawn_block("upper_walkway", (ux + S.goal_x) * 0.5, uy - 0.15, (uz + S.goal_z) * 0.5,
                1.15, 0.30, 2.8, up_yaw, {0.62, 0.88, 0.82, 1.0})
    spawn_block("upper_tower", S.goal_x, uy - 2.6, S.goal_z,
                0.95, 2.5, 0.95, 0.0, {0.54, 0.78, 0.76, 1.0}, S.pillar_mesh)

    S.shrine_ent = eng.scene.spawn("lotus_shrine")
    eng.scene.set_pos(S.shrine_ent, S.goal_x, uy + 0.05, S.goal_z)
    eng.scene.set_mesh(S.shrine_ent, S.crystal_mesh, { color = {1.0, 0.90, 0.35, 1.0} })
    S.ents[#S.ents + 1] = S.shrine_ent

    S.pilgrim_ent = eng.scene.spawn("silent_pilgrim")
    eng.procgen.person(S.pilgrim_ent, S.seed_base + idx * 29)
    eng.scene.set_scale(S.pilgrim_ent, 0.65, 0.65, 0.65)
    S.ents[#S.ents + 1] = S.pilgrim_ent

    evaluate_links()
    sync_pilgrim()
    eng.camera.look_at(CAM_X, CAM_Y, CAM_Z, -1.0, 1.0, -1.0, 0)
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.008 })
    eng.render.set_sky(0.14, 0.12, 0.28, 0.58, 0.42, 0.54)
    eng.render.add_light({ type = "dir", dir = {-0.45, -0.85, -0.30}, color = {2.2, 2.0, 1.9}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 6.0, 2.0}, color = {1.8, 1.6, 2.2}, range = 28.0 })

    S.seed_base = math.floor(eng.math.range(100, 900000))
    S.stone_tex = eng.procgen.texture("stone_brick", S.seed_base, 64)
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.sfx_align = eng.audio.synth("sine", 540, 0.14, 810)
    S.sfx_shrine = eng.audio.synth("triangle", 620, 0.22, 1040)

    S.illusion_crossings = 0
    S.arch_turns = 0
    S.snap_cd = 0.0
    S.was_aligned = false
    S.won = false

    build_stage(1)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end
    S.snap_cd = math.max(0.0, S.snap_cd - dt)

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    if math.abs(mx) > 0.01 then
        S.arch_yaw = (S.arch_yaw + mx * 165.0 * dt) % 360.0
        S.arch_turns = S.arch_turns + math.abs(mx) * 165.0 * dt
        evaluate_links()
    elseif eng.input.pressed("fire") and S.snap_cd <= 0.0 then
        S.arch_yaw = (math.floor((S.arch_yaw + 22.5) / 45.0) * 45.0 + 45.0) % 360.0
        S.arch_turns = S.arch_turns + 45.0
        S.snap_cd = 0.10
        evaluate_links()
    end

    if S.illusion_linked and not S.was_aligned then
        eng.audio.play(S.sfx_align, 0.0, S.high_y, 0.0, 0)
    end
    S.was_aligned = S.illusion_linked

    local walk = (my > 0.1) or eng.input.down("jump")
    if walk then
        if S.phase == 1 then
            S.prog = math.min(1.0, S.prog + 2.2 * dt)
            if S.prog >= 1.0 and S.lower_linked then
                S.phase = 2
                S.prog = 0.0
            end
        elseif S.phase == 2 then
            S.prog = math.min(1.0, S.prog + 2.2 * dt)
            if S.prog >= 1.0 and S.illusion_linked then
                -- Perspective illusion seam! Step from y = 0.8 directly onto Upper Citadel Walkway y = S.high_y!
                S.phase = 3
                S.prog = 0.0
                S.illusion_crossings = S.illusion_crossings + 1
                eng.audio.play(S.sfx_align, S.up_lip_x, S.high_y, S.up_lip_z, 0)
            end
        elseif S.phase == 3 then
            S.prog = math.min(1.0, S.prog + 2.2 * dt)
            if S.prog >= 1.0 then
                eng.audio.play(S.sfx_shrine, S.goal_x, S.high_y, S.goal_z, 0)
                if S.stage < 2 then
                    eng.save.write("iso_path_illusion", "monument_2")
                    build_stage(S.stage + 1)
                else
                    S.won = true
                    eng.save.write("iso_path_illusion", "clear")
                end
                return
            end
        end
    end

    sync_pilgrim()
end

function draw()
    if S.illusion_linked then
        eng.render.draw_sprite(S.up_lip_x, S.high_y + 0.55, S.up_lip_z, 0.65, 0.65, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 640, 52, 1280, 720)
    local link_txt = S.illusion_linked and (" | " .. eng.i18n.t("aligned")) or ""
    local win_txt = S.won and (" | " .. eng.i18n.t("victory")) or ""
    eng.ui.label(x, y, eng.i18n.t("title") .. string.format(" | SPIRE %d/2 | ARCH %3.0f deg%s%s", S.stage, S.arch_yaw, link_txt, win_txt), 1.0, {1.0, 0.90, 0.86, 1.0})
    eng.ui.bar(x, y + 24, 240, ((S.stage - 1) * 3 + S.phase - 1 + S.prog) / 6.0, "ASCENT ")
end
