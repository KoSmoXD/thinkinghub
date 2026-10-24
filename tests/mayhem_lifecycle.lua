-- Exercise adapter functions with camera/lighting/controller mocks.
local f=assert(io.open("doors_mayhem.lua","rb"))
local source=f:read("*a"):gsub("\r\n","\n");f:close()
local function region(first,last)
    local a=assert(source:find(first,1,true))
    local b=assert(source:find(last,a,true))
    return source:sub(a,b-1)
end
local visuals=region("local function applyVisuals()","local function restoreCamera()")
assert(load([[
local state={fovOn=false,fov=100,bright=false}
local Workspace={CurrentCamera={FieldOfView=70}}
local Lighting={Brightness=1,ClockTime=3,FogEnd=500,GlobalShadows=true}
local oldCamera,oldFov,originalLighting
]]..visuals..[[
local first=Workspace.CurrentCamera
setFov(true);setFov(true);setFov(false)
assert(first.FieldOfView==70,"duplicate enable must preserve original FOV")
setFov(true)
local second={FieldOfView=80}
Workspace.CurrentCamera=second
applyVisuals()
assert(first.FieldOfView==70 and second.FieldOfView==100)
setFov(false)
assert(second.FieldOfView==80,"replacement camera must restore its own FOV")
setFullbright(true);setFullbright(true);setFullbright(false)
assert(Lighting.Brightness==1 and Lighting.ClockTime==3)
assert(Lighting.FogEnd==500 and Lighting.GlobalShadows)
]],"@visual_lifecycle"))()
local guard=region("local controllerFaults = {}","env.ZincMayhem.Errors = controllerFaults")
assert(load([[
local notices=0
local warn=function()end
local window={SetStatus=function()notices=notices+1 end}
]]..guard..[[
local calls,stops,healthy=0,0,0
local broken={Step=function()calls=calls+1;error("broken")end,
    Unload=function()stops=stops+1 end}
local working={Step=function()healthy=healthy+1 end}
for i=1,3 do
    stepController("broken",broken,.1)
    stepController("working",working,.1)
end
assert(calls==1 and stops==1 and notices==1)
assert(healthy==3 and controllerFaults.broken:find("broken"))
]],"@controller_isolation"))()
local holds=region("local heldPrompts = {}","do\n    local url")
assert(load(holds..[[
local calls=0
local prompt={InputHoldEnd=function()calls=calls+1 end}
heldPrompts[prompt]={}
releasePrompts();releasePrompts()
assert(calls==1 and next(heldPrompts)==nil)
]],"@prompt_release"))()
print("mayhem lifecycle: visual restoration, controller fault isolation, hold cancellation OK")
