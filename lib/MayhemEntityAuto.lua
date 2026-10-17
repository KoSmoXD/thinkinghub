-- Zinc Hub | DOORS: MAYHEM entity auto-play v0.8 beta
-- Shared client-side controller. No game remotes or teleports.
-- Requires a Humanoid and pathfinding-compatible rig for movement.
local M = {}
local PROFILES = {
    Rush = {slots={"Rush Hour", "Coming Through", "Shockwave", "Blackout"},
        cooldown={45,18,75,250}, ranges={{18,130},{15,55},{0,17},{0,150}}},
    Figure = {slots={"Attack", "Snare / Slash", "Focus / Charge", "Switch Instinct"},
        cooldown={1.5,25,30,8}, ranges={{0,7},{0,28},{8,55},{10,80}}},
    Bramble = {slots={"Attack", "Ability 1", "Ability 2", "Ability 3"},
        cooldown={2,20,35,55}, ranges={{0,8},{6,38},{9,65},{15,90}}},
    Seek = {slots={"Attack", "Ability 1", "Ability 2", "Ability 3"},
        cooldown={2,20,40,60}, ranges={{0,8},{8,48},{6,30},{15,90}}},
    Halt = {slots={"Attack", "Ability 1", "Ability 2", "Ability 3"},
        cooldown={3,20,45,60}, ranges={{0,8},{8,65},{7,30},{15,100}}},
    Eyes = {slots={"Attack", "Ability 1", "Ability 2", "Ability 3"},
        cooldown={3,15,30,60}, ranges={{0,12},{6,65},{0,24},{15,100}}},
    Jeff = {slots={"Attack", "Invisibility", "Rage", "Ultra Attack (manual only)"},
        cooldown={2,25,15,2010}, ranges={{0,7},{12,60},{0,25},{0,0}}},
    Generic = {slots={"Primary", "Ability 1", "Ability 2", "Ability 3"},
        cooldown={3,20,45,75}, ranges={{0,8},{7,45},{0,22},{18,85}}},
}
M.Profiles = PROFILES
M.ProfileNames = {"Rush","Figure","Bramble","Seek","Halt","Eyes","Jeff","Generic"}
local ALIASES = {
    rush="Rush",figure="Figure",bramble="Bramble",seek="Seek",
    halt="Halt",eyes="Eyes",jeff="Jeff",jeffthekiller="Jeff",
}
local ENTITY_TEAM = {
    entity=true,entities=true,monster=true,monsters=true,
    killer=true,killers=true,antagonist=true,antagonists=true,
    hunters=true,rush=true,figure=true,bramble=true,seek=true,
    halt=true,eyes=true,
}
local function norm(value)
    return tostring(value or ""):lower():gsub("[^%w]", "")
end
local function getAttr(obj, key)
    if not obj then return nil end
    local ok,value = pcall(obj.GetAttribute,obj,key)
    return ok and value or nil
end
local function teamName(player)
    return player and player.Team and norm(player.Team.Name) or ""
end
local function namedProfile(name)
    local n=norm(name)
    return ALIASES[n]
end
local function entityTeam(player)
    return ENTITY_TEAM[teamName(player)] == true
end
local function activeProfile(player)
    if not player or not player.Character then return nil end
    local team = teamName(player)
    if team == "survivor" or team == "survivors" or team == "human"
        or team == "humans" then return nil end
    local char = player.Character
    for _,obj in ipairs({char,player}) do
        for _,key in ipairs({"CurrentEntity","ActiveEntity","EntityType",
            "CurrentRole","Role","CharacterRole","Monster","CurrentMonster"}) do
            local value=getAttr(obj,key)
            local known=namedProfile(value)
            if known then return known end
            if norm(value)=="entity" or norm(value)=="monster"
                or norm(value)=="killer" then return "Generic" end
        end
    end
    local fromCharacter=namedProfile(char.Name)
    if fromCharacter then return fromCharacter end
    local fromTeam=namedProfile(team)
    if fromTeam then return fromTeam end
    if entityTeam(player) then
        for _,obj in ipairs({char,player}) do
            for _,key in ipairs({"SelectedEntity","SelectedRole","Entity"}) do
                local value=getAttr(obj,key)
                local found=namedProfile(value)
                if found then return found end
            end
        end
        return "Generic"
    end
    return nil
end
M.DetectProfile=activeProfile
local function entityAlly(other, me)
    if other==me then return true end
    local otherTeam=teamName(other)
    local ownTeam=teamName(me)
    if ownTeam~="" and otherTeam~="" and other.Team==me.Team then return true end
    if ENTITY_TEAM[otherTeam] then return true end
    if activeProfile(other) then return true end
    for _,obj in ipairs({other,other.Character or other}) do
        for _,key in ipairs({"Role","CurrentRole","CharacterRole"}) do
            local n=norm(getAttr(obj,key))
            if n=="entity" or n=="monster" or n=="killer" then return true end
        end
    end
    return false
end
local function rig(player)
    local c=player and player.Character
    if not c then return nil,nil end
    local h=c:FindFirstChildOfClass("Humanoid")
    local root=c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart
    if not h or not root or h.Health<=0 then return nil,nil end
    return h,root
end
local function posDistance(a,b)
    return (a-b).Magnitude
end
function M.new(deps)
    assert(type(deps)=="table" and deps.player and deps.players and deps.pathfinding,
        "Entity Auto Play requires LocalPlayer, Players and PathfindingService")
    local self={
        player=deps.player,players=deps.players,pathfinding=deps.pathfinding,
        enabled=false,autoAbility=true,manualProfile="Auto",
        profile=nil,target=nil,path=nil,route={},waypoint=1,
        blocked=nil,computing=false,token=0,
        now=0,lastScan=-math.huge,lastPlan=-math.huge,
        lastMove=-math.huge,lastSample=0,lastPos=nil,
        stagnant=0,stuck=0,plans=0,abilities=0,
        status="Off",goal=nil,lastCharacter=nil,
        cooldownUntil=-math.huge,slotTimes={},
        binds={},
        async=deps.async or function(fn) task.spawn(fn) end,
        sendAbility=deps.sendAbility,
        pathSuccess=deps.pathSuccess or Enum.PathStatus.Success,
        jumpAction=deps.jumpAction or Enum.PathWaypointAction.Jump,
    }
    for _,name in ipairs(M.ProfileNames) do
        self.binds[name]={"None","None","None","None"}
        self.slotTimes[name]={-math.huge,-math.huge,-math.huge,-math.huge}
    end
    local function dismissRoute()
        self.token=self.token+1
        self.computing=false
        if self.blocked then pcall(function() self.blocked:Disconnect() end) end
        self.blocked=nil
        if self.path then pcall(function() self.path:Destroy() end) end
        self.path=nil;self.route={};self.waypoint=1;self.goal=nil
    end
    local function stopMovement()
        local hum,root=rig(self.player)
        if hum then pcall(hum.MoveTo,hum,root.Position) end
    end
    local function survivor(other)
        if not other or entityAlly(other,self.player) then return nil end
        local _,root=rig(other)
        if not root then return nil end
        if getAttr(other,"IsHiding")==true or getAttr(other,"Hiding")==true then
            return nil
        end
        return root
    end
    function self:CurrentProfile()
        if self.manualProfile~="Auto" then return self.manualProfile end
        return activeProfile(self.player)
    end
    function self:SetBindings(profile, textOrList)
        if not PROFILES[profile] then return false end
        local values={}
        if type(textOrList)=="string" then
            for term in (textOrList..","):gmatch("(.-),") do
                values[#values+1]=term:match("^%s*(.-)%s*$")
            end
        elseif type(textOrList)=="table" then
            for i=1,4 do values[i]=textOrList[i] end
        else return false end
        if #values~=4 then return false end
        local allowed={None=true,Q=true,E=true,R=true,F=true,Z=true,X=true,
            C=true,V=true,One=true,Two=true,Three=true,Four=true,Five=true}
        for _,v in ipairs(values) do if not allowed[v] then return false end end
        self.binds[profile]=values
        return true
    end
    function self:Bindings(profile)
        return table.concat(self.binds[profile] or {"None","None","None","None"},",")
    end
    function self:SetEnabled(value)
        self.enabled=value==true
        dismissRoute()
        self.target=nil;self.profile=nil
        self.stagnant=0;self.lastPos=nil;self.lastSample=self.now
        self.lastScan=-math.huge;self.lastPlan=-math.huge
        if self.enabled then
            self.lastCharacter=self.player.Character
            self.status="Waiting for entity role"
        else
            self.lastCharacter=nil
            stopMovement()
            self.status="Off"
        end
    end
    function self:FindNearest()
        local _,root=rig(self.player)
        if not root then return nil end
        local best,shortest=nil,math.huge
        for _,other in ipairs(self.players:GetPlayers()) do
            local otherRoot=survivor(other)
            if otherRoot then
                local d=posDistance(root.Position,otherRoot.Position)
                if d<shortest then best,shortest=other,d end
            end
        end
        return best,shortest
    end
    function self:Rescan()
        self.target=self:FindNearest()
        dismissRoute()
        self.lastScan=self.now
        self.lastPlan=-math.huge
        self.stagnant=0
        self.lastPos=nil
        self.status=self.target and "Target: "..self.target.Name or "No survivors"
        return self.target
    end
    function self:Plan(reason)
        if not self.enabled or self.computing then return false end
        local _,root=rig(self.player)
        local targetRoot=survivor(self.target)
        if not root or not targetRoot then return false end
        if self.now-self.lastPlan<1.2 and reason~="stuck"
            and reason~="blocked" then return false end
        dismissRoute()
        self.lastPlan=self.now;self.computing=true
        local token=self.token
        local from,to=root.Position,targetRoot.Position
        self.goal=to
        self.status="Pathfinding: "..tostring(reason)
        self.async(function()
            local path
            local ok=pcall(function()
                path=self.pathfinding:CreatePath({
                    AgentRadius=2,AgentHeight=5,AgentCanJump=true,
                    WaypointSpacing=5,
                })
                path:ComputeAsync(from,to)
            end)
            if token~=self.token or not self.enabled then
                if path then pcall(function() path:Destroy() end) end
                return
            end
            self.computing=false;self.plans=self.plans+1
            if not ok or not path or path.Status~=self.pathSuccess then
                if path then pcall(function() path:Destroy() end) end
                self.route={{Position=to}}
                self.status="No path: direct attempt"
                return
            end
            local succeeded,waypoints=pcall(function() return path:GetWaypoints() end)
            if not succeeded or type(waypoints)~="table" or #waypoints==0 then
                pcall(function() path:Destroy() end)
                self.route={{Position=to}}
                self.status="Empty path: direct attempt"
                return
            end
            self.path=path
            self.route=waypoints
            self.waypoint=#waypoints>1 and 2 or 1
            self.status="Following "..self.target.Name
            if path.Blocked then
                self.blocked=path.Blocked:Connect(function(idx)
                    if idx>=self.waypoint then
                        -- Defer route replacement until the next update.
                        self.lastPlan=-math.huge
                        self.goal=nil
                    end
                end)
            end
        end)
        return true
    end
    function self:UseAbility(distance)
        if not self.autoAbility or not self.profile or not self.sendAbility then
            return false
        end
        if self.now<self.cooldownUntil then return false end
        local profile=PROFILES[self.profile] or PROFILES.Generic
        for i=1,4 do
            -- Jeff's Ultra Attack kicks its user; never automate this ability.
            if self.profile=="Jeff" and i==4 then break end
            local binding=self.binds[self.profile] and self.binds[self.profile][i]
            local range=profile.ranges[i]
            if binding and binding~="None" and distance>=range[1]
                and distance<=range[2]
                and self.now-self.slotTimes[self.profile][i]>=profile.cooldown[i] then
                local ok,accepted=pcall(self.sendAbility,binding)
                if ok and accepted then
                    self.slotTimes[self.profile][i]=self.now
                    self.cooldownUntil=self.now+0.8
                    self.abilities=self.abilities+1
                    return true
                end
            end
        end
        return false
    end
    function self:Step(delta)
        if not self.enabled then return end
        local dt=type(delta)=="number" and math.max(0,math.min(delta,1)) or 0
        self.now=self.now+dt
        local profile=self:CurrentProfile()
        local character=self.player.Character
        if character~=self.lastCharacter then
            dismissRoute()
            self.lastCharacter=character
            self.target=nil
            self.lastPlan=-math.huge
            self.lastPos=nil
            self.stagnant=0
        end
        if profile~=self.profile then
            dismissRoute();self.profile=profile;self.target=nil
            self.lastScan=-math.huge
            self.lastPlan=-math.huge
            if not profile then stopMovement() end
        end
        if not profile then
            self.status="Not an entity (or role hidden)"
            return
        end
        local hum,root=rig(self.player)
        if not hum then
            self.status="Waiting for humanoid-controlled "..profile
            return
        end
        if self.now-self.lastScan>=0.6 or not survivor(self.target) then
            self.lastScan=self.now
            local newTarget=self:FindNearest()
            if newTarget~=self.target then
                self.target=newTarget
                dismissRoute()
                self.lastPlan=-math.huge
                self.lastPos=nil;self.stagnant=0
                if not newTarget then stopMovement() end
            end
        end
        if not self.target then
            self.status="No valid survivors"
            return
        end
        local targetRoot=survivor(self.target)
        if not targetRoot then
            self:Rescan()
            return
        end
        local gap=posDistance(root.Position,targetRoot.Position)
        self:UseAbility(gap)
        if gap<=4 then
            self.status=profile..": target in range ("..self.target.Name..")"
            self.stagnant=0;self.lastPos=root.Position
            return
        end
        if self.now-self.lastSample>=0.65 then
            if self.lastPos then
                if posDistance(root.Position,self.lastPos)<1.0 then
                    self.stagnant=self.stagnant+self.now-self.lastSample
                else self.stagnant=0 end
            end
            self.lastPos=root.Position;self.lastSample=self.now
        end
        if self.stagnant>=2.2 then
            self.stuck=self.stuck+1
            self:Rescan()
            self:Plan("stuck")
            return
        end
        if self.computing then return end
        local point=self.route[self.waypoint]
        if point and posDistance(root.Position,point.Position)<4 then
            self.waypoint=self.waypoint+1
            point=self.route[self.waypoint]
        end
        if (not point or not self.goal
            or (self.goal and posDistance(self.goal,targetRoot.Position)>12)
            or self.now-self.lastPlan>3.5)
            and self.now-self.lastPlan>=1.2 then
            self:Plan("replan")
            -- ComputeAsync yields. Wait for the route instead of issuing a
            -- direct MoveTo through an obstacle while the planner is running.
            if self.computing then return end
            point=self.route[self.waypoint]
        end
        if not point then point={Position=targetRoot.Position} end
        if self.now-self.lastMove>=0.45 then
            if point.Action==self.jumpAction then hum.Jump=true end
            pcall(hum.MoveTo,hum,point.Position)
            self.lastMove=self.now
            self.status=profile.." chasing "..self.target.Name.." ("..math.floor(gap).." studs)"
        end
    end
    function self:Status()
        return self.status.." | paths "..self.plans.." | stuck "..self.stuck
            .." | abilities "..self.abilities
    end
    function self:Unload() self:SetEnabled(false) end
    return self
end
return M
