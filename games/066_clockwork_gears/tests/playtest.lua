-- Headless playtest for 066_clockwork_gears: mounts exact gear ratios across single-plane & 3D coaxial dual-plane shafts
local CMDS = {
    -- Stage 1 (starts peg=1, size=1 SMALL):
    -- Peg 1 needs MEDIUM (size 2): up, fire; Peg 2 needs SMALL (size 1): right, down, fire
    { frame = 4,  act = "up"    },
    { frame = 8,  act = "fire"  },
    { frame = 12, act = "right" },
    { frame = 16, act = "down"  },
    { frame = 20, act = "fire"  },
    -- Wait ~25 frames for 0.35s bell spin -> Stage 2 starts (peg=1, size=1 SMALL):
    -- Peg 1 needs LARGE (size 3): up, up, fire
    { frame = 52, act = "up"    },
    { frame = 56, act = "up"    },
    { frame = 60, act = "fire"  },
    -- Peg 2 needs MEDIUM (size 2): right, down, fire
    { frame = 64, act = "right" },
    { frame = 68, act = "down"  },
    { frame = 72, act = "fire"  },
    -- Peg 3 needs SMALL (size 1): right, down, fire
    { frame = 76, act = "right" },
    { frame = 80, act = "down"  },
    { frame = 84, act = "fire"  },
}

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
    for i = 1, #CMDS do
        if f == CMDS[i].frame then
            eng.input.inject(CMDS[i].act, true)
        end
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.placements >= 5, "Must mount all 5 intermediate brass gear wheels")
    eng.test.assert_true(eng, math.abs(S.bell_omega) > 50.0, "Escapement bell must spin with propagated angular velocity")
    eng.test.assert_eq(eng, S.stage, 2, "Must reach clockwork tower 2")
    eng.test.assert_true(eng, S.won == true, "Must ring escapement bell in both clockwork towers")
    eng.test.assert_eq(eng, eng.save.read("clockwork_gears"), "clear", "Save slot must record clear")
end
