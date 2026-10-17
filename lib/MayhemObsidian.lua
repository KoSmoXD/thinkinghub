-- Zinc Hub | Obsidian facade for the DOORS MAYHEM game adapter
-- Exposes the ZincUI window/tab/section methods used by doors_mayhem.lua.
local sourceURL = "https://raw.githubusercontent.com/deividcomsono/Obsidian/d62041eda54085a03259c789d4af2be76077379f/Library.lua"
local ok, source = pcall(function() return game:HttpGet(sourceURL) end)
assert(ok and type(source) == "string", "Mayhem Obsidian: failed to download library")
local chunk, err = loadstring(source, "@Mayhem/Obsidian")
assert(chunk, err)
local Library = chunk()
assert(type(Library) == "table" and type(Library.CreateWindow) == "function",
    "Mayhem Obsidian: invalid library API")
local Adapter = {}
local counter = 0
local function makeId()
    counter = counter + 1
    return "MH_MAYHEM_" .. tostring(counter)
end
local function bind(control, callback)
    if callback then control:OnChanged(callback) end
    return control
end
function Adapter:CreateWindow(opts)
    local actual = Library:CreateWindow({
        Title = opts.Title or "Zinc Hub",
        Footer = opts.Subtitle or "DOORS: MAYHEM",
        Center = true, AutoShow = true, Resizable = true,
        NotifySide = "Right", ShowCustomCursor = false,
    })
    local wrapper = {actual = actual, status = nil, statusMessage = "Ready"}
    function wrapper:CreateTab(name)
        local rawTab = actual:AddTab(name)
        local sideCount = 0
        local tab = {}
        function tab:CreateSection(title)
            sideCount = sideCount + 1
            local group
            if sideCount % 2 == 0 and type(rawTab.AddRightGroupbox) == "function" then
                group = rawTab:AddRightGroupbox(title)
            elseif type(rawTab.AddLeftGroupbox) == "function" then
                group = rawTab:AddLeftGroupbox(title)
            else
                group = rawTab:AddLeftTabbox():AddTab(title)
            end
            local section = {}
            if name == "Home" and not wrapper.status then
                wrapper.status = group:AddLabel(wrapper.statusMessage, true)
            end
            function section:AddLabel(text)
                local label = group:AddLabel(tostring(text), true)
                return {Set = function(_, value) label:SetText(tostring(value)) end}
            end
            function section:AddButton(opts)
                return group:AddButton({
                    Text = opts.Name, Func = opts.Callback,
                })
            end
            function section:AddToggle(opts)
                return bind(group:AddToggle(makeId(), {
                    Text = opts.Name, Default = opts.Default == true,
                }), opts.Callback)
            end
            function section:AddDropdown(opts)
                return bind(group:AddDropdown(makeId(), {
                    Text = opts.Name, Values = opts.Options or {},
                    Default = opts.Default, Multi = false,
                }), opts.Callback)
            end
            function section:AddTextbox(opts)
                return bind(group:AddInput(makeId(), {
                    Text = opts.Name, Default = opts.Default or "",
                    Placeholder = opts.Placeholder,
                    Finished = true, ClearTextOnFocus = false,
                }), opts.Callback)
            end
            function section:AddSlider(opts)
                return bind(group:AddSlider(makeId(), {
                    Text = opts.Name, Min = opts.Min, Max = opts.Max,
                    Default = opts.Default, Rounding = 0,
                }), opts.Callback)
            end
            return section
        end
        return tab
    end
    function wrapper:SetStatus(message)
        self.statusMessage = tostring(message)
        if self.status then self.status:SetText(self.statusMessage) end
    end
    function wrapper:SetTheme(_) end -- Obsidian's theme is managed by itself.
    function wrapper:Notify(opts)
        Library:Notify({
            Title = opts.Title or "Zinc Hub",
            Description = opts.Content or "",
            Time = opts.Duration or 4,
        })
    end
    function wrapper:Destroy() Library:Unload() end
    Library:OnUnload(function()
        if type(wrapper.Destroy) == "function" then wrapper:Destroy() end
    end)
    return wrapper
end
return Adapter
