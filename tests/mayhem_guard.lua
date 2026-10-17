-- Verify direct adapter accepts MAYHEM and only explicitly approved TESTING instances.
local handle = assert(io.open("doors_mayhem.lua", "rb"))
local source = handle:read("*a")
handle:close()
local endpoint = assert(source:find("\nlocal Players = game:GetService", 1, true))
local guard = source:sub(1, endpoint - 1)

local function check(name, placeId, universeId, info, forced, expected)
    local gameMock = {PlaceId = placeId, GameId = universeId}
    function gameMock:GetService(service)
        assert(service == "MarketplaceService")
        return {GetProductInfo = function(_, targetId)
            assert(targetId == placeId)
            if not info then error("not available") end
            return info
        end}
    end
    local env = {ZincMayhemForceOverhaul = forced}
    local sandbox = {game = gameMock, Enum = {InfoType = {Asset = "Asset"}},
        getgenv = function() return env end}
    setmetatable(sandbox, {__index = _G})
    local chunk = assert(load(guard, "@mayhem_guard", "t", sandbox))
    local success, err = pcall(chunk)
    assert(success == expected, name .. ": " .. tostring(err))
end
check("classic", 119040856156269, 6537995571, false, false, true)
check("testing metadata", 99887, 1,
    {Name = "DM: OVERHAUL TESTING", Creator = {Name = "MISTICHISKII"}},
    false, true)
check("testing metadata unavailable", 99887, 1, false, false, false)
check("explicit testing override", 99887, 1, false, true, true)
check("unrelated title by developer", 99887, 1,
    {Name = "NOT MAYHEM", Creator = {Name = "MISTICHISKII"}},
    false, false)
check("testing title wrong creator", 99887, 1,
    {Name = "DM: OVERHAUL TESTING", Creator = {Name = "Imposter"}},
    false, false)
print("mayhem direct adapter guard: ok")
