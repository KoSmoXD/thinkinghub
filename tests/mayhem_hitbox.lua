local Vector={new=function(x,y,z)return {X=x,Y=y,Z=z} end}
local f=assert(io.open("lib/MayhemHitbox.lua","rb"))
local M=assert(load(f:read("*a"),"@Hitbox","t",
    setmetatable({Vector3=Vector},{__index=_G})))();f:close()
local function player()
    local part={Size=Vector.new(2,3,1),Transparency=1,CanCollide=true,Massless=false}
    function part:IsA(kind)return kind=="BasePart"end
    local hum={Health=100}
    local char={attrs={}}
    function char:FindFirstChild()return part end
    function char:FindFirstChildOfClass()return hum end
    function char:GetAttribute(k)return self.attrs[k]end
    return {Character=char},part,hum
end
local me,myPart=player()
local enemy,part,hum=player()
local friend,friendPart=player()
local all={me,enemy,friend}
local eligible=true
local c=M.new({player=me,players={GetPlayers=function()return all end},
    eligible=function(p)return p==enemy and eligible or p==me end})
local size=part.Size
c:SetEnabled(true);c:Step(.1)
assert(part.Size.X==8 and part.Transparency==.75 and not part.CanCollide and part.Massless)
assert(myPart.Size.X==2 and friendPart.Size.X==2,"self and teammates unchanged")
c:SetSize(12);c:Step(.1)
assert(part.Size.X==12 and c.count==1)
eligible=false;c:Step(.2)
assert(part.Size==size and part.Transparency==1 and part.CanCollide and not part.Massless)
eligible=true;c:Step(.2)
hum.Health=0;c:Step(.2)
assert(part.Size==size,"dead character restored")
hum.Health=100;c:Step(.2)
local replacement,newPart=player()
enemy.Character=replacement.Character;c:Step(.2)
assert(part.Size==size and newPart.Size.X==12,"respawn restores old rig and expands new")
all={me,friend};c:Step(.2)
assert(newPart.Size.X==2,"departed player restored")
all={me,enemy,friend};c:Step(.2)
c:SetEnabled(false)
assert(newPart.Size.X==2 and c.count==0)
c:SetEnabled(true);c:Step(.2);c:Unload();c:Unload()
assert(newPart.Size.X==2 and next(c.originals)==nil)
assert(not c:SetSize(0/0));c:SetSize(100)
assert(c.size==20)
print("mayhem hitbox: targeting, size, death, teams, respawn, departure and restoration OK")
