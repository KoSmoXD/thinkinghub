-- Client-side opponent root expansion; server hit validation may ignore it.
local M = {}
function M.new(deps)
    assert(deps.player and deps.players and deps.eligible, "Hitbox dependencies required")
    local self={enabled=false,size=8,elapsed=0,originals={},count=0}
    local function restore(part)
        local original=self.originals[part]
        if not original then return end
        for key,value in pairs(original) do
            pcall(function() part[key]=value end)
        end
        self.originals[part]=nil
    end
    function self:SetSize(value)
        value=tonumber(value)
        if not value or value~=value then return false end
        self.size=math.max(2,math.min(20,value))
        self.elapsed=.2
        return true
    end
    function self:SetEnabled(value)
        self.enabled=value==true
        self.elapsed=.2
        if not self.enabled then
            for part in pairs(self.originals) do restore(part) end
            self.count=0
        end
    end
    function self:Step(dt)
        if not self.enabled then return end
        self.elapsed=self.elapsed+math.max(0,math.min(tonumber(dt) or 0,1))
        if self.elapsed<.2 then return end
        self.elapsed=0
        local desired={}
        for _,player in ipairs(deps.players:GetPlayers()) do
            if player~=deps.player and deps.eligible(player) then
                local char=player.Character
                local hum=char and char:FindFirstChildOfClass("Humanoid")
                local part=char and char:FindFirstChild("HumanoidRootPart")
                if char and char~=deps.player.Character and part and part:IsA("BasePart")
                    and hum and hum.Health>0 and char:GetAttribute("Dead")~=true
                    and char:GetAttribute("IsDead")~=true then desired[part]=true end
            end
        end
        for part in pairs(self.originals) do
            if not desired[part] then restore(part) end
        end
        self.count=0
        for part in pairs(desired) do
            if not self.originals[part] then
                self.originals[part]={Size=part.Size,Transparency=part.Transparency,
                    CanCollide=part.CanCollide,Massless=part.Massless}
            end
            local original=self.originals[part]
            part.Size=Vector3.new(math.max(original.Size.X,self.size),
                math.max(original.Size.Y,self.size),math.max(original.Size.Z,self.size))
            part.Transparency=.75
            part.CanCollide=false
            part.Massless=true
            self.count=self.count+1
        end
    end
    function self:Status()
        if not self.enabled then return "Off" end
        return self.count.." opponent hitbox(es) | "..self.size.." studs (client-side)"
    end
    function self:Unload() self:SetEnabled(false) end
    return self
end
return M
