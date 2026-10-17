-- MAYHEM all-entity autoplay regression tests (pure Lua 5.4 mocks).
local handle = assert(io.open("lib/MayhemEntityAuto.lua","rb"))
local source=handle:read("*a"); handle:close()
local world={instances={}}
local function v(x,y,z)
    return setmetatable({X=x,Y=y,Z=z or 0,Magnitude=math.sqrt(x*x+y*y+(z or 0)^2)},
        {__sub=function(a,b) return v(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end})
end
local function signal()
    local s={callbacks={}}
    function s:Connect(fn)
        local c={Connected=true,callback=fn}
        function c:Disconnect()self.Connected=false end
        table.insert(s.callbacks,c)
        return c
    end
    function s:Fire(value)
        for _,c in ipairs(self.callbacks) do
            if c.Connected then c.callback(value) end
        end
    end
    return s
end
local function player(name,team,entity,x,health)
    local obj={Name=name,Team={Name=team},attributes={}}
    function obj:GetAttribute(key) return self.attributes[key] end
    local root={Name="HumanoidRootPart",Position=v(x,0)}
    local human={Name="Humanoid",Health=health or 100,Moves={}}
    function human:MoveTo(position) self.Moves[#self.Moves+1]=position end
    local c={Name=name,attributes={},PrimaryPart=root}
    function c:GetAttribute(key)return self.attributes[key]end
    function c:FindFirstChild(k)
        if k=="HumanoidRootPart" then return root end
    end
    function c:FindFirstChildOfClass(k)
        if k=="Humanoid" then return human end
    end
    if entity then c.attributes.CurrentEntity=entity end
    obj.Character=c
    return obj,root,human
end
local enum={PathStatus={Success="Success"},
    PathWaypointAction={Jump="Jump"}}
local mod=assert(load(source,"@EntityAuto","t",
    setmetatable({Enum=enum,task={spawn=function(fn)fn()end}},
        {__index=_G})))()
for _,name in ipairs({"Rush","Figure","Bramble","Seek","Halt","Eyes","Jeff","Generic"}) do
    assert(mod.Profiles[name] and #mod.Profiles[name].slots==4)
end
local own,ownRoot,ownHuman=player("Local","Entity","Rush",0)
local a,aroot=player("SurvivorA","Survivors",nil,22)
local b,broot=player("SurvivorB","Survivors",nil,14)
local ally=player("Teammate","Entity","Halt",3)
local dead=player("Dead","Survivors",nil,1,0)
local all={own,a,b,ally,dead}
local players={GetPlayers=function()return all end}
local paths={}
local service={}
function service:CreatePath(opts)
    assert(opts.AgentCanJump==true)
    local route={Status=enum.PathStatus.Success,Blocked=signal(),destroyed=false}
    function route:ComputeAsync(origin,goal)
        self.origin=origin;self.goal=goal
    end
    function route:GetWaypoints()
        return {{Position=v(0,0)},{Position=v(5,0)},{Position=self.goal}}
    end
    function route:Destroy()self.destroyed=true end
    paths[#paths+1]=route
    return route
end
local queued={}
local keys={}
local ctrl=mod.new({player=own,players=players,pathfinding=service,
    pathSuccess=enum.PathStatus.Success,
    jumpAction=enum.PathWaypointAction.Jump,
    async=function(fn) table.insert(queued,fn) end,
    sendAbility=function(key)keys[#keys+1]=key;return true end})
local function flush()
    while #queued>0 do
        local fn=table.remove(queued,1);fn()
    end
end
assert(mod.DetectProfile(own)=="Rush")
local p,d=ctrl:FindNearest()
assert(p==b and d==14,"nearest excludes dead and entity teammates")
assert(ctrl:SetBindings("Rush","Q,E,R,F"))
assert(ctrl:Bindings("Rush")=="Q,E,R,F")
assert(not ctrl:SetBindings("Rush","Keyboard,E,R,F"))
assert(not ctrl:SetBindings("Rush","Q,E,R"))
ctrl:SetEnabled(true)
ctrl:Step(.5)
assert(ctrl.profile=="Rush" and ctrl.target==b)
assert(ctrl.computing,"should schedule a path computation")
assert(#ownHuman.Moves==0,"must wait for asynchronous route before moving")
flush()
assert(#ctrl.route==3 and #paths==1 and not ctrl.computing)
ctrl:Step(.5)
assert(#ownHuman.Moves>=1,"humanoid must move to path waypoint")
ctrl:Step(.85)
assert(#keys>=1 and keys[1]=="R","Rush selects close-range configured ability at 14 studs")
local oldPath=paths[1]
oldPath.Blocked:Fire(2)
ctrl:Step(.5)
assert(#paths>=1,"blocked route should replan")
flush()
assert(ctrl.plans>=1)
-- Switch entity while still on Entity team; per-profile bindings are independent.
for _,entity in ipairs({"Figure","Bramble","Seek","Halt","Eyes","Jeff"}) do
    own.Character.attributes.CurrentEntity=entity
    assert(mod.DetectProfile(own)==entity)
    ctrl:Step(.5)
    flush()
    assert(ctrl.profile==entity)
end
assert(ctrl:Bindings("Figure")=="None,None,None,None")
assert(ctrl:SetBindings("Figure","Q,None,None,None"))
assert(ctrl:Bindings("Rush")=="Q,E,R,F")
own.Character.attributes.CurrentEntity="Figure"
ctrl:Step(.5);flush()
assert(ctrl.profile=="Figure")
-- A generic undisclosed testing character is supported when the team is Entity.
own.Character.attributes.CurrentEntity="NewMonsterName"
assert(mod.DetectProfile(own)=="Generic")
ctrl:Step(.7);flush()
assert(ctrl.profile=="Generic")
-- Invalid survivor role cannot start autopilot unless explicitly overridden.
own.Team={Name="Survivors"}
own.Character.attributes.CurrentEntity="Rush"
assert(mod.DetectProfile(own)==nil,"survivor team overrides stale entity attribute")
ctrl:Step(.7)
assert(ctrl.profile==nil)
ctrl.manualProfile="Bramble"
ctrl:Step(.7);flush()
assert(ctrl.profile=="Bramble")
ctrl.manualProfile="Auto"
own.Team={Name="Entities"}
own.Character.attributes.CurrentEntity="Bramble"
ctrl:Step(.7);flush()
ctrl.lastSample=ctrl.now
ctrl.lastPos=v(0,0)
ctrl.stagnant=2.3
ctrl:Step(.7);flush()
assert(ctrl.stuck>=1,"stuck should trigger rescan and replan")
assert(ctrl:Status():find("stuck"),"live status reports recovery")
-- Do not automate Jeff's dangerous/admin-only ultra ability.
own.Character.attributes.CurrentEntity="Jeff The Killer"
own.Team={Name="Entities"}
ctrl:Step(.8);flush()
assert(ctrl.profile=="Jeff")
assert(ctrl:SetBindings("Jeff","None,None,None,Five"))
local before=#keys
for i=1,6 do ctrl:Step(1);flush() end
assert(#keys==before,"Jeff fourth slot must remain unused")
local n=#ownHuman.Moves
ctrl:SetEnabled(false)
assert(not ctrl.enabled and ctrl.target==nil)
ctrl:Step(1)
assert(#ownHuman.Moves==n+1,"disable sends one stop MoveTo")
ctrl:Unload()
assert(ctrl:Status():find("Off"))
assert(next(ctrl.route)==nil)

-- Computation failures must release the allocated Path, then allow retry.
local failingPath
local failureService={CreatePath=function()
    failingPath={Destroy=function(self)self.destroyed=true end,
        ComputeAsync=function()error("mock computation failure")end}
    return failingPath
end}
local failing=mod.new({player=own,players=players,pathfinding=failureService,
    async=function(fn)fn()end})
failing:SetEnabled(true)
failing:Step(.5)
assert(failingPath.destroyed,"failed ComputeAsync must destroy its Path")
assert(not failing.computing and #failing.route==1,
    "failed computation must finish and expose the direct fallback")
failing:Unload()

-- A result arriving after disable must never install a route or move the rig.
ctrl:SetEnabled(true)
ctrl:Step(.5)
assert(ctrl.computing)
ctrl:SetEnabled(false)
local stoppedMoves=#ownHuman.Moves
flush()
assert(not ctrl.path and #ctrl.route==0 and not ctrl.computing)
assert(paths[#paths].destroyed,"cancelled computation must destroy its result")
assert(#ownHuman.Moves==stoppedMoves,"cancelled result must not move the rig")
print("mayhem all-entity autoplay: role detection, chasing, path replan, abilities, teardown OK")
