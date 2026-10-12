-- Thinking Hub | Always fetch the current published hub.
local url="https://raw.githubusercontent.com/KoSmoXD/thinkinghub/main/rooms_revisited.lua"
local ok,source=pcall(function()
    return game:HttpGet(url.."?reload="..game:GetService("HttpService"):GenerateGUID(false))
end)
assert(ok and type(source)=="string","Thinking Hub download failed: "..tostring(source))
local chunk,reason=loadstring(source,"@ThinkingHub")
assert(chunk,reason)
return chunk()
