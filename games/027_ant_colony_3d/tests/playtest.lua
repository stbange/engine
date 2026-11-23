-- Automated headless playtest for 027_ant_colony_3d: paints pheromone trails from nest to crystals & harvests 6 loads
local WAYPOINTS = {
    { 4.4, -3.6}, -- Highway 1: Nest (-4.4, -4.4) -> North-East Crystal (4.4, -3.3)
    {-4.4, -4.4}, -- Return brush to Nest
    {-3.6,  4.4}  -- Highway 2: Nest -> South-West Crystal (-3.3, 4.4)
}
local wp_idx = 1

function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    eng.input.inject("interact", (f % 45) == 0)

    if wp_idx <= #WAYPOINTS then
        local tx, tz = WAYPOINTS[wp_idx][1], WAYPOINTS[wp_idx][2]
        local dx, dz = tx - S.bx, tz - S.bz
        eng.input.inject("left", dx < -0.15)
        eng.input.inject("right", dx > 0.15)
        eng.input.inject("up", dz < -0.15)
        eng.input.inject("down", dz > 0.15)
        eng.input.inject("fire", wp_idx ~= 2)
        if math.abs(dx) <= 0.22 and math.abs(dz) <= 0.22 then
            wp_idx = wp_idx + 1
        end
    else
        eng.input.inject("left", false)
        eng.input.inject("right", false)
        eng.input.inject("up", false)
        eng.input.inject("down", false)
        eng.input.inject("fire", false)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_eq(eng, S.ant_count, 6, "Must spawn 6 procedural insectoid worker ants")
    eng.test.assert_true(eng, S.pheromone_laid >= 6, "Must paint pheromone foraging highway")
    eng.test.assert_true(eng, S.food_stored >= S.target_food, "Worker ants must deliver food crystals to Queen's nest")
    eng.test.assert_true(eng, S.won == true, "Colony foraging simulation must succeed")
end
