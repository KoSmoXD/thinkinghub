-- Pure classification checks extracted from the client module (Lua 5.4).
local handle = assert(io.open("doors_mayhem.lua", "rb"))
local source = handle:read("*a")
handle:close()
local first = assert(source:find("local fragmentAliases = {}", 1, true))
local last = assert(source:find("\nlocal function index(instance)", first, true))
local extracted = source:sub(first, last - 1)
local prefix = [[
local function norm(s) return tostring(s or ""):lower():gsub("[^%w]", "") end
local Players = {GetPlayerFromCharacter = function() return nil end}
]]
local module = assert(load(prefix .. extracted .. "\nreturn classify, fragmentAliases\n", "@mayhem_classifier"))
local classify, aliases = module()

local function fake(name, kind, opts)
    opts = opts or {}
    local instance = {Name = name, kind = kind, Parent = opts.parent,
        ObjectText = opts.objectText or "", ActionText = opts.actionText or "",
        attrs = opts.attrs or {}}
    function instance:IsA(expected)
        return self.kind == expected or (self.kind == "BasePart" and expected == "BasePart")
    end
    function instance:GetAttribute(key) return self.attrs[key] end
    return instance
end
local function verify(name, instance, expected)
    local actual = classify(instance)
    assert(actual == expected,
        name .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

verify("named model", fake("GlitchFragment", "Model"), "fragment")
verify("named part", fake("Glitch Fragment", "BasePart"), "fragment")
verify("shard variation", fake("GlitchShard", "BasePart"), "fragment")
verify("pickup variation", fake("Item_GlitchFragmentPickup", "Model"), "fragment")
verify("nested fragment", fake("Fragment", "BasePart",
    {parent = fake("GlitchLoot", "Model")}), "fragment")
verify("attribute name", fake("Pickup", "BasePart",
    {attrs = {ItemName = "Glitch Fragment"}}), "fragment")
verify("prompt object text", fake("Interaction", "ProximityPrompt",
    {objectText = "Glitch Fragment", actionText = "Pick up"}), "fragment")
verify("prompt action text", fake("Interaction", "ProximityPrompt",
    {actionText = "Pick up Glitch Fragment"}), "fragment")
verify("glitch entity false positive", fake("Glitch", "Model"), nil)
verify("unrelated fragment", fake("Fragment", "BasePart"), nil)
verify("normal item", fake("Apple", "BasePart"), nil)
verify("fuse stays objective", fake("FuseBox", "Model"), "objective")
verify("exit stays exit", fake("ExitDoor", "Model"), "exit")
aliases.corruptedshard = true
verify("overhaul alias", fake("CorruptedShard", "BasePart"), "fragment")
verify("overhaul alias model suffix", fake("CorruptedShardPickup", "Model"), "fragment")
aliases.corruptedshard = nil
verify("alias clears", fake("CorruptedShard", "BasePart"), nil)
print("mayhem fragment classifier: ok")
