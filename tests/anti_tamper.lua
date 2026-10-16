-- Zinc Hub anti-tamper behavior tests (Lua 5.3 / texlua).
-- Run from repository root: texlua tests/anti_tamper.lua
-- Does not start Roblox, DEX, or Remote Spy; services are mocked.
local AntiTamper = assert(loadfile("lib/AntiTamper.lua"))()

local function event()
    local e = {handlers = {}}
    function e:Connect(fn)
        local connection = {Connected = true}
        function connection:Disconnect() self.Connected = false end
        table.insert(self.handlers, {fn = fn, connection = connection})
        return connection
    end
    function e:Fire(...)
        for _, h in ipairs(self.handlers) do
            if h.connection.Connected then h.fn(...) end
        end
    end
    return e
end

local function makeGui(name, class)
    local gui = {Name = name, Parent = {}}
    function gui:IsA(candidate) return candidate == (class or "ScreenGui") end
    return gui
end

local function setup(options)
    options = options or {}
    local core = {DescendantAdded = event(), children = options.children or {}}
    function core:GetDescendants()
        if options.blocked then error("CoreGui access denied") end
        return self.children
    end
    local log = {MessageOut = event(), history = options.history or {}}
    function log:GetLogHistory()
        if options.blockedLogs then error("logs unavailable") end
        return self.history
    end
    local run = {Heartbeat = event()}
    local own = makeGui("ZincUI", "ScreenGui")
    local confirmations, signals = {}, {}
    local detector = AntiTamper.Start({
        CoreGui = core,
        LogService = log,
        RunService = run,
        GetOwnGui = function() return own end,
        OnSignal = function(kind, channel)
            signals[#signals + 1] = kind .. "/" .. channel
        end,
        OnConfirmed = function(kind, reason)
            confirmations[#confirmations + 1] = kind .. "/" .. reason
        end,
    })
    return detector, core, log, run, own, confirmations, signals
end

-- A console message is not sufficient evidence.
local d, g, l, r, own, c, s = setup()
l.MessageOut:Fire("Remote Spy loaded")
assert(#c == 0 and #s == 1, "a log alone must not kick")
g.DescendantAdded:Fire(makeGui("SimpleSpyV3"))
assert(#c == 1 and c[1] == "RSPY/gui+log", "matching GUI and log confirm")
g.DescendantAdded:Fire(makeGui("DarkDex"))
assert(#c == 1, "confirm callback must fire at most once")
d:Stop()
d:Stop()
assert(not d.running, "Stop must be idempotent")
for _, source in ipairs({g.DescendantAdded, l.MessageOut, r.Heartbeat}) do
    for _, hook in ipairs(source.handlers) do
        assert(not hook.connection.Connected, "Stop leaked a handler")
    end
end

-- Startup: recent history and accessible CoreGui descendants.
local d2, g2, l2, r2, own2, c2 = setup({
    history = {{message = "Dark Dex started"}},
    children = {makeGui("DarkDexV3")},
})
assert(#c2 == 1 and c2[1] == "DEX/gui+log", "startup history + CoreGui")
d2:Stop()

-- GUI alone is non-conclusive; the monitor's own warning cannot corroborate.
local d3, g3, l3, r3, own3, c3 = setup({children = {makeGui("DarkDexV3")}})
assert(#c3 == 0, "GUI alone should not confirm")
l3.MessageOut:Fire("[Zinc Hub] Anti-tamper indicator: DEX / gui")
assert(#c3 == 0, "self-warning cannot corroborate")
l3.MessageOut:Fire("dex loaded")
assert(#c3 == 1 and c3[1] == "DEX/gui+log", "corroborating log")
d3:Stop()

-- Different tool signals may not be mixed into one confirmation.
local d4, g4, l4, r4, own4, c4 = setup()
g4.DescendantAdded:Fire(makeGui("DarkDex"))
l4.MessageOut:Fire("SimpleSpy loaded")
assert(#c4 == 0, "DEX GUI and RSPY log cannot be correlated")
d4:Stop()

-- The inspector cannot assume it is allowed to enumerate CoreGui.
local d5, g5, l5, r5, own5, c5 = setup({
    blocked = true, blockedLogs = true,
})
assert(#c5 == 0, "CoreGui/log permission errors must not confirm")
own5.Parent = nil
r5.Heartbeat:Fire(6)
assert(#c5 == 1 and c5[1] == "HubUI/own_gui_missing", "missing UI")
d5:Stop()

-- Similar text or child Frames should not produce tool evidence.
local d6, g6, l6, r6, own6, c6, s6 = setup()
l6.MessageOut:Fire("index contains dex")
g6.DescendantAdded:Fire(makeGui("SimpleSpy", "Frame"))
g6.DescendantAdded:Fire(makeGui("Zinc-Dex-Notes"))
assert(#c6 == 0 and #s6 == 0, "avoid substring / Frame false positives")
d6:Stop()
assert(#c6 == 0, "Stop is harmless after a clean run")


-- A tool GUI may be parented to a separate UI root, not CoreGui.
local function uiRoot()
    local root = {DescendantAdded = event(), children = {}}
    function root:GetDescendants() return self.children end
    return root
end
local firstRoot, secondRoot = uiRoot(), uiRoot()
local logger = {MessageOut = event(), history = {}}
function logger:GetLogHistory() return self.history end
local runner = {Heartbeat = event()}
local found = {}
local multi = AntiTamper.Start({
    Roots = {firstRoot, secondRoot, firstRoot},
    LogService = logger, RunService = runner,
    OnConfirmed = function(kind, reason)
        found[#found + 1] = kind .. "/" .. reason
    end,
})
logger.MessageOut:Fire("SimpleSpy V3 loaded")
secondRoot.DescendantAdded:Fire(makeGui("SimpleSpyV3"))
assert(#found == 1 and found[1] == "RSPY/gui+log", "multiple roots")
assert(#firstRoot.DescendantAdded.handlers == 1, "deduplicate listeners")
multi:Stop()
for _, hook in ipairs(firstRoot.DescendantAdded.handlers) do
    assert(not hook.connection.Connected, "multi-root listener leaked")
end

print("PASS: tool signals, false positives, corroboration, startup, permissions, UI removal, disconnect")
