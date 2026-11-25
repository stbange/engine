-- Immediate-mode resolution-anchored In-Game HUD helpers (eng.ui)
local M = { _cmds = {} }

function M.anchor(anchor, ox, oy, w, h, sw, sh)
    sw, sh = sw or 1280, sh or 720
    local sx, sy = sw / 1280.0, sh / 720.0
    local s = math.max(0.25, math.min(sx, sy))
    local rw, rh = math.min(sw, w * s), math.min(sh, h * s)
    local x, y = ox * sx, oy * sy
    if anchor == "top_right" then x = sw - rw - ox * sx
    elseif anchor == "bottom_left" then y = sh - rh - oy * sy
    elseif anchor == "bottom_right" then x, y = sw - rw - ox * sx, sh - rh - oy * sy
    elseif anchor == "center" then x, y = (sw - rw) * 0.5 + ox * sx, (sh - rh) * 0.5 + oy * sy end
    x = math.max(0.0, math.min(sw - rw, x))
    y = math.max(0.0, math.min(sh - rh, y))
    return x, y, rw, rh, s
end

function M.viewport_anchor(vp, anchor, ox, oy, w, h, sw, sh)
    sw, sh = sw or 1280, sh or 720
    local vx, vy, vw, vh = (vp[1] or 0) * sw, (vp[2] or 0) * sh, (vp[3] or 1) * sw, (vp[4] or 1) * sh
    local x, y, rw, rh, s = M.anchor(anchor, ox, oy, w, h, vw, vh)
    return vx + x, vy + y, rw, rh, s
end

function M.label(x, y, text, scale, color)
    M._cmds[#M._cmds + 1] = { kind = "text", x = x, y = y, text = tostring(text), scale = scale or 1.0, color = color or {1, 1, 1, 1} }
end

function M.bar(x, y, w, frac, label_prefix)
    local f = math.max(0.0, math.min(1.0, frac or 0.0))
    local filled = math.floor(f * 10.0 + 0.5)
    local s = (label_prefix or "") .. "[" .. string.rep("#", filled) .. string.rep("-", 10 - filled) .. "]"
    M.label(x, y, s, 1.0, {0.3, 0.95, 0.45, 1.0})
end

function M.flush(eng_root)
    for i = 1, #M._cmds do
        local c = M._cmds[i]
        eng_root.render.draw_text(c.text, c.x, c.y, c.scale, c.color[1], c.color[2], c.color[3], c.color[4] or 1.0)
    end
    M._cmds = {}
end

return M
