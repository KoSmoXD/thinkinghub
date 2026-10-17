-- Zinc Hub | game-aware entry point
-- MAYHEM classic and the separately published DM: OVERHAUL TESTING build.
-- Game metadata is read only to identify testing's unverified PlaceId.
local MAYHEM_MAIN = 119040856156269
local MAYHEM_UNIVERSE = 6537995571

local function norm(value)
    return tostring(value or ""):lower():gsub("[^%w]", "")
end

local function isMayhemTesting()
    local ok, info = pcall(function()
        return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId, Enum.InfoType.Asset)
    end)
    if not ok or type(info) ~= "table" then return false end
    local title = norm(info.Name)
    local isTesting = title == "dmoverhaultesting"
        or title == "doorsmayhemoverhaultesting"
        or title == "doorsmayhemtesting"
    if not isTesting then return false end
    local creator = type(info.Creator) == "table" and norm(info.Creator.Name) or ""
    return creator == "mistichiskii" or game.GameId == MAYHEM_UNIVERSE
end

local target
if game.PlaceId == MAYHEM_MAIN or isMayhemTesting() then
    target = "doors_mayhem.lua"
else
    target = "rooms_revisited.lua"
end
local url = "https://raw.githubusercontent.com/KoSmoXD/thinkinghub/main/" .. target
local ok, source = pcall(function()
    return game:HttpGet(url .. "?reload="
        .. game:GetService("HttpService"):GenerateGUID(false))
end)
assert(ok and type(source) == "string",
    "Zinc Hub download failed (" .. target .. "): " .. tostring(source))
local chunk, reason = loadstring(source, "@ZincHub/" .. target)
assert(chunk, reason)
return chunk()
