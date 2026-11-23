-- 060_terra_garden: Orbit & terraform a barren 3D cube-sphere planet with rain/forests & wildlife to 100% biosphere
local S = game.state

local PLANET_R = 10.5
local BIOME_COORDS = {
    { lat =  20.0, lon =   0.0, arch = "quadruped" },
    { lat = -16.0, lon =  60.0, arch = "avian" },
    { lat =  24.0, lon = 120.0, arch = "biped" },
    { lat = -20.0, lon = 180.0, arch = "insectoid" },
    { lat =  18.0, lon = 240.0, arch = "serpentine" },
    { lat = -14.0, lon = 300.0, arch = "aquatic" }
}

local function sphere_dir(lat_deg, lon_deg)
    local lat = math.rad(lat_deg)
    local lon = math.rad(lon_deg)
    local cl = math.cos(lat)
    return cl * math.sin(lon), math.sin(lat), cl * math.cos(lon)
end

local function orient_radial(ent, nx, ny, nz)
    local pitch = math.deg(math.acos(eng.math.clamp(ny, -1.0, 1.0)))
    local yaw = math.deg(math.atan2(nx, nz))
    eng.scene.set_rot_deg(ent, pitch, yaw, 0.0)
end

local function sync_probe_and_camera()
    local nx, ny, nz = sphere_dir(S.orbit_lat, S.orbit_lon)
    local pr = PLANET_R + 3.6
    S.px, S.py, S.pz = nx * pr, ny * pr, nz * pr
    eng.scene.set_pos(S.probe_ent, S.px, S.py, S.pz)
    orient_radial(S.probe_ent, nx, ny, nz)

    local cr = PLANET_R + 17.5
    local cx = nx * cr + (-nz) * 2.5
    local cy = ny * cr + 4.5
    local cz = nz * cr + nx * 2.5
    eng.camera.look_at(cx, cy, cz, 0.0, 0.0, 0.0, 0)
end

local function refresh_planet_tint()
    local f = S.biosphere / 100.0
    local r = 0.76 * (1.0 - f) + 0.34 * f
    local g = 0.54 * (1.0 - f) + 0.86 * f
    local b = 0.38 * (1.0 - f) + 0.54 * f
    eng.scene.set_mesh(S.planet_ent, S.planet_mesh, { tex = S.grass_tex, color = {r, g, b, 1.0}, roughness = 0.82 })
    eng.render.set_sky(0.05 + 0.12 * f, 0.07 + 0.28 * f, 0.14 + 0.44 * f, 0.24 * (1.0 - f) + 0.48 * f, 0.18 + 0.44 * f, 0.22 + 0.52 * f)
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.006 })
    eng.render.add_light({ type = "dir", dir = {-0.45, -0.75, -0.5}, color = {2.3, 2.2, 2.0}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 18.0, 18.0}, color = {1.5, 1.9, 2.4}, range = 52.0 })

    S.seed_base = math.floor(eng.math.range(100, 900000))
    S.planet_mesh = eng.procgen.planet(S.seed_base, PLANET_R, 18, -0.25)
    S.grass_tex = eng.procgen.texture("grass", S.seed_base + 11, 64)
    S.stone_tex = eng.procgen.texture("cobble", S.seed_base + 23, 64)
    S.cyl_mesh = eng.asset.cylinder(0.95, 1.15, 0.25, 12)
    S.cloud_mesh = eng.asset.sphere(0.65, 10, 12)
    S.probe_mesh = eng.asset.load_mesh("assets/shared/meshes/starfighter.obj")
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.sfx_rain = eng.audio.synth("noise", 420, 0.14, 180)
    S.sfx_life = eng.audio.synth("triangle", 520, 0.18, 920)

    -- Barren 3D Cube-Sphere Planet + Radial Spherical Gravity
    S.planet_ent = eng.scene.spawn("barren_planet")
    eng.scene.set_pos(S.planet_ent, 0.0, 0.0, 0.0)
    eng.physics.set_planet_gravity(0, 0.0, 0.0, 0.0, 9.81, S.seed_base, PLANET_R)

    -- Pre-generate 3 varied L-system tree meshes for forest groves
    S.tree_meshes = {
        eng.procgen.tree(S.seed_base + 31, 2, 2.5, 0.18),
        eng.procgen.tree(S.seed_base + 47, 3, 2.9, 0.20),
        eng.procgen.tree(S.seed_base + 61, 2, 2.2, 0.16)
    }

    S.biomes = {}
    S.creatures = {}
    for i = 1, #BIOME_COORDS do
        local bc = BIOME_COORDS[i]
        local nx, ny, nz = sphere_dir(bc.lat, bc.lon)
        local sr = PLANET_R + 0.35
        local bx, by, bz = nx * sr, ny * sr, nz * sr

        local pad = eng.scene.spawn("biome_basin_" .. tostring(i))
        eng.scene.set_pos(pad, bx, by, bz)
        orient_radial(pad, nx, ny, nz)
        eng.scene.set_mesh(pad, S.cyl_mesh, { tex = S.stone_tex, color = {0.72, 0.46, 0.30, 1.0}, cast_shadow = true })

        local beacon = eng.scene.spawn("biome_beacon_" .. tostring(i))
        eng.scene.set_pos(beacon, nx * (sr + 0.35), ny * (sr + 0.35), nz * (sr + 0.35))
        orient_radial(beacon, nx, ny, nz)
        eng.scene.set_mesh(beacon, S.crystal_mesh, { color = {1.0, 0.65, 0.25, 1.0} })

        S.biomes[i] = {
            idx = i, lat = bc.lat, lon = bc.lon, arch = bc.arch,
            nx = nx, ny = ny, nz = nz, x = bx, y = by, z = bz,
            pad_ent = pad, beacon_ent = beacon, stage = 0
        }
    end

    S.probe_ent = eng.scene.spawn("terra_probe")
    eng.scene.set_scale(S.probe_ent, 0.75, 0.75, 0.75)
    eng.scene.set_mesh(S.probe_ent, S.probe_mesh, { color = {0.55, 0.92, 1.0, 1.0}, cast_shadow = true })

    S.orbit_lat = 20.0
    S.orbit_lon = 0.0
    S.seed_cd = 0.0
    S.time = 0.0
    S.steps_done = 0
    S.total_steps = #BIOME_COORDS * 2
    S.rain_bursts = 0
    S.trees_planted = 0
    S.animals_seeded = 0
    S.biosphere = 0
    S.won = false

    refresh_planet_tint()
    sync_probe_and_camera()
    eng.mod.emit("post_init")
end

local function seed_biome(b)
    if b.stage == 0 then
        -- Step 1: Seed raincloud & sprout procedural 3D L-system forest!
        b.stage = 1
        S.rain_bursts = S.rain_bursts + 1
        eng.scene.set_mesh(b.pad_ent, S.cyl_mesh, { tex = S.grass_tex, color = {0.28, 0.82, 0.42, 1.0}, cast_shadow = true })
        eng.scene.set_mesh(b.beacon_ent, S.crystal_mesh, { color = {0.30, 0.85, 1.0, 1.0} })

        local cloud = eng.scene.spawn("rain_cloud_" .. tostring(b.idx))
        local cr = PLANET_R + 2.45
        eng.scene.set_pos(cloud, b.nx * cr, b.ny * cr, b.nz * cr)
        eng.scene.set_scale(cloud, 1.35, 0.65, 1.15)
        eng.scene.set_mesh(cloud, S.cloud_mesh, { color = {0.82, 0.92, 1.0, 1.0} })

        local offsets = { {5.0, -5.0}, {-5.5, 5.5} }
        for t = 1, 2 do
            local tnx, tny, tnz = sphere_dir(b.lat + offsets[t][1], b.lon + offsets[t][2])
            local tr = PLANET_R + 0.30
            local te = eng.scene.spawn("forest_tree_" .. tostring(b.idx) .. "_" .. tostring(t))
            eng.scene.set_pos(te, tnx * tr, tny * tr, tnz * tr)
            orient_radial(te, tnx, tny, tnz)
            local tm = S.tree_meshes[((b.idx + t - 2) % #S.tree_meshes) + 1]
            eng.scene.set_mesh(te, tm, { color = {0.26, 0.78, 0.36, 1.0}, cast_shadow = true })
            S.trees_planted = S.trees_planted + 1
        end
        eng.audio.play(S.sfx_rain, b.x, b.y, b.z, 0)
    elseif b.stage == 1 then
        -- Step 2: Seed procedural articulated DNA animal into the lush forest!
        b.stage = 2
        eng.scene.despawn(b.beacon_ent)
        b.beacon_ent = nil

        local ae = eng.scene.spawn("wildlife_" .. tostring(b.idx))
        local ar = PLANET_R + 0.55
        local ax, ay, az = b.nx * ar, b.ny * ar, b.nz * ar
        eng.scene.set_pos(ae, ax, ay, az)
        orient_radial(ae, b.nx, b.ny, b.nz)
        eng.procgen.animal(ae, S.seed_base + b.idx * 83, b.arch)

        S.animals_seeded = S.animals_seeded + 1
        S.creatures[#S.creatures + 1] = { ent = ae, base_lat = b.lat, base_lon = b.lon, phase = b.idx * 1.1 }
        eng.audio.play(S.sfx_life, ax, ay, az, 0)
    end

    S.steps_done = S.steps_done + 1
    S.biosphere = math.floor((S.steps_done / S.total_steps) * 100.0 + 0.5)
    refresh_planet_tint()
    if S.biosphere >= 100 then
        S.biosphere = 100
        S.won = true
        eng.save.write("terra_garden", "biosphere_100")
    end
end

function update(dt)
    if S.won then return end
    S.time = S.time + dt
    S.seed_cd = math.max(0.0, S.seed_cd - dt)

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    if math.abs(mx) > 0.01 or math.abs(my) > 0.01 then
        S.orbit_lon = (S.orbit_lon + mx * 165.0 * dt) % 360.0
        S.orbit_lat = eng.math.clamp(S.orbit_lat + my * 110.0 * dt, -65.0, 65.0)
    end
    sync_probe_and_camera()

    -- Seed rain/forest or procedural wildlife onto aligned biome below orbital probe
    local act = eng.input.pressed("fire") or eng.input.pressed("jump") or eng.input.pressed("interact")
    if act and S.seed_cd <= 0.0 then
        local pnx, pny, pnz = sphere_dir(S.orbit_lat, S.orbit_lon)
        local best_b, best_dot = nil, 0.90 -- within ~25 degrees of orbital reticle
        for i = 1, #S.biomes do
            local b = S.biomes[i]
            if b.stage < 2 then
                local dot = pnx * b.nx + pny * b.ny + pnz * b.nz
                if dot > best_dot then
                    best_dot = dot
                    best_b = b
                end
            end
        end
        if best_b then
            S.seed_cd = 0.10
            seed_biome(best_b)
        end
    end

    -- Gentle surface roaming for seeded procedural wildlife
    for i = 1, #S.creatures do
        local c = S.creatures[i]
        local t = S.time * 1.6 + c.phase
        local clat = c.base_lat + math.sin(t) * 3.5
        local clon = c.base_lon + math.cos(t) * 4.5
        local cnx, cny, cnz = sphere_dir(clat, clon)
        local cr = PLANET_R + 0.55
        eng.scene.set_pos(c.ent, cnx * cr, cny * cr, cnz * cr)
        orient_radial(c.ent, cnx, cny, cnz)
    end
end

function draw()
    eng.render.draw_sprite(S.px, S.py, S.pz, 0.75, 0.75, S.orb_tex)
    local x, y = eng.ui.anchor("top_left", 16, 14, 620, 52, 1280, 720)
    local status = S.won and (" | " .. eng.i18n.t("victory")) or ""
    eng.ui.label(x, y, eng.i18n.t("title") .. string.format(" | TREES %d | WILDLIFE %d/6%s", S.trees_planted, S.animals_seeded, status), 1.0, {0.75, 1.0, 0.80, 1.0})
    eng.ui.bar(x, y + 24, 240, S.biosphere / 100.0, "BIOSPHERE " .. S.biosphere .. "% ")
end
