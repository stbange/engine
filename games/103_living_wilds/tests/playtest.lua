-- Deterministic automated playtest for 103_living_wilds
return function(t)
    local S = game.state
    assert(S ~= nil, "game.state missing")

    -- 1. Verify Gerstner water surface is active and systemic fire is burning at boot
    local wh, wen = eng.render.water_height(0.0, -4.0, 0)
    assert(wen == true and wh > -0.25 and wh < 0.25, "Gerstner alpine river must be active")
    local fires0 = eng.sim.active_fires(0)
    assert(fires0 >= 1, "Campfire + oil basin should burn at startup")

    -- 2. Step 50 frames: verify cedar logs float near water surface while granite boulder sinks!
    t.step(50)
    local _, log_y, _ = eng.scene.get_pos(eng.scene.find("cedar_log_1"))
    local _, bld_y, _ = eng.scene.get_pos(eng.scene.find("river_boulder"))
    assert(log_y > -0.25, "Buoyant pine log must float on Gerstner river, got y=" .. tostring(log_y))
    assert(bld_y < log_y - 0.35, "Dense stone boulder must sink below floating log")
    assert(eng.physics.joint_active(S.lantern_joint), "Swinging lantern joint must hold")

    -- 3. Cycle through tools (shock -> acid -> blast) and fracture the ancient voxel arch!
    for _ = 1, 3 do
        eng.input.inject("switch_crew", true)
        t.step(1)
        eng.input.inject("switch_crew", false)
        t.step(1)
    end
    eng.input.inject("fire", true)
    t.step(2)
    eng.input.inject("fire", false)
    t.step(20)
    assert(S.arch_fractured == true, "Blast tool must fracture voxel ruin arch")

    -- 4. Toggle alpine rainstorm and verify soil moisture & organism homeostasis stay finite
    eng.input.inject("interact", true)
    t.step(2)
    eng.input.inject("interact", false)
    t.step(25)
    assert(S.raining == true, "Interact action must toggle rainstorm")
    local cell = eng.sim.get_cell(2, 0, 9, 0)
    assert(cell ~= nil and cell.moisture > 0.1, "Rain must moisten soil terrace")

    -- 5. Walk East across the wooden bridge, then North through the Alchemist's Pocket Mill doorway!
    S.yaw = -math.pi * 0.5
    S.pitch = 0.0
    eng.input.inject("up", true)
    t.step(160)
    S.yaw = 0.0
    t.step(95)
    eng.input.inject("up", false)
    assert(S.pocket == S.mill_pocket, "Explorer should cross doorway into mill_inside pocket, got pocket=" .. tostring(S.pocket))

    local bio = eng.sim.get_bio(S.player_bio, 0)
    assert(bio ~= nil and bio.health > 0.5, "Explorer homeostasis health must remain healthy")
end
