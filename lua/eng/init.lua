-- Engine (stbange/engine) Lua 5.1 / LuaJIT Core Runtime Bootstrap
-- Strictly adheres to Lua 5.1 + bit.* subset across Desktop and Emscripten Web.

local bit = require("bit")

local M = {
    version = "0.1.0",
    coords = { right = "+X", up = "+Y", forward = "-Z", unit = "meter" },
}

function M.mask_combine(a, b)
    return bit.bor(bit.band(a, 0xFFFF), bit.lshift(bit.band(b, 0xFFFF), 16))
end

function M.is_finite(x)
    return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

return M
