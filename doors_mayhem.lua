-- Zinc Hub | DOORS: MAYHEM (client game adapter)
-- Supports the public MAYHEM place and DM: OVERHAUL TESTING.
-- Standalone ZincUI mode with optional client-side loop teleport.
local MAYHEM_MAIN = 119040856156269
local MAYHEM_UNIVERSE = 6537995571
local function normalizeTitle(value)
    return tostring(value or ""):lower():gsub("[^%w]", "")
end
local function testingMetadata()
    local ok, info = pcall(function()
        return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId, Enum.InfoType.Asset)
    end)
    if not ok or type(info) ~= "table" then return false end
    local title = normalizeTitle(info.Name)
    local accepted = title == "dmoverhaultesting"
        or title == "doorsmayhemoverhaultesting"
        or title == "doorsmayhemtesting"
    if not accepted then return false end
    local creator = type(info.Creator) == "table" and normalizeTitle(info.Creator.Name) or ""
    return creator == "mistichiskii" or game.GameId == MAYHEM_UNIVERSE
end
local runtimeEnvironment = (type(getgenv) == "function" and getgenv()) or _G
-- Use only when manually launching this adapter inside the testing portal.
-- Never auto-route unrelated games by an unverified place ID.
local forceTesting = runtimeEnvironment.ZincMayhemForceOverhaul == true
local IS_OVERHAUL = game.PlaceId ~= MAYHEM_MAIN and (forceTesting or testingMetadata())
assert(game.PlaceId == MAYHEM_MAIN or IS_OVERHAUL,
    "Zinc Mayhem: unrecognized place "..tostring(game.PlaceId)
    .."; for the Overhaul portal, set getgenv().ZincMayhemForceOverhaul = true")

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local LocalPlayer = Players.LocalPlayer
assert(LocalPlayer, "Zinc Mayhem requires a local client")
local playerGui=LocalPlayer:FindFirstChildOfClass("PlayerGui")
local roleReport=playerGui and playerGui:FindFirstChild("MayhemRoleReport")
if roleReport then roleReport:Destroy() end

local env = runtimeEnvironment
if env.ZincMayhem and type(env.ZincMayhem.Unload) == "function" then
    pcall(env.ZincMayhem.Unload)
end

local transfer = env.ZincMayhemTransferState
env.ZincMayhemTransferState = nil
local selectedStyle = env.ZincMayhemUIStyle == "Obsidian" and "Obsidian" or "Zinc"
local selfURL = env.ZincMayhemSourceURL
    or "https://raw.githubusercontent.com/KoSmoXD/thinkinghub/feat/doors-mayhem-support/doors_mayhem.lua"

local function fetchZinc(url)
    local ok, source = pcall(function() return game:HttpGet(url) end)
    if not ok or type(source) ~= "string" then return nil end
    local compiler = loadstring
    if type(compiler) ~= "function" then return nil end
    local chunk = compiler(source, "@ZincMayhem/ZincUI")
    if not chunk then return nil end
    local ready, lib = pcall(chunk)
    if ready and type(lib) == "table" and type(lib.CreateWindow) == "function" then
        return lib
    end
end

-- Use MSESP for all visual markers (owned instances only).
-- Match the version used by ROOMS: Revisited so shared sessions stay compatible.
local MSESP = env.mstudio45_ESP
if type(MSESP) ~= "table" or type(MSESP.Add) ~= "function" or MSESP.Destroyed then
    local sourceURL = "https://raw.githubusercontent.com/mstudio45/MSESP/dbde68c85af504d58dac73a537fda21ca8fa626a/source.luau"
    local ok, libraryOrError = pcall(function()
        local source = game:HttpGet(sourceURL)
        local chunk, compileError = loadstring(source, "@ZincMayhem/MSESP")
        assert(chunk, compileError)
        return chunk()
    end)
    if ok then MSESP = libraryOrError else
        warn("[Zinc Mayhem] MSESP could not load: "..tostring(libraryOrError))
    end
end
assert(type(MSESP) == "table" and type(MSESP.Add) == "function"
    and not MSESP.Destroyed, "Zinc Mayhem requires a working MSESP library")

local UI
if selectedStyle == "Obsidian" then
    UI = fetchZinc(
        "https://raw.githubusercontent.com/KoSmoXD/thinkinghub/feat/doors-mayhem-support/lib/MayhemObsidian.lua")
    assert(UI, "Mayhem: Obsidian bridge could not be loaded")
else
    UI = fetchZinc("https://raw.githubusercontent.com/KoSmoXD/thinkinghub/feat/doors-mayhem-support/lib/ZincUI.lua")
    assert(UI, "Zinc Mayhem: failed to load ZincUI")
end

local state = {
    playerESP = false, enemyOnly = true, objectiveESP = false,
    fragmentESP = false, fragmentGame = false, fragmentGuiAlias = "",
    bookESP = false, leverESP = false,
    keyESP = false, exitESP = false, entityESP = false,
    bright = false, fovOn = false,
    fov = 90, spectate = false,
    biggerHitbox = false, hitboxSize = 8,
    loopTp = false,
    playerColor = "Green", uiTheme = "XP",
}
if type(transfer) == "table" and type(transfer.state) == "table" then
    for key, value in pairs(transfer.state) do
        if state[key] ~= nil and type(value) == type(state[key]) then
            state[key] = value
        end
    end
end
local closed = false
local connections, markers, indexed = {}, {}, {}
local originalLighting, oldCamera, oldFov = nil, nil, nil
local spectateIndex = 0
local roleLabel, countLabel
local COLORS = {
    player = Color3.fromRGB(75, 235, 110),
    friend = Color3.fromRGB(95, 160, 255),
    neutral = Color3.fromRGB(50, 225, 225),
    objective = Color3.fromRGB(255, 220, 80),
    fragment = Color3.fromRGB(255, 105, 180),
    book = Color3.fromRGB(140, 170, 255),
    lever = Color3.fromRGB(255, 190, 65),
    key = Color3.fromRGB(255, 240, 95),
    exit = Color3.fromRGB(70, 255, 160),
    entity = Color3.fromRGB(255, 125, 45),
}
local PLAYER_PALETTE = {
    Green = Color3.fromRGB(75, 235, 110),
    Blue = Color3.fromRGB(90, 160, 255),
    Cyan = Color3.fromRGB(50, 225, 225),
    Yellow = Color3.fromRGB(255, 220, 75),
    Red = Color3.fromRGB(255, 75, 75),
}
COLORS.player = PLAYER_PALETTE[state.playerColor] or PLAYER_PALETTE.Green
local LIMITS = {player = 10, objective = 12, fragment = 16,
    book = 16, lever = 12, key = 12, exit = 4, entity = 4}

local function track(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end
local function norm(name)
    return tostring(name or ""):lower():gsub("[^%w]", "")
end
-- Team is authoritative when assigning Survivor/Entity. SelectedEntity
-- is loadout metadata: a survivor can retain it from an earlier round.
local ENTITY_ROLE = {
    entity=true,entities=true,monster=true,monsters=true,killer=true,
    killers=true,rush=true,figure=true,seek=true,bramble=true,
    halt=true,eyes=true,jeff=true,jeffthekiller=true,
}
local SURVIVOR_ROLE = {
    survivor=true,survivors=true,human=true,humans=true,
    innocent=true,innocents=true,runner=true,runners=true,
}
local function roleToken(value)
    local name=norm(value)
    if SURVIVOR_ROLE[name] then return "Survivor" end
    if ENTITY_ROLE[name] then return "Entity" end
    return nil
end
local function roleOf(player)
    if not player then return "Unknown" end
    local team = player.Team
    local teamRole = team and roleToken(team.Name)
    if teamRole then return teamRole end
    local char = player.Character
    -- Observed Overhaul round roles live on Character, not Roblox Teams.
    -- SelectedEntity on Player is a loadout and must not be used here.
    if char then
        local ok,survivor=pcall(char.GetAttribute,char,"Survivor")
        if ok and survivor==true then return "Survivor" end
        local valid,entity=pcall(char.GetAttribute,char,"Entity")
        if valid and type(entity)=="string" and norm(entity)~=""
            and norm(entity)~="none" and norm(entity)~="false" then
            return "Entity"
        end
    end
    for _, obj in ipairs({char or player, player}) do
        for _, key in ipairs({"Role", "CurrentRole", "Team", "Faction",
            "CurrentEntity", "ActiveEntity", "EntityType", "CurrentMonster",
            "CharacterRole", "Monster"}) do
            local ok, value = pcall(obj.GetAttribute, obj, key)
            if ok then
                local kind=roleToken(value)
                if kind then return kind end
            end
            -- Active role metadata can also be stored in StringValue children.
            local found, child=pcall(obj.FindFirstChild,obj,key)
            if found and child then
                local valid,value=pcall(function()
                    if child:IsA("StringValue") then return child.Value end
                end)
                if valid then
                    local kind=roleToken(value)
                    if kind then return kind end
                end
            end
        end
    end
    if char then
        local found = roleToken(char.Name)
        if found then return found end
    end
    return "Unknown"
end

-- Never exclude a survivor just because its stale SelectedEntity points to a
-- monster. When enemyOnly is enabled, unknown-role players are still visible
-- unless they share our actual team.
local function playerESPRelation(localPlayer, otherPlayer, enemyOnly)
    if not otherPlayer or otherPlayer == localPlayer then return false, "self" end
    local sameTeam = localPlayer.Team ~= nil and otherPlayer.Team ~= nil
        and localPlayer.Team == otherPlayer.Team
    local ours, theirs = roleOf(localPlayer), roleOf(otherPlayer)
    if sameTeam then
        if enemyOnly then return false, "teammate" end
        return true, "friend"
    end
    if ours ~= "Unknown" and theirs ~= "Unknown" then
        if ours == theirs then
            if enemyOnly then return false, "same role" end
            return true, "friend"
        end
        return true, "enemy"
    end
    return true, "neutral"
end

local function playerESPPart(character)
    if not character then return nil, nil end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health <= 0 then return nil, "dead" end
    local dead = character:GetAttribute("Dead")
    if dead == true or character:GetAttribute("IsDead") == true then
        return nil, "dead"
    end
    local root = character:FindFirstChild("HumanoidRootPart")
        or character.PrimaryPart
        or character:FindFirstChildWhichIsA("BasePart", true)
    if not root then return nil, "no root part" end
    return root, humanoid and "humanoid" or "custom rig"
end
local fragmentAliases = {}
local loopTpController
do
    local ok,result=pcall(function()
        local source=game:HttpGet("https://raw.githubusercontent.com/KoSmoXD/thinkinghub/feat/doors-mayhem-support/lib/MayhemLoopTp.lua?v=0.10.7")
        local chunk,err=loadstring(source,"@ZincMayhem/LoopTp")
        assert(chunk,err)
        return chunk().new({player=LocalPlayer,players=Players,roleOf=roleOf})
    end)
    if ok then
        loopTpController=result
        loopTpController:SetEnabled(state.loopTp)
    else warn("[Zinc Mayhem] Auto Loop Tp unavailable: "..tostring(result)) end
end
local hitboxController
do
    local ok,result=pcall(function()
        local source=game:HttpGet("https://raw.githubusercontent.com/KoSmoXD/thinkinghub/feat/doors-mayhem-support/lib/MayhemHitbox.lua")
        local chunk,err=loadstring(source,"@ZincMayhem/Hitbox")
        assert(chunk,err)
        return chunk().new({player=LocalPlayer,players=Players,
            eligible=function(other)
                local show,relation=playerESPRelation(LocalPlayer,other,true)
                return show and relation=="enemy"
            end})
    end)
    if ok then
        hitboxController=result
        hitboxController:SetSize(state.hitboxSize)
        hitboxController:SetEnabled(state.biggerHitbox)
    else warn("[Zinc Mayhem] Bigger Hitbox unavailable: "..tostring(result)) end
end
local function hasFragmentName(value)
    local valueName = norm(value)
    if valueName:find("glitchfragment", 1, true) ~= nil
        or valueName:find("fragmentglitch", 1, true) ~= nil
        or valueName == "glitchshard"
        or valueName == "glitchpiece" then return true end
    for alias in pairs(fragmentAliases) do
        if valueName == alias or valueName:find(alias, 1, true) then return true end
    end
    return false
end

local function hasPickupHint(instance)
    if instance:IsA("ProximityPrompt") then
        local words = norm(instance.ActionText .. " " .. instance.ObjectText)
        return words:find("collect", 1, true) ~= nil
            or words:find("pickup", 1, true) ~= nil
            or words:find("grab", 1, true) ~= nil
    end
    if instance:IsA("Model") or instance:IsA("BasePart") then
        local prompt = instance:FindFirstChildWhichIsA("ProximityPrompt", true)
        return prompt and hasPickupHint(prompt) or false
    end
    return false
end
local function isGlitchFragment(instance)
    if hasFragmentName(instance.Name) then return true end
    local label = norm(instance.Name)
    local parent = instance.Parent
    if label == "fragment" then
        if parent then
            local pname = norm(parent.Name)
            if pname:find("glitch", 1, true)
                or pname == "fragments"
                or pname == "fragmentspawns" then return true end
        end
        if hasPickupHint(instance) then return true end
    end
    for _, key in ipairs({"ItemName", "ItemId", "ItemType", "PickupName",
        "DisplayName", "Collectible", "ObjectiveType"}) do
        local value = instance:GetAttribute(key)
        if type(value) == "string" and (hasFragmentName(value)
            or (label == "fragment" and norm(value) == "collectable")) then return true end
    end
    local ok, tags = pcall(CollectionService.GetTags, CollectionService, instance)
    if ok and type(tags) == "table" then
        for _, tag in ipairs(tags) do
            if hasFragmentName(tag) then return true end
        end
    end
    if instance:IsA("ProximityPrompt") then
        if hasFragmentName(instance.ObjectText)
            or hasFragmentName(instance.ActionText) then return true end
        local node = instance.Parent
        for _ = 1, 3 do
            if not node or node == Workspace then break end
            if hasFragmentName(node.Name) then return true end
            node = node.Parent
        end
    end
    return false
end

-- Cellar / Library objective categories: read-only client-side discovery.
-- Distinguish interactive puzzle objects from decorative shelves and mechanisms.
local bookAliases, leverAliases = {}, {}

local function puzzleName(value, kind)
    local name = norm(value)
    if name == "" then return false end
    if kind == "book" then
        if name == "book" or name == "codebook" or name == "librarybook"
            or name == "glitchbook" or name == "puzzlebook"
            or name == "bookpickup" or name == "bookitem"
            or name == "collectiblebook" or name == "bookcollectible"
            or name == "bookobjective" or name == "bookofcodes"
            or name:match("^book%d+$") or name:match("^glitchbook%d+$")
            or name:match("^librarybook%d+$") then return true end
        for alias in pairs(bookAliases) do
            if name == alias then return true end
        end
    elseif kind == "lever" then
        if name == "lever" or name == "cellarlever" or name == "basementlever"
            or name == "puzzlelever" or name == "pulllever"
            or name == "leverhandle" or name == "leverpickup"
            or name == "leverswitch" or name == "gatelever"
            or name == "leverobjective" or name == "librarylever"
            or name:match("^lever%d+$")
            or name:match("^cellarlever%d+$") then return true end
        for alias in pairs(leverAliases) do
            if name == alias then return true end
        end
    end
    return false
end

local function puzzleKind(instance)
    for _, kind in ipairs({"book", "lever"}) do
        if puzzleName(instance.Name, kind) then
            -- "Book" is a very common decorative shelf part; only expose one
            -- when there is evidence of an actual collectible / interaction.
            if kind == "lever" or hasPickupHint(instance)
                or norm(instance.Name) ~= "book" then return kind end
        end
    end
    for _, key in ipairs({"ItemName", "ItemId", "ItemType", "PickupName",
        "DisplayName", "ObjectiveType", "InteractType", "PuzzleType"}) do
        local value = instance:GetAttribute(key)
        if type(value) == "string" then
            for _, kind in ipairs({"book", "lever"}) do
                if puzzleName(value, kind) then return kind end
            end
        end
    end
    local ok, tags = pcall(CollectionService.GetTags, CollectionService, instance)
    if ok and type(tags) == "table" then
        for _, tag in ipairs(tags) do
            for _, kind in ipairs({"book", "lever"}) do
                if puzzleName(tag, kind) then return kind end
            end
        end
    end
    if instance:IsA("ProximityPrompt") then
        local action = norm(instance.ActionText)
        local object = norm(instance.ObjectText)
        for _, kind in ipairs({"book", "lever"}) do
            if puzzleName(object, kind) or puzzleName(action, kind) then return kind end
        end
        if action:find("book", 1, true) and
            (action:find("collect", 1, true) or action:find("pick", 1, true)
                or action:find("read", 1, true)) then return "book" end
        if action:find("lever", 1, true) and
            (action:find("pull", 1, true) or action:find("use", 1, true)
                or action:find("activate", 1, true)) then return "lever" end
        local parent = instance.Parent
        for _ = 1, 3 do
            if not parent or parent == Workspace then break end
            for _, kind in ipairs({"book", "lever"}) do
                if puzzleName(parent.Name, kind) then return kind end
            end
            parent = parent.Parent
        end
    end
    return nil
end

-- Keys are a separate category from generic puzzle objectives. Only exact
-- key labels, pickup prompts, attributes and tags count (not keyboard/keybinds).
local keyAliases = {}
local function hasKeyName(value)
    local label = norm(value)
    if label == "key" or label == "hotelkey" or label == "cellarkey"
        or label == "librarykey" or label == "exitkey" or label == "doorkey"
        or label == "roomkey" or label == "goldkey" or label == "goldenkey"
        or label == "skeletonkey" or label == "keypickup" or label == "keyitem"
        or label == "keycollectible" or label == "keyobjective"
        or label == "masterkey" or label == "rustykey" or label == "silverkey"
        or label:match("^key%d+$") or label:match("^hotelkey%d+$")
        or label:match("^cellarkey%d+$") then return true end
    for alias in pairs(keyAliases) do if label == alias then return true end end
    return false
end

local function isWorldKey(instance)
    if hasKeyName(instance.Name) then return true end
    for _, attribute in ipairs({"ItemName", "ItemId", "ItemType", "PickupName",
        "DisplayName", "Collectible", "ObjectiveType"}) do
        local value = instance:GetAttribute(attribute)
        if type(value) == "string" and hasKeyName(value) then return true end
    end
    local ok, tags = pcall(CollectionService.GetTags, CollectionService, instance)
    if ok and type(tags) == "table" then
        for _, tag in ipairs(tags) do if hasKeyName(tag) then return true end end
    end
    if instance:IsA("ProximityPrompt") then
        if hasKeyName(instance.ObjectText) then return true end
        local action = norm(instance.ActionText)
        if action:find("key", 1, true) and (
            action:find("pickup", 1, true) or action:find("collect", 1, true)
            or action:find("grab", 1, true) or action:find("take", 1, true)
        ) then return true end
        -- A prompt labeled "Use Key" on a door is not itself a key.
        local parent = instance.Parent
        for _ = 1, 2 do
            if not parent or parent == Workspace then break end
            if hasKeyName(parent.Name) then return true end
            parent = parent.Parent
        end
    end
    return false
end

-- A pickup under an avatar (especially a held "Handle" or fragment)
-- must never become world ESP. Check every ancestor, not just the root model.
local function insidePlayerCharacter(instance)
    local current = instance
    while current and current ~= Workspace do
        if current == LocalPlayer.Character then return true end
        if current:IsA("Model") and Players:GetPlayerFromCharacter(current) then
            return true
        end
        current = current.Parent
    end
    return false
end

local function classify(instance)
    if not (instance:IsA("Model") or instance:IsA("BasePart")
        or instance:IsA("ProximityPrompt")) then return nil end
    if insidePlayerCharacter(instance) then return nil end
    if isGlitchFragment(instance) then return "fragment" end
    local puzzle = puzzleKind(instance)
    if puzzle then return puzzle end
    if isWorldKey(instance) then return "key" end
    if instance:IsA("ProximityPrompt") then return nil end
    local name = norm(instance.Name)
    if instance:IsA("Model") then
        for _, entity in ipairs({"figure", "seek", "rush", "eyes", "halt", "bramble", "dread"}) do
            if name == entity or name == entity.."entity" or name == entity.."model" then
                return "entity"
            end
        end
    end
    if name == "exit" or name == "exitdoor" or name == "exitgate"
        or name == "finalexit" or name == "finaldoor" or name == "escapeexit" then
        return "exit"
    end
    if name == "breakerbox" or name == "fusebox" or name == "fuse"
        or name == "fuses" or name == "paper" or name == "timelever"
        or name == "objective" or name == "objectiveitem"
        or name == "button"
        or name == "handle" or name == "guillotine" or name == "generator" then
        return "objective"
    end
    return nil
end

local function index(instance)
    local kind = classify(instance)
    if not kind then return end
    local target = instance
    if instance:IsA("ProximityPrompt") then
        target = instance.Parent
        while target and target ~= Workspace
            and not (target:IsA("BasePart") or target:IsA("Model")) do
            target = target.Parent
        end
        if not target or target == Workspace then return end
        -- Attach to the physical puzzle/pickup rather than the prompt itself.
        local model = target:FindFirstAncestorOfClass("Model")
        if model and ((kind == "fragment" and isGlitchFragment(model))
            or ((kind == "book" or kind == "lever")
                and puzzleKind(model) == kind)
            or (kind == "key" and isWorldKey(model))) then
            target = model
        end
    end
    if not insidePlayerCharacter(target) then indexed[target] = kind end
end
for _, instance in ipairs(Workspace:GetDescendants()) do index(instance) end
track(Workspace.DescendantAdded, index)
track(Workspace.DescendantRemoving, function(instance)
    indexed[instance] = nil
    -- Prompt-derived markers clear on pickup/pull, including after streamed removal.
    if instance:IsA("ProximityPrompt") then
        local kind = isGlitchFragment(instance) and "fragment"
            or puzzleKind(instance) or (isWorldKey(instance) and "key")
        if kind then
            local node = instance.Parent
            for _ = 1, 3 do
                if not node or node == Workspace then break end
                if indexed[node] == kind then indexed[node] = nil end
                node = node.Parent
            end
        end
    end
end)

-- Hotel Glitch Fragment objective: local prompt interaction + clearly
-- exposed GUI answers only. Real puzzle internals can differ by version.
local fragmentGameController
local heldPrompts = {}
local function releasePrompts()
    for prompt in pairs(heldPrompts) do
        heldPrompts[prompt] = nil
        pcall(function() prompt:InputHoldEnd() end)
    end
end
do
    local url = "https://raw.githubusercontent.com/KoSmoXD/thinkinghub/feat/doors-mayhem-support/lib/MayhemFragmentGame.lua"
    local ok, result = pcall(function()
        local source = game:HttpGet(url)
        local chunk, err = loadstring(source, "@ZincMayhem/FragmentGame")
        assert(chunk, err)
        local module = chunk()
        local virtualInput
        pcall(function() virtualInput = game:GetService("VirtualInputManager") end)
        local clickButton = function(button)
            if not virtualInput then return false end
            local pos, size = button.AbsolutePosition, button.AbsoluteSize
            if not (pos and size) then return false end
            local x, y = pos.X + size.X/2, pos.Y + size.Y/2
            local success = pcall(function()
                virtualInput:SendMouseButtonEvent(x, y, 0, true, game, 0)
                virtualInput:SendMouseButtonEvent(x, y, 0, false, game, 0)
            end)
            return success
        end
        local activatePrompt = function(prompt)
            if type(fireproximityprompt) == "function" then
                local success = pcall(fireproximityprompt, prompt)
                if success then return true end
            end
            -- Native hold works for an ordinary proximity prompt in reach.
            local okBegin = pcall(function() prompt:InputHoldBegin() end)
            if not okBegin then return false end
            local hold = {}
            heldPrompts[prompt] = hold
            local duration = math.max(0,tonumber(prompt.HoldDuration) or 0)
            task.delay(duration + 0.1, function()
                if heldPrompts[prompt] ~= hold then return end
                heldPrompts[prompt] = nil
                pcall(function() prompt:InputHoldEnd() end)
            end)
            return true
        end
        return module.new({
            player = LocalPlayer, workspace=Workspace,
            isFragment=isGlitchFragment, inCharacter=insidePlayerCharacter,
            isEntity=function() return roleOf(LocalPlayer) == "Entity" end,
            clickButton=clickButton, activatePrompt=activatePrompt,
            cancelInput=releasePrompts,
        })
    end)
    if ok then fragmentGameController=result
    else warn("[Zinc Mayhem] Fragment Game unavailable: "..tostring(result)) end
end
if fragmentGameController then
    fragmentGameController.guiAlias=state.fragmentGuiAlias
    if state.fragmentGame then fragmentGameController:SetEnabled(true) end
end

local function positionOf(instance)
    if instance:IsA("BasePart") then return instance.Position end
    if instance:IsA("Model") then
        local part = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
        if part then return part.Position end
    end
    return nil
end
local function keepNearest(candidates, desired, kind)
    table.sort(candidates, function(a, b) return a.distance < b.distance end)
    for i = 1, math.min(#candidates, LIMITS[kind]) do
        desired[candidates[i].instance] = {
            color = candidates[i].color or COLORS[kind],
            kind = kind, distance = candidates[i].distance,
        }
    end
end

-- MSESP handles all highlights, billboards and distance text. Never clear
-- the shared library globally: another Zinc/ROOMS module may also use it.
local ESP_LABELS = {
    player = "PLAYER", objective = "OBJECTIVE", fragment = "GLITCH FRAGMENT",
    book = "GLITCH BOOK", lever = "LEVER", key = "KEY",
    exit = "EXIT", entity = "ENTITY",
}
local function removeMarker(instance)
    local record = markers[instance]
    if not record then return end
    markers[instance] = nil
    if record.object and not record.object.Deleted then
        pcall(function() record.object:Destroy() end)
    end
end

local function showMarker(instance, details)
    local label = ESP_LABELS[details.kind] or "TARGET"
    if details.kind == "player" or details.kind == "entity" then
        label = label.." | "..instance.Name
    end
    local color = details.color
    local record = markers[instance]
    if record and record.object and record.object.Deleted then
        markers[instance] = nil
        record = nil
    end
    if not record then
        local textPart = instance:IsA("BasePart") and instance
            or (instance:IsA("Model") and (instance.PrimaryPart
                or instance:FindFirstChildWhichIsA("BasePart", true)))
        if not textPart then return end
        local ok, obj = pcall(function()
            return MSESP:Add({
                Name = label, Model = instance, TextModel = textPart,
                ESPType = "Highlight", Color = color,
                FillColor = color, OutlineColor = color,
                FillTransparency = 0.75, OutlineTransparency = 0,
                TextSize = 15, StudsOffset = Vector3.new(0, 2.4, 0),
                MaxDistance = 5000,
            })
        end)
        if not ok or not obj then
            warn("[Zinc Mayhem] MSESP:Add failed: "..tostring(obj))
            return
        end
        markers[instance] = {object = obj, kind = details.kind,
            color = color, label = label}
        return
    end
    if record.kind ~= details.kind then
        removeMarker(instance)
        return showMarker(instance, details)
    end
    if record.color ~= color then
        local ok = pcall(function() record.object:SetEveryColor(color, true) end)
        if ok then record.color = color end
    end
    if record.label ~= label and record.object.CurrentSettings then
        record.object.CurrentSettings.Name = label
        record.label = label
    end
end

local function updateESP()
    local camera = Workspace.CurrentCamera
    local character = LocalPlayer.Character
    local myRoot = character and (character:FindFirstChild("HumanoidRootPart")
        or character.PrimaryPart
        or character:FindFirstChildWhichIsA("BasePart", true))
    local origin = (myRoot and myRoot.Position) or (camera and camera.CFrame.Position) or Vector3.new()
    local candidates = {player = {}, objective = {}, fragment = {}, book = {},
        lever = {}, key = {}, exit = {}, entity = {}}
    if state.playerESP then
        for _, other in ipairs(Players:GetPlayers()) do
            if other ~= LocalPlayer and other.Character
                and other.Character ~= LocalPlayer.Character then
                local show, relation = playerESPRelation(LocalPlayer, other, state.enemyOnly)
                if show then
                    local root = playerESPPart(other.Character)
                    if root then
                        table.insert(candidates.player, {
                            instance = other.Character,
                            distance = (origin-root.Position).Magnitude,
                            color = relation == "enemy" and COLORS.player
                                or relation == "friend" and COLORS.friend
                                or COLORS.neutral,
                        })
                    end
                end
            end
        end
    end
    for instance, kind in pairs(indexed) do
        -- Prefer a named model over the parts it contains; one label per pickup.
        local parentModel = instance:FindFirstAncestorOfClass("Model")
        local duplicate = parentModel and indexed[parentModel] == kind
        -- Characters can acquire items after initial indexing; exclude them here too.
        if not duplicate and not insidePlayerCharacter(instance)
            and ((kind == "objective" and state.objectiveESP)
            or (kind == "fragment" and state.fragmentESP)
            or (kind == "book" and state.bookESP)
            or (kind == "lever" and state.leverESP)
            or (kind == "key" and state.keyESP)
            or (kind == "exit" and state.exitESP)
            or (kind == "entity" and state.entityESP)) then
            if instance.Parent and instance:IsDescendantOf(Workspace) then
                local pos = positionOf(instance)
                if pos then
                    table.insert(candidates[kind], {instance = instance, distance = (origin - pos).Magnitude})
                end
            else
                indexed[instance] = nil
            end
        end
    end
    local desired = {}
    for _, kind in ipairs({"player", "objective", "fragment", "book", "lever", "key", "exit", "entity"}) do
        keepNearest(candidates[kind], desired, kind)
    end
    for instance in pairs(markers) do
        if not desired[instance] then removeMarker(instance) end
    end
    for instance, details in pairs(desired) do showMarker(instance, details) end
    return #candidates.player, #candidates.objective, #candidates.fragment,
        #candidates.book, #candidates.lever, #candidates.key,
        #candidates.exit, #candidates.entity
end

local function applyVisuals()
    local cam = Workspace.CurrentCamera
    if state.fovOn and cam then
        if oldCamera ~= cam then
            if oldCamera and oldFov then
                pcall(function() oldCamera.FieldOfView = oldFov end)
            end
            oldCamera, oldFov = cam, cam.FieldOfView
        end
        cam.FieldOfView = state.fov
    end
    if state.bright then
        Lighting.Brightness = 3
        Lighting.ClockTime = 12
        Lighting.FogEnd = 100000
        Lighting.GlobalShadows = false
    end
end
local function setFullbright(value)
    state.bright = value
    if value then
        originalLighting = originalLighting or {
            Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime,
            FogEnd = Lighting.FogEnd, GlobalShadows = Lighting.GlobalShadows,
        }
        applyVisuals()
    elseif originalLighting then
        for property, old in pairs(originalLighting) do Lighting[property] = old end
        originalLighting = nil
    end
end
local function setFov(value)
    state.fovOn = value
    if value then
        applyVisuals()
    elseif oldCamera and oldFov then
        pcall(function() oldCamera.FieldOfView = oldFov end)
        oldCamera, oldFov = nil, nil
    end
end
local function restoreCamera()
    local camera = Workspace.CurrentCamera
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if camera and hum then camera.CameraSubject = hum end
    state.spectate = false
    spectateIndex = 0
end
local function nextSpectate()
    local list = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local hum = player.Character:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then table.insert(list, hum) end
        end
    end
    if #list == 0 then restoreCamera(); return "No live players" end
    spectateIndex = (spectateIndex % #list) + 1
    local camera = Workspace.CurrentCamera
    if camera then camera.CameraSubject = list[spectateIndex] end
    state.spectate = true
    return "Spectating "..list[spectateIndex].Parent.Name
end
local function diagnostics()
    local counted = {player = 0, objective = 0, fragment = 0,
        book = 0, lever = 0, key = 0, exit = 0, entity = 0}
    local examples = {}
    for inst, kind in pairs(indexed) do
        if not insidePlayerCharacter(inst) then
            counted[kind] = counted[kind] + 1
            if #examples < 12 then
                table.insert(examples, kind.." = "..inst:GetFullName())
            end
        end
    end
    print("[Zinc Mayhem] PlaceId="..tostring(game.PlaceId)
        .." GameId="..tostring(game.GameId).." Team="..tostring(LocalPlayer.Team))
    print("[Zinc Mayhem] Local role="..roleOf(LocalPlayer)
        .." objects="..counted.objective.." fragments="..counted.fragment
        .." books="..counted.book.." levers="..counted.lever
        .." keys="..counted.key.." exits="..counted.exit.." world entities="..counted.entity)
    for _, example in ipairs(examples) do print("[Zinc Mayhem] "..example) end
    return "Diagnostics printed to console (F9)"
end
local function pickupDiagnostics()
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local origin = root and root.Position or Vector3.new()
    local matches = {}
    local prompts = 0
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and not insidePlayerCharacter(obj) then
            prompts = prompts + 1
            local parent = obj.Parent
            local part = parent and (parent:IsA("BasePart") and parent
                or parent:FindFirstChildWhichIsA("BasePart"))
            local pos = part and part.Position or origin
            table.insert(matches, {
                prompt = obj, distance = (pos-origin).Magnitude,
            })
        end
    end
    table.sort(matches, function(a,b) return a.distance < b.distance end)
    print("[Zinc Mayhem] Pickup diagnostics: "..prompts.." prompts, nearest 40:")
    for i = 1, math.min(#matches, 40) do
        local item = matches[i]
        local obj = item.prompt
        local parent = obj.Parent
        local grand = parent and parent.Parent
        print(("[Zinc Mayhem] #%d @%.0f studs | %s | Object=%q Action=%q | Parent=%s | Grand=%s | Category=%s")
            :format(i, item.distance, obj:GetFullName(), obj.ObjectText,
                obj.ActionText, parent and parent.Name or "(none)",
                grand and grand.Name or "(none)", tostring(classify(obj))))
    end
    return "Pickup diagnostics in console (F9): "..prompts.." prompts"
end

local window = UI:CreateWindow({
    Title = "ZINC HUB  /  DOORS: MAYHEM",
    Subtitle = IS_OVERHAUL and "OVERHAUL TEST 0.10.7 | "..selectedStyle
        or "MAYHEM ADAPTER 0.10.7 | "..selectedStyle,
    Theme = state.uiTheme,
    ToggleKey = selectedStyle == "Obsidian"
        and Enum.KeyCode.RightShift or Enum.KeyCode.RightControl,
})
local nativeDestroy = window.Destroy
local unload
unload = function()
    if closed then return end
    closed = true
    for _, connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
    table.clear(connections)
    setFov(false)
    setFullbright(false)
    restoreCamera()
    if hitboxController then hitboxController:Unload() end
    if loopTpController then loopTpController:Unload() end
    if fragmentGameController then fragmentGameController:Unload() end
    for instance in pairs(markers) do removeMarker(instance) end
    table.clear(markers)
    table.clear(indexed)
    if env.ZincMayhem and env.ZincMayhem.Unload == unload then env.ZincMayhem = nil end
    pcall(nativeDestroy, window)
end
window.Destroy = function() unload() end
env.ZincMayhem = {Unload = unload, Version = "0.10.7",
    PlaceId = game.PlaceId, Overhaul = IS_OVERHAUL, UIStyle = selectedStyle}
-- End is available even when the window is hidden. Never intercept typing.
local UserInputService = game:GetService("UserInputService")
track(UserInputService.InputBegan, function(input, processed)
    if not processed and not UserInputService:GetFocusedTextBox()
        and input.KeyCode == Enum.KeyCode.End then unload() end
end)
window:SetStatus((IS_OVERHAUL and "OVERHAUL TESTING" or "DOORS: MAYHEM").." | ready")

local home = window:CreateTab("Home")
local info = home:CreateSection("Session")
roleLabel = info:AddLabel("Role: detecting")
countLabel = info:AddLabel("ESP objects: scanning")
info:AddLabel(IS_OVERHAUL and "Build: OVERHAUL TESTING (beta)" or "Build: MAYHEM classic")
info:AddLabel("Rounds and objectives; no linear Auto Floor.")
info:AddLabel("Emergency stop: End unloads automation and restores visuals.")
info:AddButton({Name = "Copy diagnostics to console", ButtonText = "Inspect", Callback = function()
    window:SetStatus(diagnostics())
end})
info:AddButton({Name = "Scan pickup names to console", ButtonText = "Scan", Callback = function()
    window:SetStatus(pickupDiagnostics())
end})
info:AddButton({Name = "Unload Zinc Hub", ButtonText = "Unload", Callback = unload})

local exploitsTab = window:CreateTab("Exploits")
local teleportSection=exploitsTab:CreateSection("Teleport")
teleportSection:AddButton({Name="Inspect role detection (F9)",ButtonText="Inspect",
    Callback=function()
        print("[Zinc Mayhem role] detected="..roleOf(LocalPlayer)
            .." team="..tostring(LocalPlayer.Team and LocalPlayer.Team.Name))
        for _,obj in ipairs({LocalPlayer,LocalPlayer.Character or LocalPlayer}) do
            print("[Zinc Mayhem role] object="..obj.Name)
            for _,key in ipairs({"Role","CurrentRole","Team","Faction","CurrentEntity",
                "ActiveEntity","EntityType","CurrentMonster","CharacterRole","Monster",
                "Entity","Survivor"}) do
                local child=obj:FindFirstChild(key)
                local value=child and child:IsA("StringValue") and child.Value or nil
                print("[Zinc Mayhem role] "..key.." attribute="..tostring(obj:GetAttribute(key))
                    .." value="..tostring(value))
            end
        end
        window:SetStatus("Role detection details printed to F9")
    end})
teleportSection:AddToggle({Name="Auto Loop Tp",Risky=true,
    Description="This is bannable,dont abuse this too much",
    Flag="mayhem_loop_tp",Default=state.loopTp,Callback=function(value)
        state.loopTp=value
        if loopTpController then loopTpController:SetEnabled(value) end
    end})
local loopTpStatus=teleportSection:AddLabel(loopTpController and loopTpController:Status()
    or "Auto Loop Tp module unavailable")
local exploits = exploitsTab:CreateSection("Bigger Hitbox")
exploits:AddLabel("Known opponents only. Server hit validation may ignore client size.")
local hitboxStatus=exploits:AddLabel(hitboxController and hitboxController:Status()
    or "Hitbox module unavailable")
exploits:AddToggle({Name="Bigger Hitbox",Flag="mayhem_bigger_hitbox",
    Default=state.biggerHitbox,Callback=function(value)
        state.biggerHitbox=value
        if hitboxController then hitboxController:SetEnabled(value) end
    end})
exploits:AddSlider({Name="Hitbox size (studs)",Flag="mayhem_hitbox_size",
    Min=2,Max=20,Increment=1,Default=state.hitboxSize,Callback=function(value)
        state.hitboxSize=value
        if hitboxController then hitboxController:SetSize(value) end
    end})
local esp = window:CreateTab("ESP")
local playersSection = esp:CreateSection("Teams")
playersSection:AddToggle({Name = "Player highlights", Flag = "mayhem_players",
    Default = state.playerESP, Callback = function(v) state.playerESP = v end})
playersSection:AddToggle({Name = "Opponents only (unknown roles: all)", Flag = "mayhem_enemy",
    Default = state.enemyOnly, Callback = function(v) state.enemyOnly = v end})
playersSection:AddDropdown({Name = "Player ESP color", Flag = "mayhem_player_color",
    Options = {"Green", "Blue", "Cyan", "Yellow", "Red"},
    Default = state.playerColor, Callback = function(color)
        if PLAYER_PALETTE[color] then
            state.playerColor = color
            COLORS.player = PLAYER_PALETTE[color]
        end
    end})
playersSection:AddLabel("Enemy: green; friend: blue; unknown: cyan.")
playersSection:AddButton({Name="Inspect player ESP filter (F9)",
    ButtonText="Inspect", Callback=function()
        local total,shown=0,0
        print("[Zinc Mayhem] Local role: "..roleOf(LocalPlayer))
        for _,other in ipairs(Players:GetPlayers()) do
            if other~=LocalPlayer then
                total=total+1
                local show, relation=playerESPRelation(LocalPlayer,other,state.enemyOnly)
                local root, rigType=playerESPPart(other.Character)
                if show and root then shown=shown+1 end
                print("[Zinc Mayhem] Player "..other.Name
                    .." role="..roleOf(other)
                    .." team="..(other.Team and other.Team.Name or "none")
                    .." relation="..relation
                    .." rig="..tostring(rigType)
                    .." visible="..tostring(show and root~=nil))
            end
        end
        window:SetStatus("Player ESP: "..shown.."/"..total
            .." candidates; diagnostics in F9")
    end})
local mapSection = esp:CreateSection("Map objectives")
mapSection:AddToggle({Name = "Objectives (yellow)", Flag = "mayhem_objectives",
    Default = state.objectiveESP, Callback = function(v) state.objectiveESP = v end})
mapSection:AddToggle({Name = "Glitch Fragment ESP (pink + distance)",
    Flag = "mayhem_fragments", Default = state.fragmentESP,
    Callback = function(v) state.fragmentESP = v end})
mapSection:AddToggle({Name = "Glitch Book ESP (Library, blue)",
    Flag = "mayhem_books", Default = state.bookESP,
    Callback = function(v) state.bookESP = v end})
mapSection:AddToggle({Name = "Lever ESP (Cellar, gold)",
    Flag = "mayhem_levers", Default = state.leverESP,
    Callback = function(v) state.leverESP = v end})
mapSection:AddToggle({Name = "Key ESP (yellow)",
    Flag = "mayhem_keys", Default = state.keyESP,
    Callback = function(v) state.keyESP = v end})
local fragmentSection = esp:CreateSection("Glitch Fragment detection")
local customFragmentNames = (type(transfer) == "table" and transfer.fragmentNames) or ""
local customBookNames = (type(transfer) == "table" and transfer.bookNames) or ""
local customLeverNames = (type(transfer) == "table" and transfer.leverNames) or ""
local customKeyNames = (type(transfer) == "table" and transfer.keyNames) or ""
if type(transfer) == "table" then
    for source, target in pairs({
        aliases = fragmentAliases, bookAliases = bookAliases, leverAliases = leverAliases,
        keyAliases = keyAliases,
    }) do
        if type(transfer[source]) == "table" then
            for name in pairs(transfer[source]) do target[name] = true end
        end
    end
end
fragmentSection:AddTextbox({Name = "Extra fragment aliases", Flag = "mayhem_fragment_names",
    Default = customFragmentNames, Placeholder = "e.g. CorruptedShard, RiftPiece",
    Callback = function(value) customFragmentNames = tostring(value or "") end})
fragmentSection:AddButton({Name = "Apply aliases and rescan", ButtonText = "Rescan",
    Callback = function()
        table.clear(fragmentAliases)
        local count = 0
        for term in customFragmentNames:gmatch("[^,]+") do
            local alias = norm(term)
            if #alias >= 5 and alias ~= "glitch" and alias ~= "fragment"
                and count < 16 then
                fragmentAliases[alias] = true
                count = count + 1
            end
        end
        for instance, kind in pairs(indexed) do
            if kind == "fragment" then indexed[instance] = nil end
        end
        local found = 0
        for _, instance in ipairs(Workspace:GetDescendants()) do
            index(instance)
            if indexed[instance] == "fragment" then found = found + 1 end
        end
        window:SetStatus("Fragment scan complete: "..found.." candidates")
    end})
local fragmentGameSection = esp:CreateSection("Hotel Fragment Game (experimental)")
fragmentGameSection:AddLabel("Auto-interact in reach; solve only explicitly marked GUI answers.")
fragmentGameSection:AddLabel("Does not guess unknown puzzle sequences or use game remotes.")
local fragmentGameStatus=fragmentGameSection:AddLabel(
    fragmentGameController and fragmentGameController:Status() or "Module unavailable")
fragmentGameSection:AddToggle({
    Name="Auto Glitch Fragment Game (beta)", Flag="mayhem_fragment_game",
    Default=state.fragmentGame,
    Callback=function(enabled)
        state.fragmentGame=enabled
        if fragmentGameController then
            fragmentGameController:SetEnabled(enabled)
            window:SetStatus(fragmentGameController:Status())
        else window:SetStatus("Fragment game controller unavailable") end
    end})
fragmentGameSection:AddTextbox({
    Name="Puzzle GUI name (optional alias)", Flag="mayhem_fragment_gui",
    Default=state.fragmentGuiAlias,
    Placeholder="e.g. GlitchFragmentGUI",
    Callback=function(value)
        state.fragmentGuiAlias=tostring(value or "")
        if fragmentGameController then
            fragmentGameController.guiAlias=state.fragmentGuiAlias
        end
    end})
fragmentGameSection:AddButton({
    Name="Inspect visible fragment puzzle (F9)", ButtonText="Inspect",
    Callback=function()
        if not fragmentGameController then return end
        for _,line in ipairs(fragmentGameController:Inspect()) do print(line) end
        window:SetStatus("Fragment puzzle inspection printed to F9")
    end})
fragmentGameSection:AddLabel("If status says no explicit answer, send F9 output for mapping.")

local puzzleSection = esp:CreateSection("Library / Cellar detection")
puzzleSection:AddTextbox({Name = "Additional book names (comma-separated)",
    Flag = "mayhem_book_names", Default = customBookNames,
    Placeholder = "e.g. CorruptedTome, LibraryCollectible",
    Callback = function(value) customBookNames = tostring(value or "") end})
puzzleSection:AddTextbox({Name = "Additional lever names (comma-separated)",
    Flag = "mayhem_lever_names", Default = customLeverNames,
    Placeholder = "e.g. CellarSwitch, LeverInteract",
    Callback = function(value) customLeverNames = tostring(value or "") end})
puzzleSection:AddButton({Name = "Apply aliases and rescan objectives", ButtonText = "Rescan",
    Callback = function()
        local function rebuild(target, value)
            table.clear(target)
            local count = 0
            for term in value:gmatch("[^,]+") do
                local alias = norm(term)
                if #alias >= 5 and alias ~= "handle" and alias ~= "model"
                    and alias ~= "player" and alias ~= "door"
                    and alias ~= "object" and count < 16 then
                    target[alias] = true
                    count = count + 1
                end
            end
        end
        rebuild(bookAliases, customBookNames)
        rebuild(leverAliases, customLeverNames)
        for instance, kind in pairs(indexed) do
            if kind == "book" or kind == "lever" then indexed[instance] = nil end
        end
        local seen = {book = 0, lever = 0}
        for _, instance in ipairs(Workspace:GetDescendants()) do
            index(instance)
            local kind = indexed[instance]
            if seen[kind] then seen[kind] = seen[kind] + 1 end
        end
        window:SetStatus("Puzzle scan: "..seen.book.." books / "..seen.lever.." levers")
    end})
local keySection = esp:CreateSection("Key detection")
keySection:AddTextbox({Name = "Additional key names (comma-separated)",
    Flag = "mayhem_key_names", Default = customKeyNames,
    Placeholder = "e.g. CorruptedKey, SecretDoorKey",
    Callback = function(value) customKeyNames = tostring(value or "") end})
keySection:AddButton({Name = "Apply key aliases and rescan", ButtonText = "Rescan",
    Callback = function()
        table.clear(keyAliases)
        local count = 0
        for term in customKeyNames:gmatch("[^,]+") do
            local alias = norm(term)
            if #alias >= 5 and alias ~= "keyboard"
                and alias ~= "keybind" and alias ~= "keyhole"
                and alias ~= "door" and count < 16 then
                keyAliases[alias] = true
                count = count + 1
            end
        end
        for instance, kind in pairs(indexed) do
            if kind == "key" then indexed[instance] = nil end
        end
        for _, instance in ipairs(Workspace:GetDescendants()) do index(instance) end
        local total = 0
        for _, kind in pairs(indexed) do
            if kind == "key" then total = total + 1 end
        end
        window:SetStatus("Key scan: "..total.." candidates")
    end})

mapSection:AddToggle({Name = "Exits (green)", Flag = "mayhem_exits",
    Default = state.exitESP, Callback = function(v) state.exitESP = v end})
mapSection:AddToggle({Name = "World entities (orange)", Flag = "mayhem_entities",
    Default = state.entityESP, Callback = function(v) state.entityESP = v end})
mapSection:AddLabel("Markers rely on streamed object names; map variants can differ.")

local visuals = window:CreateTab("Visual")
local cameraSection = visuals:CreateSection("Camera")
cameraSection:AddToggle({Name = "Custom FOV", Flag = "mayhem_fov_toggle",
    Default = state.fovOn, Callback = setFov})
cameraSection:AddSlider({Name = "Field of view", Flag = "mayhem_fov",
    Min = 50, Max = 120, Increment = 1, Default = state.fov,
    Callback = function(v) state.fov = v end})
cameraSection:AddToggle({Name = "Fullbright", Flag = "mayhem_fullbright",
    Default = state.bright, Callback = setFullbright})
local spectateSection = visuals:CreateSection("Spectator")
spectateSection:AddButton({Name = "Next live player", ButtonText = "Next", Callback = function()
    window:SetStatus(nextSpectate())
end})
spectateSection:AddButton({Name = "Back to my character", ButtonText = "Stop", Callback = function()
    restoreCamera(); window:SetStatus("Spectate disabled")
end})
local styleSection = visuals:CreateSection("Interface")
local switchingStyle = false
styleSection:AddDropdown({Name = "UI library", Flag = "mayhem_ui_library",
    Options = {"Zinc", "Obsidian"}, Default = selectedStyle,
    Callback = function(chosen)
        if closed or switchingStyle then return end
        if chosen == selectedStyle then return end
        if chosen ~= "Obsidian" and chosen ~= "Zinc" then return end
        switchingStyle = true
        task.defer(function()
            local ok, source = pcall(function() return game:HttpGet(selfURL
                .. "?style=" .. game:GetService("HttpService"):GenerateGUID(false)) end)
            if closed then return end
            if not ok or type(source) ~= "string" then
                switchingStyle = false
                window:SetStatus("Style switch failed: source download error")
                return
            end
            local chunk, err = loadstring(source, "@ZincMayhem/StyleSwitch")
            if not chunk then
                switchingStyle = false
                window:SetStatus("Style switch error: "..tostring(err)); return
            end
            local snapshot = {}
            for key, value in pairs(state) do snapshot[key] = value end
            local aliases = {}
            for name in pairs(fragmentAliases) do aliases[name] = true end
            local books, levers, keys = {}, {}, {}
            for name in pairs(bookAliases) do books[name] = true end
            for name in pairs(leverAliases) do levers[name] = true end
            for name in pairs(keyAliases) do keys[name] = true end
            local saved = {state = snapshot, aliases = aliases,
                bookAliases = books, leverAliases = levers, keyAliases = keys,
                fragmentNames = customFragmentNames, keyNames = customKeyNames,
                bookNames = customBookNames, leverNames = customLeverNames}
            env.ZincMayhemTransferState = saved
            env.ZincMayhemUIStyle = chosen
            local success, result = pcall(chunk)
            if not success then
                warn("[Zinc Mayhem] UI switch failure: "..tostring(result))
                env.ZincMayhemTransferState = saved
                env.ZincMayhemUIStyle = selectedStyle
                local restored, restoreError = pcall(chunk)
                if not restored then
                    warn("[Zinc Mayhem] UI restore failed: "..tostring(restoreError))
                end
            end
        end)
    end})
if selectedStyle == "Zinc" then
    styleSection:AddDropdown({Name = "Zinc window theme", Flag = "mayhem_theme",
        Options = {"XP", "Dark", "Midnight"}, Default = state.uiTheme,
        Callback = function(theme)
            state.uiTheme = theme
            window:SetTheme(theme)
        end})
end

if state.bright then setFullbright(true) end
if state.fovOn then setFov(true) end
local clock, scanClock, scanBusy = 0, 0, false
local controllerFaults = {}
local function stepController(name, controller, dt)
    if not controller or controllerFaults[name] then return end
    local ok, err = pcall(controller.Step, controller, dt)
    if not ok then
        controllerFaults[name] = tostring(err)
        pcall(controller.Unload, controller)
        warn("[Zinc Mayhem] "..name.." stopped: "..tostring(err))
        window:SetStatus(name.." stopped after an error; see F9. Reload to retry.")
    end
end
env.ZincMayhem.Errors = controllerFaults
track(RunService.Heartbeat, function(dt)
    if closed then return end
    stepController("Bigger Hitbox", hitboxController, dt)
    stepController("Auto Loop Tp", loopTpController, dt)
    stepController("Fragment game", fragmentGameController, dt)
    clock = clock + math.min(dt, 1)
    scanClock = scanClock + math.min(dt, 1)
    if scanClock >= 12 and not scanBusy and (state.fragmentESP or state.bookESP
        or state.leverESP or state.keyESP or state.objectiveESP
        or state.exitESP or state.entityESP) then
        scanClock = 0
        scanBusy = true
        task.spawn(function()
            local ok, err = pcall(function()
                if closed then return end
                local all = Workspace:GetDescendants()
                for i, instance in ipairs(all) do
                    if closed then return end
                    index(instance)
                    if i % 350 == 0 then task.wait() end
                end
            end)
            scanBusy = false
            if not ok then warn("[Zinc Mayhem] rescan failed: "..tostring(err)) end
        end)
    end
    if clock < 0.5 then return end
    clock = 0
    applyVisuals()
    if hitboxController then hitboxStatus:Set(hitboxController:Status()) end
    if loopTpController then loopTpStatus:Set(loopTpController:Status()) end
    if fragmentGameController then
        fragmentGameStatus:Set(fragmentGameController:Status())
    end
    local playersCount, objectiveCount, fragmentCount, bookCount,
        leverCount, keyCount, exitCount, entityCount = updateESP()
    local team = LocalPlayer.Team and LocalPlayer.Team.Name or "unassigned"
    roleLabel:Set("Role: "..roleOf(LocalPlayer).." | Team: "..team)
    countLabel:Set("Seen: "..playersCount.." players / "..objectiveCount
        .." objectives / "..fragmentCount.." fragments / "
        ..bookCount.." books / "..leverCount.." levers / "
        ..keyCount.." keys / "..exitCount.." exits / "..entityCount.." entities")
end)

return env.ZincMayhem
