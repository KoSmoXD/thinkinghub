-- Thinking Hub | ROOMS: Revisited | Mr H - Owner
-- Standalone Obsidian + MSESP hub. No tplay code or game remote guesses.
-- Runtime object names are configurable under Floor > Detection.
-- Requires a client environment providing loadstring and game:HttpGet.
local VERSION = "1.4.0"
local env = getgenv and getgenv() or _G
if env.ThinkingHub and env.ThinkingHub.Unload then env.ThinkingHub.Unload() end
local function download(url, name)
    local ok, source = pcall(function() return game:HttpGet(url) end)
    assert(ok and type(source) == "string", "Thinking Hub: cannot download " .. name)
    local fn, reason = loadstring(source, "@ThinkingHub/" .. name)
    assert(fn, reason)
    return fn()
end
local Library = download("https://raw.githubusercontent.com/deividcomsono/Obsidian/d62041eda54085a03259c789d4af2be76077379f/Library.lua", "Obsidian")
local espOK, ESP = pcall(function()
    return env.mstudio45_ESP or download("https://raw.githubusercontent.com/mstudio45/MSESP/dbde68c85af504d58dac73a537fda21ca8fa626a/source.luau", "MSESP")
end)
if not espOK then ESP = nil end
local Players, RS = game:GetService("Players"), game:GetService("RunService")
local WS, PF = game:GetService("Workspace"), game:GetService("PathfindingService")
local HTTP, SoundService = game:GetService("HttpService"), game:GetService("SoundService")
local PPS = game:GetService("ProximityPromptService")
local player = Players.LocalPlayer
local closed, revision, planning = false, 0, false
local connections, savedSpeeds, savedHolds = {}, {}, {}
local objects, prompts, clicks, espObjects = {}, {}, {}, {}
local doorObjects, visualObjects = {}, {}
local lookupClock, nextLookupAt, cachedDoor, cachedRoomKey = 0, 0, nil, nil
local visited, cooldown, notified = {}, {}, {}
local route, target, movementGoal, pathVisual, blockedConnection
local retryAt, lastProgress, progressPosition, targetSince = 0, 0, nil, 0
local danger, hidden, heldLocker, lastDanger, threatScan = false, false, nil, -math.huge, 0
local cachedContainer, containerUntil, cachedGeometricRoom, roomUntil = nil, 0, nil, 0
local character, humanoid, root
local configControls, controls, statusLabel, detectionLabel = {}, {}, nil, nil
local lastStatus, lastError, soundId = "", nil, ""
local savedFOV, savedOffsets = {}, {}
local cameraFrame, frameCamera
local renderName = "ThinkingHub_" .. HTTP:GenerateGUID(false)
local state = {
    LoopFOV=false, FOV=70, NoShake=false,
    SpeedEnabled=false, Speed=40, Instant=false, Interact=false,
    DoorESP=false, BucksESP=false, EntitiesESP=false, LockerESP=false, Notify=false,
    AutoFloor=false, Method="Pathfind", AutoLocker=false, AutoLoot=false, AutoLook=false, Smooth=true,
    PathColor=Color3.fromRGB(80, 230, 190), DoorColor=Color3.fromRGB(80, 200, 255),
    LockerColor=Color3.fromRGB(170, 130, 255), BucksColor=Color3.fromRGB(255, 215, 70), EntitiesColor=Color3.fromRGB(255, 80, 90),
    Sound="", RoomsPath="", DoorNames="DOORMODEL_REAL,Door,ExitDoor,RoomDoor,RoomExit,Exit",
    BucksNames="Bucks,Buck,Money,Cash,MoneyPile,BucksPickup,CashPickup",
    DrawerNames="Drawer,Drawers,DrawerContainer",
    EntityNames="A60,A60b,A70,A90,A90b,A200,A25,MultiMonster,MultiBounder,Paralysis,Sensation",
}
local function normalize(s) return tostring(s):lower():gsub("[^%w]", "") end
local function nameSet(text)
    local result = {}
    for name in text:gmatch("[^,]+") do result[normalize(name)] = true end
    return result
end
local names = {}
local function updateNames()
    names.Door=nameSet(state.DoorNames); names.Bucks=nameSet(state.BucksNames)
    names.Drawer=nameSet(state.DrawerNames); names.Entities=nameSet(state.EntityNames)
end
updateNames()
local function notify(text)
    if not closed then Library:Notify({Title="Thinking Hub", Description=tostring(text), Time=5}) end
end
local function status(text)
    if closed or text == lastStatus then return end
    lastStatus=text
    if statusLabel then statusLabel:SetText(text) end
end
local function connect(signal, fn)
    local c=signal:Connect(fn); connections[#connections+1]=c; return c
end
local function position(o)
    if not o then return nil end
    if o:IsA("Attachment") then return o.WorldPosition end
    if o:IsA("BasePart") then return o.Position end
    if o:IsA("Model") then
        local part=o.PrimaryPart or o:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position
    end
    return o.Parent and position(o.Parent)
end
local function isPlayerObject(o)
    local p=o
    while p and p~=WS do
        if p:IsA("Model") and Players:GetPlayerFromCharacter(p) then return true end
        p=p.Parent
    end
    return false
end
local function classify(o)
    if not (o:IsA("Model") or o:IsA("BasePart")) or isPlayerObject(o) then return nil end
    local n=normalize(o.Name)
    if names.Entities[n] or o:GetAttribute("IsEntity")==true then return "Entities" end
    if names.Bucks[n] or n:match("^bucks?%d+$") or n:match("^money%d+$") or n:match("^cash%d+$") then return "Bucks" end
    if names.Drawer[n] or n:match("^drawer%d+$") then return "Drawer" end
    if n=="locker" or n:match("^locker%d+$") then return "Locker" end
    if n=="doormodelreal" or names.Door[n] then return "Door" end
end
local function canonical(o, kind)
    local chosen=o
    local p=o.Parent
    while p and p~=WS do
        if classify(p)==kind then chosen=p end
        p=p.Parent
    end
    return chosen
end
local function interactionKind(p)
    local raw=p:IsA("ProximityPrompt") and (p.ObjectText.." "..p.ActionText.." "..p.Name) or p.Name
    local label=normalize(raw)
    local semantic
    if label:find("buck",1,true) or label:find("cash",1,true) or label:find("money",1,true)
        or raw:match("%$%s*%d") then semantic="Bucks"
    elseif label:find("drawer",1,true) then semantic="Drawer" end
    local fallback
    local o=p.Parent
    while o and o~=WS do
        if not fallback and (o:IsA("BasePart") or o:IsA("Model")) then fallback=o end
        local kind=classify(o)
        -- A cash prompt inside a drawer still describes cash, not the drawer.
        if kind and (not semantic or semantic==kind) then return kind,canonical(o,kind) end
        o=o.Parent
    end
    if semantic and fallback and not isPlayerObject(fallback) then return semantic,fallback end
end
local function roomContainer()
    if state.RoomsPath~="" then
        local current=WS
        local path=state.RoomsPath:gsub("^workspace[./]", "")
        for segment in path:gmatch("[^./]+") do current=current and current:FindFirstChild(segment) end
        return current
    end
    if cachedContainer and cachedContainer.Parent and lookupClock<containerUntil then return cachedContainer end
    containerUntil=lookupClock+2
    for _, n in ipairs({"CurrentRooms","Rooms","GeneratedRooms","ActiveRooms"}) do
        local f=WS:FindFirstChild(n, true)
        if f then cachedContainer=f; return f end
    end
end
local function roomOf(o, container)
    if not container then return nil end
    local p=o
    while p and p.Parent~=container do p=p.Parent end
    return p
end
-- Accept full room identifiers, never arbitrary digits inside asset names.
local function roomNumber(value)
    if type(value)=="number" then return value>=0 and value%1==0 and value or nil end
    if type(value)~="string" then return nil end
    local text=value:match("^%s*(.-)%s*$"):upper()
    local digits=text:match("^ROOM[%s_%-]+(%d+)$") or text:match("^A[%s_%-]*(%d+)$") or text:match("^(%d+)$")
    return digits and tonumber(digits) or nil
end
local function currentRoom(container)
    if not container then return nil end
    local value=player:GetAttribute("CurrentRoom") or (character and character:GetAttribute("CurrentRoom"))
    if value~=nil then
        local r=container:FindFirstChild(tostring(value))
        if r then return r end
        local number=roomNumber(value)
        if number then
            for _,candidate in ipairs(container:GetChildren()) do
                if roomNumber(candidate.Name)==number then return candidate end
            end
        end
    end
    if not root then return nil end
    if cachedGeometricRoom and cachedGeometricRoom.Parent==container and lookupClock<roomUntil then return cachedGeometricRoom end
    -- Rank by pivot first: bounding every streamed room each route was expensive.
    local nearby={}
    for _,r in ipairs(container:GetChildren()) do
        if r:IsA("Model") then nearby[#nearby+1]={model=r,distance=(r:GetPivot().Position-root.Position).Magnitude} end
    end
    table.sort(nearby,function(a,b) return a.distance<b.distance end)
    local best,score
    for i=1,math.min(3,#nearby) do
        local r=nearby[i].model
        local cf,size=r:GetBoundingBox()
        local p=cf:PointToObjectSpace(root.Position)
        local d=Vector3.new(math.max(0,math.abs(p.X)-size.X/2),math.max(0,math.abs(p.Y)-size.Y/2),math.max(0,math.abs(p.Z)-size.Z/2)).Magnitude
        local rank=d*1000+(cf.Position-root.Position).Magnitude
        if not score or rank<score then best,score=r,rank end
    end
    cachedGeometricRoom=best; roomUntil=lookupClock+0.75
    return best
end
local function clearRoute()
    if blockedConnection then blockedConnection:Disconnect(); blockedConnection=nil end
    if route then route.path:Destroy(); route=nil end
    if pathVisual then pathVisual:Destroy(); pathVisual=nil end
    movementGoal=nil
end
local function resetRoute()
    revision=revision+1; target=nil; clearRoute(); retryAt=0
    if humanoid and humanoid.Parent then humanoid:Move(Vector3.zero,false) end
end
local function restoreSpeed()
    for h,s in pairs(savedSpeeds) do if h.Parent then h.WalkSpeed=s end end
    savedSpeeds={}
end
local function restoreHolds()
    for p,v in pairs(savedHolds) do if p.Parent then p.HoldDuration=v end end
    savedHolds={}
end
local function instant(p)
    if state.Instant and p:IsA("ProximityPrompt") then
        if savedHolds[p]==nil then savedHolds[p]=p.HoldDuration end
        p.HoldDuration=0
    end
end
local function register(o)
    if pathVisual and (o==pathVisual or o:IsDescendantOf(pathVisual)) then return end
    if o:IsA("ProximityPrompt") then prompts[o]=true; instant(o)
    elseif o:IsA("ClickDetector") then clicks[o]=true
    elseif o:IsA("Model") or o:IsA("BasePart") or normalize(o.Name)=="roomnum" then
        objects[o]=true
        local kind=classify(o)
        visualObjects[o]=(kind=="Bucks" or kind=="Locker" or kind=="Entities") and true or nil
        doorObjects[o]=(kind=="Door" or normalize(o.Name)=="roomnum"
            or o.Name:upper():match("^ROOM[_%- ]+%d+$") or o.Name:upper():match("^A[%s_%-]*%d+$")) and true or nil
        if doorObjects[o] then nextLookupAt=0 end
    end
end
local sound=Instance.new("Sound")
sound.Name="ThinkingHubNotify"; sound.Volume=0.75; sound.Parent=SoundService
local function playSound()
    if soundId~="" then sound.SoundId="rbxassetid://"..soundId; sound:Stop(); sound:Play() end
end
local function applySound(value, preview)
    local id=tostring(value):match("^%s*(%d+)%s*$") or tostring(value):match("^rbxassetid://(%d+)$")
    if value=="" then soundId=""; sound:Stop(); return true end
    if not id or tonumber(id)==0 then notify("Enter a numeric Roblox sound ID."); return false end
    soundId=id
    if preview then playSound(); notify("Sound applied. Playback requires an accessible audio asset.") end
    return true
end
local function interactionAvailable(p)
    if not (p and p.Parent and p:IsDescendantOf(WS)) then return false end
    if p:IsA("ProximityPrompt") then
        if not p.Enabled then return false end
        local kind=interactionKind(p)
        if kind=="Drawer" and normalize(p.ActionText):find("close",1,true) then return false end
    end
    return true
end
local function interact(p)
    if not interactionAvailable(p) or (cooldown[p] or 0)>os.clock() then return false end
    local pos=position(p.Parent)
    if not pos or not root then return false end
    local distance=(root.Position-pos).Magnitude
    if distance>p.MaxActivationDistance then return false end
    if p:IsA("ProximityPrompt") then
        if type(fireproximityprompt)~="function" then status("Auto interact requires fireproximityprompt in this client."); return false end
        cooldown[p]=os.clock()+math.max(0.7,p.HoldDuration+0.3)
        local generation=revision
        task.spawn(function()
            if closed or not (state.Interact or state.AutoLoot or state.AutoFloor) then return end
            if generation~=revision and state.AutoFloor then return end
            local ok,err=pcall(fireproximityprompt,p,p.HoldDuration)
            if not ok then status("Interaction failed: "..tostring(err)) end
        end)
    else
        if type(fireclickdetector)~="function" then status("Auto interact requires fireclickdetector in this client."); return false end
        cooldown[p]=os.clock()+0.8
        local ok,err=pcall(fireclickdetector,p)
        if not ok then status("Click failed: "..tostring(err)) end
    end
    return true
end
local function interactionFor(o)
    if o:IsA("ProximityPrompt") or o:IsA("ClickDetector") then return o end
    return o:FindFirstChildWhichIsA("ProximityPrompt",true) or o:FindFirstChildWhichIsA("ClickDetector",true)
end
local function showPath(points)
    pathVisual=Instance.new("Folder"); pathVisual.Name="ThinkingHubPath"; pathVisual.Parent=WS
    local previous
    local sampled={}
    local stride=math.max(1,math.ceil(#points/64))
    for i=1,#points,stride do sampled[#sampled+1]=points[i] end
    if sampled[#sampled]~=points[#points] then sampled[#sampled+1]=points[#points] end
    for _,p in ipairs(sampled) do
        local part=Instance.new("Part")
        part.Anchored=true; part.CanCollide=false; part.CanQuery=false; part.CanTouch=false
        part.Size=Vector3.new(0.1,0.1,0.1); part.Transparency=1; part.Position=p.Position+Vector3.new(0,0.3,0)
        part.Parent=pathVisual
        local a=Instance.new("Attachment"); a.Parent=part
        if previous then
            local beam=Instance.new("Beam"); beam.Attachment0=previous; beam.Attachment1=a
            beam.FaceCamera=true; beam.Width0=0.13; beam.Width1=0.13
            beam.Color=ColorSequence.new(state.PathColor); beam.Parent=part
        end
        previous=a
    end
end
local function ground(point)
    local params=RaycastParams.new(); params.FilterType=Enum.RaycastFilterType.Exclude
    local excluded={character}; if pathVisual then excluded[#excluded+1]=pathVisual end
    params.FilterDescendantsInstances=excluded; params.RespectCanCollide=true
    local hit=WS:Raycast(point+Vector3.new(0,3,0),Vector3.new(0,-18,0),params)
    return hit and hit.Position+Vector3.new(0,2,0) or point
end
local function doorPart(o)
    if o:IsA("BasePart") then return o end
    local mesh
    for _,child in ipairs(o:GetDescendants()) do
        if child:IsA("BasePart") then
            local n=normalize(child.Name)
            if n=="door" or n=="doormesh" then return child end
            if child:IsA("MeshPart") and not mesh then mesh=child end
        end
    end
    return mesh or o.PrimaryPart or o:FindFirstChildWhichIsA("BasePart",true)
end
local function doorNumber(model)
    if model:IsA("TextLabel") or model:IsA("TextButton") then return roomNumber(model.Text) end
    if model:IsA("StringValue") or model:IsA("IntValue") or model:IsA("NumberValue") then return roomNumber(model.Value) end
    for _,key in ipairs({"DestinationRoom","NextRoom","DoorNumber","RoomNumber","Room_NUM","Number","Num"}) do
        local n=roomNumber(model:GetAttribute(key))
        if n then return n end
    end
    local n=roomNumber(model.Name)
    if n then return n end
    -- Number signs are often SurfaceGui TextLabels under the actual door.
    for _,child in ipairs(model:GetDescendants()) do
        if child:IsA("TextLabel") or child:IsA("TextButton") then
            n=roomNumber(child.Text)
            if n then return n end
        elseif child:IsA("StringValue") or child:IsA("IntValue") or child:IsA("NumberValue") then
            local key=normalize(child.Name)
            if key=="doornumber" or key=="roomnumber" or key=="nextroom" or key=="roomnum" then
                n=roomNumber(child.Value)
                if n then return n end
            end
        end
    end
end
local function realDoorFor(marker)
    local ancestor=marker
    while ancestor and ancestor~=WS do
        if normalize(ancestor.Name)=="doormodelreal" then return ancestor end
        ancestor=ancestor.Parent
    end
    -- The number sign can be a sibling of the actual door model.
    local parent=marker.Parent
    if parent and (normalize(marker.Name)=="roomnum" or marker.Name:upper():match("^ROOM[_%- ]+%d+$")) then
        for _,sibling in ipairs(parent:GetChildren()) do
            if normalize(sibling.Name)=="doormodelreal" then return sibling end
        end
    end
end
local function computeNextDoor()
    if not root then return nil end
    local container=roomContainer()
    local room=currentRoom(container)
    local current=roomNumber(player:GetAttribute("CurrentRoom"))
        or roomNumber(character and character:GetAttribute("CurrentRoom"))
        or (room and roomNumber(room.Name))
    if not current then return nil end
    local best,score,seen=nil,nil,{}
    for o in pairs(doorObjects) do
        if o.Parent and not isPlayerObject(o) then
            local kind=classify(o)
            local numbered=roomNumber(o.Name)
            local marker=normalize(o.Name)=="roomnum" or o.Name:upper():match("^ROOM[_%- ]+%d+$")~=nil
            local explicit=marker or kind=="Door" or (numbered and o:IsA("Model") and o:FindFirstChild("Door"))
            if explicit then
                local source=kind=="Door" and canonical(o,"Door") or o
                local number=doorNumber(source)
                local real=realDoorFor(source)
                if real then
                    number=number or doorNumber(real)
                    if not number and real.Parent then
                        local sign=real.Parent:FindFirstChild("Room_NUM")
                        if sign then number=doorNumber(sign) end
                    end
                end
                local model=real or source
                -- Room_NUM may be a SurfaceGui label: highlight its physical sign/door.
                while model and model~=WS and not (model:IsA("Model") or model:IsA("BasePart")) do model=model.Parent end
                if model and model~=WS and model~=room and number==current+1 then
                    local owner=roomOf(model,container)
                    local connected=not room or model:IsDescendantOf(room)
                        or (owner and roomNumber(owner.Name)==current+1)
                    if connected then
                        local part
                        if model.Parent==container and model:IsA("Model") then
                            -- A numbered room container is not itself a door.
                            local entrance=model:FindFirstChild("RoomEntrance",true) or model:FindFirstChild("Entrance",true)
                            if entrance and entrance:IsA("BasePart") then part=entrance; model=entrance end
                        else part=doorPart(model) end
                        if part and not seen[model] then
                            seen[model]=true
                            local distance=(part.Position-root.Position).Magnitude
                            if not score or distance<score then
                                best={model=model,part=part,number=number,room=room}; score=distance
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end
local function nextDoor()
    local key=tostring(player:GetAttribute("CurrentRoom"))..":"..tostring(character and character:GetAttribute("CurrentRoom"))
    if lookupClock>=nextLookupAt or key~=cachedRoomKey or (cachedDoor and not cachedDoor.model.Parent) then
        cachedDoor=computeNextDoor(); cachedRoomKey=key; nextLookupAt=lookupClock+0.3
    end
    return cachedDoor
end
local function isHidden()
    if not character then return false end
    if character:GetAttribute("Hiding")==true or character:GetAttribute("Hidden")==true
        or character:GetAttribute("InLocker")==true or player:GetAttribute("Hiding")==true then return true end
    if heldLocker and heldLocker.Parent then
        local occupant=heldLocker:FindFirstChild("HiddenPlayer",true) or heldLocker:FindFirstChild("Occupant",true)
        if occupant and occupant:IsA("ObjectValue") then return occupant.Value==player or occupant.Value==character end
    end
    return false
end
local function updateDanger()
    local active=false
    if state.AutoLocker and state.AutoFloor and root then
        if lookupClock>=threatScan then
            threatScan=lookupClock+0.2
            for o in pairs(visualObjects) do
                if o.Parent and classify(o)=="Entities" then
                    local n=normalize(o.Name)
                    -- Locker mimics and screen-only A-90 encounters are not rushers.
                    if n~="a70" and n~="a90" and n~="a90b" and n~="paralysis" and n~="sensation" then
                        local pos=position(o)
                        if pos and (pos-root.Position).Magnitude<300 then lastDanger=lookupClock; break end
                    end
                end
            end
        end
        active=lookupClock-lastDanger<2
    end
    if active~=danger then danger=active; resetRoute() end
    local nowHidden=isHidden()
    if nowHidden~=hidden then
        hidden=nowHidden; resetRoute()
        if not hidden then heldLocker=nil end
    end
end
local function lockerCandidates()
    local list,seen={},{}
    for o in pairs(visualObjects) do
        if o.Parent and classify(o)=="Locker" then
            local model=canonical(o,"Locker")
            if not seen[model] then
                seen[model]=true
                local occupant=model:FindFirstChild("HiddenPlayer",true) or model:FindFirstChild("Occupant",true)
                local occupied=model:GetAttribute("Occupied")==true or model:GetAttribute("IsEntity")==true
                    or (occupant and occupant:IsA("ObjectValue") and occupant.Value~=nil)
                local prompt=model:FindFirstChild("HidePrompt",true) or model:FindFirstChildWhichIsA("ProximityPrompt",true)
                if not occupied and prompt and interactionAvailable(prompt)
                    and (cooldown[model] or 0)<=os.clock() and (cooldown[prompt] or 0)<=os.clock() then
                    local pos=position(prompt.Parent)
                    if pos then list[#list+1]={model=model,prompt=prompt,kind="Locker",pos=pos,priority=-1} end
                end
            end
        end
    end
    table.sort(list,function(a,b) return (a.pos-root.Position).Magnitude<(b.pos-root.Position).Magnitude end)
    return list
end
local function leaveLocker()
    movementGoal=nil
    if danger then status("Auto Locker: hiding until the entity clears."); return end
    if heldLocker and heldLocker.Parent then
        for _,p in ipairs(heldLocker:GetDescendants()) do
            if p:IsA("ProximityPrompt") and p.Enabled then
                local action=normalize(p.ActionText)
                if action:find("exit",1,true) or action:find("leave",1,true) then
                    interact(p); status("Auto Locker: leaving locker..."); return
                end
            end
        end
    end
    status("Entity cleared. No exit prompt detected; leave the locker to resume.")
end
local function candidates()
    if state.AutoLocker and danger then return lockerCandidates() end
    local container=roomContainer()
    local room=currentRoom(container)
    local list,seen={},{}
    if state.AutoLoot then
        for p in pairs(prompts) do
            local kind,model=interactionKind(p)
            if (kind=="Bucks" or kind=="Drawer") and interactionAvailable(p) and (cooldown[p] or 0)<=os.clock()
                and (not room or p:IsDescendantOf(room)) then
                local pos=position(p.Parent)
                if pos and (pos-root.Position).Magnitude<100 then
                    list[#list+1]={model=model,prompt=p,kind=kind,pos=pos,priority=0}
                end
            end
        end
        for p in pairs(clicks) do
            local kind,model=interactionKind(p)
            if (kind=="Bucks" or kind=="Drawer") and interactionAvailable(p) and (cooldown[p] or 0)<=os.clock()
                and (not room or p:IsDescendantOf(room)) then
                local pos=position(p.Parent)
                if pos and (pos-root.Position).Magnitude<100 then list[#list+1]={model=model,prompt=p,kind=kind,pos=pos,priority=0} end
            end
        end
    end
    local next=nextDoor()
    if next and not visited[next.model] and (cooldown[next.model] or 0)<=os.clock() then
        local model,part=next.model,next.part
        local pos=part.Position
        local normal=Vector3.new(part.CFrame.LookVector.X,0,part.CFrame.LookVector.Z)
        if normal.Magnitude>0.01 then
            normal=normal.Unit
            local entrance=room and room:FindFirstChild("RoomEntrance",true)
            local inside=position(entrance) or root.Position
            if (inside-pos):Dot(normal)<0 then normal=-normal end
            list[#list+1]={model=model,prompt=interactionFor(model),kind="Door",pos=pos,
                number=next.number,approach=pos+normal*5,crossing=pos-normal*5,priority=1}
        end
    end
    table.sort(list,function(a,b)
        if a.priority~=b.priority then return a.priority<b.priority end
        return (a.pos-root.Position).Magnitude<(b.pos-root.Position).Magnitude
    end)
    return list
end
local function plan()
    local token=revision
    local startRoot=root
    local list=candidates()
    if #list==0 then status(danger and "Auto Locker: no available locker prompt detected." or "No numbered next door detected. Waiting for an A-### sign / destination."); retryAt=os.clock()+1; return end
    for index,item in ipairs(list) do
        if index>3 then break end
        if closed or token~=revision or not state.AutoFloor then return end
        local delta=startRoot.Position-item.pos
        local flat=Vector3.new(delta.X,0,delta.Z)
        local offset=flat.Magnitude>0.01 and flat.Unit*math.min(3, item.prompt and item.prompt.MaxActivationDistance*0.5 or 3) or Vector3.zero
        local goal=ground(item.approach or (item.pos+offset))
        if state.Method=="TP" then
            target=item; target.goal=goal; targetSince=os.clock(); target.phase="approach"; return
        end
        local path=PF:CreatePath({AgentRadius=1.5,AgentHeight=5,AgentCanJump=true,WaypointSpacing=3})
        local ok,err=pcall(function() path:ComputeAsync(startRoot.Position,goal) end)
        if closed or token~=revision or startRoot~=root then path:Destroy(); return end
        if ok and path.Status==Enum.PathStatus.Success then
            local points=path:GetWaypoints()
            if #points>0 then
                target=item; targetSince=os.clock(); target.phase="approach"
                route={path=path,points=points,index=math.min(2,#points)}
                progressPosition=root.Position; lastProgress=os.clock()
                blockedConnection=path.Blocked:Connect(function(index)
                    if route and index>=route.index then resetRoute() end
                end)
                showPath(points)
                status("Pathfind: "..item.kind.." - "..item.model.Name)
                return
            end
        end
        path:Destroy()
        if not ok then lastError=tostring(err) end
        cooldown[item.prompt or item.model]=os.clock()+3
    end
    status("No reachable route. "..(lastError or "Retrying in 2 seconds.")); retryAt=os.clock()+2
end
local function finishTarget(success)
    if target then
        if target.kind=="Locker" and not success then cooldown[target.model]=os.clock()+5 end
        if target.kind=="Door" and success then visited[target.model]=true
        else cooldown[target.prompt or target.model]=os.clock()+(success and 8 or 3) end
    end
    resetRoute()
end
local function moveController()
    if not state.AutoFloor or not root or not humanoid or humanoid.Health<=0 then return end
    if hidden then leaveLocker(); return end
    if root.Anchored or humanoid.Sit or humanoid.PlatformStand or character:GetAttribute("Hiding")==true then
        movementGoal=nil; status("Paused: character immobilized or hiding."); return
    end
    if not target then return end
    if target.kind=="Door" then
        local selected=nextDoor()
        if not selected or selected.model~=target.model then resetRoute(); return end
    end
    if not target.model or not target.model:IsDescendantOf(WS) then finishTarget(true); return end
    local now=os.clock()
    if now-targetSince>12 then status("Target timed out; selecting again."); finishTarget(false); return end
    if target.kind=="Locker" then
        if not danger then resetRoute(); return end
        if not interactionAvailable(target.prompt) then finishTarget(false); return end
        local occupant=target.model:FindFirstChild("HiddenPlayer",true) or target.model:FindFirstChild("Occupant",true)
        if target.model:GetAttribute("Occupied")==true or (occupant and occupant:IsA("ObjectValue") and occupant.Value~=nil) then
            finishTarget(false); return
        end
        if target.phase=="hiding" then
            movementGoal=nil
            if now>target.waitUntil then
                status("Locker entry not confirmed; trying another locker."); finishTarget(false)
            end
            return
        end
        if interact(target.prompt) then
            heldLocker=target.model; target.phase="hiding"
            target.waitUntil=now+math.max(2,target.prompt.HoldDuration+1)
            movementGoal=nil; status("Auto Locker: waiting for confirmed entry."); return
        end
    end
    if target.kind~="Door" and target.kind~="Locker" and target.prompt then
        if not interactionAvailable(target.prompt) then finishTarget(true); return end
        if target.phase=="collect" then
            movementGoal=nil
            if now<(target.waitUntil or 0) then return end
            if (target.attempts or 0)>=2 then
                local p=target.prompt
                finishTarget(false); cooldown[p]=now+30
                status("Loot not confirmed; skipping temporarily.")
                return
            end
        end
        if interact(target.prompt) then
            target.attempts=(target.attempts or 0)+1; target.phase="collect"
            target.waitUntil=now+math.max(1.2,target.prompt:IsA("ProximityPrompt") and target.prompt.HoldDuration+0.5 or 1.2)
            movementGoal=nil; status("Collecting "..target.kind)
            return
        end
        if target.phase=="collect" then return end
    end
    if target.kind=="Door" then
        if target.prompt then interact(target.prompt) end
        if (root.Position-target.pos).Magnitude<8 and target.phase=="approach" then
            target.phase="cross"; clearRoute(); target.goal=ground(target.crossing)
        end
        if target.phase=="cross" and (root.Position-target.goal).Magnitude<3 then finishTarget(true); return end
    end
    if state.Method=="TP" then
        if not target.lastTP or now-target.lastTP>0.35 then
            target.lastTP=now
            character:PivotTo(character:GetPivot()+(target.goal-root.Position))
        end
        status("TP: "..target.kind); return
    end
    if target.phase=="cross" then movementGoal=target.goal
    elseif route then
        local point=route.points[route.index]
        if point then
            local delta=root.Position-point.Position
            if Vector3.new(delta.X,0,delta.Z).Magnitude<2 and math.abs(delta.Y)<6 then
                route.index=route.index+1; point=route.points[route.index]
            end
        end
        if not point then
            if target.kind=="Door" then target.phase="cross"; target.goal=ground(target.crossing); movementGoal=target.goal
            else finishTarget(false); return end
        else
            if point.Action==Enum.PathWaypointAction.Jump then humanoid.Jump=true end
            movementGoal=point.Position
        end
    end
    if progressPosition and (root.Position-progressPosition).Magnitude>=1 then progressPosition=root.Position; lastProgress=now
    elseif now-lastProgress>1.5 then status("Recalculating blocked route..."); finishTarget(false) end
end
local function destroyESP(o)
    local entry=espObjects[o]
    if entry then if not entry.object.Deleted then entry.object:Destroy() end; espObjects[o]=nil end
end
local function refreshESP()
    local wanted,seen,list={},{},{}
    local selected=nextDoor()
    local count={Door=selected and 1 or 0,Bucks=0,Entities=0,Locker=0}
    if selected and state.DoorESP and ESP then
        list[#list+1]={model=selected.model,kind="Door",distance=-1,label=string.format("Next door | A-%03d",selected.number)}
    end
    for o in pairs(visualObjects) do
        if o.Parent then
            local kind=classify(o)
            if kind and kind~="Drawer" and kind~="Door" then
                local model=canonical(o,kind)
                if not seen[model] then
                    seen[model]=true; count[kind]=count[kind]+1
                    if kind=="Entities" and state.Notify and not notified[model] then
                        notified[model]=true; notify("Entity detected: "..model.Name); playSound()
                    end
                    if state[kind.."ESP"] and ESP then
                        local pos=position(model)
                        if pos then list[#list+1]={model=model,kind=kind,distance=root and (pos-root.Position).Magnitude or 0} end
                    end
                end
            end
        end
    end
    -- Cash can have an anonymous part name but a descriptive pickup prompt.
    for _,set in ipairs({prompts,clicks}) do
        for p in pairs(set) do
            local kind,model=interactionKind(p)
            if kind=="Bucks" and model and not seen[model] and interactionAvailable(p) then
                seen[model]=true; count.Bucks=count.Bucks+1
                if state.BucksESP and ESP then
                    local pos=position(model)
                    if pos then list[#list+1]={model=model,kind="Bucks",distance=root and (pos-root.Position).Magnitude or 0} end
                end
            end
        end
    end
    table.sort(list,function(a,b) return a.distance<b.distance end)
    for i=1,math.min(80,#list) do
        local item=list[i]; wanted[item.model]=true
        local entry=espObjects[item.model]
        local color=state[item.kind.."Color"]
        if not entry or entry.object.Deleted then
            local ok,obj=pcall(function() return ESP:Add({Name=item.label or (item.kind.." | "..item.model.Name),
                Model=item.model,ESPType="Text",Color=color,MaxDistance=5000,TextSize=16}) end)
            if ok then espObjects[item.model]={object=obj,kind=item.kind} end
        else
            if entry.color~=color then entry.object:SetEveryColor(color,true); entry.color=color end
            if entry.object.CurrentSettings then entry.object.CurrentSettings.Name=item.label or (item.kind.." | "..item.model.Name) end
        end
    end
    for o in pairs(espObjects) do if not wanted[o] then destroyESP(o) end end
    if detectionLabel then detectionLabel:SetText(string.format("Detected: %d doors | %d bucks | %d entities | %d lockers",count.Door,count.Bucks,count.Entities,count.Locker)) end
end
local function restoreFOV()
    for camera,value in pairs(savedFOV) do
        if camera.Parent then camera.FieldOfView=value end
    end
    savedFOV={}
end
local function restoreOffsets()
    for h,value in pairs(savedOffsets) do
        if h.Parent then h.CameraOffset=value end
    end
    savedOffsets={}; cameraFrame=nil; frameCamera=nil
end
local function cleanup()
    if closed then return end
    closed=true; state.AutoFloor=false; resetRoute(); restoreSpeed(); restoreHolds()
    RS:UnbindFromRenderStep(renderName)
    RS:UnbindFromRenderStep(renderName.."CameraBefore")
    RS:UnbindFromRenderStep(renderName.."CameraCapture")
    restoreFOV(); restoreOffsets()
    for _,c in ipairs(connections) do c:Disconnect() end
    for o in pairs(espObjects) do destroyESP(o) end
    sound:Destroy()
    if env.ThinkingHub and env.ThinkingHub.Library==Library then env.ThinkingHub=nil end
end
Library:OnUnload(cleanup)
env.ThinkingHub={Library=Library,Unload=function() cleanup(); Library:Unload() end}
local Window=Library:CreateWindow({Title="Thinking Hub | ROOMS: Revisited",Footer="Mr H | "..VERSION,
    Center=true,AutoShow=true,Resizable=true,NotifySide="Right",ShowCustomCursor=false})
local Credits=Window:AddTab("Credits","crown")
local owner=Credits:AddLeftGroupbox("Credits")
owner:AddLabel('<font color="#FFFF00">Mr H - Owner</font>',true)
owner:AddLabel("Thinking Hub\nROOMS: Revisited",true)
local libraries=Credits:AddRightGroupbox("Libraries")
libraries:AddLabel("Obsidian - deividcomsono\nMSESP - mstudio45",true)
local Home=Window:AddTab("Home","house")
local homeTabs=Home:AddLeftTabbox()
local general=homeTabs:AddTab("General")
local configs=homeTabs:AddTab("Configs")
general:AddButton({Text="Unload",Func=function() env.ThinkingHub.Unload() end})
general:AddLabel("Menu key: Right Control",true)
local info=Home:AddRightGroupbox("Status")
statusLabel=info:AddLabel("Ready. Choose your features.",true)
detectionLabel=info:AddLabel("Detecting objects...",true)
info:AddLabel("If Auto Floor cannot find a target, adjust Floor > Detection. Custom game interactions may need an adapter update.",true)
local Main=Window:AddTab("Main","user")
local playerBox=Main:AddLeftTabbox():AddTab("Player")
local Visual=Window:AddTab("Visual","eye")
local visuals=Visual:AddLeftTabbox()
local espBox=visuals:AddTab("ESP")
local notifyBox=visuals:AddTab("Notify")
local cameraBox=visuals:AddTab("Camera")
local Floor=Window:AddTab("Floor","route")
local floorTabs=Floor:AddLeftTabbox()
local auto=floorTabs:AddTab("Auto Floor")
local detection=Floor:AddRightGroupbox("Detection")
local function addToggle(box,key,text,callback)
    local c=box:AddToggle("TH_"..key,{Text=text,Default=state[key]})
    controls[key]=c; configControls[key]={control=c,kind="boolean"}
    c:OnChanged(function(v) state[key]=v; if callback then callback(v) end end)
    return c
end
local function addInput(box,key,text,callback)
    local c=box:AddInput("TH_"..key,{Text=text,Default=state[key],Finished=true,ClearTextOnFocus=false})
    controls[key]=c; configControls[key]={control=c,kind="string"}
    c:OnChanged(function(v) state[key]=v; if callback then callback(v) end end)
    return c
end
local function addColor(box,key,text)
    box:AddLabel(text):AddColorPicker("TH_"..key,{Default=state[key],Title=text})
    local c=Library.Options["TH_"..key]
    controls[key]=c; configControls[key]={control=c,kind="color"}
    c:OnChanged(function(v)
        state[key]=v
        if key=="PathColor" and pathVisual then
            for _,o in ipairs(pathVisual:GetDescendants()) do if o:IsA("Beam") then o.Color=ColorSequence.new(v) end end
        end
    end)
end
addToggle(playerBox,"SpeedEnabled","Loop speed",function(v) if not v and not state.AutoFloor then restoreSpeed() end end)
local speed=playerBox:AddSlider("TH_Speed",{Text="Speed",Default=40,Min=0,Max=1000,Rounding=0})
controls.Speed=speed; configControls.Speed={control=speed,kind="number"}
speed:OnChanged(function(v) state.Speed=v end)
addToggle(playerBox,"Instant","Instant interact",function(v)
    if v then for p in pairs(prompts) do instant(p) end else restoreHolds() end
end)
addToggle(playerBox,"Interact","Auto interact (drawers / money)")
playerBox:AddLabel("Loop speed reapplies WalkSpeed each frame. Auto interact uses nearby prompts and click detectors.",true)
for _,entry in ipairs({{"Door","Door"},{"Bucks","Bucks"},{"Entities","Entities"},{"Locker","Locker"}}) do
    addToggle(espBox,entry[1].."ESP",entry[1]=="Door" and "Next door ESP" or entry[2].." ESP")
    addColor(espBox,entry[1].."Color",entry[2].." color")
end
addToggle(cameraBox,"LoopFOV","Loop FOV",function(v) if not v then restoreFOV() end end)
local fov=cameraBox:AddSlider("TH_FOV",{Text="Field of view",Default=70,Min=1,Max=120,Rounding=0})
controls.FOV=fov; configControls.FOV={control=fov,kind="number",min=1,max=120}
fov:OnChanged(function(v) state.FOV=v end)
addToggle(cameraBox,"NoShake","No Camera Shake",function(v) if not v then restoreOffsets() end end)
cameraBox:AddLabel("Loop FOV reapplies your chosen FOV each frame. No Camera Shake removes camera offsets and late shake on the standard camera; scripted cutscenes keep their camera control.",true)
addToggle(notifyBox,"Notify","Notify entities",function() notified={} end)
notifyBox:AddLabel("Roblox sound ID (numbers or rbxassetid://ID)",true)
addInput(notifyBox,"Sound","Notify sound ID")
notifyBox:AddButton({Text="Apply Notify Sound",Func=function() applySound(state.Sound,true) end})
notifyBox:AddLabel("Notifications cover detected world entities. Screen-only encounters need a game-specific adapter.",true)
addToggle(auto,"AutoFloor","Auto Floor",function(v)
    resetRoute(); visited={}
    if not v then if not state.SpeedEnabled then restoreSpeed() end; status("Auto Floor disabled.") end
end)
local method=auto:AddDropdown("TH_Method",{Text="Method",Values={"TP","Pathfind"},Default="Pathfind",Multi=false})
controls.Method=method; configControls.Method={control=method,kind="method"}
method:OnChanged(function(v) state.Method=v; resetRoute() end)
addToggle(auto,"AutoLocker","Auto Locker (TP / Pathfind)",function()
    lastDanger=-math.huge; threatScan=0; resetRoute()
end)
addToggle(auto,"AutoLoot","Auto loot",resetRoute)
addToggle(auto,"AutoLook","Auto look")
addToggle(auto,"Smooth","Smooth camera")
addColor(auto,"PathColor","Path color")
auto:AddLabel("Auto loot checks drawers and bucks before doors. With Auto Floor off, it only collects nearby items. Auto look faces the current target.",true)
auto:AddLabel("Auto Locker prioritizes hiding over loot and doors. It uses locker prompts and confirms entry. Special events still need manual control.",true)
addInput(detection,"RoomsPath","Room folder path (blank = detect)",resetRoute)
for _,item in ipairs({{"DoorNames","Door names"},{"BucksNames","Bucks names"},{"DrawerNames","Drawer names"},{"EntityNames","Entity names"}}) do
    addInput(detection,item[1],item[2],function() updateNames(); for o in pairs(objects) do register(o) end; nextLookupAt=0; resetRoute(); notified={} end)
end
detection:AddLabel("Comma-separated instance names. Case, spaces and hyphens are ignored.",true)
detection:AddButton({Text="Rescan",Func=function()
    for _,o in ipairs(WS:GetDescendants()) do register(o) end
    refreshESP(); resetRoute(); notify("Detection refreshed.")
end})
detection:AddButton({Text="Copy interaction diagnostics",Func=function()
    local rows={"Thinking Hub "..VERSION,
        "fireproximityprompt="..type(fireproximityprompt).." fireclickdetector="..type(fireclickdetector)}
    local nearby={}
    for _,o in ipairs(WS:GetDescendants()) do
        if o:IsA("ProximityPrompt") or o:IsA("ClickDetector") or o:IsA("TouchTransmitter") then
            local pos=position(o.Parent)
            if pos and root and (pos-root.Position).Magnitude<=40 then
                nearby[#nearby+1]={object=o,distance=(pos-root.Position).Magnitude}
            end
        end
    end
    table.sort(nearby,function(a,b) return a.distance<b.distance end)
    for i=1,math.min(40,#nearby) do
        local o=nearby[i].object
        local kind=interactionKind(o)
        local details=o:IsA("ProximityPrompt") and string.format(" action=%q object=%q enabled=%s range=%s",o.ActionText,o.ObjectText,tostring(o.Enabled),tostring(o.MaxActivationDistance)) or ""
        rows[#rows+1]=string.format("%.1f studs | %s | %s | detected=%s%s",nearby[i].distance,o.ClassName,o:GetFullName(),tostring(kind),details)
    end
    if #nearby==0 then rows[#rows+1]="No standard interactions within 40 studs." end
    local report=table.concat(rows,"\n")
    print(report)
    if type(setclipboard)=="function" then setclipboard(report); notify("Diagnostics copied. Paste them into chat.")
    else notify("Diagnostics printed in the client console.") end
end})
-- Configs are data-only JSON; config names cannot escape the hub folder.
local configFolder="ThinkingHub/ROOMSRevisited/configs"
local fsReady=type(isfolder)=="function" and type(makefolder)=="function" and type(isfile)=="function"
    and type(writefile)=="function" and type(readfile)=="function" and type(listfiles)=="function" and type(delfile)=="function"
if fsReady then
    local ok=pcall(function()
        for _,p in ipairs({"ThinkingHub","ThinkingHub/ROOMSRevisited",configFolder}) do if not isfolder(p) then makefolder(p) end end
    end)
    fsReady=ok
end
local configName=configs:AddInput("TH_ConfigName",{Text="Config name",Default="",Finished=true,ClearTextOnFocus=false})
local configList=configs:AddDropdown("TH_ConfigList",{Text="Select config",Values={},AllowNull=true,Multi=false})
local function validConfigName(name)
    return type(name)=="string" and #name>0 and #name<=64 and name:match("^[%w_%- ]+$")~=nil
end
local function configPath(name)
    assert(validConfigName(name),"Use 1-64 letters, numbers, spaces, underscores or hyphens.")
    return configFolder.."/"..name..".json"
end
local function refreshConfigs()
    if not fsReady then return end
    local values={}
    for _,p in ipairs(listfiles(configFolder)) do
        local name=p:gsub("\\","/"):match("([^/]+)%.json$")
        if validConfigName(name) then values[#values+1]=name end
    end
    table.sort(values); configList:SetValues(values)
end
local function saveConfig(name,overwrite)
    local path=configPath(name)
    assert(overwrite or not isfile(path),"Config exists. Use Overwrite config.")
    assert(not overwrite or isfile(path),"Select an existing config.")
    local values={}
    for key,entry in pairs(configControls) do
        local v=state[key]
        values[key]=entry.kind=="color" and {v.R,v.G,v.B} or v
    end
    writefile(path,HTTP:JSONEncode({version=1,values=values})); refreshConfigs(); configList:SetValue(name)
end
local function loadConfig(name)
    local data=HTTP:JSONDecode(readfile(configPath(name)))
    assert(type(data)=="table" and data.version==1 and type(data.values)=="table","Unsupported config.")
    local pending={}
    for key,entry in pairs(configControls) do
        local v=data.values[key]
        if v~=nil then
            if entry.kind=="color" then
                assert(type(v)=="table" and #v==3,"Invalid color: "..key)
                for _,n in ipairs(v) do assert(type(n)=="number" and n>=0 and n<=1,"Invalid color channel") end
                v=Color3.new(v[1],v[2],v[3])
            elseif entry.kind=="method" then assert(v=="TP" or v=="Pathfind","Invalid method")
            else
                assert(type(v)==entry.kind,"Invalid setting: "..key)
                if entry.kind=="number" then assert(v>=(entry.min or 0) and v<=(entry.max or 1000),"Invalid range: "..key) end
                if entry.kind=="string" then assert(#v<=2048,"Setting too long") end
            end
            pending[key]=v
        end
    end
    -- Apply movement switches last; avoid briefly running with old options.
    controls.AutoFloor:SetValue(false); controls.SpeedEnabled:SetValue(false)
    for key,v in pairs(pending) do if key~="AutoFloor" and key~="SpeedEnabled" then controls[key]:SetValue(v) end end
    applySound(state.Sound,false)
    if pending.SpeedEnabled~=nil then controls.SpeedEnabled:SetValue(pending.SpeedEnabled) end
    if pending.AutoFloor~=nil then controls.AutoFloor:SetValue(pending.AutoFloor) end
end
local function configAction(fn)
    return function()
        if not fsReady then notify("Config storage requires filesystem support."); return end
        local ok,err=pcall(fn)
        if ok then notify("Config updated.") else notify(err) end
    end
end
configs:AddButton({Text="Create config",Func=configAction(function() saveConfig(configName.Value,false) end)})
configs:AddButton({Text="Load config",Func=configAction(function() loadConfig(configList.Value) end)})
configs:AddButton({Text="Overwrite config",Func=configAction(function() saveConfig(configList.Value,true) end)})
configs:AddButton({Text="Delete config",Func=configAction(function()
    local path=configPath(configList.Value); assert(isfile(path),"Config does not exist.")
    delfile(path); configList:SetValue(nil); refreshConfigs()
end)})
configs:AddButton({Text="Refresh configs",Func=configAction(refreshConfigs)})
if not fsReady then configs:AddLabel("Filesystem unavailable: configs cannot be saved here.",true) end
local ok,err=pcall(refreshConfigs); if not ok then notify(err) end
for _,o in ipairs(WS:GetDescendants()) do register(o) end
connect(WS.DescendantAdded,register)
connect(WS.DescendantRemoving,function(o)
    if doorObjects[o] then nextLookupAt=0 end
    doorObjects[o]=nil; visualObjects[o]=nil
    objects[o]=nil; prompts[o]=nil; clicks[o]=nil; savedHolds[o]=nil
    cooldown[o]=nil; visited[o]=nil; notified[o]=nil; destroyESP(o)
end)
connect(PPS.PromptShown,instant)
local elapsed,scanElapsed=0,0
connect(RS.Heartbeat,function(dt)
    if closed then return end
    lookupClock=lookupClock+dt
    local ok,reason=pcall(function()
        local c=player.Character
        local h=c and c:FindFirstChildOfClass("Humanoid")
        local r=c and c:FindFirstChild("HumanoidRootPart")
        if c~=character or h~=humanoid or r~=root then
            resetRoute(); restoreSpeed(); character,humanoid,root=c,h,r; visited={}; nextLookupAt=0
        end
        if h and h.Health>0 then
            if state.SpeedEnabled or state.AutoFloor then
                if savedSpeeds[h]==nil then savedSpeeds[h]=h.WalkSpeed end
                h.WalkSpeed=state.SpeedEnabled and state.Speed or 40
            end
        end
        scanElapsed=scanElapsed+dt
        if scanElapsed>=1 then
            scanElapsed=0
            if state.DoorESP or state.BucksESP or state.EntitiesESP or state.LockerESP or state.Notify or next(espObjects) then refreshESP() end
        end
        if not root or not humanoid or humanoid.Health<=0 then
            if state.AutoFloor then status("Waiting for character...") end
            return
        end
        elapsed=elapsed+dt; if elapsed<0.1 then return end; elapsed=0
        updateDanger()
        if not danger and not hidden and (state.Interact or (state.AutoLoot and not state.AutoFloor)) then
            for _,set in ipairs({prompts,clicks}) do
                for p in pairs(set) do
                    local kind=interactionKind(p)
                    if kind=="Bucks" or kind=="Drawer" then interact(p) end
                end
            end
        end
        moveController()
        if state.AutoFloor and not hidden and not target and not planning and os.clock()>=retryAt and not root.Anchored then
            planning=true
            task.spawn(function()
                local success,problem=pcall(plan)
                planning=false
                if not success and not closed then resetRoute(); retryAt=os.clock()+1; status("Path error: "..tostring(problem)) end
            end)
        end
    end)
    if not ok and not closed then
        resetRoute(); retryAt=os.clock()+1
        status("Controller error: "..tostring(reason))
        if reason~=lastError then lastError=reason; warn("[ThinkingHub] "..tostring(reason)) end
    end
end)
-- Capture the normal camera before later shake effects. Do not pin a
-- Scriptable camera, since the game may update it outside this priority range.
RS:BindToRenderStep(renderName.."CameraBefore",Enum.RenderPriority.Camera.Value-1,function()
    cameraFrame=nil; frameCamera=nil
    if closed or not state.NoShake then return end
    local c=player.Character
    local h=c and c:FindFirstChildOfClass("Humanoid")
    if h then
        if savedOffsets[h]==nil then savedOffsets[h]=h.CameraOffset end
        h.CameraOffset=Vector3.zero
    end
end)
RS:BindToRenderStep(renderName.."CameraCapture",Enum.RenderPriority.Camera.Value+1,function()
    local camera=WS.CurrentCamera
    if not closed and state.NoShake and camera and camera.CameraType~=Enum.CameraType.Scriptable then
        frameCamera=camera; cameraFrame=camera.CFrame
    end
end)
RS:BindToRenderStep(renderName,Enum.RenderPriority.Last.Value+1,function(dt)
    if closed then return end
    local camera=WS.CurrentCamera
    if camera then
        if state.LoopFOV then
            if savedFOV[camera]==nil then savedFOV[camera]=camera.FieldOfView end
            camera.FieldOfView=state.FOV
        end
        if state.NoShake and camera==frameCamera and cameraFrame and camera.CameraType~=Enum.CameraType.Scriptable then
            camera.CFrame=cameraFrame
        end
    end
    cameraFrame=nil; frameCamera=nil
    if not state.AutoFloor or not humanoid or not root or humanoid.Health<=0 then return end
    if hidden or root.Anchored or humanoid.Sit or humanoid.PlatformStand or character:GetAttribute("Hiding")==true then return end
    if state.Method=="Pathfind" then
        local delta=movementGoal and movementGoal-root.Position or Vector3.zero
        local flat=Vector3.new(delta.X,0,delta.Z)
        humanoid:Move(flat.Magnitude>0.5 and flat.Unit or Vector3.zero,false)
    end
    local camera=WS.CurrentCamera
    if state.AutoLook and target and camera then
        -- Follow the route ahead, not the door behind the player after crossing.
        local goal=state.Method=="Pathfind" and movementGoal or target.goal
        if goal then
            local delta=goal-root.Position
            local heading=Vector3.new(delta.X,0,delta.Z)
            if heading.Magnitude>2 then
                local cf=CFrame.lookAt(camera.CFrame.Position,camera.CFrame.Position+heading.Unit)
                camera.CFrame=state.Smooth and camera.CFrame:Lerp(cf,1-math.exp(-5*dt)) or cf
            end
        end
    end
end)
if not ESP then notify("MSESP could not load. ESP is unavailable; other controls still work.") end
if type(fireproximityprompt)~="function" then notify("Prompt automation unavailable: fireproximityprompt is missing.") end
notify("Thinking Hub loaded | Mr H - Owner")
return env.ThinkingHub
