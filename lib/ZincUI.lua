-- ZincUI v0.1.0
-- Client-side Roblox Luau UI library. No third-party dependencies.
-- Run from a LocalScript, or load the returned library through loadstring.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local Zinc = {
    Version = "0.1.0",
    Themes = {
        Dark = {
            Background = Color3.fromRGB(16, 19, 26),
            Sidebar = Color3.fromRGB(20, 24, 32),
            Surface = Color3.fromRGB(27, 32, 42),
            Elevated = Color3.fromRGB(35, 41, 53),
            Border = Color3.fromRGB(51, 59, 73),
            Text = Color3.fromRGB(242, 244, 249),
            Muted = Color3.fromRGB(153, 163, 180),
            Accent = Color3.fromRGB(125, 99, 255),
        },
        Midnight = {
            Background = Color3.fromRGB(9, 13, 26),
            Sidebar = Color3.fromRGB(12, 18, 35),
            Surface = Color3.fromRGB(19, 27, 45),
            Elevated = Color3.fromRGB(29, 40, 62),
            Border = Color3.fromRGB(48, 66, 92),
            Text = Color3.fromRGB(237, 245, 255),
            Muted = Color3.fromRGB(150, 169, 194),
            Accent = Color3.fromRGB(68, 165, 255),
        },
    },
    _windows = {},
}

local Window = {}
Window.__index = Window
local Tab = {}
Tab.__index = Tab
local Section = {}
Section.__index = Section

local function make(className, props, parent)
    local object = Instance.new(className)
    for key, value in pairs(props or {}) do
        object[key] = value
    end
    object.Parent = parent
    return object
end

local function corner(object, radius)
    make("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, object)
    return object
end

local function textLabel(parent, props)
    local defaults = {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }
    for k, v in pairs(props or {}) do defaults[k] = v end
    return make("TextLabel", defaults, parent)
end

local function clickButton(parent, props)
    local defaults = {
        AutoButtonColor = false,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
    }
    for k, v in pairs(props or {}) do defaults[k] = v end
    return make("TextButton", defaults, parent)
end

local function call(callback, ...)
    if type(callback) ~= "function" then return end
    local ok, err = pcall(callback, ...)
    if not ok then warn("[ZincUI] callback failed: " .. tostring(err)) end
end

local function copyTheme(theme)
    local copy = {}
    for key, value in pairs(Zinc.Themes.Dark) do copy[key] = value end
    for key, value in pairs(theme) do
        assert(typeof(value) == "Color3", "ZincUI theme field " .. tostring(key) .. " must be Color3")
        copy[key] = value
    end
    return copy
end

local function resolveTheme(value)
    if value == nil then return copyTheme(Zinc.Themes.Dark) end
    if type(value) == "string" then
        assert(Zinc.Themes[value], "ZincUI: unknown theme " .. value)
        return copyTheme(Zinc.Themes[value])
    end
    assert(type(value) == "table", "ZincUI: Theme must be a name or color table")
    return copyTheme(value)
end

function Window:_connect(signal, handler)
    local connection = signal:Connect(handler)
    table.insert(self._connections, connection)
    return connection
end

function Window:_bind(object, propertyMap)
    table.insert(self._bindings, { object = object, props = propertyMap })
    for property, colorKey in pairs(propertyMap) do
        object[property] = self._theme[colorKey]
    end
end

function Window:_onThemeChanged(handler)
    table.insert(self._dynamicColors, handler)
    handler()
end

function Window:SetTheme(theme)
    assert(not self._destroyed, "ZincUI: window destroyed")
    self._theme = resolveTheme(theme)
    for _, entry in ipairs(self._bindings) do
        if entry.object.Parent then
            for property, key in pairs(entry.props) do
                entry.object[property] = self._theme[key]
            end
        end
    end
    for _, handler in ipairs(self._dynamicColors) do handler() end
end

function Window:SetAccent(color)
    assert(typeof(color) == "Color3", "ZincUI: accent must be Color3")
    local updated = copyTheme(self._theme)
    updated.Accent = color
    self:SetTheme(updated)
end

function Window:Toggle(force)
    if self._destroyed then return end
    if force == nil then
        self._main.Visible = not self._main.Visible
    else
        self._main.Visible = not not force
    end
end

function Window:Minimize(force)
    if self._destroyed then return end
    if force == nil then force = not self._minimized end
    self._minimized = not not force
    self._main.Size = self._minimized
        and UDim2.new(self._fullSize.X.Scale, self._fullSize.X.Offset, 0, 54)
        or self._fullSize
    self._sidebar.Visible = not self._minimized
    self._contentHost.Visible = not self._minimized
    self._minimizeButton.Text = self._minimized and "+" or "−"
end

function Window:Destroy()
    if self._destroyed then return end
    self._destroyed = true
    for _, connection in ipairs(self._connections) do
        connection:Disconnect()
    end
    self._gui:Destroy()
    for i = #Zinc._windows, 1, -1 do
        if Zinc._windows[i] == self then table.remove(Zinc._windows, i) end
    end
    self._connections = {}
    self._bindings = {}
    self._dynamicColors = {}
    self._flags = {}
end

function Window:_register(flag, kind, controller)
    if flag == nil then return end
    assert(type(flag) == "string" and flag ~= "", "ZincUI: Flag must be a nonempty string")
    assert(self._flags[flag] == nil, "ZincUI: duplicate flag " .. flag)
    self._flags[flag] = { kind = kind, control = controller }
end

function Window:GetFlag(flag)
    local record = self._flags[flag]
    if not record then return nil end
    return record.control:Get()
end

function Window:SetFlag(flag, value, silent)
    local record = self._flags[flag]
    assert(record, "ZincUI: flag not found: " .. tostring(flag))
    record.control:Set(value, silent)
end

function Window:ExportConfig()
    local values = {}
    for flag, record in pairs(self._flags) do
        local value = record.control:Get()
        if record.kind == "color" then
            values[flag] = {
                math.round(value.R * 255),
                math.round(value.G * 255),
                math.round(value.B * 255),
            }
        elseif record.kind == "keybind" then
            values[flag] = value.Name
        elseif value ~= nil then
            values[flag] = value
        end
    end
    return HttpService:JSONEncode({ version = 1, flags = values })
end

function Window:ImportConfig(json, silent)
    assert(type(json) == "string", "ZincUI: config must be JSON text")
    local ok, decoded = pcall(function() return HttpService:JSONDecode(json) end)
    if not ok or type(decoded) ~= "table" or type(decoded.flags) ~= "table" then
        return false, "invalid ZincUI config"
    end
    local failed = {}
    for flag, value in pairs(decoded.flags) do
        if self._flags[flag] then
            local success, err = pcall(function()
                self:SetFlag(flag, value, silent)
            end)
            if not success then table.insert(failed, flag .. ": " .. tostring(err)) end
        end
    end
    if #failed > 0 then return false, table.concat(failed, "; ") end
    return true
end

function Window:Notify(opts)
    if self._destroyed then return end
    opts = opts or {}
    local toast = corner(make("Frame", {
        Size = UDim2.new(1, 0, 0, 66),
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
    }, self._notifications), 9)
    self:_bind(toast, { BackgroundColor3 = "Elevated" })
    local bar = make("Frame", {
        Size = UDim2.fromOffset(4, 44),
        Position = UDim2.fromOffset(10, 11),
        BorderSizePixel = 0,
    }, toast)
    corner(bar, 3)
    self:_bind(bar, { BackgroundColor3 = "Accent" })
    local title = textLabel(toast, {
        Position = UDim2.fromOffset(23, 8),
        Size = UDim2.new(1, -32, 0, 22),
        Font = Enum.Font.GothamBold,
        Text = tostring(opts.Title or "ZincUI"),
        TextSize = 13,
    })
    self:_bind(title, { TextColor3 = "Text" })
    local message = textLabel(toast, {
        Position = UDim2.fromOffset(23, 30),
        Size = UDim2.new(1, -32, 0, 27),
        Text = tostring(opts.Content or opts.Message or ""),
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextSize = 11,
    })
    self:_bind(message, { TextColor3 = "Muted" })
    task.delay(math.max(0.5, tonumber(opts.Duration) or 3), function()
        if toast.Parent then toast:Destroy() end
    end)
    return toast
end

function Zinc:Notify(opts)
    for i = #self._windows, 1, -1 do
        if not self._windows[i]._destroyed then
            return self._windows[i]:Notify(opts)
        end
    end
end

function Zinc:CreateWindow(options)
    options = options or {}
    assert(type(options) == "table", "ZincUI: CreateWindow expects a table")
    local fullSize = options.Size or UDim2.fromOffset(680, 460)
    assert(typeof(fullSize) == "UDim2", "ZincUI: Size must be UDim2")
    local player = Players.LocalPlayer
    assert(player, "ZincUI must run on the Roblox client")

    local guiParent = options.Parent
    if not guiParent then
        local ok, result = pcall(function()
            if type(gethui) == "function" then return gethui() end
            return nil
        end)
        guiParent = (ok and result) or player:WaitForChild("PlayerGui")
    end

    local self = setmetatable({
        _theme = resolveTheme(options.Theme),
        _connections = {},
        _bindings = {},
        _dynamicColors = {},
        _flags = {},
        _tabs = {},
        _activeTab = nil,
        _fullSize = fullSize,
        _destroyed = false,
        _minimized = false,
        _capturingKeybind = false,
    }, Window)

    local gui = make("ScreenGui", {
        Name = "ZincUI_" .. HttpService:GenerateGUID(false),
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = tonumber(options.DisplayOrder) or 50,
    }, guiParent)
    self._gui = gui

    local main = corner(make("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = fullSize,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Active = true,
    }, gui), 12)
    self._main = main
    self:_bind(main, { BackgroundColor3 = "Background" })
    local mainScale = make("UIScale", { Scale = 1 }, main)

    if options.AutoScale ~= false then
        local function updateScale()
            local camera = workspace.CurrentCamera
            if not camera then return end
            local viewport = camera.ViewportSize
            local targetWidth = fullSize.X.Offset > 0 and fullSize.X.Offset or 680
            local targetHeight = fullSize.Y.Offset > 0 and fullSize.Y.Offset or 460
            mainScale.Scale = math.min(1, (viewport.X - 24) / targetWidth,
                (viewport.Y - 24) / targetHeight)
        end
        updateScale()
        local currentCamera = workspace.CurrentCamera
        if currentCamera then
            self:_connect(currentCamera:GetPropertyChangedSignal("ViewportSize"), updateScale)
        end
        self:_connect(workspace:GetPropertyChangedSignal("CurrentCamera"), function()
            updateScale()
        end)
    end

    local stroke = make("UIStroke", { Thickness = 1 }, main)
    self:_bind(stroke, { Color = "Border" })

    local header = make("Frame", {
        Size = UDim2.new(1, 0, 0, 54),
        BackgroundTransparency = 1,
        Active = true,
    }, main)
    local title = textLabel(header, {
        Position = UDim2.fromOffset(17, 7),
        Size = UDim2.new(1, -112, 0, 23),
        Text = tostring(options.Title or "Zinc UI"),
        Font = Enum.Font.GothamBold,
        TextSize = 16,
    })
    self:_bind(title, { TextColor3 = "Text" })
    local subtitle = textLabel(header, {
        Position = UDim2.fromOffset(17, 29),
        Size = UDim2.new(1, -112, 0, 16),
        Text = tostring(options.Subtitle or "custom roblox interface"),
        TextSize = 10,
    })
    self:_bind(subtitle, { TextColor3 = "Muted" })
    local minimize = corner(clickButton(header, {
        Size = UDim2.fromOffset(30, 28),
        Position = UDim2.new(1, -74, 0, 12),
        Text = "−",
        TextSize = 20,
    }), 7)
    self._minimizeButton = minimize
    self:_bind(minimize, { BackgroundColor3 = "Elevated", TextColor3 = "Text" })
    local close = corner(clickButton(header, {
        Size = UDim2.fromOffset(30, 28),
        Position = UDim2.new(1, -39, 0, 12),
        Text = "×",
        TextSize = 18,
    }), 7)
    self:_bind(close, { BackgroundColor3 = "Elevated", TextColor3 = "Text" })
    self:_connect(minimize.Activated, function() self:Minimize() end)
    self:_connect(close.Activated, function() self:Destroy() end)

    local divider = make("Frame", {
        Position = UDim2.new(0, 0, 0, 53),
        Size = UDim2.new(1, 0, 0, 1),
        BorderSizePixel = 0,
    }, main)
    self:_bind(divider, { BackgroundColor3 = "Border" })

    local sidebar = make("Frame", {
        Position = UDim2.fromOffset(0, 54),
        Size = UDim2.new(0, 170, 1, -54),
        BorderSizePixel = 0,
    }, main)
    self._sidebar = sidebar
    self:_bind(sidebar, { BackgroundColor3 = "Sidebar" })
    local tabScroll = make("ScrollingFrame", {
        Position = UDim2.fromOffset(8, 10),
        Size = UDim2.new(1, -16, 1, -20),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        CanvasSize = UDim2.fromOffset(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
    }, sidebar)
    self:_bind(tabScroll, { ScrollBarImageColor3 = "Muted" })
    make("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, tabScroll)

    local sideDivider = make("Frame", {
        Position = UDim2.fromOffset(170, 54),
        Size = UDim2.new(0, 1, 1, -54),
        BorderSizePixel = 0,
    }, main)
    self:_bind(sideDivider, { BackgroundColor3 = "Border" })

    local contentHost = make("Frame", {
        Position = UDim2.fromOffset(181, 62),
        Size = UDim2.new(1, -190, 1, -71),
        BackgroundTransparency = 1,
    }, main)
    self._contentHost = contentHost
    self._tabScroll = tabScroll

    local notifications = make("Frame", {
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -14, 1, -14),
        Size = UDim2.new(0, 272, 1, -28),
        BackgroundTransparency = 1,
        ZIndex = 10,
    }, gui)
    self._notifications = notifications
    make("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
    }, notifications)

    local dragging, dragStart, startPosition, touchDrag = false, nil, nil, nil
    self:_connect(header.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = main.Position
            touchDrag = input.UserInputType == Enum.UserInputType.Touch and input or nil
        end
    end)
    self:_connect(UserInputService.InputChanged, function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement and input ~= touchDrag then return end
        local delta = input.Position - dragStart
        main.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X,
            startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
    end)
    self:_connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input == touchDrag then
            dragging = false
            touchDrag = nil
        end
    end)

    local toggleKey = options.ToggleKey
    if toggleKey == nil then toggleKey = Enum.KeyCode.RightControl end
    if toggleKey ~= false then
        assert(typeof(toggleKey) == "EnumItem" and toggleKey.EnumType == Enum.KeyCode,
            "ZincUI: ToggleKey must be Enum.KeyCode or false")
        self:_connect(UserInputService.InputBegan, function(input, processed)
            if processed or self._capturingKeybind or UserInputService:GetFocusedTextBox() then return end
            if input.KeyCode == toggleKey then self:Toggle() end
        end)
    end

    table.insert(Zinc._windows, self)
    return self
end

function Window:CreateTab(opts)
    assert(not self._destroyed, "ZincUI: window destroyed")
    if type(opts) == "string" then opts = { Name = opts } end
    opts = opts or {}
    local name = tostring(opts.Name or "New tab")
    local button = corner(clickButton(self._tabScroll, {
        Size = UDim2.new(1, -5, 0, 38),
        Text = name,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextSize = 12,
        LayoutOrder = #self._tabs + 1,
    }), 8)
    make("UIPadding", { PaddingLeft = UDim.new(0, 12) }, button)
    self:_bind(button, { TextColor3 = "Text" })

    local page = make("ScrollingFrame", {
        Name = "Tab_" .. tostring(#self._tabs + 1),
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.fromOffset(0, 0),
        ScrollingDirection = Enum.ScrollingDirection.Y,
        Visible = false,
    }, self._contentHost)
    self:_bind(page, { ScrollBarImageColor3 = "Muted" })
    make("UIListLayout", { Padding = UDim.new(0, 11), SortOrder = Enum.SortOrder.LayoutOrder }, page)
    make("UIPadding", {
        PaddingTop = UDim.new(0, 2),
        PaddingBottom = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 8),
    }, page)

    local tab = setmetatable({
        _window = self,
        _button = button,
        _page = page,
        _sections = {},
        Name = name,
    }, Tab)
    table.insert(self._tabs, tab)
    self:_onThemeChanged(function()
        if self._activeTab == tab then
            button.BackgroundColor3 = self._theme.Accent
        else
            button.BackgroundColor3 = self._theme.Sidebar
        end
    end)
    self:_connect(button.Activated, function() tab:Select() end)
    if not self._activeTab then tab:Select() end
    return tab
end

function Tab:Select()
    local window = self._window
    for _, tab in ipairs(window._tabs) do
        tab._page.Visible = tab == self
    end
    window._activeTab = self
    for _, refresh in ipairs(window._dynamicColors) do refresh() end
end

function Tab:CreateSection(name)
    local window = self._window
    local sectionFrame = corner(make("Frame", {
        LayoutOrder = #self._sections + 1,
        Size = UDim2.new(1, -2, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BorderSizePixel = 0,
    }, self._page), 9)
    window:_bind(sectionFrame, { BackgroundColor3 = "Surface" })
    make("UIPadding", {
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
        PaddingTop = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 10),
    }, sectionFrame)
    make("UIListLayout", { Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }, sectionFrame)
    local heading = textLabel(sectionFrame, {
        Text = tostring(name or "Section"),
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        Size = UDim2.new(1, 0, 0, 23),
        LayoutOrder = 0,
    })
    window:_bind(heading, { TextColor3 = "Text" })
    local section = setmetatable({
        _window = window,
        _frame = sectionFrame,
        _nextOrder = 0,
    }, Section)
    table.insert(self._sections, section)
    return section
end

function Section:_row(height, title, description)
    self._nextOrder = self._nextOrder + 1
    local window = self._window
    local frame = corner(make("Frame", {
        Size = UDim2.new(1, 0, 0, height),
        LayoutOrder = self._nextOrder,
        BorderSizePixel = 0,
    }, self._frame), 7)
    window:_bind(frame, { BackgroundColor3 = "Elevated" })
    if title then
        local label = textLabel(frame, {
            Position = UDim2.fromOffset(11, description and 7 or 0),
            Size = UDim2.new(1, -179, 0, description and 23 or height),
            Text = tostring(title),
            Font = Enum.Font.GothamMedium,
            TextSize = 12,
        })
        window:_bind(label, { TextColor3 = "Text" })
    end
    if description then
        local desc = textLabel(frame, {
            Position = UDim2.fromOffset(11, 28),
            Size = UDim2.new(1, -20, 0, 16),
            Text = tostring(description),
            TextSize = 10,
        })
        window:_bind(desc, { TextColor3 = "Muted" })
    end
    return frame
end

function Section:AddButton(opts)
    if type(opts) == "string" then opts = { Name = opts } end
    opts = opts or {}
    local row = self:_row(opts.Description and 54 or 45, opts.Name or "Button", opts.Description)
    local action = corner(clickButton(row, {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(76, 27),
        Text = tostring(opts.ButtonText or "RUN"),
    }), 6)
    self._window:_bind(action, { BackgroundColor3 = "Accent", TextColor3 = "Text" })
    self._window:_connect(action.Activated, function() call(opts.Callback) end)
    return { Press = function() call(opts.Callback) end }
end

function Section:AddLabel(value)
    local row = self:_row(34)
    local label = textLabel(row, {
        Position = UDim2.fromOffset(11, 0),
        Size = UDim2.new(1, -22, 1, 0),
        Text = tostring(value or ""),
        TextSize = 12,
        RichText = true,
    })
    self._window:_bind(label, { TextColor3 = "Muted" })
    return { Set = function(_, text) label.Text = tostring(text or "") end }
end

function Section:AddToggle(opts)
    opts = opts or {}
    local window = self._window
    local value = not not opts.Default
    local row = self:_row(opts.Description and 54 or 45, opts.Name or "Toggle", opts.Description)
    local button = corner(clickButton(row, {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(42, 23),
        Text = "",
    }), 12)
    local dot = corner(make("Frame", {
        Size = UDim2.fromOffset(17, 17),
        Position = UDim2.fromOffset(3, 3),
        BorderSizePixel = 0,
        BackgroundColor3 = Color3.new(1, 1, 1),
    }, button), 9)
    local function refresh()
        button.BackgroundColor3 = value and window._theme.Accent or window._theme.Border
        dot.Position = UDim2.fromOffset(value and 22 or 3, 3)
    end
    window:_onThemeChanged(refresh)
    local controller = {}
    function controller:Set(newValue, silent)
        local updated = not not newValue
        local changed = value ~= updated
        value = updated
        refresh()
        if changed and not silent then call(opts.Callback, value) end
    end
    function controller:Get() return value end
    window:_connect(button.Activated, function() controller:Set(not value) end)
    window:_register(opts.Flag, "toggle", controller)
    return controller
end

local function sliderControl(section, opts)
    local window = section._window
    local minimum = tonumber(opts.Min) or 0
    local maximum = tonumber(opts.Max) or 100
    local increment = tonumber(opts.Increment) or 1
    assert(maximum > minimum and increment > 0, "ZincUI slider: Max must exceed Min; Increment > 0")
    local value = minimum
    local row = section:_row(70, opts.Name or "Slider", opts.Description)
    local display = textLabel(row, {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -12, 0, 7),
        Size = UDim2.fromOffset(90, 20),
        TextXAlignment = Enum.TextXAlignment.Right,
        TextSize = 12,
    })
    window:_bind(display, { TextColor3 = "Accent" })
    local track = corner(make("Frame", {
        Position = UDim2.new(0, 12, 0, 51),
        Size = UDim2.new(1, -24, 0, 7),
        BorderSizePixel = 0,
    }, row), 5)
    window:_bind(track, { BackgroundColor3 = "Border" })
    local fill = corner(make("Frame", {
        Size = UDim2.fromScale(0, 1),
        BorderSizePixel = 0,
    }, track), 5)
    window:_bind(fill, { BackgroundColor3 = "Accent" })
    local hitbox = clickButton(row, {
        Position = UDim2.new(0, 12, 0, 42),
        Size = UDim2.new(1, -24, 0, 25),
        BackgroundTransparency = 1,
        Text = "",
    })
    local controller = {}
    function controller:Set(newValue, silent)
        assert(tonumber(newValue), "ZincUI slider requires a number")
        local rounded = minimum + math.floor(((tonumber(newValue) - minimum) / increment) + 0.5) * increment
        local updated = math.clamp(rounded, minimum, maximum)
        local changed = updated ~= value
        value = updated
        display.Text = string.format("%g", value)
        fill.Size = UDim2.fromScale((value - minimum) / (maximum - minimum), 1)
        if changed and not silent then call(opts.Callback, value) end
    end
    function controller:Get() return value end
    local function updateAt(position)
        local width = math.max(1, track.AbsoluteSize.X)
        controller:Set(minimum + (math.clamp((position.X - track.AbsolutePosition.X) / width, 0, 1)
            * (maximum - minimum)))
    end
    local dragging = false
    local touch = nil
    window:_connect(hitbox.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            touch = input.UserInputType == Enum.UserInputType.Touch and input or nil
            updateAt(input.Position)
        end
    end)
    window:_connect(UserInputService.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input == touch) then
            updateAt(input.Position)
        end
    end)
    window:_connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input == touch then
            dragging = false
            touch = nil
        end
    end)
    controller:Set(opts.Default ~= nil and opts.Default or minimum, true)
    window:_register(opts.Flag, "slider", controller)
    return controller
end

function Section:AddSlider(opts)
    return sliderControl(self, opts or {})
end

function Section:AddDropdown(opts)
    opts = opts or {}
    local window = self._window
    local values = opts.Options or {}
    assert(type(values) == "table", "ZincUI dropdown: Options must be a table")
    local selected = nil
    local expanded = false
    local row = self:_row(54, opts.Name or "Dropdown", opts.Description)
    local chooser = corner(clickButton(row, {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -10, 0, 11),
        Size = UDim2.fromOffset(153, 31),
        Text = "select  ▾",
        TextTruncate = Enum.TextTruncate.AtEnd,
    }), 6)
    window:_bind(chooser, { BackgroundColor3 = "Surface", TextColor3 = "Text" })
    local choices = make("ScrollingFrame", {
        Position = UDim2.fromOffset(10, 51),
        Size = UDim2.new(1, -20, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.fromOffset(0, 0),
        Visible = false,
        ScrollingDirection = Enum.ScrollingDirection.Y,
    }, row)
    window:_bind(choices, { ScrollBarImageColor3 = "Muted" })
    make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, choices)
    local controller = {}
    local function contains(candidate)
        for _, entry in ipairs(values) do
            if entry == candidate then return true end
        end
        return false
    end
    local function updateOpen()
        local height = math.min(#values, 5) * 31
        choices.Visible = expanded and #values > 0
        choices.Size = UDim2.new(1, -20, 0, height)
        row.Size = UDim2.new(1, 0, 0, (expanded and #values > 0) and (58 + height) or 54)
    end
    local function updateText()
        chooser.Text = (selected == nil and "select" or tostring(selected)) .. "  ▾"
    end
    function controller:Set(value, silent)
        assert(value == nil or contains(value), "ZincUI dropdown: invalid option " .. tostring(value))
        local changed = selected ~= value
        selected = value
        updateText()
        if changed and not silent then call(opts.Callback, selected) end
    end
    function controller:Get() return selected end
    function controller:Refresh(nextValues, keepSelection)
        assert(type(nextValues) == "table", "ZincUI dropdown: Options must be a table")
        values = nextValues
        for _, child in ipairs(choices:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
        for i, option in ipairs(values) do
            local optionButton = corner(clickButton(choices, {
                LayoutOrder = i,
                Size = UDim2.new(1, -4, 0, 28),
                Text = tostring(option),
                TextXAlignment = Enum.TextXAlignment.Left,
            }), 5)
            make("UIPadding", { PaddingLeft = UDim.new(0, 10) }, optionButton)
            window:_bind(optionButton, { BackgroundColor3 = "Surface", TextColor3 = "Text" })
            window:_connect(optionButton.Activated, function()
                controller:Set(option)
                expanded = false
                updateOpen()
            end)
        end
        if not keepSelection or not contains(selected) then controller:Set(nil, true) end
        updateText()
        updateOpen()
    end
    window:_connect(chooser.Activated, function()
        expanded = not expanded
        updateOpen()
    end)
    controller:Refresh(values)
    if opts.Default ~= nil then controller:Set(opts.Default, true) end
    window:_register(opts.Flag, "dropdown", controller)
    return controller
end

function Section:AddTextbox(opts)
    opts = opts or {}
    local window = self._window
    local value = tostring(opts.Default or "")
    local row = self:_row(opts.Description and 54 or 45, opts.Name or "Textbox", opts.Description)
    local input = corner(make("TextBox", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(160, 29),
        BorderSizePixel = 0,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        Text = value,
        PlaceholderText = tostring(opts.Placeholder or "enter text..."),
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row), 6)
    make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, input)
    window:_bind(input, { BackgroundColor3 = "Surface", TextColor3 = "Text", PlaceholderColor3 = "Muted" })
    local controller = {}
    function controller:Set(newValue, silent)
        local updated = tostring(newValue or "")
        local changed = updated ~= value
        value = updated
        input.Text = value
        if changed and not silent then call(opts.Callback, value) end
    end
    function controller:Get() return value end
    window:_connect(input.FocusLost, function()
        controller:Set(input.Text)
    end)
    window:_register(opts.Flag, "textbox", controller)
    return controller
end

function Section:AddKeybind(opts)
    opts = opts or {}
    local window = self._window
    local key = opts.Default or Enum.KeyCode.F
    assert(typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode,
        "ZincUI keybind: Default must be Enum.KeyCode")
    local waiting = false
    local row = self:_row(45, opts.Name or "Keybind")
    local button = corner(clickButton(row, {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(117, 28),
        Text = key.Name,
    }), 6)
    window:_bind(button, { BackgroundColor3 = "Surface", TextColor3 = "Text" })
    local controller = {}
    function controller:Set(nextKey, silent)
        if type(nextKey) == "string" then nextKey = Enum.KeyCode[nextKey] end
        assert(typeof(nextKey) == "EnumItem" and nextKey.EnumType == Enum.KeyCode,
            "ZincUI keybind: invalid KeyCode")
        local changed = key ~= nextKey
        key = nextKey
        button.Text = key.Name
        if changed and not silent then call(opts.OnChanged, key) end
    end
    function controller:Get() return key end
    window:_connect(button.Activated, function()
        if window._capturingKeybind then return end
        waiting = true
        window._capturingKeybind = true
        button.Text = "press key..."
    end)
    window:_connect(UserInputService.InputBegan, function(input, processed)
        if waiting then
            if input.KeyCode ~= Enum.KeyCode.Unknown then
                waiting = false
                window._capturingKeybind = false
                if input.KeyCode == Enum.KeyCode.Escape then
                    button.Text = key.Name
                else
                    controller:Set(input.KeyCode)
                end
            end
        elseif not processed and not window._capturingKeybind and not UserInputService:GetFocusedTextBox()
            and input.KeyCode == key then
            call(opts.Callback, key)
        end
    end)
    window:_register(opts.Flag, "keybind", controller)
    return controller
end

function Section:AddColorPicker(opts)
    opts = opts or {}
    local window = self._window
    local value = opts.Default or Color3.fromRGB(255, 255, 255)
    assert(typeof(value) == "Color3", "ZincUI color picker: Default must be Color3")
    local expanded = false
    local row = self:_row(52, opts.Name or "Color", opts.Description)
    local preview = corner(clickButton(row, {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -10, 0, 9),
        Size = UDim2.fromOffset(112, 31),
        Text = "EDIT  ▾",
    }), 6)
    local swatch = corner(make("Frame", {
        Position = UDim2.fromOffset(7, 7),
        Size = UDim2.fromOffset(18, 17),
        BorderSizePixel = 0,
    }, preview), 4)
    window:_bind(preview, { BackgroundColor3 = "Surface", TextColor3 = "Text" })
    local channels = {}
    local controller = {}
    local function channelValue(channel)
        local component = channel == "R" and value.R or (channel == "G" and value.G or value.B)
        return math.round(component * 255)
    end
    local function refresh()
        swatch.BackgroundColor3 = value
        for channel, data in pairs(channels) do
            local n = channelValue(channel)
            data.label.Text = string.format("%s  %d", channel, n)
            data.fill.Size = UDim2.fromScale(n / 255, 1)
        end
    end
    function controller:Set(color, silent)
        if type(color) == "table" then
            color = Color3.fromRGB(tonumber(color[1]) or 0,
                tonumber(color[2]) or 0, tonumber(color[3]) or 0)
        end
        assert(typeof(color) == "Color3", "ZincUI color picker: value must be Color3")
        local changed = value ~= color
        value = color
        refresh()
        if changed and not silent then call(opts.Callback, value) end
    end
    function controller:Get() return value end
    for index, channel in ipairs({ "R", "G", "B" }) do
        local y = 52 + (index - 1) * 32
        local label = textLabel(row, {
            Position = UDim2.fromOffset(11, y),
            Size = UDim2.fromOffset(65, 25),
            Text = channel,
            TextSize = 11,
            Visible = false,
        })
        window:_bind(label, { TextColor3 = "Text" })
        local track = corner(make("Frame", {
            Position = UDim2.new(0, 88, 0, y + 10),
            Size = UDim2.new(1, -100, 0, 6),
            BorderSizePixel = 0,
            Visible = false,
        }, row), 4)
        window:_bind(track, { BackgroundColor3 = "Border" })
        local fill = corner(make("Frame", {
            Size = UDim2.fromScale(0, 1),
            BorderSizePixel = 0,
        }, track), 4)
        window:_bind(fill, { BackgroundColor3 = "Accent" })
        local hit = clickButton(row, {
            Position = UDim2.new(0, 88, 0, y + 2),
            Size = UDim2.new(1, -100, 0, 23),
            BackgroundTransparency = 1,
            Text = "",
            Visible = false,
        })
        channels[channel] = { label = label, track = track, fill = fill, hit = hit }
        local dragging, touch = false, nil
        local function updateAt(position)
            local width = math.max(1, track.AbsoluteSize.X)
            local amount = math.round(math.clamp((position.X - track.AbsolutePosition.X) / width, 0, 1) * 255)
            local r, g, b = channelValue("R"), channelValue("G"), channelValue("B")
            if channel == "R" then r = amount elseif channel == "G" then g = amount else b = amount end
            controller:Set(Color3.fromRGB(r, g, b))
        end
        window:_connect(hit.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                touch = input.UserInputType == Enum.UserInputType.Touch and input or nil
                updateAt(input.Position)
            end
        end)
        window:_connect(UserInputService.InputChanged, function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input == touch) then
                updateAt(input.Position)
            end
        end)
        window:_connect(UserInputService.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input == touch then
                dragging = false
                touch = nil
            end
        end)
    end
    local function showChannels()
        row.Size = UDim2.new(1, 0, 0, expanded and 155 or 52)
        for _, item in pairs(channels) do
            item.label.Visible = expanded
            item.track.Visible = expanded
            item.hit.Visible = expanded
        end
    end
    window:_connect(preview.Activated, function()
        expanded = not expanded
        showChannels()
    end)
    refresh()
    window:_register(opts.Flag, "color", controller)
    return controller
end

return Zinc