-- Quantitative Game-Feel, Flow & Bot-Persona Telemetry (eng.fun)
local M = {}

function M.new_tracker()
    return {
        actions = 0,
        hits = 0,
        near_misses = 0,
        cells = {},
        cell_count = 0,
        wins = 0,
        deaths = 0,
    }
end

function M.record_action(tr, rewarded)
    tr.actions = tr.actions + 1
    if rewarded then tr.hits = tr.hits + 1 end
end

function M.record_near_miss(tr)
    tr.near_misses = tr.near_misses + 1
end

function M.record_position(tr, x, z, cell_size)
    local cs = cell_size or 4.0
    local key = tostring(math.floor(x / cs)) .. ":" .. tostring(math.floor(z / cs))
    if not tr.cells[key] then
        tr.cells[key] = true
        tr.cell_count = tr.cell_count + 1
    end
end

function M.record_outcome(tr, won)
    if won then tr.wins = tr.wins + 1 else tr.deaths = tr.deaths + 1 end
end

function M.evaluate(tr)
    local agency = tr.actions > 0 and (tr.hits / tr.actions) or 0.0
    local explore = math.min(1.0, tr.cell_count / 8.0)
    local tension = math.min(1.0, (tr.near_misses + tr.deaths) / 4.0)
    local score = 0.45 * math.min(1.0, agency + 0.3) + 0.35 * explore + 0.20 * math.min(1.0, tension + 0.4)
    return { agency = agency, exploration = explore, tension = tension, fun_score = score, cells = tr.cell_count }
end

return M
