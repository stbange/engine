-- 048_monster_tamer_ring: Elemental Creature Battles with All 4 DNA IK Animal Archetypes
local S = game.state

local PARTY_SPEC = {
    { name = "Pyrofang",   arch = "quadruped",  elem = "fire",   bx = -4.8, bz = 4.6 },
    { name = "Zephyrwing", arch = "avian",      elem = "wind",   bx = -2.4, bz = 5.2 },
    { name = "Tidecoil",   arch = "serpentine", elem = "water",  bx =  2.4, bz = 5.2 },
    { name = "Thornscale", arch = "insectoid",  elem = "nature", bx =  4.8, bz = 4.6 }
}

local RIVAL_SPEC = {
    { name = "Briarhorn",  arch = "insectoid",  elem = "nature", hp = 36 },
    { name = "Cindermaw",  arch = "quadruped",  elem = "fire",   hp = 40 },
    { name = "Abysswyrm",  arch = "serpentine", elem = "water",  hp = 42 },
    { name = "Galeskull",  arch = "avian",      elem = "earth",  hp = 44 }
}

local SUPER = { fire = "nature", nature = "water", water = "fire", wind = "earth" }

local function place_party()
    for i = 1, #S.party do
        local p = S.party[i]
        if i == S.active_idx then
            eng.scene.set_pos(p.ent, 0.0, 0.25, 2.6)
            eng.scene.set_rot_deg(p.ent, 0.0, 0.0, 0.0)
        else
            eng.scene.set_pos(p.ent, p.bx, 0.25, p.bz)
            eng.scene.set_rot_deg(p.ent, 0.0, 0.0, 0.0)
        end
    end
end

local function spawn_rival(idx)
    local spec = RIVAL_SPEC[idx]
    local re = eng.scene.spawn("rival_mon_" .. idx)
    eng.scene.set_pos(re, 0.0, 0.25, -2.6)
    eng.scene.set_rot_deg(re, 0.0, 180.0, 0.0)
    eng.scene.set_scale(re, 1.25, 1.25, 1.25)
    eng.procgen.animal(re, S.seed + 200 + idx * 43, spec.arch)
    S.rival = {
        ent = re, idx = idx, name = spec.name, arch = spec.arch,
        elem = spec.elem, hp = spec.hp, max_hp = spec.hp, atb = 0.0
    }
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.008 })
    eng.render.set_sky(0.16, 0.28, 0.58, 0.52, 0.68, 0.88)
    eng.render.add_light({ type = "dir", dir = {-0.35, -1.0, -0.4}, color = {2.2, 2.15, 2.0}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 6.0, 0.0}, color = {1.6, 2.2, 2.8}, range = 28.0 })

    S.seed = math.floor(eng.math.range(100, 800000))
    local ring_tex = eng.procgen.texture("stone_brick", S.seed, 64)
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.cyl_mesh = eng.asset.cylinder(0.5, 0.5, 1.0, 18)
    S.pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.sfx_atk = eng.audio.synth("saw", 320, 0.14, 680)
    S.sfx_swap = eng.audio.synth("triangle", 440, 0.10, 620)

    -- Elemental Battle Ring Stadium
    local base = eng.scene.spawn("stadium_floor")
    eng.scene.set_pos(base, 0.0, -0.25, 0.0)
    eng.scene.set_scale(base, 22.0, 0.5, 22.0)
    eng.scene.set_mesh(base, S.cyl_mesh, { tex = ring_tex, color = {0.42, 0.46, 0.55, 1.0} })

    local rune_ring = eng.scene.spawn("elemental_ring")
    eng.scene.set_pos(rune_ring, 0.0, 0.12, 0.0)
    eng.scene.set_scale(rune_ring, 10.0, 0.25, 10.0)
    eng.scene.set_mesh(rune_ring, S.cyl_mesh, { color = {0.28, 0.65, 0.88, 1.0} })

    for i = 1, 8 do
        local a = (i / 8.0) * math.pi * 2.0
        local pe = eng.scene.spawn("stadium_pillar_" .. i)
        eng.scene.set_pos(pe, math.cos(a) * 9.2, 0.0, math.sin(a) * 9.2)
        eng.scene.set_mesh(pe, S.pillar_mesh, { color = {0.75, 0.78, 0.85, 1.0} })
    end

    -- Player & Rival Tamers on opposite podiums
    local tamer_p = eng.scene.spawn("player_tamer")
    eng.scene.set_pos(tamer_p, 0.0, 0.0, 6.2)
    eng.procgen.person(tamer_p, S.seed + 7)

    local tamer_r = eng.scene.spawn("rival_tamer")
    eng.scene.set_pos(tamer_r, 0.0, 0.0, -6.2)
    eng.scene.set_rot_deg(tamer_r, 0.0, 180.0, 0.0)
    eng.procgen.person(tamer_r, S.seed + 19)

    -- Spawn all 4 DNA-generated IK Animal Archetypes for Player Party
    S.party = {}
    for i = 1, #PARTY_SPEC do
        local sp = PARTY_SPEC[i]
        local me = eng.scene.spawn("party_" .. sp.arch)
        eng.scene.set_scale(me, 1.15, 1.15, 1.15)
        eng.procgen.animal(me, S.seed + i * 31, sp.arch)
        S.party[i] = {
            ent = me, name = sp.name, arch = sp.arch, elem = sp.elem,
            bx = sp.bx, bz = sp.bz, hp = 60, max_hp = 60
        }
    end

    S.active_idx = 1
    S.player_atb = 1.0
    S.lunge_t = 0.0
    S.orb_t = 0.0
    S.swaps = 0
    S.super_hits = 0
    S.rivals_defeated = 0
    S.won = false

    place_party()
    spawn_rival(1)

    eng.camera.look_at(0.0, 7.2, 10.8, 0.0, 0.8, -0.5, 0)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won or not S.rival then return end

    S.player_atb = math.min(1.0, S.player_atb + 3.4 * dt)
    S.lunge_t = math.max(0.0, S.lunge_t - dt * 4.0)
    S.orb_t = math.max(0.0, S.orb_t - dt * 3.5)

    -- Swap active creature archetype (left / right / interact)
    if eng.input.pressed("right") or eng.input.pressed("interact") then
        S.active_idx = (S.active_idx % #S.party) + 1
        S.swaps = S.swaps + 1
        place_party()
        eng.audio.play(S.sfx_swap, 0.0, 1.0, 2.6, 0)
    elseif eng.input.pressed("left") then
        S.active_idx = ((S.active_idx - 2) % #S.party) + 1
        S.swaps = S.swaps + 1
        place_party()
        eng.audio.play(S.sfx_swap, 0.0, 1.0, 2.6, 0)
    end

    local act_mon = S.party[S.active_idx]
    local riv = S.rival

    -- Elemental Mend on jump
    if eng.input.pressed("jump") and S.player_atb >= 0.5 then
        S.player_atb = 0.0
        act_mon.hp = math.min(act_mon.max_hp, act_mon.hp + 18)
    end

    -- Elemental Strike when ATB gauge is ready!
    if eng.input.pressed("fire") and S.player_atb >= 1.0 then
        S.player_atb = 0.0
        S.lunge_t = 1.0
        S.orb_t = 1.0
        eng.audio.play(S.sfx_atk, 0.0, 1.0, 0.0, 0)

        local is_super = (SUPER[act_mon.elem] == riv.elem)
        local dmg = is_super and 24 or 14
        if is_super then S.super_hits = S.super_hits + 1 end
        riv.hp = riv.hp - dmg
        if riv.hp <= 0 then
            eng.scene.despawn(riv.ent)
            S.rivals_defeated = S.rivals_defeated + 1
            if S.rivals_defeated < #RIVAL_SPEC then
                spawn_rival(S.rivals_defeated + 1)
                return
            else
                S.rival = nil
                S.won = true
                eng.save.write("monster_tamer", "cup_champion")
                return
            end
        end
    end

    -- Animate lunge offset on active creature
    local lz = 2.6 - math.sin(S.lunge_t * math.pi) * 1.4
    eng.scene.set_pos(act_mon.ent, 0.0, 0.25, lz)

    -- Rival ATB counter-attack
    riv.atb = riv.atb + 1.5 * dt
    if riv.atb >= 1.0 then
        riv.atb = 0.0
        act_mon.hp = math.max(12, act_mon.hp - 7)
    end

    eng.camera.look_at(0.0, 7.2, 10.8, 0.0, 0.8, -0.5, 0)
end

function draw()
    if S.orb_t > 0.0 then
        local oz = 2.2 - (1.0 - S.orb_t) * 4.6
        eng.render.draw_sprite(0.0, 1.1, oz, 0.7, 0.7, S.orb_tex)
    end
    local act_mon = S.party[S.active_idx]
    local rname = S.rival and (S.rival.name .. " [" .. S.rival.elem .. "]") or "DEFEATED"
    local x, y = eng.ui.anchor("top_left", 16, 14, 620, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | " .. act_mon.name .. " (" .. act_mon.arch .. "/" .. act_mon.elem .. ") VS " .. rname, 1.0, {0.65, 0.95, 1.0, 1.0})
    eng.ui.bar(x, y + 24, 200, act_mon.hp / act_mon.max_hp, "ALLY ")
    eng.ui.bar(x + 220, y + 24, 200, S.player_atb, "ATB  ")
end
