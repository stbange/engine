-- 059_lighthouse_warden: Volumetric spotlight cone guiding cargo ships past jagged sea rocks
local S = game.state

local LH_X, LH_Z = 9.0, 7.5
local HARBOR_X, HARBOR_Z = -9.5, 7.5

local function spawn_ship(idx)
    local sx = -6.5 + ((idx * 3) % 5) * 3.4
    local sz = -13.5 - (idx % 2) * 1.8
    local hull = eng.scene.spawn("cargo_ship_" .. tostring(idx))
    eng.scene.set_pos(hull, sx, 0.35, sz)
    eng.scene.set_scale(hull, 1.15, 0.65, 2.3)
    eng.scene.set_mesh(hull, S.box_mesh, { tex = S.metal_tex, color = {0.82, 0.36, 0.22, 1.0}, cast_shadow = true })

    local bridge = eng.scene.spawn("ship_bridge_" .. tostring(idx))
    eng.scene.set_parent(bridge, hull)
    eng.scene.set_pos(bridge, 0.0, 0.75, 0.35)
    eng.scene.set_scale(bridge, 0.75, 0.75, 0.55)
    eng.scene.set_mesh(bridge, S.box_mesh, { color = {0.92, 0.95, 1.0, 1.0} })

    S.ships[#S.ships + 1] = { ent = hull, x = sx, z = sz, lit = false, active = true }
end

local function sync_beam()
    local rad = math.rad(S.beam_yaw)
    local dx, dz = -math.sin(rad), -math.cos(rad)
    S.bx = LH_X + dx * S.beam_dist
    S.bz = LH_Z + dz * S.beam_dist
    eng.scene.set_rot_deg(S.rotor_ent, 0.0, S.beam_yaw, 0.0)
    eng.scene.set_pos(S.spot_ring, S.bx, 0.14, S.bz)
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.018 })
    eng.render.set_sky(0.03, 0.05, 0.11, 0.09, 0.15, 0.26)

    -- Stormy moonlight + Lighthouse volumetric spot light + Harbor beacon
    eng.render.add_light({ type = "dir", dir = {-0.25, -1.0, -0.35}, color = {1.05, 1.25, 1.65}, shadow = true })
    eng.render.add_light({
        type = "spot",
        pos = {LH_X, 7.6, LH_Z},
        dir = {-0.55, -0.35, -0.75},
        color = {3.5, 3.1, 1.9},
        range = 42.0,
        shadow = true
    })
    eng.render.add_light({ type = "point", pos = {HARBOR_X, 3.2, HARBOR_Z}, color = {0.5, 2.2, 1.2}, range = 18.0 })

    local seed_base = math.floor(eng.math.range(100, 900000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.tower_mesh = eng.asset.cylinder(1.5, 0.95, 7.0, 12)
    S.cone_mesh = eng.asset.cylinder(0.22, 2.5, 17.5, 12)
    S.ring_mesh = eng.asset.cylinder(3.2, 3.2, 0.12, 14)
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.water_tex = eng.procgen.texture("water_caustics", seed_base, 64)
    S.stone_tex = eng.procgen.texture("stone_brick", seed_base + 5, 64)
    S.metal_tex = eng.procgen.texture("rust_metal", seed_base + 11, 64)
    S.wood_tex = eng.procgen.texture("wood_planks", seed_base + 17, 64)

    S.sfx_horn = eng.audio.synth("saw", 135, 0.24, 115)
    S.sfx_dock = eng.audio.synth("triangle", 520, 0.16, 840)
    S.sfx_wreck = eng.audio.synth("noise", 170, 0.22, 65)

    S.sea_ent = eng.scene.spawn("storm_ocean")
    eng.scene.set_pos(S.sea_ent, 0.0, -0.25, 0.0)
    eng.scene.set_scale(S.sea_ent, 38.0, 0.5, 36.0)
    eng.scene.set_mesh(S.sea_ent, S.box_mesh, { tex = S.water_tex, color = {0.10, 0.26, 0.46, 1.0} })

    -- Headland cliff & Lighthouse Tower
    local cliff = eng.scene.spawn("lighthouse_headland")
    eng.scene.set_pos(cliff, LH_X, 0.4, LH_Z)
    eng.scene.set_scale(cliff, 4.8, 0.9, 4.8)
    eng.scene.set_mesh(cliff, S.box_mesh, { tex = S.stone_tex, color = {0.38, 0.40, 0.44, 1.0}, cast_shadow = true })

    local tower = eng.scene.spawn("lighthouse_tower")
    eng.scene.set_pos(tower, LH_X, 4.0, LH_Z)
    eng.scene.set_mesh(tower, S.tower_mesh, { tex = S.stone_tex, color = {0.92, 0.90, 0.86, 1.0}, cast_shadow = true })

    -- Rotating Lighthouse Lamp & Volumetric Spotlight Cone
    S.rotor_ent = eng.scene.spawn("lighthouse_rotor")
    eng.scene.set_pos(S.rotor_ent, LH_X, 7.5, LH_Z)

    local cone = eng.scene.spawn("volumetric_spot_cone")
    eng.scene.set_parent(cone, S.rotor_ent)
    eng.scene.set_pos(cone, 0.0, -2.6, -8.4)
    eng.scene.set_rot_deg(cone, 73.0, 0.0, 0.0)
    eng.scene.set_mesh(cone, S.cone_mesh, { color = {1.0, 0.92, 0.45, 0.45} })

    S.spot_ring = eng.scene.spawn("beam_water_patch")
    eng.scene.set_mesh(S.spot_ring, S.ring_mesh, { color = {1.0, 0.94, 0.48, 1.0} })

    -- Safe Harbor Pier at (-9.5, 0, 7.5)
    local pier = eng.scene.spawn("harbor_pier")
    eng.scene.set_pos(pier, HARBOR_X, 0.3, HARBOR_Z)
    eng.scene.set_scale(pier, 4.6, 0.6, 4.6)
    eng.scene.set_mesh(pier, S.box_mesh, { tex = S.wood_tex, color = {0.65, 0.46, 0.28, 1.0} })

    local gate = eng.scene.spawn("harbor_arch")
    eng.scene.set_pos(gate, HARBOR_X, 0.5, HARBOR_Z - 1.6)
    eng.scene.set_scale(gate, 1.5, 1.25, 1.4)
    eng.scene.set_mesh(gate, S.arch_mesh, { color = {0.35, 0.95, 0.62, 1.0} })

    -- 4 Jagged Sea Rock Reefs
    local rock_pts = { {-3.5, -4.5}, {2.2, -2.0}, {-5.2, 1.5}, {0.8, 3.2} }
    S.rocks = {}
    for i = 1, #rock_pts do
        local rx, rz = rock_pts[i][1], rock_pts[i][2]
        local rk = eng.scene.spawn("jagged_rock_" .. tostring(i))
        eng.scene.set_pos(rk, rx, 0.0, rz)
        eng.scene.set_scale(rk, 2.2, 2.4, 2.2)
        eng.scene.set_mesh(rk, S.crystal_mesh, { tex = S.stone_tex, color = {0.34, 0.36, 0.40, 1.0}, cast_shadow = true })
        S.rocks[i] = { x = rx, z = rz }
    end

    S.beam_yaw = 42.0
    S.beam_dist = 15.5
    S.ships = {}
    S.spawned = 0
    S.saved = 0
    S.target_saved = 5
    S.wrecks = 0
    S.horns = 0
    S.horn_timer = 0.0
    S.horn_cd = 0.0
    S.spawn_cd = 0.35
    S.wave_t = 0.0
    S.won = false
    S.lost = false

    sync_beam()
    spawn_ship(1)
    spawn_ship(2)
    S.spawned = 2

    eng.camera.look_at(0.0, 20.5, 20.0, -1.0, 0.5, -1.0, 0)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won or S.lost then return end
    S.wave_t = S.wave_t + dt
    S.horn_timer = math.max(0.0, S.horn_timer - dt)
    S.horn_cd = math.max(0.0, S.horn_cd - dt)

    -- Gentle stormy ocean swell
    eng.scene.set_pos(S.sea_ent, 0.0, -0.25 + math.sin(S.wave_t * 3.0) * 0.08, 0.0)

    -- Rotate spotlight yaw & range
    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    if math.abs(mx) > 0.01 or math.abs(my) > 0.01 then
        S.beam_yaw = eng.math.clamp(S.beam_yaw - mx * 110.0 * dt, -15.0, 105.0)
        S.beam_dist = eng.math.clamp(S.beam_dist + my * 15.0 * dt, 6.0, 24.5)
        sync_beam()
    end

    -- Foghorn blast pushes ships clear of reefs
    if (eng.input.pressed("fire") or eng.input.pressed("interact")) and S.horn_cd <= 0.0 then
        S.horn_cd = 0.30
        S.horn_timer = 0.55
        S.horns = S.horns + 1
        eng.audio.play(S.sfx_horn, LH_X, 7.0, LH_Z, 0)
    end

    S.spawn_cd = S.spawn_cd - dt
    if S.spawn_cd <= 0.0 and S.spawned < 7 then
        S.spawn_cd = 0.48
        S.spawned = S.spawned + 1
        spawn_ship(S.spawned)
    end

    for i = 1, #S.ships do
        local sh = S.ships[i]
        if sh.active then
            local d_beam = eng.math.dist3(sh.x, 0, sh.z, S.bx, 0, S.bz)
            sh.lit = (d_beam < 6.2) or (S.horn_timer > 0.0)

            local vx, vz
            if sh.lit then
                -- Illuminated captain steers briskly toward Harbor while avoiding jagged rocks!
                local hx, hz = HARBOR_X - sh.x, HARBOR_Z - sh.z
                local hl = math.max(0.01, math.sqrt(hx * hx + hz * hz))
                vx, vz = (hx / hl) * 12.5, (hz / hl) * 12.5
                for r = 1, #S.rocks do
                    local rk = S.rocks[r]
                    local rx, rz = sh.x - rk.x, sh.z - rk.z
                    local rd = math.sqrt(rx * rx + rz * rz)
                    if rd > 0.01 and rd < 4.4 then
                        local repel = (4.4 - rd) * 9.5
                        vx = vx + (rx / rd) * repel
                        vz = vz + (rz / rd) * repel
                    end
                end
            else
                -- In darkness: storm gale drifts vessel toward reefs
                vx, vz = 0.8, 3.6
            end

            sh.x = sh.x + vx * dt
            sh.z = sh.z + vz * dt
            eng.scene.set_pos(sh.ent, sh.x, 0.35 + math.sin(S.wave_t * 4.0 + i) * 0.08, sh.z)
            eng.scene.set_rot_deg(sh.ent, 0.0, math.deg(math.atan2(-vx, -vz)), 0.0)

            -- Check harbor arrival vs rock collision
            if eng.math.dist3(sh.x, 0, sh.z, HARBOR_X, 0, HARBOR_Z) < 3.0 then
                sh.active = false
                eng.scene.despawn(sh.ent)
                S.saved = S.saved + 1
                eng.audio.play(S.sfx_dock, HARBOR_X, 1.2, HARBOR_Z, 0)
            else
                for r = 1, #S.rocks do
                    local rk = S.rocks[r]
                    if (not sh.lit) and eng.math.dist3(sh.x, 0, sh.z, rk.x, 0, rk.z) < 1.35 then
                        sh.active = false
                        eng.scene.despawn(sh.ent)
                        S.wrecks = S.wrecks + 1
                        eng.audio.play(S.sfx_wreck, rk.x, 1.0, rk.z, 0)
                        break
                    end
                end
            end
        end
    end

    if S.wrecks >= 2 then
        S.lost = true
        eng.save.write("lighthouse_status", "wrecked")
    elseif S.saved >= S.target_saved then
        S.won = true
        eng.save.write("lighthouse_status", "harbor_safe")
    end
end

function draw()
    eng.render.draw_sprite(LH_X, 8.2, LH_Z, 1.2, 1.2, S.orb_tex)
    eng.render.draw_sprite(HARBOR_X, 2.8, HARBOR_Z - 1.6, 0.8, 0.8, S.orb_tex)

    local x, y = eng.ui.anchor("top_left", 16, 14, 560, 54, 1280, 720)
    local status = S.won and (" | " .. eng.i18n.t("victory")) or (S.lost and (" | " .. eng.i18n.t("defeat")) or "")
    eng.ui.label(x, y, eng.i18n.t("title") .. string.format(" | BEAM %.0f deg | WRECKS: %d/2%s", S.beam_yaw, S.wrecks, status), 1.0, {1.0, 0.94, 0.55, 1.0})
    eng.ui.bar(x, y + 24, 240, S.saved / S.target_saved, "DOCKED " .. S.saved .. "/5 ")
end
