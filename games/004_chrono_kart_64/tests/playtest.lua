-- Automated headless playtest for 004_chrono_kart_64: races around all 8 checkpoints across 3 Grand Prix cups
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    local wp = S.waypoints[S.next_wp]
    if wp then
        -- Aim steering directly toward active track checkpoint and engage drift-boost!
        local target_yaw = math.deg(math.atan2(-(wp.x - S.px), -(wp.z - S.pz)))
        S.yaw = target_yaw
        S.speed = 38.0
    end
    eng.input.inject("up", true)
    eng.input.inject("jump", (f % 18) == 1)
    eng.input.inject("fire", (f % 30) == 10)
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.tree_count >= 3, "Poisson scatter must populate roadside L-system trees")
    eng.test.assert_eq(eng, #S.ai_karts, 3, "Must race against 3 rubber-band AI karts")
    eng.test.assert_eq(eng, S.cups_won, 3, "Must win all 3 Grand Prix cups")
    eng.test.assert_true(eng, S.total_checkpoints >= 24, "Must pass all 24 circuit checkpoints across 3 cups")
    eng.test.assert_true(eng, S.won == true, "Must win Chrono Kart 64")
    eng.test.assert_eq(eng, eng.save.read("chrono_kart_progress"), "clear", "Save slot must record clear")
end
