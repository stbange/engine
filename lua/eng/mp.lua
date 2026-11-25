-- Authoritative client-server multiplayer & safe packet serialization helpers (eng.mp)
local M = {}

local function esc(s)
    return (string.gsub(tostring(s), "[%%;=]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function unesc(s)
    return (string.gsub(s, "%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

function M.pack(tbl)
    local keys = {}
    for k in pairs(tbl) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    local parts = {}
    for i = 1, #keys do
        local k = keys[i]
        local v = tbl[k]
        local tv = type(v)
        if tv == "number" then
            parts[#parts + 1] = esc(k) .. "=n:" .. string.format("%.4g", v)
        elseif tv == "boolean" then
            parts[#parts + 1] = esc(k) .. "=b:" .. (v and "1" or "0")
        elseif tv == "string" then
            parts[#parts + 1] = esc(k) .. "=s:" .. esc(v)
        end
    end
    return table.concat(parts, ";")
end

function M.unpack(str)
    if type(str) ~= "string" or str == "" then return {} end
    local out = {}
    for entry in string.gmatch(str, "[^;]+") do
        local eq = string.find(entry, "=", 1, true)
        if eq then
            local k = unesc(string.sub(entry, 1, eq - 1))
            local tag = string.sub(entry, eq + 1, eq + 2)
            local raw = string.sub(entry, eq + 3)
            if tag == "n:" then out[k] = tonumber(raw) or 0
            elseif tag == "b:" then out[k] = (raw == "1")
            elseif tag == "s:" then out[k] = unesc(raw) end
        end
    end
    return out
end

function M.lerp(cur, tgt, dt, rate)
    local t = math.min(1.0, (rate or 12.0) * dt)
    return cur + (tgt - cur) * t
end

function M.create_server(eng_root, opts)
    opts = opts or {}
    local srv = {
        seed = opts.seed or 42,
        snapshot_dt = 1.0 / (opts.snapshot_hz or 20),
        players = {},
        tick = 0,
        _acc = 0.0
    }
    function srv:step(dt)
        self.tick = self.tick + 1
        while true do
            local ev = eng_root.net.poll_event("server")
            if not ev then break end
            local cid = ev.client_id
            if ev.type == "connect" then
                local p = { id = cid, x = 0, y = 1.4, z = 0, yaw = 0, pk = 0, sc = 0 }
                self.players[cid] = p
                if opts.on_join then opts.on_join(cid, p) end
                eng_root.net.send_to(cid, M.pack({ t = "welcome", id = cid, seed = self.seed }), true)
            elseif ev.type == "disconnect" then
                local p = self.players[cid]
                self.players[cid] = nil
                if opts.on_leave then opts.on_leave(cid, p) end
                eng_root.net.broadcast(M.pack({ t = "leave", id = cid }), true)
            elseif ev.type == "message" and ev.data then
                local pkt = M.unpack(ev.data)
                if opts.on_input and self.players[cid] then
                    opts.on_input(cid, self.players[cid], pkt, dt)
                end
            end
        end
        self._acc = self._acc + dt
        if self._acc >= self.snapshot_dt then
            self._acc = 0.0
            for cid, p in pairs(self.players) do
                eng_root.net.broadcast(M.pack({
                    t = "p", id = cid, x = p.x, y = p.y, z = p.z,
                    yaw = p.yaw or 0, pk = p.pk or 0, sc = p.sc or 0
                }), false)
            end
            if opts.on_snapshot then opts.on_snapshot(self) end
        end
    end
    return srv
end

function M.create_client(eng_root, opts)
    opts = opts or {}
    local cli = {
        url = opts.url or eng_root.net.launch_url(),
        input_dt = 1.0 / (opts.input_hz or 30),
        connected = false,
        local_id = nil,
        seed = nil,
        players = {},
        _acc = 0.0
    }
    function cli:connect(url)
        local target = url or self.url
        if not target or target == "" then return false end
        self.url = target
        return eng_root.net.connect(target)
    end
    function cli:step(dt, input_tbl)
        while true do
            local ev = eng_root.net.poll_event("client")
            if not ev then break end
            if ev.type == "connect" then
                self.connected = true
            elseif ev.type == "disconnect" then
                self.connected = false
            elseif ev.type == "message" and ev.data then
                local pkt = M.unpack(ev.data)
                if pkt.t == "welcome" then
                    self.local_id = pkt.id
                    self.seed = pkt.seed
                    self.connected = true
                    if opts.on_welcome then opts.on_welcome(pkt.id, pkt.seed) end
                elseif pkt.t == "leave" then
                    self.players[pkt.id] = nil
                    if opts.on_event then opts.on_event(pkt) end
                elseif pkt.t == "p" and pkt.id then
                    self.players[pkt.id] = pkt
                    if opts.on_state then opts.on_state(pkt) end
                elseif opts.on_event then
                    opts.on_event(pkt)
                end
            end
        end
        if input_tbl and eng_root.net.is_connected("client") then
            self._acc = self._acc + dt
            if self._acc >= self.input_dt then
                self._acc = 0.0
                eng_root.net.send("client", M.pack(input_tbl), false)
            end
        end
    end
    return cli
end

return M
