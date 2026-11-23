-- Frame-synchronized Lua 5.1 coroutine scheduler (eng.async)
local M = { _tasks = {} }

function M.spawn(fn)
    local co = coroutine.create(fn)
    local t = { co = co, wait = 0.0 }
    M._tasks[#M._tasks + 1] = t
    return t
end

function M.wait_seconds(sec)
    coroutine.yield(sec or 0.0)
end

function M.wait_frames(n)
    for _ = 1, (n or 1) do
        coroutine.yield(0.0)
    end
end

function M.step_all(dt)
    local i = 1
    while i <= #M._tasks do
        local t = M._tasks[i]
        t.wait = t.wait - dt
        if coroutine.status(t.co) == "dead" then
            table.remove(M._tasks, i)
        elseif t.wait <= 0.0 then
            local ok, res = coroutine.resume(t.co, dt)
            if not ok then error(tostring(res), 0) end
            t.wait = (type(res) == "number" and res > 0.0) and res or 0.0
            if coroutine.status(t.co) == "dead" then
                table.remove(M._tasks, i)
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end
end

function M.clear()
    M._tasks = {}
end

return M
