-- Automated headless playtest for 002_sky_islands_vox: harvests sky crystals & enters workshop tent across 3 stages
local function step_toward(S, tx, tz, step_len)
    local dx, dz = tx - S.px, tz - S.pz
    local d = math.sqrt(dx * dx + dz * dz)
    if d <= step_len then
        S.px, S.pz = tx, tz
    elseif d > 0.001 then
        S.px = S.px + (dx / d) * step_len
        S.pz = S.pz + (dz / d) * step_len
    end
end

function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("up", false)
    eng.input.inject("down", false)
    eng.input.inject("jump", (f % 35) == 5)
    eng.input.inject("fire", (f % 4) == 1)

    if S.pocket == S.tent.pocket_id then
        if S.harvested_this_stage >= S.stage_goal then
            -- Walk to the workshop forge at (0, 0, 2) to upgrade gear
            step_toward(S, 0.0, 2.0, 2.2)
        else
            -- Position just inside tent doorway (0, 12.2), then inject 'down' (+Z) so update(dt) crosses z=12.8!
            if S.pz < 12.3 then
                S.px, S.pz = 0.0, 12.5
            end
            eng.input.inject("down", true)
        end
    else
        local target_c = nil
        for i = 1, #S.crystals do
            if S.crystals[i].active then target_c = S.crystals[i]; break end
        end
        if target_c then
            step_toward(S, target_c.x, target_c.z, 2.4)
        else
            -- Position just in front of tent doorway (0, -4.9), then inject 'up' (-Z) so update(dt) crosses z=-5.2!
            if math.abs(S.px) > 0.15 or S.pz > -4.8 or S.pz < -5.2 then
                S.px, S.pz = 0.0, -4.95
            end
            eng.input.inject("up", true)
        end
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.tent_visits >= 3, "Must enter Bigger-on-the-Inside workshop tent on all 3 stages")
    eng.test.assert_true(eng, S.total_crystals >= 9, "Must harvest all 9 sky crystals across 3 stages")
    eng.test.assert_eq(eng, S.gear_tier, 3, "Must forge Tier 3 gear inside workshop tent")
    eng.test.assert_eq(eng, S.stage, 3, "Must reach final stage 3")
    eng.test.assert_true(eng, S.won == true, "Must win Sky Islands Vox")
    eng.test.assert_eq(eng, eng.save.read("sky_islands_progress"), "clear", "Save slot must record clear")
end
