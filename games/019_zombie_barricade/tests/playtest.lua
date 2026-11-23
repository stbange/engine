-- Headless playtest for 019_zombie_barricade:
-- Patrols cabin windows hammering wooden planks (interact) while blasting all 3 zombie waves through the windows!
function playtest_frame(f)
    local S = game.state
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("up", false)
    eng.input.inject("down", false)
    eng.input.inject("interact", true)
    eng.input.inject("fire", (f % 4) == 1)

    if S.won or S.lost then
        S.playtest_done = true
        return
    end

    -- Move toward any window missing planks first, else align with nearest living zombie's window
    local target_x = 0.0
    local found_damaged = false
    for i = 1, #S.windows do
        if S.windows[i].planks < 3 then
            target_x = S.windows[i].x
            found_damaged = true
            break
        end
    end
    if not found_damaged then
        for i = 1, #S.zombies do
            if S.zombies[i].alive then
                target_x = S.zombies[i].x
                break
            end
        end
    end

    if S.px < target_x - 0.25 then eng.input.inject("right", true)
    elseif S.px > target_x + 0.25 then eng.input.inject("left", true) end
    if S.pz > -2.6 then eng.input.inject("up", true) end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.repairs >= 3, "Player must hammer wooden plank barricades onto windows via interact")
    eng.test.assert_eq(eng, S.kills, 12, "Player must blast all 12 zombies across 3 waves through cabin windows")
    eng.test.assert_eq(eng, S.wave, 3, "Must survive through final wave 3")
    eng.test.assert_true(eng, S.hp > 0 and S.won == true, "Cabin must survive until dawn")
    eng.test.assert_eq(eng, eng.save.read("zombie_barricade"), "clear", "Save slot must record clear")
end
