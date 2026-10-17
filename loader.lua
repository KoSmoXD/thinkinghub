-- Zinc Hub | game-aware entry point
-- DOORS: MAYHEM uses a standalone asymmetric-game adapter.
-- All other places retain the existing ROOMS: Revisited loader behavior.
local routes = {
    [119040856156269] = "doors_mayhem.lua", -- DOORS: MAYHEM (public-test listing)
}
local target = routes[game.PlaceId] or "rooms_revisited.lua"
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
