-- MAYHEM experimental stamina controller mocked Lua 5.4 tests.
-- Confirm only LocalPlayer candidate properties are written.
local f = assert(io.open("lib/MayhemStamina.lua", "rb"))
local source = f:read("*a"); f:close()
local Module = assert(load(source, "@MayhemStamina"))()
local function node(class, name, props)
    props = props or {}
    local o = {ClassName=class, Name=name, Parent=nil,
        Children={}, Attributes=props.attributes or {},
        Value=props.value, Writes=0}
    function o:IsA(kind) return class==kind end
    function o:GetAttributes() return self.Attributes end
    function o:GetAttribute(key) return self.Attributes[key] end
    function o:SetAttribute(key,value)
        self.Attributes[key]=value; self.Writes=self.Writes+1
    end
    function o:Add(child)
        child.Parent=self; self.Children[#self.Children+1]=child
        return child
    end
    function o:FindFirstChild(key)
        for _,child in ipairs(self.Children) do
            if child.Name==key then return child end
        end
        return nil
    end
    function o:GetDescendants()
        local result={}
        local function walk(root)
            for _,child in ipairs(root.Children) do
                result[#result+1]=child
                walk(child)
            end
        end
        walk(self); return result
    end
    function o:IsDescendantOf(root)
        local parent=self.Parent
        while parent do
            if parent==root then return true end
            parent=parent.Parent
        end
        return false
    end
    function o:GetFullName()
        if self.Parent then return self.Parent:GetFullName().."."..self.Name end
        return self.Name
    end
    return o
end
local player=node("Player","LocalPlayer")
local gui=player:Add(node("PlayerGui","PlayerGui"))
local fakeUI=gui:Add(node("NumberValue","Stamina",{value=4}))
local stats=player:Add(node("Folder","Stats"))
local realStamina=stats:Add(node("NumberValue","Stamina",{value=25}))
stats:Add(node("NumberValue","MaxStamina",{value=150}))
local otherPlayer=node("Player","OtherPlayer")
local otherStamina=otherPlayer:Add(node("NumberValue","Stamina",{value=3}))
local rig=node("Model","Character",{attributes={Stamina=20,MaxStamina=80}})
player.Character=rig
local hum=rig:Add(node("Humanoid","Humanoid",{attributes={SprintStamina=12}}))
local stamina=Module.new(player)
assert(not stamina.enabled)
assert(#stamina:Scan()==3,"should find Stats value + Character stamina + Humanoid stamina")
assert(stamina:Status()=="Off")
stamina:Enabled(true)
assert(stamina.enabled and stamina:Status():find("3 source"))
stamina:Step(.05)
assert(realStamina.Value==25,"throttle should delay writes")
stamina:Step(.05)
assert(realStamina.Value==150,"reads MaxStamina sibling")
assert(rig:GetAttribute("Stamina")==80,"reads character max attribute")
assert(hum:GetAttribute("SprintStamina")==80,
    "should find character maximum even for humanoid stamina")
assert(fakeUI.Value==4,"must never overwrite stamina bar")
assert(otherStamina.Value==3,"must never touch another player")
assert(stamina.writes==3)
assert(#stamina:Describe()==3,"F9 diagnostics should list real stamina paths")
stamina:Step(.1)
assert(stamina.writes==3,"fully charged values should not be written repeatedly")
stamina:Enabled(false)
rig:SetAttribute("Stamina", 50)
realStamina.Value=20
stamina:Step(1)
assert(rig:GetAttribute("Stamina")==50 and realStamina.Value==20,
    "turning off should stop refill")
assert(stamina:Status()=="Off")

-- A round respawn must rescan the new character without keeping old references.
local newRig=node("Model","NewCharacter",{attributes={Stamina=10,MaxStamina=110}})
player.Character=newRig
stamina:Enabled(true)
assert(#stamina.sources==2,"should track fresh character and player Stats")
stamina:Step(.1)
assert(newRig:GetAttribute("Stamina")==110)
assert(rig:GetAttribute("Stamina")==50,"old character remains untouched")
stamina:Unload()
assert(not stamina.enabled and #stamina.sources==0)

-- With no exposed value, admit that the game is likely closure/server-driven.
local barePlayer=node("Player","Empty")
local empty=Module.new(barePlayer)
empty:Enabled(true)
assert(#empty.sources==0)
assert(empty:Status()=="No accessible stamina source found")
empty:Step(4)
assert(empty.writes==0)
print("mayhem experimental stamina: detection, local refill, GUI exclusion, respawn, disable: ok")
