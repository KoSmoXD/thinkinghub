-- Mocked Obsidian bridge contract test (Lua 5.4).
local h = assert(io.open("lib/MayhemObsidian.lua", "rb"))
local source = h:read("*a"); h:close()
local registered, onUnload, rawLibrary = {}, nil, {}
local function control(default)
    local o = {Value = default}
    function o:OnChanged(callback) self.callback = callback end
    function o:Fire(value) self.Value = value; if self.callback then self.callback(value) end end
    return o
end
local function group()
    local g = {}
    function g:AddLabel(text)
        local label = {text = text}
        function label:SetText(value) self.text = value end
        table.insert(registered, {kind = "label", label = label})
        return label
    end
    function g:AddButton(opts)
        assert(type(opts.Func) == "function")
        return {Click = function() opts.Func() end}
    end
    function g:AddToggle(id, opts)
        assert(type(id) == "string" and type(opts.Default) == "boolean")
        return control(opts.Default)
    end
    function g:AddDropdown(id, opts)
        assert(type(opts.Values) == "table" and type(opts.Default) == "string")
        return control(opts.Default)
    end
    function g:AddInput(id, opts)
        assert(type(opts.Text) == "string")
        return control(opts.Default)
    end
    function g:AddSlider(id, opts)
        assert(type(opts.Min) == "number" and type(opts.Max) == "number")
        return control(opts.Default)
    end
    return g
end
local mainFrame = {Name = "Main"}
local capturedGrip
function rawLibrary:MakeDraggable(frame, grip, ignoreToggled, mainWindow)
    assert(frame == mainFrame and grip.Name == "MayhemBottomDrag")
    assert(ignoreToggled == false and mainWindow == true)
    capturedGrip = grip
end
function rawLibrary:CreateWindow(opts)
    assert(opts.ToggleKeybind == "RightShift",
        "Obsidian window must use RightShift for toggle")
    return {MainFrame = mainFrame, AddTab = function(_,name)
        assert(type(name) == "string")
        return {AddLeftGroupbox = function() return group() end,
            AddRightGroupbox = function() return group() end}
    end}
end
function rawLibrary:Notify() end
function rawLibrary:OnUnload(callback) onUnload = callback end
function rawLibrary:Unload()
    local callback = onUnload
    onUnload = nil
    if callback then callback() end
end
local sandbox = {
    Instance = {new = function(class)
        assert(class == "Frame")
        return {ClassName = class}
    end},
    UDim2 = {new = function(...) return {...} end},
    Enum = {KeyCode = {RightShift = "RightShift", RightControl = "RightControl"}},
    game = {HttpGet = function() return "mock-ob-library" end},
    loadstring = function(text)
        assert(text == "mock-ob-library")
        return function() return rawLibrary end
    end
}
setmetatable(sandbox,{__index=_G})
local ui=assert(load(source, "@MayhemObsidian", "t", sandbox))()
local window=ui:CreateWindow({Title="Zinc Mayhem",Subtitle="Test"})
assert(capturedGrip and capturedGrip.Parent == mainFrame and capturedGrip.Active,
    "Obsidian footer should be draggable")
local home=window:CreateTab("Home")
local section=home:CreateSection("General")
local label=section:AddLabel("Original")
label:Set("Updated")
window:SetStatus("Ready")
assert(registered[1].label.text == "Ready")
assert(registered[2].label.text == "Updated")
local toggleValue
local toggle=section:AddToggle({Name="Toggle",Default=true,Callback=function(v)
    toggleValue=v
end})
toggle:Fire(false)
assert(toggleValue == false)
local dropdownValue
local dropdown=section:AddDropdown({Name="UI library",Default="Zinc",
    Options={"Zinc","Obsidian"},Callback=function(v) dropdownValue=v end})
dropdown:Fire("Obsidian")
assert(dropdownValue=="Obsidian")
local amount
section:AddSlider({Name="FOV",Min=50,Max=120,Default=90,Callback=function(v)
    amount=v
end}):Fire(110)
assert(amount==110)
local input
section:AddTextbox({Name="Aliases",Default="",Callback=function(v) input=v end}):Fire("fragment")
assert(input=="fragment")
local clicked=false
section:AddButton({Name="Reset",Callback=function()clicked=true end}):Click()
assert(clicked)
local count=0
window.Destroy=function() count=count+1 end
rawLibrary:Unload()
assert(count == 1)
-- Regression: Zinc should keep RightControl and Obsidian should use RightShift.
local sourceFile = assert(io.open("doors_mayhem.lua", "rb"))
local moduleCode = sourceFile:read("*a")
sourceFile:close()
assert(moduleCode:find('ToggleKey = selectedStyle == "Obsidian"', 1, true))
assert(moduleCode:find("Enum.KeyCode.RightShift or Enum.KeyCode.RightControl", 1, true))
print("mayhem Obsidian RightShift toggle + facade contract: ok")
