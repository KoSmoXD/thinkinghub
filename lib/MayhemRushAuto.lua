-- Zinc Hub | Rush Auto Play controller (client-side pathfinding + input)
-- No remote calls, teleports, memory/closure hooks, or server-side claims.
local Module = {}
local function norm(x) return tostring(x or ""):lower():gsub("[^%w]", "") end
local function number(x) return type(x) == "number" and x == x and x >= 0 end
local function getAttribute(instance, name)
    if not instance then return nil end
    local ok, value = pcall(instance.GetAttribute, instance, name)
    return ok and value or nil
end
local function isRush(player)
    if not player then return false end
    for _, source in ipairs({player, player.Character or player}) do
        for _, key in ipairs({"Role", "CurrentRole", "SelectedEntity", "Entity", "CharacterRole", "Monster"}) do
            local v = getAttribute(source, key)
            if type(v) == "string" and norm(v) == "rush" then return true end
        end
        if getAttribute(source, "IsRush") == true then return true end
    end
    local team = player.Team
    return team and norm(team.Name) == "rush" or false
end
local function isSurvivor(player, localPlayer)
    if not player or player == localPlayer or not player.Character then return false end
    local hum = player.Character:FindFirstChildOfClass("Humanoid")
    local root = player.Character:FindFirstChild("HumanoidRootPart")
    if not (hum and hum.Health > 0 and root) then return false end
    if localPlayer.Team and player.Team and player.Team == localPlayer.Team then
        return false
    end
    for _, source in ipairs({player, player.Character}) do
        for _, key in ipairs({"Role", "CurrentRole", "SelectedEntity", "CharacterRole"}) do
            local v = getAttribute(source, key)
            if type(v) == "string" then
                local role = norm(v)
                if role == "entity" or role == "rush" or role == "figure"
                    or role == "seek" or role == "bramble" or role == "monster"
                    or role == "killer" then return false end
            end
        end
    end
    return true, root
end
function Module.new(cfg)
    assert(type(cfg) == "table" and cfg.player and cfg.players and cfg.pathfinding,
        "Rush Auto Play requires player, Players and PathfindingService")
    local self = {
        player=cfg.player, players=cfg.players, pathfinding=cfg.pathfinding,
        workspace=cfg.workspace, sendAbility=cfg.sendAbility,
        now=0, enabled=false, autoAbility=true, manualRush=false,
        target=nil, route={}, waypoint=1, path=nil, blockedConnection=nil,
        pending=false, pathToken=0, lastPlan=-math.huge,
        lastScan=-math.huge, lastCommand=-math.huge,
        samplePosition=nil, stallFor=0, lastSample=0,
        replans=0, stuckEvents=0, abilityUses=0, status="Off",
        abilityKeys={rushHour="None", comingThrough="None",
            shockwave="None", blackout="None"},
        lastAbility={rushHour=-math.huge, comingThrough=-math.huge,
            shockwave=-math.huge, blackout=-math.huge},
        -- Conservative windows prevent unintended double activation.
        abilityCooldown={rushHour=45, comingThrough=18,
            shockwave=75, blackout=250},
        lastRushHourStart=-math.huge, chargeUntil=0,
        config = {replanInterval=1.3, targetMoveDistance=12,
            stallThreshold=1, stallWindow=2.4, scanInterval=0.65},
        async=cfg.async or function(fn) task.spawn(fn) end,
    }
    local function ownHumanoid()
        local rig = self.player.Character
        if not rig then return nil,nil end
        local hum=rig:FindFirstChildOfClass("Humanoid")
        local root=rig:FindFirstChild("HumanoidRootPart")
        if not hum or hum.Health<=0 or not root then return nil,nil end
        return hum,root
    end
    local function destination(target)
        local live,root=isSurvivor(target,self.player)
        return live and root or nil
    end
    local function closePath()
        if self.blockedConnection then
            pcall(function() self.blockedConnection:Disconnect() end)
        end
        self.blockedConnection=nil
        self.path=nil
    end
    local function resetRoute()
        self.pathToken=self.pathToken+1
        self.route={};self.waypoint=1
        self.pending=false;closePath()
    end
    local function cease()
        local hum,root=ownHumanoid()
        if hum and root then pcall(function() hum:MoveTo(root.Position) end) end
    end
    function self:CanRun()
        return self.manualRush or isRush(self.player)
    end
    function self:SetEnabled(value)
        self.enabled=value==true
        resetRoute()
        self.target=nil;self.stallFor=0;self.samplePosition=nil
        self.lastSample=self.now;self.lastScan=-math.huge
        self.lastCommand=-math.huge
        if not self.enabled then
            cease()
            self.status="Off"
        else
            self.status="Waiting for Rush character"
        end
    end
    function self:Stop() self:SetEnabled(false) end
    function self:FindNearest()
        local _,root=ownHumanoid()
        if not root then return nil end
        local best,bestDistance=nil,math.huge
        for _,p in ipairs(self.players:GetPlayers()) do
            local valid,otherRoot=isSurvivor(p,self.player)
            if valid then
                local distance=(root.Position-otherRoot.Position).Magnitude
                if distance<bestDistance then
                    best,bestDistance=p,distance
                end
            end
        end
        return best,bestDistance
    end
    function self:Plan(reason)
        if not self.enabled or self.pending then return false end
        local hum,root=ownHumanoid()
        local targetRoot=destination(self.target)
        if not hum or not root or not targetRoot then return false end
        if self.now-self.lastPlan < self.config.replanInterval
            and reason~="stuck" and reason~="blocked" then return false end
        resetRoute()
        self.pending=true;self.pathToken=self.pathToken+1
        local token=self.pathToken
        self.lastPlan=self.now
        local startPosition,goal=root.Position,targetRoot.Position
        self.status="Pathfinding ("..tostring(reason)..")"
        self.async(function()
            local ok,path=pcall(function()
                local p=self.pathfinding:CreatePath({
                    AgentRadius=2,AgentHeight=5,AgentCanJump=true,
                    WaypointSpacing=5,
                })
                p:ComputeAsync(startPosition,goal)
                return p
            end)
            if token~=self.pathToken or not self.enabled then return end
            self.pending=false
            self.replans=self.replans+1
            if not ok or not path or path.Status~=Enum.PathStatus.Success then
                self.route={{Position=goal}}
                self.status="Fallback: direct chase"
                return
            end
            local points=path:GetWaypoints()
            if not points or #points==0 then
                self.route={{Position=goal}}
                self.status="Fallback: empty route"
                return
            end
            self.path=path
            self.route=points
            self.waypoint=#points>1 and 2 or 1
            self.status="Following "..self.target.Name
            if path.Blocked then
                self.blockedConnection=path.Blocked:Connect(function(at)
                    if self.enabled and at>=self.waypoint then
                        self.lastPlan=-math.huge
                        self:Plan("blocked")
                    end
                end)
            end
        end)
        return true
    end
    local function stamina()
        for _,item in ipairs({self.player, self.player.Character or self.player}) do
            for _,name in ipairs({"Stamina","CurrentStamina","SprintStamina"}) do
                local v=getAttribute(item,name)
                if number(v) then return v end
                local ok,child=pcall(item.FindFirstChild,item,name)
                if ok and child then
                    local good,value=pcall(function() return child.Value end)
                    if good and number(value) then return value end
                end
            end
        end
        return nil
    end
    local function spawned()
        for _,item in ipairs({self.player,self.player.Character or self.player}) do
            for _,name in ipairs({"RushSpawned","IsSpawned","Spawned"}) do
                local value=getAttribute(item,name)
                if type(value)=="boolean" then return value end
            end
        end
        return nil
    end
    local function useAbility(self,key,condition)
        if not condition or not self.autoAbility then return false end
        local binding=self.abilityKeys[key]
        if not binding or binding=="None" or not self.sendAbility then return false end
        if self.now-self.lastAbility[key] < self.abilityCooldown[key] then return false end
        local ok,done=pcall(self.sendAbility,binding)
        if not ok or not done then return false end
        self.lastAbility[key]=self.now
        self.abilityUses=self.abilityUses+1
        if key=="rushHour" then self.lastRushHourStart=self.now end
        if key=="comingThrough" then self.chargeUntil=self.now+10 end
        return true
    end
    function self:Abilities(distance)
        if not self.enabled or not self.autoAbility then return end
        local currentStamina=stamina()
        local canSpend=function(cost) return currentStamina==nil or currentStamina>=cost end
        local active=spawned()
        -- Rush Hour is a toggle during 5.5-second windup; never re-press it.
        useAbility(self,"rushHour",distance<=130 and distance>=18
            and canSpend(30) and active~=true)
        local channeling=self.now-self.lastRushHourStart < 6
        if channeling then return end
        if self.chargeUntil>self.now then return end
        useAbility(self,"shockwave",distance<=17 and canSpend(20))
        useAbility(self,"comingThrough",distance>=15 and distance<=55)
        local damage=getAttribute(self.player,"DamageDealt")
            or getAttribute(self.player.Character,"DamageDealt")
        useAbility(self,"blackout",distance<=150 and canSpend(50)
            and number(damage) and damage>=150)
    end
    function self:Step(dt)
        if not self.enabled then return end
        self.now=self.now+(type(dt)=="number" and math.max(0,math.min(dt,1)) or 0)
        if not self:CanRun() then
            resetRoute();self.status="Paused: only works as Rush"
            return
        end
        local hum,root=ownHumanoid()
        if not hum or not root then
            resetRoute();self.status="Waiting for Rush character"
            return
        end
        if self.now-self.lastScan>=self.config.scanInterval
            or not destination(self.target) then
            self.lastScan=self.now
            local nearest,distance=self:FindNearest()
            if nearest~=self.target then
                self.target=nearest
                resetRoute()
                if nearest then self.lastPlan=-math.huge end
            end
            if not nearest then
                self.status="No valid survivors"
                return
            end
        end
        local goal=destination(self.target)
        if not goal then self.status="Rescanning survivors"; return end
        local distance=(root.Position-goal.Position).Magnitude
        self:Abilities(distance)
        if distance<=4 then
            self.status="Target close: "..self.target.Name
            return
        end
        if self.now-self.lastSample>=0.6 then
            if self.samplePosition then
                local progress=(root.Position-self.samplePosition).Magnitude
                if progress<self.config.stallThreshold then
                    self.stallFor=self.stallFor+(self.now-self.lastSample)
                else self.stallFor=0 end
            end
            self.lastSample=self.now
            self.samplePosition=root.Position
        end
        if self.stallFor>=self.config.stallWindow then
            self.stallFor=0;self.stuckEvents=self.stuckEvents+1
            self:FindNearest() -- refresh target scan and plan
            self.lastPlan=-math.huge
            self:Plan("stuck")
            return
        end
        if self.pending then return end
        local point=self.route[self.waypoint]
        if point and (root.Position-point.Position).Magnitude<=5 then
            self.waypoint=self.waypoint+1
            point=self.route[self.waypoint]
        end
        if (not point or self.now-self.lastPlan>=2.8 or
            (self.route[#self.route] and
             (self.route[#self.route].Position-goal.Position).Magnitude>
                self.config.targetMoveDistance)) and
            self.now-self.lastPlan>=self.config.replanInterval then
            self:Plan("target moved")
            point=self.route[self.waypoint]
        end
        if not point then point={Position=goal.Position} end
        if self.now-self.lastCommand>=0.45 then
            self.lastCommand=self.now
            if point.Action==Enum.PathWaypointAction.Jump then hum.Jump=true end
            pcall(hum.MoveTo,hum,point.Position)
            self.status="Chasing "..self.target.Name.." ("..math.floor(distance).." studs)"
        end
    end
    function self:Status()
        return self.status.." | paths="..self.replans
            .." stuck="..self.stuckEvents.." abilities="..self.abilityUses
    end
    function self:Unload() self:Stop() end
    return self
end
return Module
