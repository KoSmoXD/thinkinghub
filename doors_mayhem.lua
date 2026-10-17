-- Zinc Hub | DOORS: MAYHEM (client game adapter)
-- Supports the public MAYHEM place and DM: OVERHAUL TESTING.
-- Standalone ZincUI mode. No remotes, teleports, or arbitrary game hooks.
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

local UI
if selectedStyle == "Obsidian" then
    UI = fetchZinc(
        "https://raw.githubusercontent.com/KoSmoXD/thinkinghub/feat/doors-mayhem-support/lib/MayhemObsidian.lua")
    assert(UI, "Mayhem: Obsidian bridge could not be loaded")
else
    UI = fetchZinc("https://raw.githubusercontent.com/KoSmoXD/ZincUI/main/ZincUI.lua")
        or fetchZinc("https://raw.githubusercontent.com/KoSmoXD/thinkinghub/main/lib/ZincUI.lua")
    assert(UI, "Zinc Mayhem: failed to load ZincUI")
end

local state = {
    playerESP = false, enemyOnly = true, objectiveESP = false,
    fragmentESP = false, exitESP = false, entityESP = false,
    bright = false, fovOn = false,
    fov = 90, spectate = false,
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
    fragment = Color3.fromRGB(80, 255, 255),
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
local LIMITS = {player = 10, objective = 12, fragment = 16, exit = 4, entity = 4}

local function track(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end
local function norm(name)
    return tostring(name or ""):lower():gsub("[^%w]", "")
end
local function roleOf(player)
    local values = {}
    if player.Team then table.insert(values, player.Team.Name) end
    for _, key in ipairs({"Role", "Team", "CurrentRole", "SelectedEntity"}) do
        local value = player:GetAttribute(key)
        if type(value) == "string" then table.insert(values, value) end
    end
    local role = norm(table.concat(values, " "))
    if role:find("survivor", 1, true) or role:find("human", 1, true) then return "Survivor" end
    if role:find("entity", 1, true) or role:find("monster", 1, true) or role:find("killer", 1, true) then
        return "Entity"
    end
    for _, name in ipairs({"Figure", "Seek", "Rush", "Eyes", "Halt", "Bramble"}) do
        if role:find(norm(name), 1, true) then return "Entity" end
    end
    return "Unknown"
end
local fragmentAliases = {}
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
        or name == "fuses" or name == "book" or name == "codebook"
        or name == "paper" or name == "lever" or name == "timelever"
        or name == "objective" or name == "objectiveitem"
        or name == "key" or name == "hotelkey" or name == "button"
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
        -- Prefer the physical fragment model over a generic Handle.
        local model = target:FindFirstAncestorOfClass("Model")
        if model and isGlitchFragment(model) then target = model end
    end
    indexed[target] = kind
end
for _, instance in ipairs(Workspace:GetDescendants()) do index(instance) end
track(Workspace.DescendantAdded, index)
track(Workspace.DescendantRemoving, function(instance)
    indexed[instance] = nil
    -- Prompt-derived entries disappear once their pickup prompt is removed.
    if instance:IsA("ProximityPrompt") and isGlitchFragment(instance) then
        local part = instance.Parent
        if part and indexed[part] == "fragment" then indexed[part] = nil end
    end
end)

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

local markerFolder = Instance.new("Folder")
markerFolder.Name = "ZincMayhemMarkers"
-- Parent to Workspace, not CurrentCamera: camera replacements destroy old children.
markerFolder.Parent = Workspace
local labelsFolder = Instance.new("Folder")
labelsFolder.Name = "ZincMayhemLabels"
labelsFolder.Parent = LocalPlayer:WaitForChild("PlayerGui")

local function showMarker(instance, details)
    local record = markers[instance]
    if not record then
        local highlight = Instance.new("Highlight")
        highlight.Name = "ZincMayhem"
        highlight.FillTransparency = 0.75
        highlight.OutlineTransparency = 0
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Adornee = instance
        highlight.Parent = markerFolder
        record = {highlight = highlight}
        markers[instance] = record
    end
    record.highlight.FillColor = details.color
    record.highlight.OutlineColor = details.color
    record.highlight.Enabled = true

    if details.kind == "fragment" then
        local part = instance:IsA("BasePart") and instance
            or (instance:IsA("Model") and (instance.PrimaryPart
                or instance:FindFirstChildWhichIsA("BasePart", true)))
        if part and not record.billboard then
            local billboard = Instance.new("BillboardGui")
            billboard.Name = "GlitchFragmentESP"
            billboard.AlwaysOnTop = true
            billboard.Size = UDim2.fromOffset(165, 25)
            billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
            billboard.Adornee = part
            billboard.Parent = labelsFolder
            local text = Instance.new("TextLabel")
            text.BackgroundTransparency = 1
            text.Size = UDim2.fromScale(1, 1)
            text.Font = Enum.Font.Code
            text.TextSize = 13
            text.TextStrokeTransparency = 0.2
            text.TextColor3 = COLORS.fragment
            text.Parent = billboard
            record.billboard, record.text = billboard, text
        end
        if record.text then
            record.text.Text = "GLITCH FRAGMENT  ["..math.floor(details.distance).. " studs]"
        end
    elseif record.billboard then
        record.billboard:Destroy()
        record.billboard, record.text = nil, nil
    end
end
local function updateESP()
    local camera = Workspace.CurrentCamera
    local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local origin = (myRoot and myRoot.Position) or (camera and camera.CFrame.Position) or Vector3.new()
    local candidates = {player = {}, objective = {}, fragment = {}, exit = {}, entity = {}}
    local localRole = roleOf(LocalPlayer)
    if state.playerESP then
        for _, other in ipairs(Players:GetPlayers()) do
            if other ~= LocalPlayer and other.Character
                and other.Character ~= LocalPlayer.Character then
                local humanoid = other.Character:FindFirstChildOfClass("Humanoid")
                local root = other.Character:FindFirstChild("HumanoidRootPart")
                local targetRole = roleOf(other)
                local known = localRole ~= "Unknown" and targetRole ~= "Unknown"
                local enemy = known and targetRole ~= localRole
                if humanoid and humanoid.Health > 0 and root
                    and (not state.enemyOnly or not known or enemy) then
                    table.insert(candidates.player, {
                        instance = other.Character, distance = (origin - root.Position).Magnitude,
                        color = (not known) and COLORS.neutral
                            or (enemy and COLORS.player or COLORS.friend),
                    })
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
    for _, kind in ipairs({"player", "objective", "fragment", "exit", "entity"}) do
        keepNearest(candidates[kind], desired, kind)
    end
    for instance, marker in pairs(markers) do
        if not desired[instance] then
            marker.highlight:Destroy()
            if marker.billboard then marker.billboard:Destroy() end
            markers[instance] = nil
        end
    end
    for instance, details in pairs(desired) do showMarker(instance, details) end
    return #candidates.player, #candidates.objective, #candidates.fragment,
        #candidates.exit, #candidates.entity
end

local function applyVisuals()
    local cam = Workspace.CurrentCamera
    if state.fovOn and cam then
        if oldCamera ~= cam then
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
        originalLighting = {
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
        oldCamera = Workspace.CurrentCamera
        oldFov = oldCamera and oldCamera.FieldOfView or nil
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
    local counted = {player = 0, objective = 0, fragment = 0, exit = 0, entity = 0}
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
        .." exits="..counted.exit.." world entities="..counted.entity)
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
        print(("[Zinc Mayhem] #%d @%.0f studs | %s | Object=%q Action=%q | Parent=%s | Grand=%s | Fragment=%s")
            :format(i, item.distance, obj:GetFullName(), obj.ObjectText,
                obj.ActionText, parent and parent.Name or "(none)",
                grand and grand.Name or "(none)", tostring(isGlitchFragment(obj))))
    end
    return "Pickup diagnostics in console (F9): "..prompts.." prompts"
end

local window = UI:CreateWindow({
    Title = "ZINC HUB  /  DOORS: MAYHEM",
    Subtitle = IS_OVERHAUL and "OVERHAUL TEST 0.3 | "..selectedStyle
        or "MAYHEM ADAPTER 0.3 | "..selectedStyle,
    Theme = state.uiTheme,
    ToggleKey = Enum.KeyCode.RightControl,
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
    markerFolder:Destroy()
    labelsFolder:Destroy()
    table.clear(markers)
    table.clear(indexed)
    if env.ZincMayhem and env.ZincMayhem.Unload == unload then env.ZincMayhem = nil end
    pcall(nativeDestroy, window)
end
window.Destroy = function() unload() end
env.ZincMayhem = {Unload = unload, Version = "0.3.0",
    PlaceId = game.PlaceId, Overhaul = IS_OVERHAUL, UIStyle = selectedStyle}
window:SetStatus((IS_OVERHAUL and "OVERHAUL TESTING" or "DOORS: MAYHEM").." | ready")

local home = window:CreateTab("Home")
local info = home:CreateSection("Session")
roleLabel = info:AddLabel("Role: detecting")
countLabel = info:AddLabel("ESP objects: scanning")
info:AddLabel(IS_OVERHAUL and "Build: OVERHAUL TESTING (beta)" or "Build: MAYHEM classic")
info:AddLabel("Rounds and objectives; no linear Auto Floor.")
info:AddButton({Name = "Copy diagnostics to console", ButtonText = "Inspect", Callback = function()
    window:SetStatus(diagnostics())
end})
info:AddButton({Name = "Scan pickup names to console", ButtonText = "Scan", Callback = function()
    window:SetStatus(pickupDiagnostics())
end})
info:AddButton({Name = "Unload Zinc Hub", ButtonText = "Unload", Callback = unload})

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
playersSection:AddLabel("Same-team players: blue. Unknown roles: cyan.")
local mapSection = esp:CreateSection("Map objectives")
mapSection:AddToggle({Name = "Objectives (yellow)", Flag = "mayhem_objectives",
    Default = state.objectiveESP, Callback = function(v) state.objectiveESP = v end})
mapSection:AddToggle({Name = "Glitch Fragment ESP (cyan + distance)",
    Flag = "mayhem_fragments", Default = state.fragmentESP,
    Callback = function(v) state.fragmentESP = v end})
local fragmentSection = esp:CreateSection("Glitch Fragment detection")
local customFragmentNames = (type(transfer) == "table" and transfer.fragmentNames) or ""
if type(transfer) == "table" and type(transfer.aliases) == "table" then
    for name in pairs(transfer.aliases) do fragmentAliases[name] = true end
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
styleSection:AddDropdown({Name = "UI library", Flag = "mayhem_ui_library",
    Options = {"Zinc", "Obsidian"}, Default = selectedStyle,
    Callback = function(chosen)
        if chosen == selectedStyle then return end
        if chosen ~= "Obsidian" and chosen ~= "Zinc" then return end
        task.defer(function()
            local ok, source = pcall(function() return game:HttpGet(selfURL
                .. "?style=" .. game:GetService("HttpService"):GenerateGUID(false)) end)
            if not ok or type(source) ~= "string" then
                window:SetStatus("Style switch failed: source download error")
                return
            end
            local chunk, err = loadstring(source, "@ZincMayhem/StyleSwitch")
            if not chunk then window:SetStatus("Style switch error: "..tostring(err)); return end
            local snapshot = {}
            for key, value in pairs(state) do snapshot[key] = value end
            local aliases = {}
            for name in pairs(fragmentAliases) do aliases[name] = true end
            local saved = {state = snapshot, aliases = aliases,
                fragmentNames = customFragmentNames}
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
local clock, scanClock = 0, 0
track(RunService.Heartbeat, function(dt)
    if closed then return end
    clock = clock + math.min(dt, 1)
    scanClock = scanClock + math.min(dt, 1)
    if scanClock >= 12 and state.fragmentESP then
        scanClock = 0
        local found = false
        for instance, kind in pairs(indexed) do
            if kind == "fragment" and instance.Parent
                and instance:IsDescendantOf(Workspace) then found = true; break end
        end
        if not found then
            task.spawn(function()
                if closed then return end
                local all = Workspace:GetDescendants()
                for i, instance in ipairs(all) do
                    if closed then return end
                    index(instance)
                    if i % 350 == 0 then task.wait() end
                end
            end)
        end
    end
    if clock < 0.5 then return end
    clock = 0
    applyVisuals()
    local playersCount, objectiveCount, fragmentCount, exitCount, entityCount = updateESP()
    local team = LocalPlayer.Team and LocalPlayer.Team.Name or "unassigned"
    roleLabel:Set("Role: "..roleOf(LocalPlayer).." | Team: "..team)
    countLabel:Set("Seen: "..playersCount.." players / "..objectiveCount
        .." objectives / "..fragmentCount.." fragments / "
        ..exitCount.." exits / "..entityCount.." entities")
end)

return env.ZincMayhem
