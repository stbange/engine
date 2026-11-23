-- Headless playtest for 090_joust_sky_knights: flaps avian mount to higher Y altitude, wins all 4 jousts & scoops all 4 eggs!
local WRAP_X = 13.0

local function wrap_dx(dx)
    if dx > WRAP_X then return dx - WRAP_X * 2.0 end
    if dx < -WRAP_X then return dx + WRAP_X * 2.0 end
    return dx
end

function playtest_frame(f)
    local S = game.state
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("jump", false)

    if S.won then
        S.playtest_done = true
        return
    end

    -- Priority 1: Scoop any dropped knight egg immediately
    if #S.eggs > 0 then
        local best_egg, best_d = nil, 999.0
        for i = 1, #S.eggs do
            local eg = S.eggs[i]
            local d = math.abs(wrap_dx(eg.x - S.px)) + math.abs(eg.y - (S.py + 0.65))
            if d < best_d then best_d = d; best_egg = eg end
        end
        if best_egg then
            local dx = wrap_dx(best_egg.x - S.px)
            local lead_dx = dx - (S.vx - best_egg.vx) * 0.08
            if lead_dx > 0.12 then eng.input.inject("right", true)
            elseif lead_dx < -0.12 then eng.input.inject("left", true) end

            local want_y = math.max(1.1, best_egg.y - 0.55)
            if (S.py + S.vy * 0.10) < want_y then
                eng.input.inject("jump", true)
            end
            return
        end
    end

    -- Priority 2: Climb strictly ABOVE the nearest living enemy Sky Knight, then swoop into lance collision!
    local best_en, best_d = nil, 999.0
    for i = 1, #S.enemies do
        local en = S.enemies[i]
        if en.alive then
            local d = math.abs(wrap_dx(en.x - S.px)) + math.abs(en.y - S.py) * 0.5
            if d < best_d then best_d = d; best_en = en end
        end
    end
    if not best_en then return end

    local dx = wrap_dx(best_en.x - S.px)
    local want_y = math.min(9.3, best_en.y + 0.90)

    -- Always flap first to establish superior Y altitude before closing horizontal lance range!
    if (S.py + S.vy * 0.10) < want_y then
        eng.input.inject("jump", true)
    end

    if S.py < best_en.y + 0.40 and math.abs(dx) < 3.4 then
        -- Hold back horizontally while gaining altitude so we never strike from below!
        if dx >= 0.0 then eng.input.inject("left", true) else eng.input.inject("right", true) end
    else
        local lead_dx = dx - (S.vx - best_en.vx) * 0.08
        if lead_dx > 0.10 then eng.input.inject("right", true)
        elseif lead_dx < -0.10 then eng.input.inject("left", true) end
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.flaps >= 8, "Must flap winged avian mount over lava platforms")
    eng.test.assert_eq(eng, S.jousts_won, 4, "Must win all 4 aerial lance collisions from higher Y altitude")
    eng.test.assert_eq(eng, S.eggs_collected, 4, "Must collect all 4 dropped knight eggs")
    eng.test.assert_true(eng, S.won == true, "Must win Joust Sky Knights")
end
