-- Automated headless playtest for 070_domino_chain_lab:
-- Places missing domino slabs into every track gap, then flicks the starter domino (`fire`) to topple the golden bell!
function playtest_frame(f)
    local S = game.state
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("up", false)
    eng.input.inject("down", false)
    eng.input.inject("jump", false)
    eng.input.inject("fire", false)

    if S.won then
        S.playtest_done = true
        return
    end
    if S.chain_running then return end

    local gap = nil
    for i = 1, #S.dominoes do
        if not S.dominoes[i].present then
            gap = S.dominoes[i]
            break
        end
    end

    if gap then
        local dx, dz = gap.x - S.cx, gap.z - S.cz
        if math.abs(dx) > 0.35 or math.abs(dz) > 0.35 then
            eng.input.inject("right", dx > 0.2)
            eng.input.inject("left", dx < -0.2)
            eng.input.inject("up", dz < -0.2)
            eng.input.inject("down", dz > 0.2)
        else
            eng.input.inject("jump", (f % 2) == 1)
        end
    else
        -- All missing slabs placed! Flick starter domino via `fire`!
        eng.input.inject("fire", (f % 2) == 1)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_eq(eng, S.placed_total, 7, "Must place all 7 missing domino slabs across both lab tracks")
    eng.test.assert_true(eng, S.flicks >= 2, "Must flick starter domino via fire on each track")
    eng.test.assert_true(eng, S.toppled_total >= 29, "Chain reaction must topple all 29 dominoes")
    eng.test.assert_eq(eng, S.bells_rung, 2, "Chain reaction must topple both golden bells")
    eng.test.assert_eq(eng, S.stage, 2, "Must complete Lab Track 2")
    eng.test.assert_true(eng, S.won == true, "Domino Chain Lab must win")
    eng.test.assert_eq(eng, eng.save.read("domino_chain_lab"), "clear", "Save slot must record clear")
end
