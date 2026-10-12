-- Offline behavior checks, Lua 5.3 (texlua). Roblox and UI APIs are mocked.
-- Run from the repository directory: texlua tests/smoke.lua
loadstring=load
local function signal()
    local s={listeners={}}
    function s:Connect(fn)
        local c={Connected=true}; function c:Disconnect() self.Connected=false end
        self.listeners[#self.listeners+1]={fn=fn,c=c}; return c
    end
    function s:Fire(...)
        for _,v in ipairs(self.listeners) do if v.c.Connected then v.fn(...) end end
    end
    return s
end
local vm={}
function vm.__index(t,k)
    if k=="Magnitude" then return math.sqrt(t.X*t.X+t.Y*t.Y+t.Z*t.Z) end
    if k=="Unit" then return t/t.Magnitude end
    if k=="Dot" then return function(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end end
end
Vector3={new=function(x,y,z) return setmetatable({X=x,Y=y,Z=z},vm) end}
Vector3.zero=Vector3.new(0,0,0)
vm.__add=function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vm.__sub=function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vm.__mul=function(a,b) return Vector3.new(a.X*b,a.Y*b,a.Z*b) end
vm.__div=function(a,b) return a*(1/b) end
vm.__unm=function(a) return a*-1 end
local function cf(pos)
    local t={Position=pos,LookVector=Vector3.new(1,0,0)}
    function t:PointToObjectSpace(p) return p-self.Position end
    function t:Lerp(b) return b end
    return setmetatable(t,{__add=function(a,b) return cf(a.Position+b) end})
end
CFrame={lookAt=function(p) return cf(p) end}
Color3={new=function(r,g,b) return {R=r,G=g,B=b} end}
Color3.fromRGB=function(r,g,b) return Color3.new(r/255,g/255,b/255) end
ColorSequence={new=function(v) return v end}
RaycastParams={new=function() return {} end}
Enum={RaycastFilterType={Exclude=1},PathStatus={Success=1},PathWaypointAction={Jump=1},CameraType={Scriptable=2,Custom=1},RenderPriority={Camera={Value=100},Last={Value=200}},KeyCode={RightControl=1}}
local function node(class,name,parent)
    local o={ClassName=class,Name=name or class,Parent=parent,children={},attrs={},Position=Vector3.zero,CFrame=cf(Vector3.zero),Size=Vector3.new(2,2,2)}
    if parent then parent.children[#parent.children+1]=o end
    function o:IsA(c) return self.ClassName==c or (c=="BasePart" and self.ClassName=="Part") end
    function o:GetChildren() return self.children end
    function o:GetDescendants()
        local out={}; for _,v in ipairs(self.children) do out[#out+1]=v; for _,d in ipairs(v:GetDescendants()) do out[#out+1]=d end end
        return out
    end
    function o:FindFirstChild(n,recursive)
        for _,v in ipairs(recursive and self:GetDescendants() or self.children) do if v.Name==n then return v end end
    end
    function o:FindFirstChildWhichIsA(c,recursive)
        for _,v in ipairs(recursive and self:GetDescendants() or self.children) do if v:IsA(c) then return v end end
    end
    o.FindFirstChildOfClass=o.FindFirstChildWhichIsA
    function o:GetAttribute(k) return self.attrs[k] end
    function o:IsDescendantOf(p) local v=self.Parent; while v do if v==p then return true end; v=v.Parent end; return false end
    function o:GetPivot() return cf(self.PrimaryPart and self.PrimaryPart.Position or self.Position) end
    function o:PivotTo(v) self.PrimaryPart.Position=v.Position end
    function o:GetBoundingBox() return cf(self.Position),Vector3.new(20,10,20) end
    function o:Destroy() self.Parent=nil; self.Destroyed=true end
    function o:Play() self.played=true end
    function o:Stop() self.played=false end
    return o
end
Instance={new=function(c) return node(c) end}
local buttons,ui={},{}
local library={Options={},Toggles={},notes={}}
local function control(id,info)
    local c={Value=info.Default,info=info}
    function c:OnChanged(fn) self.changed=fn end
    function c:SetValue(v) self.Value=v; if self.changed then self.changed(v) end end
    function c:SetValues(v) self.values=v end
    ui[id]=c; return c
end
local box={}
function box:AddTab() return self end
function box:AddLeftTabbox() return self end
function box:AddLeftGroupbox() return self end
function box:AddRightGroupbox() return self end
function box:AddToggle(id,info) local c=control(id,info); library.Toggles[id]=c; return c end
function box:AddInput(id,info) local c=control(id,info); library.Options[id]=c; return c end
box.AddSlider=box.AddInput; box.AddDropdown=box.AddInput
function box:AddButton(info) buttons[info.Text]=info.Func; return {} end
function box:AddLabel(text)
    local label={text=text}
    function label:SetText(v) self.text=v end
    function label:AddColorPicker(id,info) library.Options[id]=control(id,info); return self end
    return label
end
function library:CreateWindow() return box end
function library:OnUnload(fn) self.onUnload=fn end
function library:Unload() self.Unloaded=true; self.onUnload() end
function library:Notify(v) self.notes[#self.notes+1]=v.Description end
_G.__testLibrary=library
local esp={created={}}
function esp:Add(settings)
    local e={settings=settings,CurrentSettings=settings}
    function e:Destroy() self.Deleted=true end
    function e:SetEveryColor(c) self.color=c end
    self.created[#self.created+1]=e; return e
end
_G.__testESP=esp
local ws=node("Workspace","Workspace"); ws.DescendantAdded=signal(); ws.DescendantRemoving=signal()
function ws:Raycast() return nil end
local rooms=node("Folder","CurrentRooms",ws)
local room=node("Model","1",rooms)
local door=node("Model","Door",room)
door.attrs.DoorNumber="A-002"
local dp=node("Part","Door",door); dp.Position=Vector3.new(10,0,0); dp.CFrame=cf(dp.Position); door.PrimaryPart=dp
local char=node("Model","PlayerCharacter",ws)
local hrp=node("Part","HumanoidRootPart",char); char.PrimaryPart=hrp
local hum=node("Humanoid","Humanoid",char); hum.Health=100; hum.WalkSpeed=16
function hum:Move(v) self.lastMove=v end
local player={Character=char,GetAttribute=function(_,k) if k=="CurrentRoom" then return 1 end end}
local players={LocalPlayer=player,GetPlayerFromCharacter=function(_,c) if c==char then return player end end}
local run={Heartbeat=signal(),bindings={}}
function run:BindToRenderStep(n,_,fn) self.bindings[n]=fn end
function run:UnbindFromRenderStep(n) self.bindings[n]=nil end
local pf={}
function pf:CreatePath()
    local p={Blocked=signal()}
    function p:ComputeAsync(a,b) if pf.onCompute then pf.onCompute() end; self.Status=1; self.points={{Position=a},{Position=b}} end
    function p:GetWaypoints() return self.points end
    function p:Destroy() self.Destroyed=true end
    return p
end
local encoded={}; local serial=0
local http={GenerateGUID=function() return "test-guid" end}
function http:JSONEncode(v) serial=serial+1; local key="json-"..serial; encoded[key]=v; return key end
function http:JSONDecode(v) assert(encoded[v],"bad json"); return encoded[v] end
local services={Players=players,Workspace=ws,RunService=run,PathfindingService=pf,HttpService=http,
    SoundService=node("SoundService"),ProximityPromptService={PromptShown=signal()}}
game={GetService=function(_,n) assert(services[n],n); return services[n] end,
    HttpGet=function(_,url) return url:find("MSESP",1,true) and "return _G.__testESP" or "return _G.__testLibrary" end}
local files,folders={},{}
isfolder=function(p) return folders[p]==true end
makefolder=function(p) folders[p]=true end
isfile=function(p) return files[p]~=nil end
writefile=function(p,v) files[p]=v end
readfile=function(p) assert(files[p]); return files[p] end
delfile=function(p) files[p]=nil end
listfiles=function(prefix) local out={}; for p in pairs(files) do if p:sub(1,#prefix)==prefix then out[#out+1]=p end end; return out end
local fired=0
fireproximityprompt=function() fired=fired+1 end
fireclickdetector=function() fired=fired+1 end
task={spawn=function(fn) fn() end}
warn=function(s) error(s) end
hum.CameraOffset=Vector3.new(0,1,0)
local hub=assert(loadfile("rooms_revisited.lua"))()
assert(hub and buttons["Unload"] and ui.TH_EntitiesColor,"Hub bootstrap failed")
ui.TH_Speed:SetValue(1000); ui.TH_SpeedEnabled:SetValue(true)
run.Heartbeat:Fire(0.1); assert(hum.WalkSpeed==1000,"Loop speed not applied")
ui.TH_SpeedEnabled:SetValue(false); assert(hum.WalkSpeed==16,"WalkSpeed not restored")
ui.TH_AutoFloor:SetValue(true)
run.Heartbeat:Fire(0.1); run.Heartbeat:Fire(0.1)
for _,fn in pairs(run.bindings) do fn(0.016) end
assert(hum.lastMove and hum.lastMove.X>0,"Pathfind did not drive humanoid")
ui.TH_Method:SetValue("TP"); run.Heartbeat:Fire(0.1); run.Heartbeat:Fire(0.1)
assert(hrp.Position.X>0,"TP did not move character")
ui.TH_AutoFloor:SetValue(false); assert(hum.WalkSpeed==16)
ui.TH_Method:SetValue("Pathfind")
pf.onCompute=function() ui.TH_AutoFloor:SetValue(false) end
ui.TH_AutoFloor:SetValue(true); run.Heartbeat:Fire(0.1)
assert(not ui.TH_AutoFloor.Value and hum.WalkSpeed==16,"Cancelled path restarted movement")
pf.onCompute=nil
local drawer=node("Model","Drawer",room)
local part=node("Part","Handle",drawer); drawer.PrimaryPart=part
local prompt=node("ProximityPrompt","Prompt",part)
prompt.HoldDuration=2; prompt.Enabled=true; prompt.MaxActivationDistance=30; prompt.ActionText="Open"; prompt.ObjectText="Drawer"
ws.DescendantAdded:Fire(drawer); ws.DescendantAdded:Fire(part); ws.DescendantAdded:Fire(prompt)
ui.TH_Instant:SetValue(true); assert(prompt.HoldDuration==0)
ui.TH_Interact:SetValue(true); run.Heartbeat:Fire(0.1); assert(fired>0,"Auto interact failed")
ui.TH_Instant:SetValue(false); assert(prompt.HoldDuration==2,"Prompt hold not restored")
local generic=node("Model","Door",room)
local gp=node("Part","Door",generic); generic.PrimaryPart=gp
local old=node("Model","Door",room); old.attrs.DoorNumber="A-001"
local op=node("Part","Door",old); old.PrimaryPart=op
local future=node("Model","Door",room); future.attrs.DoorNumber="A-212"
local fp=node("Part","Door",future); future.PrimaryPart=fp
for _,o in ipairs({generic,gp,old,op,future,fp}) do ws.DescendantAdded:Fire(o) end
ui.TH_DoorESP:SetValue(true); run.Heartbeat:Fire(1)
assert(#esp.created==1,"Door ESP duplication or missing ESP")
assert(esp.created[1].settings.Model==door,"ESP selected a generic, old or future door")
local entity=node("Model","A-60",ws)
local ep=node("Part","Root",entity); entity.PrimaryPart=ep
ws.DescendantAdded:Fire(entity); ws.DescendantAdded:Fire(ep)
ui.TH_Notify:SetValue(true)
local n=#library.notes
run.Heartbeat:Fire(1); run.Heartbeat:Fire(1)
assert(#library.notes==n+1,"Entity notification missing or repeated")
local color=Color3.new(0.1,0.2,0.3); ui.TH_DoorColor:SetValue(color); run.Heartbeat:Fire(1)
assert(esp.created[1].color==color,"ESP color did not update")
local originalAttribute=player.GetAttribute
player.GetAttribute=function(_,key) if key=="CurrentRoom" then return "A-211" end end
run.Heartbeat:Fire(1)
assert(esp.created[#esp.created].settings.Model==future and esp.created[1].Deleted,"Next door did not advance to A-212")
future.attrs.DoorNumber="A-1000"
player.GetAttribute=function(_,key) if key=="CurrentRoom" then return "A-999" end end
run.Heartbeat:Fire(1)
assert(esp.created[#esp.created].settings.Name=="Next door | A-1000","Four-digit door label failed")
future.attrs.DoorNumber=nil
run.Heartbeat:Fire(1)
assert(esp.created[#esp.created].Deleted,"Generic doors used when next number missing")
player.GetAttribute=originalAttribute
run.Heartbeat:Fire(1)

ui.TH_ConfigName:SetValue("test"); buttons["Create config"]()
assert(files["ThinkingHub/ROOMSRevisited/configs/test.json"],"Config create failed")
ui.TH_Speed:SetValue(5); buttons["Load config"](); assert(ui.TH_Speed.Value==1000,"Config load failed")
ui.TH_Speed:SetValue(42); buttons["Overwrite config"](); ui.TH_Speed:SetValue(10); buttons["Load config"](); assert(ui.TH_Speed.Value==42)
ui.TH_ConfigName:SetValue("../escape"); buttons["Create config"](); assert(not files["ThinkingHub/ROOMSRevisited/configs/../escape.json"])
buttons["Delete config"](); assert(not next(files),"Config delete failed")
ui.TH_SpeedEnabled:SetValue(true); ui.TH_Instant:SetValue(true); run.Heartbeat:Fire(0.1)
local camera=node("Camera","Camera",ws); camera.FieldOfView=70; camera.CameraType=1; ws.CurrentCamera=camera
local function render(name) assert(run.bindings["ThinkingHub_test-guid"..name])() end
ui.TH_FOV:SetValue(95); ui.TH_LoopFOV:SetValue(true)
render(""); assert(camera.FieldOfView==95,"FOV depends on Auto Floor")
camera.FieldOfView=50; render(""); assert(camera.FieldOfView==95,"FOV did not loop")
ui.TH_LoopFOV:SetValue(false); assert(camera.FieldOfView==70,"FOV restore failed")
ui.TH_NoShake:SetValue(true); render("CameraBefore"); assert(hum.CameraOffset.Magnitude==0)
local base=cf(Vector3.zero); camera.CFrame=base; render("CameraCapture")
camera.CFrame=cf(Vector3.new(3,0,0)); render(""); assert(camera.CFrame==base,"Late shake was not removed")
camera.CameraType=2; render("CameraBefore"); render("CameraCapture")
local scripted=cf(Vector3.new(4,0,0)); camera.CFrame=scripted; render(""); assert(camera.CFrame==scripted,"Scripted camera overwritten")
ui.TH_NoShake:SetValue(false); assert(hum.CameraOffset.Y==1,"CameraOffset not restored")
ui.TH_LoopFOV:SetValue(true); render("")
hub.Unload(); hub.Unload()
assert(camera.FieldOfView==70,"FOV not restored on unload")
assert(hum.WalkSpeed==16 and prompt.HoldDuration==2,"Unload restore failed")
assert(not next(run.bindings),"Render callback leaked")
for _,c in ipairs(run.Heartbeat.listeners) do assert(not c.c.Connected,"Heartbeat leaked") end
assert(esp.created[1].Deleted,"ESP leaked")
print("PASS: bootstrap, speed restore, Pathfind movement, TP, interaction, ESP colors, config CRUD, name validation, idempotent unload")
