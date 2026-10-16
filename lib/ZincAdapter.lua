-- Zinc Hub / Obsidian-compatible adapter for our own ZincUI library.
-- API bridge: existing features and callbacks stay unchanged.
local source = game:HttpGet("https://raw.githubusercontent.com/KoSmoXD/thinkinghub/main/lib/ZincUI.lua")
local compile, reason = loadstring(source, "@ZincHub/ZincUI")
assert(compile, reason)
local Zinc = compile()
local Library = {Options = {}, _window = nil, _onUnload = nil, _unloaded = false}

local function bind(section, id, opts, method, extra)
    opts = opts or {}
    local proxy = {Value = opts.Default, _onChanged = nil}
    local props = {Name = opts.Text or id, Default = opts.Default,
        Callback = function(value)
            proxy.Value = value
            if proxy._onChanged then proxy._onChanged(value) end
        end}
    if extra then for key, val in pairs(extra) do props[key] = val end end
    local controller = section[method](section, props)
    proxy.Value = controller:Get()
    function proxy:OnChanged(callback) self._onChanged = callback; return self end
    function proxy:SetValue(value)
        controller:Set(value)
        self.Value = controller:Get()
    end
    function proxy:SetValues(values)
        assert(method == "AddDropdown", "SetValues is only valid for a dropdown")
        controller:Refresh(values, true)
        self.Value = controller:Get()
    end
    if id then Library.Options[id] = proxy end
    return proxy
end

local function wrapSection(section)
    local box = {}
    function box:AddButton(opts)
        return section:AddButton({Name = opts.Text, Callback = opts.Func})
    end
    function box:AddLabel(value)
        local label = section:AddLabel(value)
        local result = {}
        function result:SetText(text)
            label:Set(text)
            if value == "Ready. Choose your features." and Library._window then
                Library._window:SetStatus(text)
            end
        end
        function result:AddColorPicker(id, opts)
            bind(section, id, {Text = opts.Title or id, Default = opts.Default}, "AddColorPicker")
            return self
        end
        return result
    end
    function box:AddToggle(id, opts) return bind(section, id, opts, "AddToggle") end
    function box:AddInput(id, opts) return bind(section, id, opts, "AddTextbox") end
    function box:AddSlider(id, opts)
        return bind(section, id, opts, "AddSlider", {
            Min = opts.Min, Max = opts.Max, Increment = 10 ^ -(opts.Rounding or 0),
        })
    end
    function box:AddDropdown(id, opts)
        return bind(section, id, opts, "AddDropdown", {Options = opts.Values or {}})
    end
    return box
end

function Library:CreateWindow(opts)
    assert(not self._window, "ZincAdapter: window already created")
    local zincWindow = Zinc:CreateWindow({
        Title = opts.Title or "Zinc Hub", Subtitle = opts.Footer or "Mr H",
        Theme = "XP", ToggleKey = Enum.KeyCode.RightControl,
    })
    self._window = zincWindow
    local originalDestroy = zincWindow.Destroy
    zincWindow.Destroy = function()
        Library:Unload()
    end
    self._destroyView = function() originalDestroy(zincWindow) end
    local view = {}
    function view:AddTab(name)
        local zincTab = zincWindow:CreateTab(name)
        local tab = {}
        function tab:AddLeftGroupbox(title) return wrapSection(zincTab:CreateSection(title)) end
        function tab:AddRightGroupbox(title) return wrapSection(zincTab:CreateSection(title)) end
        function tab:AddLeftTabbox()
            return {AddTab = function(_, title)
                return wrapSection(zincTab:CreateSection(title))
            end}
        end
        function tab:AddRightTabbox() return self:AddLeftTabbox() end
        return tab
    end
    return view
end

function Library:Notify(opts)
    if self._window and not self._unloaded then
        self._window:Notify({Title = opts.Title, Content = opts.Description,
            Duration = opts.Time})
    end
end

function Library:OnUnload(callback)
    self._onUnload = callback
end

function Library:Unload()
    if self._unloaded then return end
    self._unloaded = true
    if self._onUnload then self._onUnload() end
    if self._destroyView then self._destroyView() end
    self._window = nil
    table.clear(self.Options)
end

return Library
