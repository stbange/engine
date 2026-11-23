-- Headless playtest for 063_gravity_flip_rooms: flips gravity across all 6 axes (-X, +X, -Y, +Y, -Z, +Z)
local FLIPS = {
    -- Stage 1: -X (left) -> +Y (up) -> +X (right) into East Wall Socket
    { frame = 4,   act = "left"  },
    { frame = 50,  act = "up"    },
    { frame = 96,  act = "right" },
    -- Stage 2: -Z (fire) -> +Y (up, ceiling latch) -> +Z (jump, south wall) -> -Y (down, final socket)
    { frame = 152, act = "fire"  },
    { frame = 198, act = "up"    },
    { frame = 248, act = "jump"  },
    { frame = 300, act = "down"  },
}

function playtest_frame(f)
    local S = game.state
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("up", false)
    eng.input.inject("down", false)
    eng.input.inject("fire", false)
    eng.input.inject("jump", false)

    if S.won then
        S.playtest_done = true
        return
    end
    for i = 1, #FLIPS do
        if f == FLIPS[i].frame then
            eng.input.inject(FLIPS[i].act, true)
        end
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_eq(eng, S.axes_count, 6, "Must exercise all 6 cardinal gravity axes (-X, +X, -Y, +Y, -Z, +Z)")
    eng.test.assert_eq(eng, S.stage, 2, "Must reach gravity room 2")
    eng.test.assert_true(eng, S.won == true, "Must slide key cubes into all wall/ceiling sockets")
    eng.test.assert_eq(eng, eng.save.read("gravity_flip_rooms"), "clear", "Save slot must record clear")
end
