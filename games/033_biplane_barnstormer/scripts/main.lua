-- 033_biplane_barnstormer: Retro island biplane pitch/roll flight through sky rings & barn arches
local S = game.state

function init()
    eng.xr.set_mode("cockpit")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.009 })
    eng.render.set_sky(0.18, 0.52, 0.94, 0.72, 0.88, 0.98)
    eng.render.add_light({ type = "dir", dir = {-0.35, -1.0, -0.3}, color = {2.2, 2.1, 1.85}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 18.0, -40.0}, color = {1.5, 1.5, 1.2}, range = 90.0 })

    local seed = math.floor(eng.math.range(100, 60000))
    local sea_tex = eng.procgen.texture("water_caustics", seed, 64)
    local grass_tex = eng.procgen.texture("grass", seed + 3, 64)
    local wood_tex = eng.procgen.texture("wood_planks", seed + 9, 64)

    local sea_mesh = eng.asset.box(140.0, 0.5, 160.0)
    local isle_mesh = eng.asset.box(42.0, 2.2, 118.0)
    local wing_mesh = eng.asset.box(4.2, 0.12, 0.85)
    local prop_mesh = eng.asset.box(1.3, 0.14, 0.08)
    local barn_wall_mesh = eng.asset.box(1.4, 5.2, 5.0)
    local arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")
    local ship_mesh = eng.asset.load_mesh("assets/shared/meshes/starfighter.obj")
    local crys_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    local tree_mesh = eng.procgen.tree(seed + 21, 2, 3.6, 0.25)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    S.sfx_gate = eng.audio.synth("triangle", 540, 0.18, 1080)
    S.sfx_barn = eng.audio.synth("saw", 320, 0.22, 840)

    local sea = eng.scene.spawn("ocean")
    eng.scene.set_pos(sea, 0.0, -0.3, -40.0)
    eng.scene.set_mesh(sea, sea_mesh, { tex = sea_tex, color = {0.16, 0.52, 0.85, 1.0}, roughness = 0.25 })

    local isle = eng.scene.spawn("island")
    eng.scene.set_pos(isle, 0.0, 0.9, -42.0)
    eng.scene.set_mesh(isle, isle_mesh, { tex = grass_tex, color = {0.35, 0.75, 0.32, 1.0}, roughness = 0.85 })

    for i = 1, 8 do
        local tx = ((i % 2 == 0) and 14.5 or -14.5)
        local tz = -8.0 - i * 10.5
        local tr = eng.scene.spawn("island_tree_" .. tostring(i))
        eng.scene.set_pos(tr, tx, 2.0, tz)
        eng.scene.set_mesh(tr, tree_mesh, { color = {0.22, 0.62, 0.25, 1.0}, cast_shadow = true })
    end

    -- 5 Barnstorming Gates (alternating Golden Sky Rings and Red Island Barn Arches)
    local defs = {
        { x = 0.0,  y = 7.4, z = -8.0,  barn = false },
        { x = -4.5, y = 5.0, z = -25.0, barn = true  },
        { x = 0.0,  y = 6.8, z = -43.0, barn = false },
        { x = 4.5,  y = 5.0, z = -61.0, barn = true  },
        { x = 0.0,  y = 7.0, z = -78.0, barn = false }
    }
    S.gates = {}
    for i = 1, #defs do
        local d = defs[i]
        local ge = eng.scene.spawn("gate_" .. tostring(i))
        eng.scene.set_pos(ge, d.x, d.y - 2.2, d.z)
        eng.scene.set_scale(ge, 2.6, 2.0, d.barn and 3.5 or 1.4)
        local col = d.barn and {0.86, 0.22, 0.18, 1.0} or {1.0, 0.86, 0.20, 1.0}
        eng.scene.set_mesh(ge, arch_mesh, { tex = d.barn and wood_tex or nil, color = col, cast_shadow = true })

        if d.barn then
            for s = -1, 1, 2 do
                local bw = eng.scene.spawn("barn_flank_" .. tostring(i) .. "_" .. tostring(s))
                eng.scene.set_pos(bw, d.x + s * 3.4, 4.4, d.z)
                eng.scene.set_mesh(bw, barn_wall_mesh, { tex = wood_tex, color = {0.80, 0.20, 0.16, 1.0}, cast_shadow = true })
            end
        end

        local be = eng.scene.spawn("gate_star_" .. tostring(i))
        eng.scene.set_pos(be, d.x, d.y, d.z)
        eng.scene.set_mesh(be, crys_mesh, { color = {1.0, 0.95, 0.35, 1.0} })
        S.gates[i] = { x = d.x, y = d.y, z = d.z, barn = d.barn, star = be, cleared = false }
    end

    -- Spawn Retro Biplane (fuselage + upper wing + spinning nose propeller)
    S.plane = eng.scene.spawn("biplane")
    eng.scene.set_mesh(S.plane, ship_mesh, { color = {0.92, 0.24, 0.18, 1.0}, cast_shadow = true })

    local uwing = eng.scene.spawn("upper_wing")
    eng.scene.set_parent(uwing, S.plane)
    eng.scene.set_pos(uwing, 0.0, 0.55, -0.1)
    eng.scene.set_mesh(uwing, wing_mesh, { color = {0.96, 0.90, 0.72, 1.0}, cast_shadow = true })

    S.prop = eng.scene.spawn("propeller")
    eng.scene.set_parent(S.prop, S.plane)
    eng.scene.set_pos(S.prop, 0.0, 0.05, -1.55)
    eng.scene.set_mesh(S.prop, prop_mesh, { color = {0.25, 0.22, 0.18, 1.0} })

    S.px, S.py, S.pz = 0.0, 7.5, 8.0
    S.pitch = 0.0
    S.yaw = 0.0
    S.roll = 0.0
    S.airspeed = 28.0
    S.prop_ang = 0.0
    S.cleared = 0
    S.barnstorms = 0
    S.score = 0
    S.won = false

    sync_biplane_cam()
    eng.mod.emit("post_init")
end

function sync_biplane_cam()
    eng.scene.set_pos(S.plane, S.px, S.py, S.pz)
    eng.scene.set_rot_deg(S.plane, S.pitch, S.yaw, S.roll)
    eng.scene.set_rot_deg(S.prop, 0.0, 0.0, S.prop_ang)

    local yr = math.rad(S.yaw)
    local pr = math.rad(S.pitch)
    local fx = -math.sin(yr) * math.cos(pr)
    local fy = math.sin(pr)
    local fz = -math.cos(yr) * math.cos(pr)
    -- Cockpit-over-shoulder camera showing upper biplane wing, prop & island arches ahead
    eng.camera.look_at(S.px - fx * 3.2, S.py - fy * 2.0 + 1.15, S.pz - fz * 3.2,
                       S.px + fx * 12.0, S.py + fy * 12.0, S.pz + fz * 12.0, 0)
end

function update(dt)
    if S.won then return end
    S.prop_ang = (S.prop_ang + 1440.0 * dt) % 360.0

    local roll_in, pitch_in = eng.input.axis2d("left", "right", "down", "up")
    local target_roll = -roll_in * 55.0
    S.roll = S.roll + (target_roll - S.roll) * math.min(1.0, dt * 13.0)
    S.pitch = eng.math.clamp(S.pitch + pitch_in * 110.0 * dt, -38.0, 38.0)
    if math.abs(pitch_in) < 0.05 then
        S.pitch = S.pitch * math.max(0.0, 1.0 - 2.5 * dt)
    end

    -- Coordinated bank-to-yaw aerodynamics: rolling banks the biplane's heading
    S.yaw = S.yaw + math.sin(math.rad(S.roll)) * 125.0 * dt

    local boost = (eng.input.down("fire") or eng.input.down("jump")) and 34.0 or 27.0
    S.airspeed = S.airspeed + (boost - S.airspeed - math.sin(math.rad(S.pitch)) * 4.0) * math.min(1.0, dt * 5.0)
    S.airspeed = eng.math.clamp(S.airspeed, 18.0, 37.0)

    local yr = math.rad(S.yaw)
    local pr = math.rad(S.pitch)
    local fx = -math.sin(yr) * math.cos(pr)
    local fy = math.sin(pr)
    local fz = -math.cos(yr) * math.cos(pr)

    S.px = eng.math.clamp(S.px + fx * S.airspeed * dt, -32.0, 32.0)
    S.py = eng.math.clamp(S.py + fy * S.airspeed * dt, 2.5, 24.0)
    S.pz = S.pz + fz * S.airspeed * dt

    for i = 1, #S.gates do
        local g = S.gates[i]
        if not g.cleared and eng.math.dist3(S.px, S.py, S.pz, g.x, g.y, g.z) < 4.2 then
            g.cleared = true
            eng.scene.despawn(g.star)
            S.cleared = S.cleared + 1
            if g.barn then
                S.barnstorms = S.barnstorms + 1
                S.score = S.score + 350
                eng.audio.play(S.sfx_barn, g.x, g.y, g.z, 0)
            else
                S.score = S.score + 200
                eng.audio.play(S.sfx_gate, g.x, g.y, g.z, 0)
            end
        end
    end

    if S.cleared >= #S.gates then
        S.won = true
        eng.save.write("barnstormer_clear", tostring(S.score))
    end

    sync_biplane_cam()
end

function draw()
    for i = 1, #S.gates do
        local g = S.gates[i]
        if not g.cleared then eng.render.draw_sprite(g.x, g.y + 1.1, g.z, 1.0, 1.0, S.orb_tex) end
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 520, 52, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. string.format(" | GATES %d/%d | BARNS %d | SCORE %d", S.cleared, #S.gates, S.barnstorms, S.score), 1.0, {1.0, 0.94, 0.55, 1.0})
    eng.ui.bar(x, y + 26, 220, (S.airspeed - 15.0) / 21.0, "THROTTLE ")
end
