-- Headless playtest for 065_magnet_polarity: toggles magnet polarity (`fire`) to carry & repel spheres across 3D chasms
local toggle_cooldown = 0

local function steer_toward(tx, tz)
    local S = game.state
    if S.mx < tx - 0.12 then eng.input.inject("right", true)
    elseif S.mx > tx + 0.12 then eng.input.inject("left", true) end
    if S.mz > tz + 0.12 then eng.input.inject("up", true)
    elseif S.mz < tz - 0.12 then eng.input.inject("down", true) end
end

function playtest_frame(f)
    (void_f_noop or function() end)(f)
    local S = game.state
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("up", false)
    eng.input.inject("down", false)
    eng.input.inject("fire", false)
    if toggle_cooldown > 0 then toggle_cooldown = toggle_cooldown - 1 end

    if S.won then
        S.playtest_done = true
        return
    end

    -- Pick first unlocked sphere & its matching goal plate
    local target_sp, target_gl = nil, nil
    for i = 1, #S.spheres do
        if not S.spheres[i].locked then
            target_sp = S.spheres[i]
            for j = 1, #S.goals do
                if S.goals[j].pol == target_sp.pol and not S.goals[j].satisfied then
                    target_gl = S.goals[j]
                    break
                end
            end
            break
        end
    end
    if not target_sp or not target_gl then return end

    local sx, sy, sz = eng.scene.get_pos(target_sp.ent)
    local dist_goal = eng.math.dist3(sx, 0.0, sz, target_gl.x, 0.0, target_gl.z)

    if dist_goal < 0.55 then
        -- Over goal plate: switch to SAME polarity to repel sphere down onto plate!
        steer_toward(target_gl.x, target_gl.z)
        if S.mag_pol ~= target_sp.pol and toggle_cooldown == 0 then
            eng.input.inject("fire", true)
            toggle_cooldown = 8
        end
    elseif eng.math.dist3(S.mx, 0.0, S.mz, sx, 0.0, sz) > 0.9 or sy < 1.1 then
        -- Fly magnet over sphere & ensure OPPOSITE polarity to attract/levitate
        steer_toward(sx, sz)
        if eng.math.dist3(S.mx, 0.0, S.mz, sx, 0.0, sz) < 1.1 and S.mag_pol == target_sp.pol and toggle_cooldown == 0 then
            eng.input.inject("fire", true)
            toggle_cooldown = 8
        end
    else
        -- Sphere is levitated under magnet: carry across chasm to goal plate!
        steer_toward(target_gl.x, target_gl.z)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.toggles >= 3, "Must toggle magnet polarity multiple times via fire")
    eng.test.assert_true(eng, S.chasm_crossings >= 3, "Must transport all 3 spheres across the 3D chasm")
    eng.test.assert_eq(eng, S.stage, 2, "Must reach lab 2")
    eng.test.assert_true(eng, S.won == true, "Must energize all magnetic goal plates")
    eng.test.assert_eq(eng, eng.save.read("magnet_polarity"), "clear", "Save slot must record clear")
end
