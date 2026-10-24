-- Zinc Hub | MAYHEM stamina adapter (experimental, local-client only).
-- Does not touch remotes, other players, movement speed or game scripts.
-- Server-owned / closure-held stamina is intentionally out of reach here.
local Module = {}

local CURRENT = {
    stamina = true, currentstamina = true, staminalevel = true,
    staminalevelcurrent = true, staminavalue = true,
    sprintstamina = true, runstamina = true, remainingstamina = true,
    staminaamount = true,
}
local MAXIMUM = {
    "MaxStamina", "StaminaMax", "MaximumStamina", "MaxSprintStamina",
    "MaxRunStamina", "StaminaCapacity",
}
local function norm(value)
    return tostring(value or ""):lower():gsub("[^%w]", "")
end
local function goodNumber(value)
    return type(value) == "number" and value == value
        and value >= 0 and value <= 100000
end
local function maxNumber(value)
    return goodNumber(value) and value > 0 and value or nil
end
local function descendants(object)
    if not object then return {} end
    local ok, result = pcall(object.GetDescendants, object)
    if ok and type(result) == "table" then return result end
    return {}
end
local function attributes(object)
    local ok, result = pcall(object.GetAttributes, object)
    if ok and type(result) == "table" then return result end
    return {}
end
local function prop(object, name)
    if not object then return nil end
    local value = attributes(object)[name]
    if maxNumber(value) then return value end
    local ok, child = pcall(object.FindFirstChild, object, name)
    if not ok or not child then return nil end
    local success, v = pcall(function() return child.Value end)
    return success and maxNumber(v) or nil
end

function Module.new(player)
    assert(player, "Mayhem stamina adapter requires LocalPlayer")
    local self = {
        enabled = false, player = player, sources = {}, writes = 0,
        errors = 0, refillInterval = 0.1, scanInterval = 2.5,
        elapsed = 0, scanClock = 0, fallbackCap = 100,
        scans = 0, lastStatus = "Off",
    }

    local function excluded(node)
        -- PlayerGui stamina bars are presentation, not authoritative stamina.
        local ok, gui = pcall(player.FindFirstChild, player, "PlayerGui")
        if ok and gui then
            if node == gui then return true end
            local success, result = pcall(node.IsDescendantOf, node, gui)
            if success and result then return true end
        end
        return false
    end
    local function allowed(node)
        if not node or excluded(node) then return false end
        if node==player or node==player.Character then return true end
        for _,root in ipairs({player,player.Character or false}) do
            if root then
                local ok,inside=pcall(node.IsDescendantOf,node,root)
                if ok and inside then return true end
            end
        end
        return false
    end
    local function cap(source, current)
        local locations = {}
        for _, item in ipairs({source.object, source.object.Parent or false,
            player.Character or false, player}) do
            if item then locations[#locations+1] = item end
        end
        for _, item in ipairs(locations) do
            if item then
                for _, name in ipairs(MAXIMUM) do
                    local ceiling = prop(item, name)
                    if ceiling then return ceiling end
                end
            end
        end
        return math.max(self.fallbackCap, current)
    end

    function self:Scan()
        local found, seen = {}, {}
        local roots = {player}
        if player.Character then roots[#roots+1] = player.Character end
        for _, root in ipairs(roots) do
            local objects = {root}
            for _, child in ipairs(descendants(root)) do
                objects[#objects+1] = child
            end
            for _, item in ipairs(objects) do
                if allowed(item) and not seen[item] then
                    seen[item] = true
                    for key, value in pairs(attributes(item)) do
                        if CURRENT[norm(key)] and goodNumber(value) then
                            found[#found+1] = {object=item, key=key, mode="attribute"}
                        end
                    end
                    local ok, isNumeric = pcall(function()
                        return item:IsA("NumberValue") or item:IsA("IntValue")
                    end)
                    if ok and isNumeric and CURRENT[norm(item.Name)] then
                        found[#found+1] = {object=item, key="Value", mode="value"}
                    end
                end
                if #found >= 24 then break end
            end
        end
        self.sources = found
        self.lastCharacter = player.Character
        self.scans = self.scans + 1
        self.lastStatus = #found == 0 and "No accessible stamina values"
            or ("Local stamina candidates: "..tostring(#found))
        return found
    end
    function self:Describe()
        local lines = {}
        for i, source in ipairs(self.sources) do
            local obj = source.object
            local ok, path = pcall(obj.GetFullName, obj)
            lines[#lines+1] = string.format(
                "[Zinc Mayhem] stamina %d: %s.%s (%s)",
                i, ok and path or tostring(obj.Name), source.key, source.mode
            )
        end
        return lines
    end
    function self:Enabled(value)
        self.enabled = value == true
        self.elapsed, self.scanClock = 0, 0
        if self.enabled then self:Scan()
        else self.lastStatus = "Off"; self.sources = {} end
    end
    function self:Step(dt)
        if not self.enabled then return end
        if self.lastCharacter ~= player.Character then self:Scan() end
        dt = type(dt) == "number" and math.max(0, math.min(dt, 1)) or 0
        self.scanClock = self.scanClock + dt
        self.elapsed = self.elapsed + dt
        if self.scanClock >= self.scanInterval then
            self.scanClock = 0
            self:Scan()
        end
        if self.elapsed < self.refillInterval then return end
        self.elapsed = 0
        for _, source in ipairs(self.sources) do
            local item = source.object
            local ok, current = pcall(function()
                return source.mode == "attribute"
                    and item:GetAttribute(source.key) or item.Value
            end)
            if allowed(item) and ok and goodNumber(current) then
                local target = cap(source, current)
                if current + 0.01 < target then
                    local updated = pcall(function()
                        if source.mode == "attribute" then
                            item:SetAttribute(source.key, target)
                        else
                            item.Value = target
                        end
                    end)
                    if updated then self.writes = self.writes+1
                    else self.errors = self.errors+1 end
                end
            end
        end
    end
    function self:Status()
        if not self.enabled then return "Off" end
        local count = #self.sources
        if count == 0 then return "No accessible stamina source found" end
        return string.format(
            "Client refill: %d source(s) / %d writes (server effect unverified)",
            count, self.writes
        )
    end
    function self:Unload()
        self:Enabled(false)
    end
    return self
end
return Module
