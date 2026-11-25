-- Automated 4-Player Split-Screen + Authoritative Loopback Server Playtest for 102_portal_arena_mp
local S = game.state

function playtest_frame(f)
    if f == 1 then
        -- Switch into full 4-way 2x2 split-screen + verify loopback online multiplayer simultaneously
        eng.input.inject("split_4", true)
        assert(eng.net.start_loopback())
        S._test_srv = eng.mp.create_server(eng, {
            seed = 102,
            snapshot_hz = 60,
            on_join = function(cid, p) p.x, p.y, p.z = 0, 1.45, 4.0 end,
            on_input = function(cid, p, pkt, dt)
                p.x = p.x + (pkt.mx or 0) * 6.0 * dt
                p.z = p.z - (pkt.my or 0) * 6.0 * dt
            end
        })
        S.cli = eng.mp.create_client(eng, { input_hz = 60 })
    else
        eng.input.inject("split_4", false)
    end

    -- Clear all 4 player inputs each frame
    for i = 1, 4 do
        eng.input.inject_player(i, "up", false)
        eng.input.inject_player(i, "down", false)
        eng.input.inject_player(i, "left", false)
        eng.input.inject_player(i, "right", false)
    end

    -- Drive all 4 split-screen players independently:
    -- P1 walks forward into the central Bigger-on-the-Inside Crystal Vault doorway!
    local p1 = S.local_players[1]
    if f <= 135 then
        if p1.x < -0.15 then eng.input.inject_player(1, "right", true)
        elseif p1.x > 0.15 then eng.input.inject_player(1, "left", true) end
        eng.input.inject_player(1, "up", true)
    end

    -- P2 strafes right toward the emerald gem, P3 walks left, P4 walks forward-right
    if f <= 50 then eng.input.inject_player(2, "right", true) end
    if f <= 50 then eng.input.inject_player(3, "left", true) end
    if f <= 50 then eng.input.inject_player(4, "up", true) end

    -- Step loopback authoritative server alongside client
    if S._test_srv then S._test_srv:step(1.0 / 60.0) end

    if f >= 140 then S.playtest_done = true end
end

function playtest_verify()
    eng.test.assert_eq(eng, S.split_count, 4, "4-player 2x2 split-screen activated")
    eng.test.assert_true(eng, S.entered_vault, "Player 1 crossed into Bigger-on-the-Inside Crystal Vault")
    eng.test.assert_true(eng, S.local_players[1].sc >= 2, "Player 1 collected Crystal Vault gem")
    eng.test.assert_true(eng, S.local_players[2].x > 4.0, "Player 2 moved right independently")
    eng.test.assert_true(eng, S.local_players[3].x < -6.5, "Player 3 moved left independently")
    eng.test.assert_true(eng, S.local_players[4].z < 6.5, "Player 4 moved forward independently")
    eng.test.assert_eq(eng, S.cli.local_id, 1, "Online client received authoritative welcome client_id=1")
    eng.test.assert_eq(eng, S.cli.seed, 102, "Online client synced deterministic world seed=102")
    eng.test.assert_true(eng, S.cli.players[1] ~= nil and S.cli.players[1].z < 3.5, "Authoritative server replicated client movement")
end
