-- Zinc Hub anti-tamper indicator smoke tests.
-- Execute from repository root: texlua tests/anti_tamper.lua
local AntiTamper = assert(loadfile("lib/AntiTamper.lua"))()
local function event()
    local e={handlers={}}
    function e:Connect(fn)
        local connection={Connected=true}
        function connection:Disconnect() self.Connected=false end
        table.insert(self.handlers,{fn=fn, connection=connection})
        return connection
    end
    function e:Fire(...)
        for _, h in ipairs(self.handlers) do if h.connection.Connected then h.fn(...) end end
    end
    return e
end
local function makeGui(name,class)
    local t={Name=name,Parent={}}
    function t:IsA(candidate) return candidate==(class or "ScreenGui") end
    return t
end
local function setup(options)
    options=options or {}
    local gui={DescendantAdded=event(),children=options.children or {}}
    function gui:GetDescendants() if options.blocked then error("blocked") end return self.children end
    local log={MessageOut=event(),history=options.history or {}}
    function log:GetLogHistory() return self.history end
    local run={Heartbeat=event()}
    local own=makeGui("ZincUI","ScreenGui")
    local confirmed,signals={},{}
    local detector=AntiTamper.Start({
        CoreGui=gui,LogService=log,RunService=run,
        GetOwnGui=function() return own end,
        OnSignal=function(kind,channel) table.insert(signals,kind.."/"..channel) end,
        OnConfirmed=function(kind,reason) table.insert(confirmed,kind.."/"..reason) end,
    })
    return detector,gui,log,run,own,confirmed,signals
end
local d,g,l,_,__,confirmed,signals=setup()
l.MessageOut:Fire("Remote Spy loaded")
assert(#confirmed==0 and #signals==1,"log alone must not confirm")
g.DescendantAdded:Fire(makeGui("SimpleSpyV3"))
assert(#confirmed==1 and confirmed[1]=="RSPY/gui+log","two channels must confirm")
g.DescendantAdded:Fire(makeGui("DarkDex"))
assert(#confirmed==1,"confirmation must fire only once")
d:Stop();d:Stop()
local d2,_,__,___,____,c2=setup({
    history={{message="Dark Dex started"}},
    children={makeGui("DarkDexV3")},
})
assert(#c2==1 and c2[1]=="DEX/gui+log","history and CoreGui match")
d2:Stop()
local d3,___,l3,____,_____,c3=setup({children={makeGui("DarkDexV3")}})
assert(#c3==0,"GUI alone should not confirm")
l3.MessageOut:Fire("[Zinc Hub] Anti-tamper indicator: DEX / gui")
assert(#c3==0,"own warnings cannot corroborate")
l3.MessageOut:Fire("dex loaded")
assert(#c3==1,"later independent log may confirm")
d3:Stop()
local d4,____,_____,r4,own4,c4=setup({blocked=true})
assert(#c4==0,"inaccessible CoreGui must not trigger")
own4.Parent=nil
r4.Heartbeat:Fire(6)
assert(#c4==1 and c4[1]=="HubUI/own_gui_missing","own GUI tamper")
d4:Stop()
local d5,_____,l5,______,_______,c5=setup()
l5.MessageOut:Fire("Dark Dex")
assert(#c5==0,"a single mention must not confirm")
d5:Stop()
print("PASS: DEX/RSPY evidence, startup logs, false positives, CoreGui fallback, own GUI loss, cleanup")
