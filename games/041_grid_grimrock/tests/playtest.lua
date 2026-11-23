-- Automated headless playtest for 041_grid_grimrock: 90-degree turns, plates, gates, skeletons!
local SCRIPT = {
    "up",                   -- (0,0) -> (0,1) facing skeleton #1 at (0,2)
    "fire", "fire",         -- slay skeleton #1
    "up",                   -- (0,1) -> (0,2)
    "right", "up",          -- turn East (+X), step onto plate #1 at (1,2) -> opens gate #1!
    "left", "left", "up",   -- turn West (-X), step back to (0,2)
    "right",                -- face North (-Z)
    "up", "up",             -- step through open gate #1 (0,3) -> (0,4) facing skeleton #2 at (0,5)
    "fire", "fire",         -- slay skeleton #2
    "up",                   -- (0,4) -> (0,5)
    "left", "up",           -- turn West (-X), step onto plate #2 at (-1,5) -> opens gate #2!
    "right", "right", "up", -- turn East (+X), step back to (0,5)
    "left",                 -- face North (-Z)
    "up", "up"              -- step through open gate #2 (0,6) -> exit shrine (0,7)!
}

function playtest_frame(f)
    local S = game.state
    eng.input.inject("up", false)
    eng.input.inject("down", false)
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("fire", false)

    if S.won then
        S.playtest_done = true
        return
    end

    if (f % 6) == 2 then
        local idx = math.floor(f / 6) + 1
        local act = SCRIPT[idx]
        if act then eng.input.inject(act, true) end
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.solvable == true, "BSP dungeon must be solvable")
    eng.test.assert_true(eng, S.turns_90 >= 6, "Must perform 90-degree grid turns")
    eng.test.assert_eq(eng, S.plates_pressed, 2, "Must depress both pressure plates")
    eng.test.assert_eq(eng, S.gates_opened, 2, "Must open both iron gates")
    eng.test.assert_eq(eng, S.kills, 2, "Must slay both skeleton guardians")
    eng.test.assert_true(eng, S.won == true, "Must reach exit shrine")
    eng.test.assert_eq(eng, eng.save.read("grimrock_progress"), "escaped", "Save must record escape")
end
