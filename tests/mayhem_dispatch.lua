-- Loader dispatch smoke test; runs without Roblox or an executor.
local file = assert(io.open("loader.lua", "rb"))
local source = file:read("*a")
file:close()

local function check(placeId, expected)
    local requested = {}
    local gameMock = {PlaceId = placeId}
    function gameMock:GetService(service)
        assert(service == "HttpService")
        return {GenerateGUID = function() return "unit-test" end}
    end
    function gameMock:HttpGet(url)
        requested[#requested + 1] = url
        return "return 'executed'"
    end
    local globals = {
        game = gameMock,
        assert = assert,
        type = type,
        tostring = tostring,
        pcall = pcall,
        loadstring = function(code, name)
            assert(code == "return 'executed'")
            assert(name:find(expected, 1, true))
            return function() return "executed" end
        end,
    }
    local loader = assert(load(source, "@loader.lua", "t", globals))
    assert(loader() == "executed")
    assert(#requested == 1)
    assert(requested[1]:find("/"..expected.."?reload=unit-test", 1, true))
end

check(119040856156269, "doors_mayhem.lua")
check(12345, "rooms_revisited.lua")
print("mayhem loader dispatch: ok")
