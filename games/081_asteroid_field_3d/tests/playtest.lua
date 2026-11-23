-- Headless playtest for 081_asteroid_field_3d: splits & clears all 3D asteroid tiers
local function shortest_wrap(d, bound)
    if d > bound then return d - bound * 2.0 end
    if d < -bound then return d + bound * 2.0 end
    return d
end

local locked_rock = nil

function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    if not locked_rock or not locked_rock.alive then
        locked_rock = nil
        local best_d = 999.0
        for i = 1, #S.rocks do
            local r = S.rocks[i]
            if r.alive then
                local dx = shortest_wrap(r.x - S.px, 15.0)
                local dz = shortest_wrap(r.z - S.pz, 15.0)
                local d = math.sqrt(dx * dx + dz * dz)
                if d < best_d then best_d = d; locked_rock = r end
            end
        end
    end

    if not locked_rock then return end

    local dx = shortest_wrap(locked_rock.x - S.px, 15.0)
    local dz = shortest_wrap(locked_rock.z - S.pz, 15.0)
    local d = math.sqrt(dx * dx + dz * dz)
    local t_lead = math.max(0.0, (d - 1.4) / 30.0)
    local lx = dx + (locked_rock.vx - S.vx * 0.25) * t_lead
    local lz = dz + (locked_rock.vz - S.vz * 0.25) * t_lead
    t_lead = math.max(0.0, (math.sqrt(lx * lx + lz * lz) - 1.4) / 30.0)
    lx = dx + (locked_rock.vx - S.vx * 0.25) * t_lead
    lz = dz + (locked_rock.vz - S.vz * 0.25) * t_lead

    local target_yaw = math.deg(math.atan2(-lx, -lz))
    local diff = (target_yaw - S.yaw + 180.0) % 360.0 - 180.0

    eng.input.inject("left", diff > 2.0)
    eng.input.inject("right", diff < -2.0)
    eng.input.inject("up", d > 12.5 and math.abs(diff) < 12.0)
    eng.input.inject("down", d < 2.6)
    eng.input.inject("fire", math.abs(diff) < 14.0)
end

function playtest_verify()
    local S = game.state
    eng.test.assert_eq(eng, S.medium_spawned, 6, "3 large rocks must split into 6 medium rocks")
    eng.test.assert_eq(eng, S.small_spawned, 12, "6 medium rocks must split into 12 small fragments")
    eng.test.assert_eq(eng, S.rocks_destroyed, 21, "All 21 asteroid tiers must be blasted")
    eng.test.assert_true(eng, S.won == true, "Sector must be cleared")
end
