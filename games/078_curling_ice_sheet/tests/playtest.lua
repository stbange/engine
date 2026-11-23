-- Headless playtest for 078_curling_ice_sheet: slides granite stones & sweeps vigorously to park on the Button!
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end
    eng.input.inject("fire", false)
    eng.input.inject("interact", false)

    if not S.sliding then
        -- Aim outside left guard (-0.28) so right-curl draws right onto the Button (0, -7.5)!
        S.aim_x = (S.stones_thrown == 1) and -0.26 or 0.18
        S.curl_dir = (S.stones_thrown == 1) and 1.0 or -0.5
        S.power = 0.62
        eng.input.inject("fire", true)
    else
        -- Sweep (`interact`) dynamically whenever v^2 / (2 * unswept_decel) would stop short of the Button (-7.5)!
        local st = S.active_stone
        local _, _, sz = eng.scene.get_pos(st.ent)
        local vx, _, vz = eng.physics.get_vel(st.body)
        local hspd = math.sqrt(vx * vx + vz * vz)
        local dist_to_btn = sz - (-7.5)
        local unswept_stop = (hspd * hspd) / (2.0 * 4.55)
        if dist_to_btn > 0.10 and unswept_stop < dist_to_btn then
            eng.input.inject("interact", true)
        end
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.sweep_ticks >= 20, "Must sweep ice vigorously with interact/jump to extend glide")
    eng.test.assert_true(eng, S.best_player < S.best_opp, "Player stone must finish closer to Button than opponent")
    eng.test.assert_true(eng, S.best_player < 0.50, "Shot stone must park inside the 4-foot ring near the Button")
    eng.test.assert_true(eng, S.won == true, "Must win the Curling End")
end
