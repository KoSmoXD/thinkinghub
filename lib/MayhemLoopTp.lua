local M = {}
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
                and not (deps.player.Team and other.Team==deps.player.Team) then
                local part=root(other)
                if part then
                    local gap=(part.Position-own.Position).Magnitude
                    if gap<distance then nearest=part;distance=gap;self.target=other end
                end
            end
        end
        if not nearest then self.status="No living survivor";return end
        own.CFrame=nearest.CFrame
        self.status="Looping to "..self.target.Name
    end
    function self:Status()return self.status end
    function self:Unload()self:SetEnabled(false)end
    return self
end
return M
