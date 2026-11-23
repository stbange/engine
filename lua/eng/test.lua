-- Automated Headless Playtest & Failing-Frame Snapshot Harness (eng.test)
local M = {}

local function fail_msg(eng_root, msg)
    local snap = eng_root and eng_root.scene and eng_root.scene.dump_json() or "{}"
    error("[PLAYTEST FAIL] " .. tostring(msg) .. "\nEntity Snapshot: " .. snap, 2)
end

function M.assert_true(eng_root, cond, msg)
    if not cond then fail_msg(eng_root, msg or "expected truthy value") end
end

function M.assert_eq(eng_root, actual, expected, msg)
    if actual ~= expected then
        fail_msg(eng_root, (msg or "mismatch") .. ": got " .. tostring(actual) .. ", expected " .. tostring(expected))
    end
end

function M.assert_near(eng_root, a, b, eps, msg)
    if math.abs((a or 0.0) - (b or 0.0)) > (eps or 1e-3) then
        fail_msg(eng_root, (msg or "not near") .. ": got " .. tostring(a) .. " vs " .. tostring(b))
    end
end

return M
