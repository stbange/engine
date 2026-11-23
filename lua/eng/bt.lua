-- Composable Lua 5.1 Behavior Tree combinators (eng.bt)
local M = { SUCCESS = "success", FAILURE = "failure", RUNNING = "running" }

function M.action(fn)
    return fn
end

function M.inverter(child)
    return function(ctx, dt)
        local s = child(ctx, dt)
        if s == M.SUCCESS then return M.FAILURE end
        if s == M.FAILURE then return M.SUCCESS end
        return M.RUNNING
    end
end

function M.sequence(children)
    return function(ctx, dt)
        for i = 1, #children do
            local s = children[i](ctx, dt)
            if s ~= M.SUCCESS then return s end
        end
        return M.SUCCESS
    end
end

function M.selector(children)
    return function(ctx, dt)
        for i = 1, #children do
            local s = children[i](ctx, dt)
            if s ~= M.FAILURE then return s end
        end
        return M.FAILURE
    end
end

return M
