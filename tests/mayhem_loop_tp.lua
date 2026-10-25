local M=dofile("lib/MayhemLoopTp.lua")
local function player(name,role,x)
    local position=setmetatable({x=x},{__sub=function(a,b)return {Magnitude=math.abs(a.x-b.x)}end})
    local part={Position=position,CFrame=name}
    function part:IsA(k)return k=="BasePart"end
    local hum={Health=100}
    local char={}
    function char:FindFirstChild()return part end
    function char:FindFirstChildOfClass()return hum end
    function char:GetAttribute()return nil end
    return {Name=name,role=role,Character=char},part,hum
end
local me,own=player("Me","Entity",0)
local near,np,nh=player("Near","Survivor",5)
local far,fp=player("Far","Survivor",20)
local ally=player("Ally","Entity",1)
local all={me,near,far,ally}
local c=M.new({player=me,players={GetPlayers=function()return all end},
    roleOf=function(p)return p.role end})
c:Step(1);assert(own.CFrame=="Me")
c:SetEnabled(true);c:Step(.1)
assert(own.CFrame==np.CFrame and c.target==near)
np.CFrame="moved";c:Step(.05);assert(own.CFrame~="moved")
c:Step(.2);assert(own.CFrame=="moved")
nh.Health=0;c:Step(.2);assert(c.target==far and own.CFrame==fp.CFrame)
me.role="Survivor";own.CFrame="stay";c:Step(1)
assert(own.CFrame=="stay" and not c.target)
me.role="Entity";all={me,ally};c:Step(1)
assert(own.CFrame=="stay" and c:Status()=="No living survivor")
all={me,far};c:Unload();c:Step(1);assert(own.CFrame=="stay")
c:SetEnabled(true)
local respawn,newRoot=player("Respawn","Entity",0)
me.Character=respawn.Character;c:Step(.2)
assert(newRoot.CFrame==fp.CFrame and own.CFrame=="stay")
c:Unload()
print("mayhem loop TP: nearest living survivor, role gate, throttle, respawn, unload OK")
