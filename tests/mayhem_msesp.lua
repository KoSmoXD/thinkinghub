-- Verify that MAYHEM uses MSESP for all owned ESP visuals, with idempotent cleanup.
local h = assert(io.open("doors_mayhem.lua", "rb"))
local source = h:read("*a")
h:close()
assert(source:find("mstudio45/MSESP/", 1, true), "MSESP upstream URL missing")
assert(not source:find('Instance.new("Highlight")', 1, true),
    "native Highlight renderer should not be used anymore")
local first = assert(source:find("local ESP_LABELS = {", 1, true))
local last = assert(source:find("\nlocal function updateESP()", first, true))
local region = source:sub(first, last - 1)
local preface = [[
local markers = {}
local Vector3 = {new = function(x,y,z) return {X=x,Y=y,Z=z} end}
local mock = {created={}, removed={}, changed={}, addCalls=0}
local MSESP = {Destroyed=false}
function MSESP:Add(settings)
    mock.addCalls = mock.addCalls + 1
    assert(settings.ESPType == "Highlight")
    assert(settings.Model and settings.TextModel)
    assert(settings.Color == settings.FillColor)
    assert(settings.Color == settings.OutlineColor)
    assert(settings.TextSize == 15)
    assert(settings.MaxDistance == 5000)
    local object = {Deleted=false, CurrentSettings={Name=settings.Name}}
    function object:Destroy()
        assert(not self.Deleted, "double destroy")
        self.Deleted=true
        mock.removed[#mock.removed+1]=self
    end
    function object:SetEveryColor(color, includeComponents)
        assert(includeComponents)
        mock.changed[#mock.changed+1]=color
    end
    mock.created[#mock.created+1]={object=object, settings=settings}
    return object
end
]]
local chunk = assert(load(preface..region..
    "\nreturn markers, MSESP, mock, showMarker, removeMarker\n", "@MSESP_adapter"))
local markers, esp, mock, show, remove = chunk()
local function part(name)
    local p={Name=name}
    function p:IsA(kind) return kind=="BasePart" end
    return p
end
local function model(name)
    local p=part("MainPart")
    local m={Name=name,PrimaryPart=p}
    function m:IsA(kind) return kind=="Model" end
    return m
end
local red={R=1,G=0,B=0}
local blue={R=0,G=0,B=1}
local keyModel = model("HotelKey")
show(keyModel, {kind="key",color=red,distance=20})
assert(mock.addCalls==1 and mock.created[1].settings.Name=="KEY")
assert(mock.created[1].settings.Model==keyModel)
assert(mock.created[1].settings.TextModel==keyModel.PrimaryPart)
show(keyModel, {kind="key",color=red,distance=12})
assert(mock.addCalls==1,"same key should not create new MSESP instance")
show(keyModel, {kind="key",color=blue,distance=12})
assert(mock.addCalls==1 and #mock.changed==1)
assert(markers[keyModel].color==blue)
remove(keyModel)
assert(#mock.removed==1 and markers[keyModel]==nil)
remove(keyModel)
assert(#mock.removed==1,"removed key should not double destroy")

local fragmentPart=part("GlitchFragment")
show(fragmentPart,{kind="fragment",color=red,distance=10})
assert(mock.created[2].settings.Name=="GLITCH FRAGMENT")
assert(mock.created[2].settings.TextModel==fragmentPart)
local book=model("GlitchBook")
show(book,{kind="book",color=red,distance=42})
assert(mock.created[3].settings.Name=="GLITCH BOOK")
show(book,{kind="lever",color=red,distance=42})
assert(mock.created[4].settings.Name=="LEVER")
assert(mock.removed[2]==mock.created[3].object, "category changes destroy old ESP")

local rig=model("OtherPlayer")
show(rig,{kind="player",color=red,distance=55})
assert(mock.created[5].settings.Name=="PLAYER | OtherPlayer")
local entity=model("Rush")
show(entity,{kind="entity",color=red,distance=33})
assert(mock.created[6].settings.Name=="ENTITY | Rush")
for target in pairs(markers) do remove(target) end
assert(#mock.removed==6, "unload must destroy every owned MSESP object")
assert(next(markers)==nil)
assert(not esp.Destroyed, "global/shared MSESP must not be destroyed")
print("mayhem MSESP renderer: ok")
