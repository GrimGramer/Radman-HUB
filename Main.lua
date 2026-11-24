--[[
    RADMAN HUB v1.0
    Roblox Studio companion interface
    Place this LocalScript in StarterPlayer > StarterPlayerScripts.

    This is a local companion UI and task-priority planner.
    It does NOT automate or modify the original Blox Fruits experience.
    Game-specific actions require an authorized API in an experience you own.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--==================================================
-- THEME / CONFIG
--==================================================

local Theme = {
    Background = Color3.fromRGB(14, 14, 17),
    Sidebar = Color3.fromRGB(19, 19, 23),
    Panel = Color3.fromRGB(27, 27, 32),
    Element = Color3.fromRGB(34, 34, 41),
    Accent = Color3.fromRGB(112, 83, 205),
    AccentLight = Color3.fromRGB(145, 119, 232),
    Text = Color3.fromRGB(245, 245, 248),
    Muted = Color3.fromRGB(155, 155, 166),
    Green = Color3.fromRGB(105, 195, 130),
    Red = Color3.fromRGB(210, 90, 95),
}

local Config = {
    Scale = 0.90,
    Animations = true,
    CompactRows = false,
    SelectedTab = "Main",
    HasHallowScythe = false,
    Tasks = {
        ["Farm Level"] = {Enabled = true, BasePriority = 3},
        ["Pirate Raid"] = {Enabled = false, BasePriority = 1},
        ["Auto Soul Reaper"] = {Enabled = false, BasePriority = 4},
    }
}

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, child in pairs(value) do
        result[key] = deepCopy(child)
    end
    return result
end

--==================================================
-- CLEANUP
--==================================================

local connections = {}
local destroyed = false

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local function cleanup()
    if destroyed then return end
    destroyed = true

    for _, connection in ipairs(connections) do
        if connection.Connected then
            connection:Disconnect()
        end
    end
    table.clear(connections)
end

--==================================================
-- PRIORITY MANAGER
-- Smaller number = higher priority.
-- Conditions are local/manual until an authorized data source exists.
--==================================================

local PriorityManager = {}

function PriorityManager:GetPriority(taskName)
    local taskData = Config.Tasks[taskName]
    if not taskData then
        return 4
    end

    if taskName == "Auto Soul Reaper" and Config.HasHallowScythe then
        return 2
    end

    return taskData.BasePriority or 4
end

function PriorityManager:GetQueue()
    local queue = {}

    for name, data in pairs(Config.Tasks) do
        if data.Enabled then
            table.insert(queue, {
                Name = name,
                Priority = self:GetPriority(name)
            })
        end
    end

    table.sort(queue, function(a, b)
        if a.Priority == b.Priority then
            return a.Name < b.Name
        end
        return a.Priority < b.Priority
    end)

    return queue
end

--==================================================
-- GUI HELPERS
--==================================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RadmanHub"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local window = Instance.new("Frame")
window.Name = "Window"
window.Size = UDim2.fromOffset(850, 570)
window.Position = UDim2.new(0.5, -425, 0.5, -285)
window.BackgroundColor3 = Theme.Background
window.BorderSizePixel = 0
window.ClipsDescendants = true
window.Parent = screenGui

local windowCorner = Instance.new("UICorner")
windowCorner.CornerRadius = UDim.new(0, 12)
windowCorner.Parent = window

local windowStroke = Instance.new("UIStroke")
windowStroke.Color = Color3.fromRGB(55, 48, 72)
windowStroke.Transparency = 0.25
windowStroke.Parent = window

local uiScale = Instance.new("UIScale")
uiScale.Scale = Config.Scale
uiScale.Parent = window

local function make(className, properties, parent)
    local object = Instance.new(className)
    for key, value in pairs(properties) do
        object[key] = value
    end
    object.Parent = parent
    return object
end

local function corner(object, radius)
    make("UICorner", {
        CornerRadius = UDim.new(0, radius or 8)
    }, object)
end

local function tween(object, properties, duration)
    if not Config.Animations then
        for key, value in pairs(properties) do
            object[key] = value
        end
        return
    end

    TweenService:Create(
        object,
        TweenInfo.new(duration or 0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        properties
    ):Play()
end

--==================================================
-- TOP BAR
--==================================================

local topbar = make("Frame", {
    Name = "Topbar",
    Size = UDim2.new(1, 0, 0, 46),
    BackgroundColor3 = Theme.Sidebar,
    BorderSizePixel = 0
}, window)

local title = make("TextLabel", {
    Position = UDim2.fromOffset(16, 0),
    Size = UDim2.new(0, 210, 1, 0),
    BackgroundTransparency = 1,
    Text = "RADMAN HUB",
    TextColor3 = Theme.Text,
    Font = Enum.Font.GothamBold,
    TextSize = 17,
    TextXAlignment = Enum.TextXAlignment.Left
}, topbar)

make("TextLabel", {
    Position = UDim2.fromOffset(155, 1),
    Size = UDim2.fromOffset(150, 44),
    BackgroundTransparency = 1,
    Text = "Blox Fruits",
    TextColor3 = Theme.Muted,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left
}, topbar)

local minimizeButton = make("TextButton", {
    Size = UDim2.fromOffset(34, 34),
    Position = UDim2.new(1, -78, 0, 6),
    BackgroundTransparency = 1,
    Text = "−",
    TextColor3 = Theme.Text,
    Font = Enum.Font.Gotham,
    TextSize = 24,
    AutoButtonColor = false
}, topbar)

local closeButton = make("TextButton", {
    Size = UDim2.fromOffset(34, 34),
    Position = UDim2.new(1, -40, 0, 6),
    BackgroundTransparency = 1,
    Text = "×",
    TextColor3 = Theme.Text,
    Font = Enum.Font.Gotham,
    TextSize = 25,
    AutoButtonColor = false
}, topbar)

--==================================================
-- BODY / SIDEBAR / CONTENT
--==================================================

local body = make("Frame", {
    Name = "Body",
    Position = UDim2.fromOffset(0, 46),
    Size = UDim2.new(1, 0, 1, -46),
    BackgroundTransparency = 1
}, window)

local sidebar = make("Frame", {
    Size = UDim2.new(0, 195, 1, 0),
    BackgroundColor3 = Theme.Sidebar,
    BorderSizePixel = 0
}, body)

local sidePadding = make("UIPadding", {
    PaddingTop = UDim.new(0, 12),
    PaddingLeft = UDim.new(0, 10),
    PaddingRight = UDim.new(0, 10)
}, sidebar)

local sideLayout = make("UIListLayout", {
    Padding = UDim.new(0, 7),
    SortOrder = Enum.SortOrder.LayoutOrder
}, sidebar)

local content = make("Frame", {
    Position = UDim2.new(0, 195, 0, 0),
    Size = UDim2.new(1, -195, 1, 0),
    BackgroundTransparency = 1
}, body)

local search = make("TextBox", {
    Position = UDim2.fromOffset(15, 12),
    Size = UDim2.new(1, -30, 0, 36),
    BackgroundColor3 = Theme.Element,
    Text = "",
    PlaceholderText = "Search functions...",
    PlaceholderColor3 = Theme.Muted,
    TextColor3 = Theme.Text,
    Font = Enum.Font.Gotham,
    TextSize = 13,
    ClearTextOnFocus = false
}, content)
corner(search, 8)

local pageTitle = make("TextLabel", {
    Position = UDim2.fromOffset(16, 58),
    Size = UDim2.new(1, -32, 0, 30),
    BackgroundTransparency = 1,
    Text = "Main",
    TextColor3 = Theme.Text,
    Font = Enum.Font.GothamBold,
    TextSize = 20,
    TextXAlignment = Enum.TextXAlignment.Left
}, content)

local page = make("ScrollingFrame", {
    Position = UDim2.fromOffset(15, 98),
    Size = UDim2.new(1, -30, 1, -112),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = Theme.Accent,
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y
}, content)

local pageLayout = make("UIListLayout", {
    Padding = UDim.new(0, 8),
    SortOrder = Enum.SortOrder.LayoutOrder
}, page)

--==================================================
-- DRAGGING
--==================================================

local dragging = false
local dragInput
local dragStart
local startPosition

connect(topbar.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPosition = window.Position
        dragInput = input
    end
end)

connect(UserInputService.InputChanged, function(input)
    if not dragging then return end

    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
        local delta = input.Position - dragStart
        window.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
    end
end)

connect(UserInputService.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
        dragInput = nil
    end
end)

--==================================================
-- CLOSE / MINIMIZE
--==================================================

local minimized = false
local fullSize = UDim2.fromOffset(850, 570)

connect(minimizeButton.MouseButton1Click, function()
    minimized = not minimized
    body.Visible = not minimized
    minimizeButton.Text = minimized and "+" or "−"
    tween(window, {
        Size = minimized and UDim2.fromOffset(850, 46) or fullSize
    })
end)

connect(closeButton.MouseButton1Click, function()
    if destroyed then return end
    tween(window, {BackgroundTransparency = 1}, 0.15)
    task.delay(0.17, function()
        cleanup()
        screenGui:Destroy()
    end)
end)

--==================================================
-- CONTROL BUILDERS
--==================================================

local controlRegistry = {}
local tabButtons = {}
local selectedTab = "Main"
local refreshCurrentPage

local function clearPage()
    for _, child in ipairs(page:GetChildren()) do
        if not child:IsA("UIListLayout") then
            child:Destroy()
        end
    end
    table.clear(controlRegistry)
end

local function section(text)
    return make("TextLabel", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = Theme.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 17,
        TextXAlignment = Enum.TextXAlignment.Left
    }, page)
end

local function infoRow(labelText, valueText)
    local row = make("Frame", {
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel = 0
    }, page)
    corner(row, 8)

    make("TextLabel", {
        Position = UDim2.fromOffset(12, 0),
        Size = UDim2.new(0.55, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = labelText,
        TextColor3 = Theme.Muted,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left
    }, row)

    make("TextLabel", {
        Position = UDim2.new(0.55, 0, 0, 0),
        Size = UDim2.new(0.45, -12, 1, 0),
        BackgroundTransparency = 1,
        Text = tostring(valueText),
        TextColor3 = Theme.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Right
    }, row)

    return row
end

local function toggle(labelText, description, initialValue, callback)
    local height = Config.CompactRows and 43 or 53
    local row = make("Frame", {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel = 0
    }, page)
    corner(row, 8)

    make("TextLabel", {
        Position = UDim2.fromOffset(12, description and 5 or 0),
        Size = UDim2.new(1, -90, 0, 23),
        BackgroundTransparency = 1,
        Text = labelText,
        TextColor3 = Theme.Text,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left
    }, row)

    if description then
        make("TextLabel", {
            Position = UDim2.fromOffset(12, 27),
            Size = UDim2.new(1, -90, 0, 16),
            BackgroundTransparency = 1,
            Text = description,
            TextColor3 = Theme.Muted,
            Font = Enum.Font.Gotham,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left
        }, row)
    end

    local button = make("TextButton", {
        Position = UDim2.new(1, -60, 0.5, -13),
        Size = UDim2.fromOffset(48, 26),
        BackgroundColor3 = Theme.Element,
        Text = "",
        AutoButtonColor = false
    }, row)
    corner(button, 20)

    local knob = make("Frame", {
        Position = UDim2.fromOffset(4, 4),
        Size = UDim2.fromOffset(18, 18),
        BackgroundColor3 = Theme.Muted
    }, button)
    corner(knob, 20)

    local value = initialValue == true

    local function render()
        tween(button, {
            BackgroundColor3 = value and Theme.Accent or Theme.Element
        })
        tween(knob, {
            Position = value and UDim2.new(1, -22, 0, 4) or UDim2.fromOffset(4, 4),
            BackgroundColor3 = value and Theme.Text or Theme.Muted
        })
    end

    local function setValue(nextValue)
        value = nextValue == true
        render()
        if callback then
            local ok, err = pcall(callback, value)
            if not ok then warn("[Radman HUB] Toggle callback:", err) end
        end
    end

    connect(button.MouseButton1Click, function()
        setValue(not value)
    end)

    render()
    controlRegistry[#controlRegistry + 1] = {
        Name = labelText,
        Object = row,
        GetValue = function() return value end
    }

    return {
        Set = setValue,
        Get = function() return value end
    }
end

local function actionButton(labelText, callback)
    local button = make("TextButton", {
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundColor3 = Theme.Element,
        Text = labelText,
        TextColor3 = Theme.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        AutoButtonColor = false
    }, page)
    corner(button, 8)

    connect(button.MouseButton1Click, function()
        if callback then
            local ok, err = pcall(callback)
            if not ok then warn("[Radman HUB] Button callback:", err) end
        end
    end)

    controlRegistry[#controlRegistry + 1] = {
        Name = labelText,
        Object = button
    }

    return button
end

local function dropdown(labelText, options, defaultValue, callback)
    local holder = make("Frame", {
        Size = UDim2.new(1, 0, 0, 68),
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel = 0
    }, page)
    corner(holder, 8)

    make("TextLabel", {
        Position = UDim2.fromOffset(12, 4),
        Size = UDim2.new(1, -24, 0, 22),
        BackgroundTransparency = 1,
        Text = labelText,
        TextColor3 = Theme.Text,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left
    }, holder)

    local selected = defaultValue or options[1]
    local button = make("TextButton", {
        Position = UDim2.fromOffset(10, 31),
        Size = UDim2.new(1, -20, 0, 29),
        BackgroundColor3 = Theme.Element,
        Text = tostring(selected) .. "  ▾",
        TextColor3 = Theme.Text,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        AutoButtonColor = false
    }, holder)
    corner(button, 6)

    connect(button.MouseButton1Click, function()
        local index = table.find(options, selected) or 0
        index = (index % #options) + 1
        selected = options[index]
        button.Text = tostring(selected) .. "  ▾"
        if callback then
            local ok, err = pcall(callback, selected)
            if not ok then warn("[Radman HUB] Dropdown callback:", err) end
        end
    end)

    controlRegistry[#controlRegistry + 1] = {
        Name = labelText,
        Object = holder,
        GetValue = function() return selected end
    }

    return {
        Get = function() return selected end
    }
end

local function slider(labelText, minValue, maxValue, defaultValue, callback)
    local holder = make("Frame", {
        Size = UDim2.new(1, 0, 0, 62),
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel = 0
    }, page)
    corner(holder, 8)

    local value = math.clamp(defaultValue, minValue, maxValue)

    local label = make("TextLabel", {
        Position = UDim2.fromOffset(12, 3),
        Size = UDim2.new(1, -24, 0, 23),
        BackgroundTransparency = 1,
        Text = labelText .. ": " .. tostring(value),
        TextColor3 = Theme.Text,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left
    }, holder)

    local track = make("Frame", {
        Position = UDim2.new(0, 12, 0, 36),
        Size = UDim2.new(1, -24, 0, 8),
        BackgroundColor3 = Theme.Element,
        BorderSizePixel = 0
    }, holder)
    corner(track, 8)

    local fill = make("Frame", {
        Size = UDim2.new((value - minValue) / (maxValue - minValue), 0, 1, 0),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0
    }, track)
    corner(fill, 8)

    local hitbox = make("TextButton", {
        Position = UDim2.new(0, 0, 0, -10),
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false
    }, track)

    local function setFromX(x)
        local alpha = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        value = math.floor((minValue + (maxValue - minValue) * alpha) * 100 + 0.5) / 100
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        label.Text = labelText .. ": " .. tostring(value)
        if callback then
            local ok, err = pcall(callback, value)
            if not ok then warn("[Radman HUB] Slider callback:", err) end
        end
    end

    connect(hitbox.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            setFromX(input.Position.X)
        end
    end)

    connect(hitbox.InputChanged, function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
                setFromX(input.Position.X)
            end
        end
    end)

    controlRegistry[#controlRegistry + 1] = {
        Name = labelText,
        Object = holder,
        GetValue = function() return value end
    }

    return {
        Get = function() return value end
    }
end

--==================================================
-- PAGE CONTENT
--==================================================

local function buildMain()
    section("Player Information")
    infoRow("Username", player.Name)
    infoRow("Display Name", player.DisplayName)
    infoRow("User ID", player.UserId)

    section("Interface")
    toggle("Animations", "Enable interface transitions", Config.Animations, function(v)
        Config.Animations = v
    end)
    toggle("Compact Rows", "Reduce control height", Config.CompactRows, function(v)
        Config.CompactRows = v
    end)
end

local function buildFarming()
    section("Local Task Planner")
    infoRow("Priority rule", "1 = highest")
    toggle("Hallow Scythe condition", "Manual condition for Soul Reaper priority", Config.HasHallowScythe, function(v)
        Config.HasHallowScythe = v
        refreshCurrentPage()
    end)

    for taskName, data in pairs(Config.Tasks) do
        toggle(taskName, "Add or remove from local queue", data.Enabled, function(v)
            Config.Tasks[taskName].Enabled = v
            refreshCurrentPage()
        end)
    end

    section("Current Priority Queue")
    local queue = PriorityManager:GetQueue()
    if #queue == 0 then
        infoRow("Queue", "No enabled tasks")
    else
        for index, taskInfo in ipairs(queue) do
            infoRow(
                tostring(index) .. ". " .. taskInfo.Name,
                "Priority " .. taskInfo.Priority
            )
        end
    end

    section("Planner note")
    infoRow("Execution", "Planner only; no game automation")
end

local function buildCombat()
    section("Combat Preferences")
    dropdown("Preferred combat style", {"Melee", "Sword", "Fruit", "Gun"}, "Melee")
    dropdown("Training profile", {"Balanced", "Defensive", "Practice"}, "Balanced")
    toggle("Show combat reminders", "Local interface preference", false)
    infoRow("PvP automation", "Not available")
end

local function buildFruit()
    section("Fruit Notebook")
    dropdown("Fruit category", {"All", "Natural", "Elemental", "Beast"}, "All")
    toggle("Track fruit notes", "Enable local notebook preference", true)
    infoRow("Live inventory", "Not connected")
    infoRow("Fruit storage actions", "Not available")
end

local function buildMovement()
    section("Movement Preferences")
    dropdown("Preferred travel mode", {"Normal", "Boat", "Flight"}, "Normal")
    slider("Reminder interval", 1, 30, 5)
    infoRow("Character movement", "Controlled by the game")
end

local function buildVisuals()
    section("Visual Preferences")
    toggle("Show player card", "Show local profile information in this hub", true)
    toggle("Compact layout", "Use smaller interface rows", Config.CompactRows, function(v)
        Config.CompactRows = v
    end)
    infoRow("Player ESP", "Not available")
end

local function buildMisc()
    section("Interface Settings")
    slider("UI Scale", 0.65, 1.15, Config.Scale, function(v)
        Config.Scale = v
        uiScale.Scale = v
    end)
    toggle("Animations", "Enable or disable transitions", Config.Animations, function(v)
        Config.Animations = v
    end)

    section("Configuration")
    actionButton("Print current configuration", function()
        print("[Radman HUB Config]", HttpService:JSONEncode(Config))
    end)
    actionButton("Reset local settings", function()
        Config.Scale = 0.90
        Config.Animations = true
        Config.CompactRows = false
        Config.HasHallowScythe = false
        Config.Tasks["Farm Level"].Enabled = true
        Config.Tasks["Pirate Raid"].Enabled = false
        Config.Tasks["Auto Soul Reaper"].Enabled = false
        uiScale.Scale = Config.Scale
        refreshCurrentPage()
    end)

    section("Project Information")
    infoRow("Version", "1.0")
    infoRow("Platform", UserInputService.TouchEnabled and "Touch" or "Desktop")
    infoRow("Game integration", "Companion mode")
end

local builders = {
    Main = buildMain,
    Farming = buildFarming,
    Combat = buildCombat,
    Fruit = buildFruit,
    Movement = buildMovement,
    Visuals = buildVisuals,
    Misc = buildMisc
}

refreshCurrentPage = function()
    clearPage()
    pageTitle.Text = selectedTab
    local builder = builders[selectedTab]
    if builder then
        local ok, err = pcall(builder)
        if not ok then
            warn("[Radman HUB] Page error:", err)
            infoRow("Page error", "See Output for details")
        end
    end
end

--==================================================
-- SEARCH FILTER
--==================================================

local function applySearch()
    local query = string.lower(search.Text)

    for _, item in ipairs(controlRegistry) do
        if item.Object and item.Object.Parent then
            local matches = query == ""
                or string.find(string.lower(item.Name), query, 1, true) ~= nil
            item.Object.Visible = matches
        end
    end
end

connect(search:GetPropertyChangedSignal("Text"), applySearch)

--==================================================
-- TABS
--==================================================

local tabNames = {
    "Main",
    "Farming",
    "Combat",
    "Fruit",
    "Movement",
    "Visuals",
    "Misc"
}

local tabIcons = {
    Main = "⌂",
    Farming = "⚒",
    Combat = "⚔",
    Fruit = "◆",
    Movement = "➤",
    Visuals = "◉",
    Misc = "◇"
}

local function selectTab(tabName)
    selectedTab = tabName
    Config.SelectedTab = tabName
    search.Text = ""

    for name, button in pairs(tabButtons) do
        button.BackgroundColor3 = name == tabName and Theme.Element or Theme.Sidebar
        button.TextColor3 = name == tabName and Theme.Text or Theme.Muted
    end

    refreshCurrentPage()
end

for index, tabName in ipairs(tabNames) do
    local button = make("TextButton", {
        Size = UDim2.new(1, 0, 0, 39),
        LayoutOrder = index,
        BackgroundColor3 = Theme.Sidebar,
        Text = "   " .. tabIcons[tabName] .. "   " .. tabName,
        TextColor3 = Theme.Muted,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        AutoButtonColor = false
    }, sidebar)
    corner(button, 8)

    tabButtons[tabName] = button
    connect(button.MouseButton1Click, function()
        selectTab(tabName)
    end)
end

--==================================================
-- RESPONSIVE SIZE
--==================================================

local function adaptToViewport()
    local camera = workspace.CurrentCamera
    if not camera then return end

    local viewport = camera.ViewportSize
    if viewport.X < 720 then
        window.Size = UDim2.new(0.96, 0, 0.82, 0)
        window.Position = UDim2.new(0.02, 0, 0.09, 0)
        uiScale.Scale = 1
    else
        window.Size = fullSize
        window.Position = UDim2.new(0.5, -425, 0.5, -285)
        uiScale.Scale = Config.Scale
    end
end

local camera = workspace.CurrentCamera
if camera then
    connect(camera:GetPropertyChangedSignal("ViewportSize"), adaptToViewport)
end

adaptToViewport()
selectTab("Main")

print("[Radman HUB] v1.0 initialized successfully.")
print("[Radman HUB] Priority Manager ready.")
print("[Radman HUB] Companion mode: no original-game automation.")
