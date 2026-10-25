local M = {}
local DOWN_FLAGS={"Downed","IsDowned","Knocked","KnockedDown","IsKnocked",
    "Incapacitated","IsIncapacitated"}
function M.IsDowned(player)
    local char=player and player.Character
    if not char then return false end
    local hum=char:FindFirstChildOfClass("Humanoid")
    local sources={player,char,hum or false}
    local info=char:FindFirstChild("InfoFolder")
    if info then
        sources[#sources+1]=info
        local effects=info:FindFirstChild("LiveEffects")
        if effects then sources[#sources+1]=effects end
    end
    for _,obj in ipairs(sources) do
        if obj then
            for _,name in ipairs(DOWN_FLAGS) do
                local ok,value=pcall(obj.GetAttribute,obj,name)
                if ok and (value==true or value==1) then return true end
                local found,child=pcall(obj.FindFirstChild,obj,name)
                if found and child then
                    local valid,active=pcall(function()
                        return child:IsA("BoolValue") and child.Value==true
                    end)
                    if valid and active then return true end
                end
            end
        end
    end
    return false
end
function M.new(deps)
    local self={enabled=false,elapsed=0,status="Off",target=nil}
    local function root(player)
        local char=player and player.Character
        local hum=char and char:FindFirstChildOfClass("Humanoid")
        local part=char and char:FindFirstChild("HumanoidRootPart")
        if not hum or hum.Health<=0 or not part or not part:IsA("BasePart")
            or char:GetAttribute("Dead")==true or char:GetAttribute("IsDead")==true then return nil end
        return part
    end
    function self:SetEnabled(value)
        self.enabled=value==true;self.elapsed=.2;self.target=nil
        self.status=self.enabled and "Waiting for entity role" or "Off"
    end
    function self:Step(dt)
        if not self.enabled then return end
        self.elapsed=self.elapsed+math.max(0,math.min(tonumber(dt) or 0,1))
        if self.elapsed<.2 then return end
        self.elapsed=0;self.target=nil
        if deps.roleOf(deps.player)~="Entity" then
            self.status="Paused: entity only";return
        end
        local own=root(deps.player)
        if not own then self.status="Waiting for character";return end
        local nearest,distance=nil,math.huge
        for _,other in ipairs(deps.players:GetPlayers()) do
            if other~=deps.player and other.Character~=deps.player.Character
                and deps.roleOf(other)=="Survivor"
                and not M.IsDowned(other)
                and not (deps.player.Team and other.Team==deps.player.Team) then
                local part=root(other)
                if part then
                    local gap=(part.Position-own.Position).Magnitude
                    if gap<distance then nearest=part;distance=gap;self.target=other end
                end
            end
        end
        if not nearest then self.status="No standing survivor";return end
        own.CFrame=nearest.CFrame
        self.status="Looping to "..self.target.Name
    end
    function self:Status()return self.status end
    function self:Unload()self:SetEnabled(false)end
    return self
end
return M
