-- Automated headless playtest for 060_terra_garden:
-- Orbits the barren 3D cube-sphere planet to seed rain/forests & procedural wildlife across all 6 biomes to 100%!
local function shortest_lon_delta(from_deg, to_deg)
    local d = (to_deg - from_deg) % 360.0
    if d > 180.0 then d = d - 360.0 end
    return d
end

function playtest_frame(f)
    local S = game.state
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("up", false)
    eng.input.inject("down", false)
    eng.input.inject("fire", false)

    if S.won then
        S.playtest_done = true
        return
    end

    local target = nil
    for i = 1, #S.biomes do
        if S.biomes[i].stage < 2 then
            target = S.biomes[i]
            break
        end
    end
    if not target then return end

    local dlon = shortest_lon_delta(S.orbit_lon, target.lon)
    local dlat = target.lat - S.orbit_lat

    if math.abs(dlon) > 3.5 or math.abs(dlat) > 3.5 then
        eng.input.inject("right", dlon > 2.0)
        eng.input.inject("left", dlon < -2.0)
        eng.input.inject("up", dlat > 2.0)
        eng.input.inject("down", dlat < -2.0)
    else
        eng.input.inject("fire", (f % 2) == 1)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.planet_mesh > 0, "Must generate 3D cube-sphere planet via eng.procgen.planet")
    eng.test.assert_true(eng, S.rain_bursts >= 6, "Must seed rainstorms across all 6 barren biomes")
    eng.test.assert_true(eng, S.trees_planted >= 12, "Must grow procedural L-system forests via eng.procgen.tree")
    eng.test.assert_eq(eng, S.animals_seeded, 6, "Must seed procedural DNA wildlife via eng.procgen.animal")
    eng.test.assert_eq(eng, S.biosphere, 100, "Planetary biosphere must reach 100%")
    eng.test.assert_true(eng, S.won == true, "Terra Garden must win")
    eng.test.assert_eq(eng, eng.save.read("terra_garden"), "biosphere_100", "Save slot must record biosphere_100")
end
