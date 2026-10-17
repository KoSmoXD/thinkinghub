-- MAYHEM Fragment Game mocked behavioral checks.
local h=assert(io.open("lib/MayhemFragmentGame.lua","rb"))
local Module=assert(load(h:read("*a"),"@FragmentGame"))()
h:close()
local function vector(x)
    return setmetatable({X=x},{__sub=function(a,b)
        return {Magnitude=math.abs(a.X-b.X)}
    end})
end
local function node(class,name,attrs)
    local n={ClassName=class,Name=name,Parent=nil,Children={},
        Attributes=attrs or {},Visible=true,Enabled=true}
    function n:IsA(what)
        return self.ClassName==what
            or (what=="GuiObject" and (self.ClassName=="Frame"
                or self.ClassName=="TextButton" or self.ClassName=="ImageButton"))
            or (what=="GuiButton" and
                (self.ClassName=="TextButton" or self.ClassName=="ImageButton"))
    end
    function n:Add(child)
        child.Parent=self; self.Children[#self.Children+1]=child
        return child
    end
    function n:GetAttribute(key) return self.Attributes[key] end
    function n:GetDescendants()
        local result={}
        local function visit(cur)
            for _,kid in ipairs(cur.Children) do
                result[#result+1]=kid; visit(kid)
            end
        end
        visit(self);return result
    end
    function n:FindFirstChild(name)
        for _,kid in ipairs(self.Children) do
            if kid.Name==name then return kid end
        end
    end
    return n
end
local player=node("Player","Me")
local gui=player:Add(node("PlayerGui","PlayerGui"))
local char=node("Model","Character")
player.Character=char
local root=char:Add(node("Part","HumanoidRootPart"))
root.Position=vector(0)
root.IsA=function(_,what)return what=="BasePart" end
local world=node("Workspace","Workspace")
local near=world:Add(node("Part","GlitchFragment"))
near.Position=vector(4)
near.IsA=function(_,what)return what=="BasePart" end
local prompt=near:Add(node("ProximityPrompt","ProximityPrompt"))
prompt.MaxActivationDistance=10
local activated,clicked={},{}
local instance=Module.new({
    player=player, workspace=world,
    isFragment=function(item)
        return item==prompt
    end,
    inCharacter=function()return false end,
    isEntity=function()return false end,
    activatePrompt=function(item)
        activated[#activated+1]=item
        return true
    end,
    clickButton=function(button)
        clicked[#clicked+1]=button;return true
    end,
})
instance:SetEnabled(true)
instance:Step(.4)
assert(#activated==1 and activated[1]==prompt,
    "fragment in reach should be activated automatically")
instance:Step(.4); instance:Step(.4)
assert(#activated==1,"same pickup prompt must not be spammed")
local far=world:Add(node("Part","GlitchFragment"))
far.Position=vector(50)
far.IsA=function(_,what)return what=="BasePart" end
local farther=far:Add(node("ProximityPrompt","ProximityPrompt"))
farther.MaxActivationDistance=12
-- Force next proximity scan after throttle.
instance:Step(1);instance:Step(1)
assert(#activated==1,"fragment outside allowed radius must be ignored")
local screen=gui:Add(node("ScreenGui","GlitchFragmentMinigame"))
local frame=screen:Add(node("Frame","PuzzleArea"))
local wrong=frame:Add(node("TextButton","Wrong"))
wrong.Text="B"
local correct=frame:Add(node("TextButton","Correct"))
correct.Text="A"
correct.Attributes.IsCorrect=true
instance:Step(.5)
assert(#clicked==1 and clicked[1]==correct,
    "puzzle explicitly marked answer should be clicked")
instance:Step(1);instance:Step(1)
assert(#clicked==1, "same stage/answer must not be clicked repeatedly")
screen.Attributes.Stage=2
instance:Step(1)
assert(#clicked==2,"new puzzle step should allow next answer")
correct.Attributes.IsCorrect=nil
instance:Step(1)
assert(#clicked==2 and instance.unsupported>0,
    "ambiguous puzzle must never guess an answer")
frame.Attributes.CorrectAnswer="B"
instance:Step(1)
assert(#clicked==3 and clicked[3]==wrong,
    "explicit parent CorrectAnswer should be respected")
local strings=instance:Inspect()
assert(table.concat(strings,"\n"):find("visible fragment puzzle GUIs: 1",1,true),
    "diagnostics lists active puzzle UI")
-- Roblox ImageButton has no Text property; this must not crash the handler.
frame.Attributes.CorrectAnswer=nil
local image=frame:Add(node("ImageButton","CorrectIcon",{IsCorrect=true}))
setmetatable(image,{__index=function(_,key)
    if key=="Text" then error("Text is not a valid member of ImageButton") end
end})
screen.Attributes.Stage=3
instance:Step(1)
assert(#clicked==4 and clicked[4]==image,
    "ImageButton answer must work without Text")
assert(#instance:Inspect()>0,"ImageButton inspector must not read missing Text")
instance:SetEnabled(false)
instance:Step(1)
assert(#clicked==4,"disable stops auto clicks")
local entity=true
local game=Module.new({
    player=player,workspace=world,
    isFragment=function(item)return item==prompt end,
    isEntity=function()return entity end,
    activatePrompt=function(item)activated[#activated+1]=item;return true end,
    clickButton=function(button)clicked[#clicked+1]=button;return true end,
})
game:SetEnabled(true)
screen.Enabled=false
game:Step(1)
assert(#activated==1,"entity players must not trigger survivor fragment prompts")
assert(game:Status():find("survivor"),"entity limitation should be visible")
game:Unload()
assert(not game.enabled and game:Status():find("Off"))
-- No arbitrary unrelated GUI buttons must be pressed.
local unrelated=gui:Add(node("ScreenGui","ZincHub"))
local menu=unrelated:Add(node("Frame","ESP"))
local uiButton=menu:Add(node("TextButton","GlitchFragmentESP"))
uiButton.Text="Glitch Fragment ESP"
screen.Enabled=false
entity=false
game:SetEnabled(true)
game:Step(1)
assert(#clicked==4,"unrelated ZincUI must not be interpreted as puzzle")

-- Prompt reach is measured from its actual supported parent position.
local probePrompt
local probe=Module.new({player=player,workspace=world,
    isFragment=function(item)return item==probePrompt end,
    activatePrompt=function(item)activated[#activated+1]=item;return true end})
local function interactionCount(parent,limit)
    probePrompt=parent:Add(node("ProximityPrompt","Probe"))
    probePrompt.MaxActivationDistance=limit
    probe:SetEnabled(true)
    local before=#activated
    probe:Step(1)
    return #activated-before
end
assert(interactionCount(near,2)==0,
    "configured ranges below three studs must not be expanded")
assert(interactionCount(near,0)==0,"zero range must not be expanded")
local model=world:Add(node("Model","GlitchFragment"))
model.PrimaryPart=near
assert(interactionCount(model,10)==1,"model-parented prompts use PrimaryPart")
local attachment=far:Add(node("Attachment","FragmentAnchor"))
attachment.WorldPosition=vector(3)
assert(interactionCount(attachment,5)==1,
    "attachment prompt must use WorldPosition instead of its distant parent part")
attachment.WorldPosition=vector(12)
assert(interactionCount(attachment,5)==0,
    "out-of-range attachment prompt must be excluded")
local noPrimary=world:Add(node("Model","Unconfigured"))
assert(interactionCount(noPrimary,10)==0,"model without PrimaryPart is unsupported")
probe:Unload()
print("mayhem fragment game: nearby prompts, explicit GUI answers, debounce, diagnostics, entity safety OK")
