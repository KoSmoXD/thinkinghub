-- Zinc Hub AntiTamper v1.0
-- Best-effort local checks. Never deliberately crash or freeze the Roblox client.
-- Suspicious GUI or log indicators alone warn; confirmed tooling requires both.
local AntiTamper = {}
AntiTamper.__index = AntiTamper

local GUI_SIGNATURES = {
    dex = "DEX", darkdex = "DEX", darkdexv3 = "DEX", dexexplorer = "DEX",
    rspy = "RSPY", simplespy = "RSPY", simplespyv3 = "RSPY",
    remotespy = "RSPY", remotespyv3 = "RSPY",
}

local function guiSignature(object)
    local ok, name, isRoot = pcall(function()
        return object.Name, object:IsA("ScreenGui") or object:IsA("Folder")
    end)
    if not ok or not isRoot or type(name) ~= "string" then return nil end
    return GUI_SIGNATURES[name:lower():gsub("[^%w]", "")]
end

local function logSignature(message)
    if type(message) ~= "string" then return nil end
    local text = message:lower()
    if text:find("[zinc hub]", 1, true)
        or text:find("[zinc antitamper]", 1, true) then return nil end
    if text:find("simple spy", 1, true) or text:find("simplespy", 1, true)
        or text:find("remote spy", 1, true) or text:find("remotespy", 1, true)
        or text:match("%f[%w]rspy%f[%W]") then return "RSPY" end
    if text:find("dark dex", 1, true) or text:find("darkdex", 1, true)
        or text:find("dex explorer", 1, true)
        or text:find("dex loaded", 1, true) then return "DEX" end
    return nil
end

local function safeConnect(self, signal, callback)
    if not signal then return end
    local ok, connection = pcall(function() return signal:Connect(callback) end)
    if ok and connection then
        self._connections[#self._connections + 1] = connection
    end
end

function AntiTamper:_confirm(kind, reason)
    if not self.running or self.triggered then return end
    self.triggered = true
    if type(self.onConfirmed) == "function" then
        local ok, err = pcall(self.onConfirmed, kind, reason)
        if not ok then warn("[Zinc AntiTamper] action failed: " .. tostring(err)) end
    end
end

function AntiTamper:_record(kind, channel)
    if not self.running or self.triggered or not kind then return end
    local evidence = self.evidence[kind]
    if not evidence or evidence[channel] then return end
    evidence[channel] = true
    if type(self.onSignal) == "function" then
        local ok, err = pcall(self.onSignal, kind, channel)
        if not ok then warn("[Zinc AntiTamper] signal error: " .. tostring(err)) end
    end
    if evidence.gui and evidence.log then
        self:_confirm(kind, "gui+log")
    end
end

function AntiTamper:InspectGui(object)
    self:_record(guiSignature(object), "gui")
end

function AntiTamper:InspectLog(message)
    self:_record(logSignature(message), "log")
end

function AntiTamper:CheckOwnGui()
    if not self.running or self.triggered or type(self.getOwnGui) ~= "function" then return end
    local ok, gui = pcall(self.getOwnGui)
    if not ok then return end
    if gui and not self.ownGui then self.ownGui = gui end
    if self.ownGui and (not gui or gui ~= self.ownGui or self.ownGui.Parent == nil) then
        self:_confirm("HubUI", "own_gui_missing")
    end
end

function AntiTamper:Scan()
    if not self.running then return end
    self:CheckOwnGui()
    if self.triggered then return end
    if self.coreGui then
        local ok, descendants = pcall(function() return self.coreGui:GetDescendants() end)
        if ok and type(descendants) == "table" then
            for _, object in ipairs(descendants) do
                self:InspectGui(object)
                if self.triggered then break end
            end
        end
    end
end

function AntiTamper:Stop()
    if not self.running then return end
    self.running = false
    for _, connection in ipairs(self._connections) do
        pcall(function() connection:Disconnect() end)
    end
    self._connections = {}
end

function AntiTamper.Start(options)
    options = options or {}
    local self = setmetatable({
        running = true,
        triggered = false,
        evidence = { DEX = {}, RSPY = {} },
        _connections = {},
        _elapsed = 0,
        coreGui = options.CoreGui,
        getOwnGui = options.GetOwnGui,
        onSignal = options.OnSignal,
        onConfirmed = options.OnConfirmed,
    }, AntiTamper)

    local logService = options.LogService
    if not logService then
        pcall(function() logService = game:GetService("LogService") end)
    end
    if not self.coreGui then
        pcall(function() self.coreGui = game:GetService("CoreGui") end)
    end
    local runService = options.RunService
    if not runService then
        pcall(function() runService = game:GetService("RunService") end)
    end
    if self.coreGui then
        safeConnect(self, self.coreGui.DescendantAdded, function(object)
            self:InspectGui(object)
        end)
    end
    if logService then
        safeConnect(self, logService.MessageOut, function(message)
            self:InspectLog(message)
        end)
        local ok, history = pcall(function() return logService:GetLogHistory() end)
        if ok and type(history) == "table" then
            for _, item in ipairs(history) do
                if type(item) == "table" then
                    self:InspectLog(item.message or item.Message)
                    if self.triggered then break end
                end
            end
        end
    end
    if runService then
        safeConnect(self, runService.Heartbeat, function(dt)
            self._elapsed = self._elapsed + (tonumber(dt) or 0)
            if self._elapsed >= 6 then
                self._elapsed = 0
                self:Scan()
            end
        end)
    end
    self:Scan()
    return self
end

return AntiTamper
