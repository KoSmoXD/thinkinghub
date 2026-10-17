-- Pure classification checks extracted from the client module (Lua 5.4).
local handle = assert(io.open("doors_mayhem.lua", "rb"))
local source = handle:read("*a")
handle:close()
local first = assert(source:find("local fragmentAliases = {}", 1, true))
local last = assert(source:find("\nlocal function index(instance)", first, true))
local extracted = source:sub(first, last - 1)
local prefix = [[
local function norm(s) return tostring(s or ""):lower():gsub("[^%w]", "") end
local Workspace = {}
local CollectionService = {GetTags = function(_, object)
    return object.tags or {}
end}
local LocalPlayer = {Character = {Name = "LocalAvatar"}}
function LocalPlayer.Character:IsA(name) return name == "Model" end
local Players = {GetPlayerFromCharacter = function(_, instance)
    if instance.Name == "OtherAvatar" then return {Name = "RemoteUser"} end
    return nil
end}
]]
local module = assert(load(prefix .. extracted
    .. "\nreturn classify, fragmentAliases, LocalPlayer.Character, Workspace, bookAliases, leverAliases\n",
    "@mayhem_classifier"))
local classify, aliases, localCharacter, workspace, books, levers = module()

local function fake(name, kind, opts)
    opts = opts or {}
    local instance = {Name = name, kind = kind, Parent = opts.parent,
        ObjectText = opts.objectText or "", ActionText = opts.actionText or "",
        attrs = opts.attrs or {}}
    function instance:IsA(expected)
        return self.kind == expected or (self.kind == "BasePart" and expected == "BasePart")
    end
    function instance:GetAttribute(key) return self.attrs[key] end
    function instance:FindFirstChildWhichIsA(name, recursive)
        return opts.prompt
    end
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
-- Regression: formerly the indexer excluded only the character root,
-- allowing equipped item parts and pickup prompts to highlight our avatar.
local localTool = fake("EquippedTool", "Model", {parent = localCharacter})
local localPart = fake("Handle", "BasePart", {parent = localTool})
local localFragment = fake("GlitchFragment", "BasePart", {parent = localTool})
local localPrompt = fake("Interact", "ProximityPrompt",
    {parent = localPart, objectText = "Glitch Fragment"})
verify("local character root", localCharacter, nil)
verify("local equipped handle", localPart, nil)
verify("local carried fragment", localFragment, nil)
verify("local carried prompt", localPrompt, nil)
local remoteRig = fake("OtherAvatar", "Model", {parent = workspace})
local remoteTool = fake("Tool", "Model", {parent = remoteRig})
verify("other player's carried objective", fake("Handle", "BasePart",
    {parent = remoteTool}), nil)
verify("other player's carried fragment", fake("GlitchFragment", "BasePart",
    {parent = remoteTool}), nil)
verify("world fragments unaffected", fake("GlitchFragment", "Model",
    {parent = workspace}), "fragment")
local tagged = fake("PickupModel", "Model", {parent = workspace})
tagged.tags = {"GlitchFragment"}
verify("tag-based fragment", tagged, "fragment")
verify("generic nearby item not fragment", fake("WaterBottle", "Model",
    {parent = workspace}), nil)
verify("glitch gate not fragment", fake("GlitchGate", "Model",
    {parent = workspace}), nil)
-- MAYHEM map-specific objective classification.
-- Books and levers must no longer be swallowed by generic Objective ESP.
verify("Library GlitchBook", fake("GlitchBook", "Model", {parent = workspace}), "book")
verify("Library code book", fake("CodeBook", "BasePart", {parent = workspace}), "book")
verify("Library numbered book", fake("Book_05", "Model", {parent = workspace}), "book")
verify("Cellar lever", fake("CellarLever", "Model", {parent = workspace}), "lever")
verify("Cellar numbered lever", fake("Lever_03", "BasePart", {parent = workspace}), "lever")
verify("plain lever", fake("Lever", "Model", {parent = workspace}), "lever")
verify("book shelf decoration excluded", fake("Book", "BasePart", {parent = workspace}), nil)
verify("book-shaped decoration excluded", fake("Bookshelf", "Model", {parent = workspace}), nil)
verify("fuse not lever", fake("FuseBox", "Model", {parent = workspace}), "objective")
verify("plain handle not lever", fake("Handle", "BasePart", {parent = workspace}), "objective")
local collectPrompt = fake("Interact", "ProximityPrompt",
    {parent = workspace, objectText = "Book", actionText = "Collect"})
verify("book prompt", collectPrompt, "book")
local leverPrompt = fake("Pull", "ProximityPrompt",
    {parent = workspace, objectText = "Cellar Lever", actionText = "Pull"})
verify("lever prompt", leverPrompt, "lever")
local readableBook = fake("Book", "Model", {parent = workspace,
    prompt = fake("Read", "ProximityPrompt", {actionText = "Collect", objectText = "Book"})})
verify("collectible named Book", readableBook, "book")
local codeTag = fake("ObjectivePart", "BasePart", {parent = workspace})
codeTag.tags = {"GlitchBook"}
verify("tagged book", codeTag, "book")
local leverAttrib = fake("InteractPart", "BasePart",
    {parent = workspace, attrs = {ObjectiveType = "CellarLever"}})
verify("attribute lever", leverAttrib, "lever")
books.corruptedtome = true
verify("custom book alias", fake("CorruptedTome", "Model", {parent = workspace}), "book")
books.corruptedtome = nil
verify("book alias clear", fake("CorruptedTome", "Model", {parent = workspace}), nil)
levers.floorhandle = true
verify("custom lever alias", fake("FloorHandle", "BasePart", {parent = workspace}), "lever")
levers.floorhandle = nil
verify("lever alias clear", fake("FloorHandle", "BasePart", {parent = workspace}), nil)
verify("local carried book excluded", fake("GlitchBook", "Model",
    {parent = localTool}), nil)
verify("other player's lever excluded", fake("CellarLever", "Model",
    {parent = remoteTool}), nil)
print("mayhem fragment + book + lever + character exclusion: ok")
