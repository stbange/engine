-- Automated headless playtest for 069_iso_path_illusion:
-- Rotates the Monument Bridge Arch to connect the lower terrace, walks onto the arch, then aligns the impossible perspective angle to ascend to the upper shrine!
local function angle_delta(from_deg, to_deg)
    local d = (to_deg - from_deg) % 360.0
    if d > 180.0 then d = d - 360.0 end
    return d
end

function playtest_frame(f)
    (void_noop or function() end)(f)
    local S = game.state
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("up", false)

    if S.won then
        S.playtest_done = true
        return
    end

    if S.phase == 1 then
        if S.prog < 0.99 then
            eng.input.inject("up", true)
        elseif not S.lower_linked then
            local d = angle_delta(S.arch_yaw, S.want_low_yaw)
            eng.input.inject("right", d > 0.0)
            eng.input.inject("left", d <= 0.0)
        else
            eng.input.inject("up", true)
        end
    elseif S.phase == 2 then
        if S.prog < 0.99 then
            eng.input.inject("up", true)
        elseif not S.illusion_linked then
            local d = angle_delta(S.arch_yaw, S.want_up_yaw)
            eng.input.inject("right", d > 0.0)
            eng.input.inject("left", d <= 0.0)
        else
            eng.input.inject("up", true)
        end
    else
        eng.input.inject("up", true)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.arch_turns >= 180.0, "Must rotate the bridge arch across multiple perspective angles")
    eng.test.assert_eq(eng, S.illusion_crossings, 2, "Must cross both lower-to-upper perspective sightline bridges")
    eng.test.assert_eq(eng, S.stage, 2, "Must complete Spire 2")
    eng.test.assert_true(eng, S.won == true, "Iso Path Illusion must win")
    eng.test.assert_eq(eng, eng.save.read("iso_path_illusion"), "clear", "Save slot must record clear")
end
