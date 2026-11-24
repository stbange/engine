-- 047_arena_gladiator: Stamina Melee & Timed Shield Parry vs 3 Rigged Colosseum Gladiators
local S = game.state

local function spawn_challenger(idx)
    S.round = idx
    local ge = eng.scene.spawn("gladiator_" .. idx)
    local gx, gz = 0.0, -4.5
    eng.scene.set_pos(ge, gx, 0.0, gz)
    local colors = { {0.85, 0.55, 0.28, 1.0}, {0.35, 0.72, 0.92, 1.0}, {0.95, 0.25, 0.32, 1.0} }
    eng.scene.set_mesh(ge, S.box_mesh, { color = colors[idx] or colors[1] })
    local info = eng.procgen.person(ge, S.seed + idx * 67)
    S.opp = {
        ent = ge, x = gx, z = gz,
        name = info.name,
        hp = 26 + idx * 8,
        max_hp = 26 + idx * 8,
        state = "advance",
        timer = 0.35,
        stagger = 0.0
    }
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.010 })
    eng.render.set_sky(0.32, 0.56, 0.88, 0.85, 0.76, 0.58)
    eng.render.add_light({ type = "dir", dir = {-0.4, -1.0, -0.35}, color = {2.35, 2.15, 1.85}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 6.0, 0.0}, color = {2.0, 1.6, 1.1}, range = 28.0 })

    S.seed = math.floor(eng.math.range(100, 700000))
    local sand_tex = eng.procgen.texture("cobble", S.seed, 64)
    local stone_tex = eng.procgen.texture("stone_brick", S.seed + 19, 64)

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.cyl_mesh = eng.asset.cylinder(0.5, 0.5, 1.0, 16)
    S.pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.sfx_slash = eng.audio.synth("saw", 250, 0.10, 110)
    S.sfx_parry = eng.audio.synth("triangle", 620, 0.18, 980)

    -- Colosseum sand floor & colonnade ring
    local arena = eng.scene.spawn("colosseum_sand")
    eng.scene.set_pos(arena, 0.0, -0.25, 0.0)
    eng.scene.set_scale(arena, 24.0, 0.5, 24.0)
    eng.scene.set_mesh(arena, S.cyl_mesh, { tex = sand_tex, color = {0.88, 0.76, 0.52, 1.0} })

    for i = 1, 10 do
        local a = (i / 10.0) * math.pi * 2.0
        local cx, cz = math.cos(a) * 10.0, math.sin(a) * 10.0
        local col = eng.scene.spawn("colosseum_pillar_" .. i)
        eng.scene.set_pos(col, cx, 0.0, cz)
        eng.scene.set_scale(col, 1.1, 1.35, 1.1)
        eng.scene.set_mesh(col, S.pillar_mesh, { tex = stone_tex, color = {0.84, 0.78, 0.68, 1.0} })
    end

    local gate = eng.scene.spawn("champion_gate")
    eng.scene.set_pos(gate, 0.0, 0.0, -10.2)
    eng.scene.set_scale(gate, 1.3, 1.3, 1.2)
    eng.scene.set_mesh(gate, S.arch_mesh, { tex = stone_tex, color = {0.75, 0.70, 0.62, 1.0} })

    -- Player Gladiator + Shield & Gladius
    S.px, S.pz = 0.0, 3.0
    S.hero_ent = eng.scene.spawn("player_gladiator")
    eng.scene.set_pos(S.hero_ent, S.px, 0.0, S.pz)
    eng.procgen.person(S.hero_ent, S.seed + 3)

    S.shield_ent = eng.scene.spawn("bronze_shield")
    eng.scene.set_parent(S.shield_ent, S.hero_ent)
    eng.scene.set_pos(S.shield_ent, -0.45, 1.0, -0.35)
    eng.scene.set_scale(S.shield_ent, 0.65, 0.75, 0.12)
    eng.scene.set_mesh(S.shield_ent, S.box_mesh, { color = {0.92, 0.74, 0.28, 1.0}, metallic = 0.85, roughness = 0.25 })

    S.hp = 100
    S.stamina = 100.0
    S.parry_timer = 0.0
    S.atk_cd = 0.0
    S.parries = 0
    S.ripostes = 0
    S.kills = 0
    S.won = false

    spawn_challenger(1)
    eng.camera.look_at(0.0, 5.8, 8.8, 0.0, 1.1, -1.5, 0)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won or not S.opp then return end

    S.stamina = math.min(100.0, S.stamina + 38.0 * dt)
    S.parry_timer = math.max(0.0, S.parry_timer - dt)
    S.atk_cd = math.max(0.0, S.atk_cd - dt)

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    if math.abs(mx) > 0.01 or math.abs(my) > 0.01 then
        S.px = eng.math.clamp(S.px + mx * 6.5 * dt, -7.5, 7.5)
        S.pz = eng.math.clamp(S.pz - my * 6.5 * dt, -7.5, 7.5)
        eng.scene.set_pos(S.hero_ent, S.px, 0.0, S.pz)
    end

    -- Raise bronze shield for timed parry
    if (eng.input.pressed("interact") or eng.input.pressed("jump")) and S.stamina >= 10.0 and S.parry_timer <= 0.0 then
        S.stamina = S.stamina - 10.0
        S.parry_timer = 0.52
        eng.scene.set_pos(S.shield_ent, 0.0, 1.12, -0.52)
    elseif S.parry_timer <= 0.0 then
        eng.scene.set_pos(S.shield_ent, -0.45, 1.0, -0.35)
    end

    local opp = S.opp
    local dist = eng.math.dist3(S.px, 0, S.pz, opp.x, 0, opp.z)

    -- Stamina-cost sword slash (double riposte damage if opponent is staggered!)
    if eng.input.pressed("fire") and S.atk_cd <= 0.0 and S.stamina >= 18.0 then
        S.stamina = S.stamina - 18.0
        S.atk_cd = 0.18
        eng.audio.play(S.sfx_slash, S.px, 1.1, S.pz, 0)
        if dist < 2.6 then
            local dmg = (opp.stagger > 0.0) and 30 or 14
            if opp.stagger > 0.0 then S.ripostes = S.ripostes + 1 end
            opp.hp = opp.hp - dmg
            if opp.hp <= 0 then
                eng.scene.despawn(opp.ent)
                S.kills = S.kills + 1
                if S.kills < 3 then
                    spawn_challenger(S.kills + 1)
                    return
                else
                    S.opp = nil
                    S.won = true
                    eng.save.write("arena_gladiator", "champion")
                    return
                end
            end
        end
    end

    -- Challenger AI: advance -> telegraphed windup -> strike (parryable!)
    if opp.stagger > 0.0 then
        opp.stagger = opp.stagger - dt
    elseif opp.state == "advance" then
        if dist > 1.85 then
            local dx, dz = S.px - opp.x, S.pz - opp.z
            opp.x = opp.x + (dx / dist) * 4.8 * dt
            opp.z = opp.z + (dz / dist) * 4.8 * dt
            eng.scene.set_pos(opp.ent, opp.x, 0.0, opp.z)
            eng.scene.set_rot_deg(opp.ent, 0.0, math.deg(math.atan2(-dx, -dz)), 0.0)
        else
            opp.state = "windup"
            opp.timer = 0.36
        end
    elseif opp.state == "windup" then
        opp.timer = opp.timer - dt
        if opp.timer <= 0.0 then
            if dist < 2.6 then
                if S.parry_timer > 0.0 then
                    S.parries = S.parries + 1
                    S.stamina = math.min(100.0, S.stamina + 28.0)
                    opp.stagger = 1.35
                    eng.audio.play(S.sfx_parry, opp.x, 1.2, opp.z, 0)
                else
                    S.hp = math.max(15, S.hp - 14)
                end
            end
            opp.state = "advance"
        end
    end

    eng.camera.look_at(S.px * 0.5, 5.8, S.pz + 5.8, S.px * 0.5, 1.1, S.pz - 1.5, 0)
end

function draw()
    if S.opp and S.opp.state == "windup" then
        eng.render.draw_sprite(S.opp.x, 2.15, S.opp.z, 0.55, 0.55, S.orb_tex)
    end
    local vs_name = S.opp and S.opp.name or "CHAMPION"
    local x, y = eng.ui.anchor("top_left", 16, 14, 560, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | DUEL " .. S.round .. "/3 (" .. vs_name .. ") | PARRIES " .. S.parries, 1.0, {1.0, 0.85, 0.45, 1.0})
    eng.ui.bar(x, y + 24, 200, S.hp / 100.0, "HP  ")
    eng.ui.bar(x + 210, y + 24, 200, S.stamina / 100.0, "STM ")
end
