-- Zinc Hub loader dispatch regression test (plain Lua 5.4)
local file = assert(io.open("loader.lua", "rb"))
local source = file:read("*a")
file:close()

local function check(name, placeId, universeId, metadata, expected, metaCalls)
    local requested, calls = {}, 0
    local gameMock = {PlaceId = placeId, GameId = universeId}
    function gameMock:GetService(service)
        if service == "HttpService" then
            return {GenerateGUID = function() return "unit-test" end}
        end
        assert(service == "MarketplaceService")
        return {GetProductInfo = function(_, id, kind)
            calls = calls + 1
            assert(id == placeId and kind == "Asset")
            if metadata == false then error("metadata inaccessible") end
            return metadata
        end}
    end
    function gameMock:HttpGet(url)
        requested[#requested + 1] = url
        return "return 'executed'"
    end
    local globals = {
        game = gameMock, Enum = {InfoType = {Asset = "Asset"}},
        assert = assert, type = type, tostring = tostring, pcall = pcall,
        loadstring = function(script, chunkName)
            assert(script == "return 'executed'")
            assert(chunkName:find(expected, 1, true))
            return function() return "executed" end
        end,
    }
    local loader = assert(load(source, "@loader.lua", "t", globals))
    assert(loader() == "executed", name)
    assert(#requested == 1, name .. ": fetched wrong number of files")
    assert(requested[1]:find("/"..expected.."?reload=unit-test", 1, true), name)
    assert(calls == metaCalls, name .. ": wrong metadata request count")
end

check("main MAYHEM", 119040856156269, 6537995571,
    false, "doors_mayhem.lua", 0)
check("overhaul by owner", 999100, 88812,
    {Name = "DM: OVERHAUL TESTING", Creator = {Name = "MISTICHISKII"}},
    "doors_mayhem.lua", 1)
check("overhaul by same universe", 999101, 6537995571,
    {Name = "DM: OVERHAUL TESTING", Creator = {Name = "MAYHEM GROUP"}},
    "doors_mayhem.lua", 1)
check("unrelated fake testing", 888222, 88812,
    {Name = "DM: OVERHAUL TESTING", Creator = {Name = "unknown"}},
    "rooms_revisited.lua", 1)
check("unrelated game by owner", 888223, 88812,
    {Name = "Random Simulator", Creator = {Name = "MISTICHISKII"}},
    "rooms_revisited.lua", 1)
check("metadata unavailable", 888224, 88812,
    false, "rooms_revisited.lua", 1)
print("mayhem classic/overhaul dispatch: ok")
