-- 084_pac_catacombs: 3D Neon Maze with Left-Right Warp Portals (eng.portal.link), Pellets, Power-Orbs & A* Ghosts
local S = game.state

local W, D = 9, 9
local CELL = 2.0

local MAZE = {
    "#########",
    "#o.....o#",
    "#.#.#.#.#",
    "#.......#",
    "=...G...=",
    "#.......#",
    "#.#.#.#.#",
    "#o..P..o#",
    "#########"
}

local function cell_char(gx, gz)
    if gz < 0 or gz >= D then return "#" end
    if gz == 4 and (gx < 0 or gx >= W) then return "=" end
    if gx < 0 or gx >= W then return "#" end
    return string.sub(MAZE[gz + 1], gx + 1, gx + 1)
end

local function is_walkable(gx, gz)
    return cell_char(gx, gz) ~= "#"
end

local function world_to_grid(x, z)
    return math.floor(x / CELL), math.floor(z / CELL)
end

local function grid_center(gx, gz)
    return (gx + 0.5) * CELL, (gz + 0.5) * CELL
end

local function can_stand(x, z, r)
    local offs = { {-r, -r}, {r, -r}, {-r, r}, {r, r} }
    for i = 1, 4 do
        local gx, gz = world_to_grid(x + offs[i][1], z + offs[i][2])
        if not is_walkable(gx, gz) then return false end
    end
    return true
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_sky(0.02, 0.02, 0.08, 0.08, 0.04, 0.18)
    eng.render.add_light({ type = "dir", dir = {-0.25, -1.0, -0.35}, color = {1.5, 1.55, 1.8}, shadow = true })
    eng.render.add_light({ type = "point", pos = {9.0, 7.0, 9.0}, color = {1.6, 1.1, 2.4}, range = 26.0 })

    local seed = math.floor(eng.math.range(10, 50000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.pac_mesh = eng.asset.sphere(0.62, 14, 18)
    S.ghost_mesh = eng.asset.cylinder(0.52, 0.42, 1.15, 14)
    S.pellet_mesh = eng.asset.sphere(0.18, 8, 10)
    S.power_mesh = eng.asset.sphere(0.38, 12, 14)
    S.arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.floor_tex = eng.procgen.texture("sci_fi_panel", seed, 64)
    S.wall_tex = eng.procgen.texture("stone_brick", seed + 13, 64)

    S.sfx_pellet = eng.audio.synth("triangle", 520, 0.04, 680)
    S.sfx_power = eng.audio.synth("sine", 360, 0.18, 880)
    S.sfx_chomp = eng.audio.synth("square", 280, 0.16, 760)
    S.sfx_warp = eng.audio.synth("sine", 640, 0.14, 320)
    S.sfx_hurt = eng.audio.synth("noise", 220, 0.16, 80)

    -- Neon Catacomb Floor
    local flr = eng.scene.spawn("maze_floor")
    eng.scene.set_pos(flr, 9.0, -0.25, 9.0)
    eng.scene.set_scale(flr, 20.0, 0.5, 18.4)
    eng.scene.set_mesh(flr, S.box_mesh, { tex = S.floor_tex, color = {0.14, 0.16, 0.28, 1.0}, roughness = 0.35 })
    eng.physics.add_body(flr, { shape = "aabb", motion = "static", half_extents = {10.0, 0.25, 9.2} })

    -- Build 3D Neon Maze Walls, Walkable NavGrid, Pellets & Power-Orbs
    local walk_tbl = {}
    S.items = {}
    S.pellets_left = 0
    S.px, S.pz = grid_center(4, 7)

    for gz = 0, D - 1 do
        for gx = 0, W - 1 do
            local ch = cell_char(gx, gz)
            local cx, cz = grid_center(gx, gz)
            if ch == "#" then
                walk_tbl[gz * W + gx + 1] = 0
                local we = eng.scene.spawn("neon_wall_" .. gx .. "_" .. gz)
                eng.scene.set_pos(we, cx, 0.65, cz)
                eng.scene.set_scale(we, CELL * 0.96, 1.30, CELL * 0.96)
                eng.scene.set_mesh(we, S.box_mesh, { tex = S.wall_tex, color = {0.16, 0.42, 0.98, 1.0}, roughness = 0.28, cast_shadow = true })
                eng.physics.add_body(we, { shape = "aabb", motion = "static", half_extents = {CELL * 0.48, 0.65, CELL * 0.48} })
            else
                walk_tbl[gz * W + gx + 1] = 1
                if ch == "P" then
                    S.px, S.pz = cx, cz
                elseif ch == "." or ch == "o" then
                    local is_pow = (ch == "o")
                    local ie = eng.scene.spawn(is_pow and "power_orb" or "pellet")
                    eng.scene.set_pos(ie, cx, is_pow and 0.55 or 0.38, cz)
                    eng.scene.set_mesh(ie, is_pow and S.power_mesh or S.pellet_mesh, {
                        color = is_pow and {1.0, 0.35, 0.92, 1.0} or {1.0, 0.90, 0.28, 1.0},
                        roughness = 0.15
                    })
                    S.items[#S.items + 1] = { ent = ie, x = cx, z = cz, power = is_pow, active = true }
                    S.pellets_left = S.pellets_left + 1
                end
            end
        end
    end
    eng.ai.set_grid(0, CELL, W, D, walk_tbl)

    -- Left-Right Bidirectional Warp Portals (`eng.portal.link`) on row gz = 4 (z = 9.0)
    local wz = 4.5 * CELL
    local arch_l = eng.scene.spawn("warp_arch_left")
    eng.scene.set_pos(arch_l, 0.8, 0.0, wz)
    eng.scene.set_rot_deg(arch_l, 0.0, 90.0, 0.0)
    eng.scene.set_mesh(arch_l, S.arch_mesh, { color = {0.25, 0.95, 1.0, 1.0}, cast_shadow = true })

    local arch_r = eng.scene.spawn("warp_arch_right")
    eng.scene.set_pos(arch_r, 17.2, 0.0, wz)
    eng.scene.set_rot_deg(arch_r, 0.0, -90.0, 0.0)
    eng.scene.set_mesh(arch_r, S.arch_mesh, { color = {1.0, 0.35, 0.92, 1.0}, cast_shadow = true })

    S.portal_left = eng.scene.spawn("portal_warp_left")
    eng.scene.set_pos(S.portal_left, 0.8, 1.1, wz)
    eng.scene.set_rot_deg(S.portal_left, 0.0, 90.0, 0.0)

    S.portal_right = eng.scene.spawn("portal_warp_right")
    eng.scene.set_pos(S.portal_right, 17.2, 1.1, wz)
    eng.scene.set_rot_deg(S.portal_right, 0.0, -90.0, 0.0)

    S.warp_portal_id = eng.portal.link(S.portal_left, S.portal_right, 1.8, 2.2, 1.0, true, true)

    -- Player Neon Chomper
    S.pac_ent = eng.scene.spawn("pac_player")
    eng.scene.set_pos(S.pac_ent, S.px, 0.62, S.pz)
    eng.scene.set_mesh(S.pac_ent, S.pac_mesh, { color = {1.0, 0.88, 0.12, 1.0}, roughness = 0.22, cast_shadow = true })

    -- 3 NavGrid A* Ghost Chasers
    local g_specs = {
        { name = "blinky", gx = 4, gz = 4, color = {1.0, 0.22, 0.26, 1.0}, spd = 4.6 },
        { name = "pinky",  gx = 3, gz = 4, color = {1.0, 0.48, 0.88, 1.0}, spd = 4.2 },
        { name = "inky",   gx = 5, gz = 4, color = {0.22, 0.92, 1.0, 1.0},  spd = 4.0 }
    }
    S.ghosts = {}
    for i = 1, #g_specs do
        local gs = g_specs[i]
        local gx, gz = grid_center(gs.gx, gs.gz)
        local ge = eng.scene.spawn("ghost_" .. gs.name)
        eng.scene.set_pos(ge, gx, 0.60, gz)
        eng.scene.set_mesh(ge, S.ghost_mesh, { color = gs.color, roughness = 0.30, cast_shadow = true })
        S.ghosts[i] = { ent = ge, x = gx, z = gz, home_x = gx, home_z = gz, base_color = gs.color, spd = gs.spd, frightened = false }
    end

    S.lives = 3
    S.score = 0
    S.power_timer = 0.0
    S.portal_warps = 0
    S.power_orbs_eaten = 0
    S.ghosts_eaten = 0
    S.pulse_t = 0.0
    S.won = false

    eng.camera.look_at(9.0, 19.5, 21.5, 9.0, 0.5, 8.8, 0)
    eng.mod.emit("post_init")
end

local function set_ghost_fright(fright)
    for i = 1, #S.ghosts do
        local g = S.ghosts[i]
        if g.frightened ~= fright then
            g.frightened = fright
            eng.scene.set_mesh(g.ent, S.ghost_mesh, {
                color = fright and {0.18, 0.36, 1.0, 1.0} or g.base_color,
                roughness = 0.30, cast_shadow = true
            })
        end
    end
end

function update(dt)
    if S.won then return end
    S.pulse_t = S.pulse_t + dt

    if S.power_timer > 0.0 then
        S.power_timer = math.max(0.0, S.power_timer - dt)
        if S.power_timer <= 0.0 then set_ghost_fright(false) end
    end

    -- Player corridor movement (+X right, -Z up screen) with smooth corner sliding & portal warp!
    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    local spd = 12.0
    local prev_x, prev_z = S.px, S.pz
    local pgx, pgz = world_to_grid(S.px, S.pz)
    local cx, cz = grid_center(pgx, pgz)

    local moved_x = false
    if math.abs(mx) > 0.05 then
        local step_x = (mx > 0 and 1.0 or -1.0) * spd * dt
        local nz = (math.abs(my) < 0.05) and (S.pz + eng.math.clamp(cz - S.pz, -spd * dt, spd * dt)) or S.pz
        if can_stand(S.px + step_x, nz, 0.40) then
            S.px, S.pz = S.px + step_x, nz
            moved_x = true
        end
    end
    if math.abs(my) > 0.05 then
        local step_z = (my > 0 and -1.0 or 1.0) * spd * dt
        local nx = (not moved_x) and (S.px + eng.math.clamp(cx - S.px, -spd * dt, spd * dt)) or S.px
        if can_stand(nx, S.pz + step_z, 0.40) then
            S.px, S.pz = nx, S.pz + step_z
        end
    end

    local dst_pk, wx, _, wz = eng.portal.check_crossing(0, prev_x, 1.0, prev_z, S.px, 1.0, S.pz)
    if dst_pk ~= nil then
        S.px, S.pz = wx, wz
        S.portal_warps = S.portal_warps + 1
        S.score = S.score + 50
        eng.audio.play(S.sfx_warp, S.px, 1.0, S.pz, 0)
    end
    eng.scene.set_pos(S.pac_ent, S.px, 0.62 + math.abs(math.sin(S.pulse_t * 10.0)) * 0.08, S.pz)

    -- Collect pellets & power-orbs
    for i = 1, #S.items do
        local it = S.items[i]
        if it.active and eng.math.dist3(S.px, 0, S.pz, it.x, 0, it.z) < 0.78 then
            it.active = false
            eng.scene.despawn(it.ent)
            S.pellets_left = S.pellets_left - 1
            if it.power then
                S.power_orbs_eaten = S.power_orbs_eaten + 1
                S.power_timer = 7.5
                S.score = S.score + 100
                set_ghost_fright(true)
                eng.audio.play(S.sfx_power, it.x, 0.6, it.z, 0)
            else
                S.score = S.score + 20
                eng.audio.play(S.sfx_pellet, it.x, 0.4, it.z, 0)
            end
        end
    end

    -- Update NavGrid A* Ghost Chasers (portal-aware!)
    for i = 1, #S.ghosts do
        local g = S.ghosts[i]
        local goal_x, goal_z = S.px, S.pz
        if S.power_timer > 0.0 then
            -- Frightened ghosts retreat toward far corner opposite player
            goal_x = (S.px < 9.0) and 15.0 or 3.0
            goal_z = (S.pz < 9.0) and 15.0 or 3.0
        end
        local path = eng.ai.find_path(0, g.x, 0.0, g.z, 0, goal_x, 0.0, goal_z)
        local tx, tz = goal_x, goal_z
        if path and #path >= 2 then tx, tz = path[2][1], path[2][3] end
        local vx, vz = tx - g.x, tz - g.z
        local vl = math.sqrt(vx * vx + vz * vz)
        local g_prev_x, g_prev_z = g.x, g.z
        local gspd = (S.power_timer > 0.0) and (g.spd * 0.62) or g.spd
        if vl > 0.05 then
            local nx = g.x + (vx / vl) * gspd * dt
            local nz = g.z + (vz / vl) * gspd * dt
            if can_stand(nx, nz, 0.35) then g.x, g.z = nx, nz end
        end
        local gpk, gwx, _, gwz = eng.portal.check_crossing(0, g_prev_x, 1.0, g_prev_z, g.x, 1.0, g.z)
        if gpk ~= nil then g.x, g.z = gwx, gwz end
        eng.scene.set_pos(g.ent, g.x, 0.60, g.z)

        if eng.math.dist3(S.px, 0, S.pz, g.x, 0, g.z) < 1.05 then
            if S.power_timer > 0.0 then
                S.ghosts_eaten = S.ghosts_eaten + 1
                S.score = S.score + 250
                g.x, g.z = g.home_x, g.home_z
                eng.scene.set_pos(g.ent, g.x, 0.60, g.z)
                eng.audio.play(S.sfx_chomp, S.px, 0.8, S.pz, 0)
            else
                S.lives = math.max(1, S.lives - 1)
                S.px, S.pz = grid_center(4, 7)
                eng.scene.set_pos(S.pac_ent, S.px, 0.62, S.pz)
                eng.audio.play(S.sfx_hurt, S.px, 0.8, S.pz, 0)
            end
        end
    end

    if S.pellets_left <= 0 then
        S.won = true
        S.score = S.score + 500
        eng.save.write("pac_catacombs_clear", tostring(S.score))
    end
end

function draw()
    -- Portal energy glow sprites
    eng.render.draw_sprite(0.8, 1.2, 9.0, 0.9, 1.3, S.orb_tex)
    eng.render.draw_sprite(17.2, 1.2, 9.0, 0.9, 1.3, S.orb_tex)

    local x, y = eng.ui.anchor("top_left", 16, 14, 560, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | PELLETS " .. S.pellets_left .. " | WARPS " .. S.portal_warps .. " | SCORE " .. S.score, 1.0, {1.0, 0.92, 0.25, 1.0})
    eng.ui.bar(x, y + 26, 200, S.power_timer / 7.5, "POWER ")
end
