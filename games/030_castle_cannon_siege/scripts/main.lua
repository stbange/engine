-- 030_castle_cannon_siege: Ballistic artillery adjusting pitch & yaw to breach a WFC voxel fortress & hit crown chest
local S = game.state

local MUZZLE_SPEED = 18.0
local GRAV = 9.81

local function shot_vel(yaw_deg, pitch_deg)
    local yr = math.rad(yaw_deg)
    local pr = math.rad(pitch_deg)
    local cp = math.cos(pr)
    return -math.sin(yr) * cp * MUZZLE_SPEED,
            math.sin(pr) * MUZZLE_SPEED,
           -math.cos(yr) * cp * MUZZLE_SPEED
end

function init()
    eng.xr.set_mode("cockpit")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.016 })
    eng.render.set_sky(0.14, 0.22, 0.38, 0.56, 0.48, 0.36)
    eng.render.add_light({ type = "dir", dir = {-0.35, -1.0, -0.45}, color = {2.2, 2.05, 1.85}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 4.0, -12.0}, color = {2.0, 1.5, 0.8}, range = 24.0 })

    local seed = math.floor(eng.math.range(100, 99999))
    local stone_tex = eng.procgen.texture("stone_brick", seed, 64)
    local grass_tex = eng.procgen.texture("grass", seed + 7, 64)
    local box_mesh = eng.asset.box(1, 1, 1)
    local cyl_mesh = eng.asset.cylinder(0.24, 0.20, 1.6, 12)
    S.ball_mesh = eng.asset.sphere(0.28, 10, 12)
    local chest_mesh = eng.asset.load_mesh("assets/shared/meshes/chest.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    -- WFC-generated procedural fortress keep
    local wfc = eng.procgen.dungeon(12, 12, seed, "wfc", 1.6, 2.8)
    S.wfc_solvable = wfc.solvable
    local keep = eng.scene.spawn("wfc_fortress_keep")
    eng.scene.set_pos(keep, -9.6, 0.0, -34.0)
    eng.scene.set_mesh(keep, wfc.mesh_id, { tex = stone_tex, color = {0.72, 0.70, 0.68, 1.0} })

    local wall_vox = eng.asset.voxel_ascii({
        "1111\n1771",
        "1111\n1771",
        "1..1\n1..1"
    }, 4, 3, 2, 0.40)

    S.sfx_fire = eng.audio.synth("noise", 200, 0.24, 55)
    S.sfx_breach = eng.audio.synth("noise", 310, 0.22, 80)
    S.sfx_crown = eng.audio.synth("triangle", 520, 0.25, 1040)

    local ground = eng.scene.spawn("siege_field")
    eng.scene.set_pos(ground, 0.0, -0.25, -6.0)
    eng.scene.set_scale(ground, 26.0, 0.5, 36.0)
    eng.scene.set_mesh(ground, box_mesh, { tex = grass_tex, color = {0.42, 0.56, 0.36, 1.0} })
    eng.physics.add_body(ground, { shape = "aabb", motion = "static", half_extents = {13.0, 0.25, 18.0} })

    -- Destructible Voxel Curtain Wall (3 columns x 2 tiers = 6 segments shielding Crown Chest)
    S.walls = {}
    local cols = {-1.75, 0.0, 1.75}
    local rows = {0.85, 2.55}
    for r = 1, #rows do
        for c = 1, #cols do
            local wx, wy, wz = cols[c], rows[r], -10.2
            local we = eng.scene.spawn(string.format("curtain_wall_%d_%d", c, r))
            eng.scene.set_pos(we, wx, wy, wz)
            local wv = eng.scene.spawn(string.format("curtain_wall_vis_%d_%d", c, r))
            eng.scene.set_parent(wv, we)
            eng.scene.set_pos(wv, -0.80, -0.60, -0.40)
            eng.scene.set_mesh(wv, wall_vox, { cast_shadow = true })
            local wb = eng.physics.add_body(we, { shape = "aabb", motion = "static", half_extents = {0.78, 0.78, 0.55} })
            S.walls[#S.walls + 1] = { ent = we, vis = wv, body = wb, x = wx, y = wy, z = wz, intact = true }
        end
    end

    -- Royal Crown Chest protected behind the curtain wall at z = -13.5
    S.chest_ent = eng.scene.spawn("royal_crown_chest")
    eng.scene.set_pos(S.chest_ent, 0.0, 0.65, -13.5)
    local cv = eng.scene.spawn("chest_vis")
    eng.scene.set_parent(cv, S.chest_ent)
    eng.scene.set_pos(cv, 0.0, -0.65, 0.0)
    eng.scene.set_scale(cv, 1.35, 1.35, 1.35)
    eng.scene.set_mesh(cv, chest_mesh, { color = {1.0, 0.85, 0.2, 1.0}, cast_shadow = true })
    eng.physics.add_body(S.chest_ent, { shape = "aabb", motion = "static", half_extents = {0.85, 0.62, 0.85} })

    -- Siege Cannon on ridge at (0, 0.6, 5.8)
    local carriage = eng.scene.spawn("cannon_carriage")
    eng.scene.set_pos(carriage, 0.0, 0.45, 5.8)
    eng.scene.set_scale(carriage, 1.1, 0.6, 1.4)
    eng.scene.set_mesh(carriage, box_mesh, { color = {0.42, 0.28, 0.16, 1.0} })

    S.barrel_ent = eng.scene.spawn("cannon_barrel")
    eng.scene.set_pos(S.barrel_ent, 0.0, 0.95, 5.6)
    eng.scene.set_mesh(S.barrel_ent, cyl_mesh, { color = {0.22, 0.24, 0.28, 1.0}, metallic = 0.8, roughness = 0.3 })

    -- Start off-axis so player adjusts both yaw and pitch
    S.yaw_deg = -12.0
    S.pitch_deg = 12.0
    eng.scene.set_rot_deg(S.barrel_ent, S.pitch_deg - 90.0, S.yaw_deg, 0.0)

    S.balls = {}
    S.shots_fired = 0
    S.walls_breached = 0
    S.fire_cd = 0.0
    S.won = false

    eng.camera.look_at(2.4, 3.6, 9.6, 0.0, 1.4, -10.5, 0)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end
    S.fire_cd = math.max(0.0, S.fire_cd - dt)

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    -- Turning right aims negative yaw (-mx in right-handed yaw, let's map +mx -> +X downrange so yaw_deg -= mx)
    S.yaw_deg = eng.math.clamp(S.yaw_deg - mx * 36.0 * dt, -35.0, 35.0)
    S.pitch_deg = eng.math.clamp(S.pitch_deg + my * 28.0 * dt, 6.0, 55.0)
    eng.scene.set_rot_deg(S.barrel_ent, S.pitch_deg - 90.0, S.yaw_deg, 0.0)

    if eng.input.pressed("fire") and S.fire_cd <= 0.0 then
        S.fire_cd = 0.35
        S.shots_fired = S.shots_fired + 1
        local vx, vy, vz = shot_vel(S.yaw_deg, S.pitch_deg)
        local be = eng.scene.spawn("cannonball_" .. S.shots_fired)
        eng.scene.set_pos(be, 0.0, 1.15, 5.2)
        eng.scene.set_mesh(be, S.ball_mesh, { color = {0.18, 0.18, 0.22, 1.0}, metallic = 0.9 })
        eng.audio.play(S.sfx_fire, 0.0, 1.15, 5.2, 0)
        S.balls[#S.balls + 1] = { ent = be, x = 0.0, y = 1.15, z = 5.2, vx = vx, vy = vy, vz = vz, active = true }
    end

    for i = 1, #S.balls do
        local b = S.balls[i]
        if b.active then
            local x0, y0, z0 = b.x, b.y, b.z
            b.vy = b.vy - GRAV * dt
            b.x = b.x + b.vx * dt
            b.y = b.y + b.vy * dt
            b.z = b.z + b.vz * dt
            eng.scene.set_pos(b.ent, b.x, b.y, b.z)

            local dx, dy, dz = b.x - x0, b.y - y0, b.z - z0
            local seg = math.sqrt(dx * dx + dy * dy + dz * dz)
            if seg > 0.001 then
                local hit = eng.physics.raycast(0, x0, y0, z0, dx / seg, dy / seg, dz / seg, seg + 0.30)
                if hit then
                    b.active = false
                    eng.scene.despawn(b.ent)

                    -- Check if hit a curtain wall block (explosive breach clears column within 1.85m!)
                    for w = 1, #S.walls do
                        local wl = S.walls[w]
                        if wl.intact and (wl.ent == hit.entity or eng.math.dist3(hit.point[1], hit.point[2], hit.point[3], wl.x, wl.y, wl.z) < 1.85) then
                            wl.intact = false
                            S.walls_breached = S.walls_breached + 1
                            eng.scene.despawn(wl.vis)
                            eng.scene.despawn(wl.ent)
                            eng.audio.play(S.sfx_breach, wl.x, wl.y, wl.z, 0)
                        end
                    end

                    -- Check if hit the Royal Crown Chest
                    if hit.entity == S.chest_ent and S.walls_breached >= 1 then
                        S.won = true
                        eng.audio.play(S.sfx_crown, 0.0, 0.8, -13.5, 0)
                        eng.save.write("castle_cannon_progress", "clear")
                    end
                elseif b.y < -1.0 or b.z < -30.0 then
                    b.active = false
                    eng.scene.despawn(b.ent)
                end
            end
        end
    end
end

function draw()
    -- Draw ballistic arc preview dots
    local vx, vy, vz = shot_vel(S.yaw_deg, S.pitch_deg)
    for step = 1, 6 do
        local t = step * 0.14
        local px = vx * t
        local py = 1.15 + vy * t - 0.5 * GRAV * t * t
        local pz = 5.2 + vz * t
        if py > 0.1 then
            eng.render.draw_sprite(px, py, pz, 0.24, 0.24, S.orb_tex)
        end
    end

    local x, y = eng.ui.anchor("top_left", 16, 14, 580, 56, 1280, 720)
    eng.ui.label(x, y, string.format("%s | YAW %.1f | PITCH %.1f | BREACHED %d | SHOTS %d",
        eng.i18n.t("title"), S.yaw_deg, S.pitch_deg, S.walls_breached, S.shots_fired), 1.0, {1.0, 0.88, 0.42, 1.0})
    eng.ui.bar(x, y + 26, 220, eng.math.clamp(S.walls_breached / 2.0, 0.0, 1.0), "SIEGE ")
end
