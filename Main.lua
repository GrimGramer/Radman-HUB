--!strict
--[[
    RADMAN HUB v1.0
    Target: Blox Fruits (Roblox Client)
    Style: Dark Theme with Purple Accents (OMG Hub & Quantum Onyx inspired)
    Author: GrimGramer / Radman Team
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Stats = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- ============================================================================
-- 1. КОНФИГУРАЦИЯ, ТЕМА И СОСТОЯНИЕ
-- ============================================================================

local HubMeta = {
    Name = "RADMAN HUB",
    Version = "v1.0",
    ConfigFolder = "RadmanHub",
    ConfigFile = "RadmanHub/BloxFruits_Config.json",
}

local Theme = {
    Background = Color3.fromRGB(16, 15, 22),
    Sidebar = Color3.fromRGB(22, 20, 31),
    Card = Color3.fromRGB(28, 25, 40),
    CardHover = Color3.fromRGB(35, 31, 50),
    Accent = Color3.fromRGB(139, 92, 246),       -- Фиолетовый акцент (#8B5CF6)
    AccentDark = Color3.fromRGB(109, 62, 216),
    AccentGlow = Color3.fromRGB(167, 139, 250),
    TextPrimary = Color3.fromRGB(244, 244, 248),
    TextSecondary = Color3.fromRGB(161, 161, 178),
    Border = Color3.fromRGB(48, 43, 68),
    Success = Color3.fromRGB(52, 211, 153),
    Warning = Color3.fromRGB(251, 191, 36),
    Danger = Color3.fromRGB(248, 113, 113),
}

local DefaultConfig: { [string]: any } = {
    -- UI
    UIScale = 1.0,
    ToggleKey = "RightControl",

    -- Farming & Priorities
    MasterScheduler = false,
    PirateRaidEnabled = true,
    AutoSoulReaperEnabled = true,
    FarmLevelEnabled = true,
    SelectedWeapon = "Melee",
    AutoEquipWeapon = false,
    SafeDistance = 25,

    -- Combat
    AutoBusoHaki = false,
    AutoObservation = false,
    SelectedSkillZ = true,
    SelectedSkillX = true,
    SelectedSkillC = true,
    SelectedSkillV = false,

    -- Fruit
    NotifyFruitSpawn = true,
    AutoStoreFruit = false,
    TargetSniperFruit = "Kitsune",

    -- Movement
    CustomWalkSpeedEnabled = false,
    WalkSpeedValue = 32,
    CustomJumpPowerEnabled = false,
    JumpPowerValue = 65,
    InfiniteDashAssist = false,

    -- Visuals
    FruitESP = false,
    ChestESP = false,
    PlayerESP = false,
    CustomFOVEnabled = false,
    FOVValue = 70,
    Fullbright = false,

    -- Misc
    AntiAFK = true,
    LowGraphicsMode = false,
    ShowFPSPing = true,
}

local State = {
    Config = table.clone(DefaultConfig),
    IsOpen = true,
    IsMinimized = false,
    ActiveTab = "Main",
    SearchQuery = "",
    HasHallowScythe = false,
    CurrentTask = "Ожидание запуска",
    Connections = {} :: { RBXScriptConnection },
    ESPObjects = {} :: { [Instance]: BillboardGui },
}

-- ============================================================================
-- 2. МЕНЕДЖЕР КОНФИГУРАЦИЙ (БЕЗОПАСНОЕ СОХРАНЕНИЕ)
-- ============================================================================

local ConfigManager = {}

function ConfigManager.Serialize(): string
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(State.Config)
    end)
    return ok and encoded or "{}"
end

function ConfigManager.Deserialize(jsonStr: string): boolean
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(jsonStr)
    end)
    if ok and type(decoded) == "table" then
        for k, v in pairs(DefaultConfig) do
            if decoded[k] ~= nil and type(decoded[k]) == type(v) then
                State.Config[k] = decoded[k]
            end
        end
        return true
    end
    return false
end

function ConfigManager.SaveToDisk(): (boolean, string)
    local env = getfenv and getfenv() or {}
    local writefileFn = (env :: any).writefile
    local isfolderFn = (env :: any).isfolder
    local makefolderFn = (env :: any).makefolder

    if type(writefileFn) == "function" then
        local ok, err = pcall(function()
            if type(isfolderFn) == "function" and type(makefolderFn) == "function" then
                if not isfolderFn(HubMeta.ConfigFolder) then
                    makefolderFn(HubMeta.ConfigFolder)
                end
            end
            writefileFn(HubMeta.ConfigFile, ConfigManager.Serialize())
        end)
        if ok then
            return true, "Конфигурация сохранена в файл."
        else
            return false, "Ошибка записи файла: " .. tostring(err)
        end
    end
    return false, "Файловая система недоступна. Используйте JSON-экспорт."
end

function ConfigManager.LoadFromDisk(): (boolean, string)
    local env = getfenv and getfenv() or {}
    local readfileFn = (env :: any).readfile
    local isfileFn = (env :: any).isfile

    if type(readfileFn) == "function" and type(isfileFn) == "function" then
        local ok, result = pcall(function()
            if isfileFn(HubMeta.ConfigFile) then
                return readfileFn(HubMeta.ConfigFile)
            end
            return nil
        end)
        if ok and type(result) == "string" then
            if ConfigManager.Deserialize(result) then
                return true, "Конфигурация загружена."
            end
        end
    end
    return false, "Сохранённый файл не найден."
end

-- ============================================================================
-- 3. ДИНАМИЧЕСКАЯ СИСТЕМА ПРИОРИТЕТОВ
-- ============================================================================

export type PriorityTask = {
    Id: string,
    Name: string,
    Priority: number,
    Enabled: boolean,
    ConditionMet: boolean,
    Note: string,
}

local PriorityManager = {}
local OnPriorityUpdated: (() -> ())? = nil

function PriorityManager.CheckInventoryForHallowScythe(): boolean
    local function hasTool(container: Instance?): boolean
        if not container then
            return false
        end
        for _, item in ipairs(container:GetChildren()) do
            if item:IsA("Tool") and string.find(string.lower(item.Name), "hallow scythe", 1, true) then
                return true
            end
        end
        return false
    end

    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    local character = LocalPlayer.Character
    return hasTool(backpack) or hasTool(character)
end

function PriorityManager.CheckPirateRaidActive(): boolean
    -- Проверка наличия активных пиратов рейда в Castle on the Sea (Sea 3)
    local enemies = workspace:FindFirstChild("Enemies")
    if not enemies then
        return false
    end
    for _, npc in ipairs(enemies:GetChildren()) do
        local nameLower = string.lower(npc.Name)
        if string.find(nameLower, "pirate", 1, true) and (
            string.find(nameLower, "raider", 1, true)
            or string.find(nameLower, "galley", 1, true)
            or string.find(nameLower, "captain", 1, true)
        ) then
            local hum = npc:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                return true
            end
        end
    end
    return false
end

function PriorityManager.CheckSoulReaperActive(): boolean
    local enemies = workspace:FindFirstChild("Enemies")
    if enemies then
        for _, npc in ipairs(enemies:GetChildren()) do
            if string.find(string.lower(npc.Name), "soul reaper", 1, true) then
                local hum = npc:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    return true
                end
            end
        end
    end
    local replicated = game:GetService("ReplicatedStorage")
    for _, obj in ipairs(replicated:GetChildren()) do
        if string.find(string.lower(obj.Name), "soul reaper", 1, true) then
            return true
        end
    end
    return false
end

function PriorityManager.GetSortedQueue(): { PriorityTask }
    State.HasHallowScythe = PriorityManager.CheckInventoryForHallowScythe()

    -- Динамический приоритет Auto Soul Reaper: 2 при наличии Hallow Scythe, иначе 4
    local soulReaperPriority = State.HasHallowScythe and 2 or 4
    local soulReaperNote = State.HasHallowScythe
        and "Повышен до 2 (обнаружена Hallow Scythe)"
        or "Базовый 4 (Hallow Scythe не найдена)"

    local tasks: { PriorityTask } = {
        {
            Id = "PirateRaid",
            Name = "Pirate Raid",
            Priority = 1,
            Enabled = State.Config.PirateRaidEnabled,
            ConditionMet = PriorityManager.CheckPirateRaidActive(),
            Note = "Высший приоритет (1) при рейде",
        },
        {
            Id = "AutoSoulReaper",
            Name = "Auto Soul Reaper",
            Priority = soulReaperPriority,
            Enabled = State.Config.AutoSoulReaperEnabled,
            ConditionMet = PriorityManager.CheckSoulReaperActive(),
            Note = soulReaperNote,
        },
        {
            Id = "FarmLevel",
            Name = "Farm Level",
            Priority = 3,
            Enabled = State.Config.FarmLevelEnabled,
            ConditionMet = true,
            Note = "Стандартный приоритет (3)",
        },
    }

    table.sort(tasks, function(a, b)
        return a.Priority < b.Priority
    end)

    return tasks
end

function PriorityManager.ResolveActiveTask(): PriorityTask?
    local queue = PriorityManager.GetSortedQueue()
    for _, taskItem in ipairs(queue) do
        if taskItem.Enabled and taskItem.ConditionMet then
            State.CurrentTask = string.format("[P%d] %s", taskItem.Priority, taskItem.Name)
            return taskItem
        end
    end
    State.CurrentTask = "Нет активных задач"
    return nil
end

-- ============================================================================
-- 4. УТИЛИТЫ UI И БИБЛИОТЕКА КОМПОНЕНТОВ
-- ============================================================================

local function Create(className: string, props: { [string]: any }, children: { Instance }?): any
    local inst = Instance.new(className)
    for k, v in pairs(props) do
        (inst :: any)[k] = v
    end
    if children then
        for _, child in ipairs(children) do
            child.Parent = inst
        end
    end
    return inst
end

local function Tween(inst: Instance, duration: number, props: { [string]: any }, style: Enum.EasingStyle?)
    local info = TweenInfo.new(duration, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    local tween = TweenService:Create(inst, info, props)
    tween:Play()
    return tween
end

-- Очистка предыдущего экземпляра хаба при перезапуске
local ParentContainer: Instance = (pcall(function() return game:GetService("CoreGui").Name end) and game:GetService("CoreGui"))
    or LocalPlayer:WaitForChild("PlayerGui")

local OldGui = ParentContainer:FindFirstChild("RadmanHubUI")
if OldGui then
    OldGui:Destroy()
end

local ScreenGui = Create("ScreenGui", {
    Name = "RadmanHubUI",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    Parent = ParentContainer,
})

local UIScaleObj = Create("UIScale", {
    Scale = State.Config.UIScale,
    Parent = ScreenGui,
})

-- Основное окно (Компактное: 620x400)
local MainFrame = Create("Frame", {
    Name = "MainFrame",
    Size = UDim2.new(0, 620, 0, 400),
    Position = UDim2.new(0.5, -310, 0.5, -200),
    BackgroundColor3 = Theme.Background,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Parent = ScreenGui,
}, {
    Create("UICorner", { CornerRadius = UDim.new(0, 12) }),
    Create("UIStroke", { Color = Theme.Border, Thickness = 1.2 }),
})

-- Верхняя панель (TopBar)
local TopBar = Create("Frame", {
    Name = "TopBar",
    Size = UDim2.new(1, 0, 0, 44),
    BackgroundColor3 = Theme.Sidebar,
    BorderSizePixel = 0,
    Parent = MainFrame,
}, {
    Create("UICorner", { CornerRadius = UDim.new(0, 12) }),
    Create("Frame", {
        Name = "BottomCover",
        Size = UDim2.new(1, 0, 0, 10),
        Position = UDim2.new(0, 0, 1, -10),
        BackgroundColor3 = Theme.Sidebar,
        BorderSizePixel = 0,
    }),
    Create("Frame", {
        Name = "Divider",
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.new(0, 0, 1, -1),
        BackgroundColor3 = Theme.Border,
        BorderSizePixel = 0,
    }),
})

-- Логотип и версия
local BrandContainer = Create("Frame", {
    Size = UDim2.new(0, 210, 1, 0),
    Position = UDim2.new(0, 14, 0, 0),
    BackgroundTransparency = 1,
    Parent = TopBar,
}, {
    Create("Frame", {
        Name = "AccentDot",
        Size = UDim2.new(0, 10, 0, 10),
        Position = UDim2.new(0, 0, 0.5, -5),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
    }, {
        Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
    }),
    Create("TextLabel", {
        Name = "Title",
        Size = UDim2.new(0, 125, 1, 0),
        Position = UDim2.new(0, 18, 0, 0),
        BackgroundTransparency = 1,
        Text = HubMeta.Name,
        TextColor3 = Theme.TextPrimary,
        Font = Enum.Font.GothamBold,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
    }),
    Create("TextLabel", {
        Name = "VersionBadge",
        Size = UDim2.new(0, 42, 0, 20),
        Position = UDim2.new(0, 142, 0.5, -10),
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 0.82,
        Text = HubMeta.Version,
        TextColor3 = Theme.AccentGlow,
        Font = Enum.Font.GothamSemibold,
        TextSize = 11,
    }, {
        Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
        Create("UIStroke", { Color = Theme.Accent, Thickness = 1 }),
    }),
})

-- Поле поиска функций в TopBar
local SearchBox = Create("TextBox", {
    Name = "SearchBox",
    Size = UDim2.new(0, 210, 0, 28),
    Position = UDim2.new(0, 235, 0.5, -14),
    BackgroundColor3 = Theme.Background,
    Text = "",
    PlaceholderText = "Поиск функций...",
    PlaceholderColor3 = Theme.TextSecondary,
    TextColor3 = Theme.TextPrimary,
    Font = Enum.Font.Gotham,
    TextSize = 12,
    ClearTextOnFocus = false,
    Parent = TopBar,
}, {
    Create("UICorner", { CornerRadius = UDim.new(0, 7) }),
    Create("UIStroke", { Color = Theme.Border, Thickness = 1 }),
    Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
})

-- Кнопки управления окном (Свернуть / Закрыть)
local MinimizeBtn = Create("TextButton", {
    Name = "MinimizeBtn",
    Size = UDim2.new(0, 28, 0, 28),
    Position = UDim2.new(1, -68, 0.5, -14),
    BackgroundColor3 = Theme.Card,
    Text = "—",
    TextColor3 = Theme.TextPrimary,
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    Parent = TopBar,
}, {
    Create("UICorner", { CornerRadius = UDim.new(0, 7) }),
})

local CloseBtn = Create("TextButton", {
    Name = "CloseBtn",
    Size = UDim2.new(0, 28, 0, 28),
    Position = UDim2.new(1, -34, 0.5, -14),
    BackgroundColor3 = Theme.Card,
    Text = "✕",
    TextColor3 = Theme.Danger,
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    Parent = TopBar,
}, {
    Create("UICorner", { CornerRadius = UDim.new(0, 7) }),
})

-- Кнопка восстановления окна при закрытии
local FloatingOpenBtn = Create("TextButton", {
    Name = "FloatingOpenBtn",
    Size = UDim2.new(0, 130, 0, 34),
    Position = UDim2.new(0, 16, 0.5, -17),
    BackgroundColor3 = Theme.Sidebar,
    Text = "RADMAN HUB",
    TextColor3 = Theme.AccentGlow,
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    Visible = false,
    Parent = ScreenGui,
}, {
    Create("UICorner", { CornerRadius = UDim.new(0, 8) }),
    Create("UIStroke", { Color = Theme.Accent, Thickness = 1.5 }),
})

-- Контейнер тела окна
local BodyContainer = Create("Frame", {
    Name = "BodyContainer",
    Size = UDim2.new(1, 0, 1, -44),
    Position = UDim2.new(0, 0, 0, 44),
    BackgroundTransparency = 1,
    Parent = MainFrame,
})

-- Левая панель вкладок
local Sidebar = Create("Frame", {
    Name = "Sidebar",
    Size = UDim2.new(0, 148, 1, 0),
    BackgroundColor3 = Theme.Sidebar,
    BorderSizePixel = 0,
    Parent = BodyContainer,
}, {
    Create("Frame", {
        Name = "RightBorder",
        Size = UDim2.new(0, 1, 1, 0),
        Position = UDim2.new(1, -1, 0, 0),
        BackgroundColor3 = Theme.Border,
        BorderSizePixel = 0,
    }),
    Create("UIListLayout", {
        Padding = UDim.new(0, 5),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }),
    Create("UIPadding", {
        PaddingTop = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
    }),
})

-- Область контента вкладок
local ContentArea = Create("Frame", {
    Name = "ContentArea",
    Size = UDim2.new(1, -148, 1, 0),
    Position = UDim2.new(0, 148, 0, 0),
    BackgroundTransparency = 1,
    Parent = BodyContainer,
})

-- Перетаскивание окна (Dragging)
do
    local dragging = false
    local dragStart = Vector2.zero
    local startPos = UDim2.new()

    TopBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = MainFrame.Position
        end
    end)

    table.insert(State.Connections, UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            MainFrame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X / UIScaleObj.Scale,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y / UIScaleObj.Scale
            )
        end
    end))

    table.insert(State.Connections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
end

-- Анимации открытия, закрытия и сворачивания
local function SetHubVisible(visible: boolean)
    State.IsOpen = visible
    if visible then
        FloatingOpenBtn.Visible = false
        MainFrame.Visible = true
        MainFrame.Size = UDim2.new(0, 620, 0, 0)
        Tween(MainFrame, 0.28, { Size = UDim2.new(0, 620, 0, State.IsMinimized and 44 or 400) })
    else
        local tw = Tween(MainFrame, 0.22, { Size = UDim2.new(0, 620, 0, 0) })
        tw.Completed:Connect(function()
            if not State.IsOpen then
                MainFrame.Visible = false
                FloatingOpenBtn.Visible = true
            end
        end)
    end
end

MinimizeBtn.MouseButton1Click:Connect(function()
    State.IsMinimized = not State.IsMinimized
    MinimizeBtn.Text = State.IsMinimized and "+" or "—"
    Tween(MainFrame, 0.24, { Size = UDim2.new(0, 620, 0, State.IsMinimized and 44 or 400) })
end)

CloseBtn.MouseButton1Click:Connect(function()
    SetHubVisible(false)
end)

FloatingOpenBtn.MouseButton1Click:Connect(function()
    SetHubVisible(true)
end)

-- ============================================================================
-- 5. КОНСТРУКТОР ЭЛЕМЕНТОВ ИНТЕРФЕЙСА (TABS, SECTIONS, CONTROLS)
-- ============================================================================

type SearchableItem = {
    Frame: Frame,
    TabName: string,
    Keywords: string,
}

local Tabs: { [string]: { Button: TextButton, Page: ScrollingFrame, Indicator: Frame } } = {}
local SearchableItems: { SearchableItem } = {}
local ConfigRefreshCallbacks: { () -> () } = {}

local function SelectTab(tabName: string)
    State.ActiveTab = tabName
    for name, tab in pairs(Tabs) do
        local isSelected = (name == tabName)
        tab.Page.Visible = isSelected
        Tween(tab.Button, 0.18, {
            BackgroundColor3 = isSelected and Theme.Card or Theme.Sidebar,
            TextColor3 = isSelected and Theme.TextPrimary or Theme.TextSecondary,
        })
        Tween(tab.Indicator, 0.18, {
            BackgroundTransparency = isSelected and 0 or 1,
        })
    end
end

local function CreateTab(name: string, order: number): ScrollingFrame
    local btn = Create("TextButton", {
        Name = name .. "TabBtn",
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = Theme.Sidebar,
        Text = "   " .. name,
        TextColor3 = Theme.TextSecondary,
        Font = Enum.Font.GothamSemibold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = order,
        Parent = Sidebar,
    }, {
        Create("UICorner", { CornerRadius = UDim.new(0, 8) }),
    })

    local indicator = Create("Frame", {
        Name = "Indicator",
        Size = UDim2.new(0, 3, 0, 18),
        Position = UDim2.new(0, 2, 0.5, -9),
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Parent = btn,
    }, {
        Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
    })

    local page = Create("ScrollingFrame", {
        Name = name .. "Page",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = Theme.Accent,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Visible = false,
        Parent = ContentArea,
    }, {
        Create("UIListLayout", {
            Padding = UDim.new(0, 8),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
        Create("UIPadding", {
            PaddingTop = UDim.new(0, 12),
            PaddingBottom = UDim.new(0, 14),
            PaddingLeft = UDim.new(0, 14),
            PaddingRight = UDim.new(0, 14),
        }),
    })

    btn.MouseButton1Click:Connect(function()
        SelectTab(name)
    end)

    Tabs[name] = { Button = btn, Page = page, Indicator = indicator }
    return page
end

local function CreateSectionHeader(parent: ScrollingFrame, tabName: string, title: string)
    local header = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 24),
        BackgroundTransparency = 1,
        Parent = parent,
    }, {
        Create("TextLabel", {
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Text = string.upper(title),
            TextColor3 = Theme.AccentGlow,
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
        }),
    })

    table.insert(SearchableItems, {
        Frame = header,
        TabName = tabName,
        Keywords = string.lower(title),
    })
end

local function CreateToggle(
    parent: ScrollingFrame,
    tabName: string,
    title: string,
    description: string,
    configKey: string,
    callback: ((boolean) -> ())?
)
    local card = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 48),
        BackgroundColor3 = Theme.Card,
        BorderSizePixel = 0,
        Parent = parent,
    }, {
        Create("UICorner", { CornerRadius = UDim.new(0, 8) }),
        Create("UIStroke", { Color = Theme.Border, Thickness = 1 }),
    })

    Create("TextLabel", {
        Size = UDim2.new(1, -70, 0, 20),
        Position = UDim2.new(0, 12, 0, 6),
        BackgroundTransparency = 1,
        Text = title,
        TextColor3 = Theme.TextPrimary,
        Font = Enum.Font.GothamSemibold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })

    Create("TextLabel", {
        Size = UDim2.new(1, -70, 0, 16),
        Position = UDim2.new(0, 12, 0, 25),
        BackgroundTransparency = 1,
        Text = description,
        TextColor3 = Theme.TextSecondary,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })

    local switchTrack = Create("TextButton", {
        Size = UDim2.new(0, 42, 0, 22),
        Position = UDim2.new(1, -54, 0.5, -11),
        BackgroundColor3 = State.Config[configKey] and Theme.Accent or Theme.Background,
        Text = "",
        AutoButtonColor = false,
        Parent = card,
    }, {
        Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
        Create("UIStroke", { Color = Theme.Border, Thickness = 1 }),
    })

    local knob = Create("Frame", {
        Size = UDim2.new(0, 16, 0, 16),
        Position = State.Config[configKey] and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8),
        BackgroundColor3 = Theme.TextPrimary,
        BorderSizePixel = 0,
        Parent = switchTrack,
    }, {
        Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
    })

    local function RefreshVisual()
        local val = State.Config[configKey] == true
        Tween(switchTrack, 0.16, { BackgroundColor3 = val and Theme.Accent or Theme.Background })
        Tween(knob, 0.16, { Position = val and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8) })
    end

    switchTrack.MouseButton1Click:Connect(function()
        local newVal = not (State.Config[configKey] == true)
        State.Config[configKey] = newVal
        RefreshVisual()
        if callback then
            callback(newVal)
        end
    end)

    table.insert(ConfigRefreshCallbacks, RefreshVisual)
    table.insert(SearchableItems, {
        Frame = card,
        TabName = tabName,
        Keywords = string.lower(title .. " " .. description),
    })
end

local function CreateSlider(
    parent: ScrollingFrame,
    tabName: string,
    title: string,
    minVal: number,
    maxVal: number,
    step: number,
    configKey: string,
    suffix: string,
    callback: ((number) -> ())?
)
    local card = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 56),
        BackgroundColor3 = Theme.Card,
        BorderSizePixel = 0,
        Parent = parent,
    }, {
        Create("UICorner", { CornerRadius = UDim.new(0, 8) }),
        Create("UIStroke", { Color = Theme.Border, Thickness = 1 }),
    })

    Create("TextLabel", {
        Size = UDim2.new(1, -90, 0, 20),
        Position = UDim2.new(0, 12, 0, 6),
        BackgroundTransparency = 1,
        Text = title,
        TextColor3 = Theme.TextPrimary,
        Font = Enum.Font.GothamSemibold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })

    local valueLabel = Create("TextLabel", {
        Size = UDim2.new(0, 75, 0, 20),
        Position = UDim2.new(1, -87, 0, 6),
        BackgroundTransparency = 1,
        Text = tostring(State.Config[configKey]) .. suffix,
        TextColor3 = Theme.AccentGlow,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = card,
    })

    local barBg = Create("TextButton", {
        Size = UDim2.new(1, -24, 0, 8),
        Position = UDim2.new(0, 12, 0, 35),
        BackgroundColor3 = Theme.Background,
        Text = "",
        AutoButtonColor = false,
        Parent = card,
    }, {
        Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
    })

    local initialAlpha = math.clamp((State.Config[configKey] - minVal) / (maxVal - minVal), 0, 1)
    local fill = Create("Frame", {
        Size = UDim2.new(initialAlpha, 0, 1, 0),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Parent = barBg,
    }, {
        Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
    })

    local function SetValue(val: number)
        local snapped = math.clamp(math.floor((val / step) + 0.5) * step, minVal, maxVal)
        -- Округление до 2 знаков для дробных шагов
        snapped = math.floor(snapped * 100 + 0.5) / 100
        State.Config[configKey] = snapped
        local alpha = (snapped - minVal) / (maxVal - minVal)
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        valueLabel.Text = tostring(snapped) .. suffix
        if callback then
            callback(snapped)
        end
    end

    local sliding = false
    local function UpdateFromInput(inputPos: Vector3)
        local relX = math.clamp((inputPos.X - barBg.AbsolutePosition.X) / barBg.AbsoluteSize.X, 0, 1)
        SetValue(minVal + (maxVal - minVal) * relX)
    end

    barBg.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            sliding = true
            UpdateFromInput(input.Position)
        end
    end)

    table.insert(State.Connections, UserInputService.InputChanged:Connect(function(input)
        if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            UpdateFromInput(input.Position)
        end
    end))

    table.insert(State.Connections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            sliding = false
        end
    end))

    table.insert(ConfigRefreshCallbacks, function()
        SetValue(State.Config[configKey])
    end)

    table.insert(SearchableItems, {
        Frame = card,
        TabName = tabName,
        Keywords = string.lower(title),
    })
end

local function CreateDropdown(
    parent: ScrollingFrame,
    tabName: string,
    title: string,
    options: { string },
    configKey: string,
    callback: ((string) -> ())?
)
    local isExpanded = false
    local baseHeight = 44
    local itemHeight = 28

    local card = Create("Frame", {
        Size = UDim2.new(1, 0, 0, baseHeight),
        BackgroundColor3 = Theme.Card,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = parent,
    }, {
        Create("UICorner", { CornerRadius = UDim.new(0, 8) }),
        Create("UIStroke", { Color = Theme.Border, Thickness = 1 }),
    })

    local headerBtn = Create("TextButton", {
        Size = UDim2.new(1, 0, 0, baseHeight),
        BackgroundTransparency = 1,
        Text = "",
        Parent = card,
    })

    Create("TextLabel", {
        Size = UDim2.new(0.55, 0, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1,
        Text = title,
        TextColor3 = Theme.TextPrimary,
        Font = Enum.Font.GothamSemibold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = headerBtn,
    })

    local selectedLabel = Create("TextLabel", {
        Size = UDim2.new(0.4, -14, 1, 0),
        Position = UDim2.new(0.6, 0, 0, 0),
        BackgroundTransparency = 1,
        Text = tostring(State.Config[configKey]) .. "  ▾",
        TextColor3 = Theme.AccentGlow,
        Font = Enum.Font.GothamSemibold,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = headerBtn,
    })

    local listContainer = Create("Frame", {
        Size = UDim2.new(1, -16, 0, #options * itemHeight),
        Position = UDim2.new(0, 8, 0, baseHeight),
        BackgroundTransparency = 1,
        Parent = card,
    }, {
        Create("UIListLayout", { Padding = UDim.new(0, 3) }),
    })

    for _, opt in ipairs(options) do
        local optBtn = Create("TextButton", {
            Size = UDim2.new(1, 0, 0, itemHeight - 3),
            BackgroundColor3 = Theme.Background,
            Text = "  " .. opt,
            TextColor3 = Theme.TextSecondary,
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = listContainer,
        }, {
            Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
        })

        optBtn.MouseButton1Click:Connect(function()
            State.Config[configKey] = opt
            selectedLabel.Text = opt .. "  ▾"
            isExpanded = false
            Tween(card, 0.18, { Size = UDim2.new(1, 0, 0, baseHeight) })
            if callback then
                callback(opt)
            end
        end)
    end

    headerBtn.MouseButton1Click:Connect(function()
        isExpanded = not isExpanded
        local targetHeight = isExpanded and (baseHeight + #options * itemHeight + 6) or baseHeight
        selectedLabel.Text = tostring(State.Config[configKey]) .. (isExpanded and "  ▴" or "  ▾")
        Tween(card, 0.2, { Size = UDim2.new(1, 0, 0, targetHeight) })
    end)

    table.insert(ConfigRefreshCallbacks, function()
        selectedLabel.Text = tostring(State.Config[configKey]) .. "  ▾"
    end)

    table.insert(SearchableItems, {
        Frame = card,
        TabName = tabName,
        Keywords = string.lower(title .. " " .. table.concat(options, " ")),
    })
end

local function CreateButton(
    parent: ScrollingFrame,
    tabName: string,
    title: string,
    subtitle: string,
    callback: () -> ()
)
    local btn = Create("TextButton", {
        Size = UDim2.new(1, 0, 0, 42),
        BackgroundColor3 = Theme.Card,
        Text = "",
        AutoButtonColor = false,
        Parent = parent,
    }, {
        Create("UICorner", { CornerRadius = UDim.new(0, 8) }),
        Create("UIStroke", { Color = Theme.Accent, Thickness = 1 }),
    })

    Create("TextLabel", {
        Size = UDim2.new(1, -24, 0, 18),
        Position = UDim2.new(0, 12, 0, 5),
        BackgroundTransparency = 1,
        Text = title,
        TextColor3 = Theme.AccentGlow,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = btn,
    })

    Create("TextLabel", {
        Size = UDim2.new(1, -24, 0, 14),
        Position = UDim2.new(0, 12, 0, 23),
        BackgroundTransparency = 1,
        Text = subtitle,
        TextColor3 = Theme.TextSecondary,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = btn,
    })

    btn.MouseEnter:Connect(function()
        Tween(btn, 0.14, { BackgroundColor3 = Theme.CardHover })
    end)
    btn.MouseLeave:Connect(function()
        Tween(btn, 0.14, { BackgroundColor3 = Theme.Card })
    end)
    btn.MouseButton1Click:Connect(callback)

    table.insert(SearchableItems, {
        Frame = btn :: any,
        TabName = tabName,
        Keywords = string.lower(title .. " " .. subtitle),
    })
end

-- ============================================================================
-- 6. ПОСТРОЕНИЕ ВСЕХ 7 ВКЛАДОК
-- ============================================================================

local MainPage = CreateTab("Main", 1)
local FarmingPage = CreateTab("Farming", 2)
local CombatPage = CreateTab("Combat", 3)
local FruitPage = CreateTab("Fruit", 4)
local MovementPage = CreateTab("Movement", 5)
local VisualsPage = CreateTab("Visuals", 6)
local MiscPage = CreateTab("Misc", 7)

-- ----------------------------------------------------------------------------
-- ВКЛАДКА 1: MAIN (Статус, Монитор приоритетов, Конфигурации, Масштаб)
-- ----------------------------------------------------------------------------
CreateSectionHeader(MainPage, "Main", "Состояние сессии и планировщика")

local StatusCard = Create("Frame", {
    Size = UDim2.new(1, 0, 0, 118),
    BackgroundColor3 = Theme.Card,
    BorderSizePixel = 0,
    Parent = MainPage,
}, {
    Create("UICorner", { CornerRadius = UDim.new(0, 8) }),
    Create("UIStroke", { Color = Theme.Accent, Thickness = 1 }),
})

local PlayerInfoLabel = Create("TextLabel", {
    Size = UDim2.new(1, -24, 0, 20),
    Position = UDim2.new(0, 12, 0, 8),
    BackgroundTransparency = 1,
    Text = string.format("Игрок: %s | PlaceId: %d", LocalPlayer.Name, game.PlaceId),
    TextColor3 = Theme.TextPrimary,
    Font = Enum.Font.GothamSemibold,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = StatusCard,
})

local ScytheStatusLabel = Create("TextLabel", {
    Size = UDim2.new(1, -24, 0, 18),
    Position = UDim2.new(0, 12, 0, 28),
    BackgroundTransparency = 1,
    Text = "Hallow Scythe: проверка инвентаря...",
    TextColor3 = Theme.TextSecondary,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = StatusCard,
})

local PriorityQueueLabel = Create("TextLabel", {
    Size = UDim2.new(1, -24, 0, 62),
    Position = UDim2.new(0, 12, 0, 48),
    BackgroundTransparency = 1,
    Text = "Очередь приоритетов загружается...",
    TextColor3 = Theme.AccentGlow,
    Font = Enum.Font.Code,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    TextWrapped = true,
    Parent = StatusCard,
})

local function UpdatePriorityDisplay()
    local queue = PriorityManager.GetSortedQueue()
    PriorityManager.ResolveActiveTask()

    ScytheStatusLabel.Text = State.HasHallowScythe
        and "Hallow Scythe: ОБНАРУЖЕНА (Auto Soul Reaper -> Приоритет 2)"
        or "Hallow Scythe: НЕ НАЙДЕНА (Auto Soul Reaper -> Приоритет 4)"
    ScytheStatusLabel.TextColor3 = State.HasHallowScythe and Theme.Success or Theme.TextSecondary

    local lines = { "Активная задача: " .. State.CurrentTask }
    for _, t in ipairs(queue) do
        local stateTag = t.Enabled and (t.ConditionMet and "ГОТОВО" or "ОЖИДАНИЕ") or "ВЫКЛ"
        table.insert(lines, string.format("P%d | %s [%s]", t.Priority, t.Name, stateTag))
    end
    PriorityQueueLabel.Text = table.concat(lines, "\n")
end

OnPriorityUpdated = UpdatePriorityDisplay

CreateSectionHeader(MainPage, "Main", "Интерфейс и масштаб")

CreateSlider(MainPage, "Main", "Масштаб окна (UI Scale)", 0.75, 1.35, 0.05, "UIScale", "x", function(val)
    UIScaleObj.Scale = val
end)

CreateSectionHeader(MainPage, "Main", "Управление конфигурациями")

local ConfigStatusLabel = Create("TextLabel", {
    Size = UDim2.new(1, 0, 0, 18),
    BackgroundTransparency = 1,
    Text = "Статус конфигурации: готовы к сохранению",
    TextColor3 = Theme.TextSecondary,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = MainPage,
})

CreateButton(MainPage, "Main", "Сохранить конфигурацию", "Записать текущие настройки на диск", function()
    local _, msg = ConfigManager.SaveToDisk()
    ConfigStatusLabel.Text = "Статус: " .. msg
    ConfigStatusLabel.TextColor3 = Theme.Success
end)

CreateButton(MainPage, "Main", "Загрузить конфигурацию", "Восстановить сохранённые настройки", function()
    local ok, msg = ConfigManager.LoadFromDisk()
    ConfigStatusLabel.Text = "Статус: " .. msg
    ConfigStatusLabel.TextColor3 = ok and Theme.Success or Theme.Warning
    if ok then
        UIScaleObj.Scale = State.Config.UIScale
        for _, refresh in ipairs(ConfigRefreshCallbacks) do
            refresh()
        end
        UpdatePriorityDisplay()
    end
end)

CreateButton(MainPage, "Main", "Сбросить настройки по умолчанию", "Вернуть все параметры к заводским", function()
    State.Config = table.clone(DefaultConfig)
    UIScaleObj.Scale = State.Config.UIScale
    for _, refresh in ipairs(ConfigRefreshCallbacks) do
        refresh()
    end
    UpdatePriorityDisplay()
    ConfigStatusLabel.Text = "Статус: настройки сброшены по умолчанию."
    ConfigStatusLabel.TextColor3 = Theme.AccentGlow
end)

-- ----------------------------------------------------------------------------
-- ВКЛАДКА 2: FARMING (Система приоритетов и авто-экипировка)
-- ----------------------------------------------------------------------------
CreateSectionHeader(FarmingPage, "Farming", "Динамический планировщик задач")

CreateToggle(
    FarmingPage,
    "Farming",
    "Включить планировщик приоритетов",
    "Автоматически выбирать активную задачу по таблице приоритетов",
    "MasterScheduler",
    function()
        UpdatePriorityDisplay()
    end
)

CreateToggle(
    FarmingPage,
    "Farming",
    "Pirate Raid (Приоритет 1)",
    "Высший приоритет при появлении пиратов в Castle on the Sea",
    "PirateRaidEnabled",
    function()
        UpdatePriorityDisplay()
    end
)

CreateToggle(
    FarmingPage,
    "Farming",
    "Auto Soul Reaper (Приоритет 4 / 2)",
    "Меняет приоритет с 4 на 2 при наличии Hallow Scythe в инвентаре",
    "AutoSoulReaperEnabled",
    function()
        UpdatePriorityDisplay()
    end
)

CreateToggle(
    FarmingPage,
    "Farming",
    "Farm Level (Приоритет 3)",
    "Базовая задача прокачки уровня персонажа",
    "FarmLevelEnabled",
    function()
        UpdatePriorityDisplay()
    end
)

CreateSectionHeader(FarmingPage, "Farming", "Параметры снаряжения")

CreateDropdown(
    FarmingPage,
    "Farming",
    "Тип оружия",
    { "Melee", "Sword", "Blox Fruit", "Gun" },
    "SelectedWeapon"
)

CreateToggle(
    FarmingPage,
    "Farming",
    "Авто-экипировка выбранного оружия",
    "Автоматически брать в руки инструмент нужной категории",
    "AutoEquipWeapon"
)

CreateSlider(FarmingPage, "Farming", "Безопасная дистанция", 10, 60, 5, "SafeDistance", " studs")

-- ----------------------------------------------------------------------------
-- ВКЛАДКА 3: COMBAT (Боевые настройки и умения)
-- ----------------------------------------------------------------------------
CreateSectionHeader(CombatPage, "Combat", "Усиления персонажа")

CreateToggle(
    CombatPage,
    "Combat",
    "Авто-активация Aura (Buso Haki)",
    "Проверять наличие эффекта Aura на персонаже",
    "AutoBusoHaki"
)

CreateToggle(
    CombatPage,
    "Combat",
    "Контроль Instinct (Observation)",
    "Отслеживать статус уклонений Observation Haki",
    "AutoObservation"
)

CreateSectionHeader(CombatPage, "Combat", "Пул используемых умений (Skills)")

CreateToggle(CombatPage, "Combat", "Использовать умение [Z]", "Разрешить навык Z в ротации", "SelectedSkillZ")
CreateToggle(CombatPage, "Combat", "Использовать умение [X]", "Разрешить навык X в ротации", "SelectedSkillX")
CreateToggle(CombatPage, "Combat", "Использовать умение [C]", "Разрешить навык C в ротации", "SelectedSkillC")
CreateToggle(CombatPage, "Combat", "Использовать умение [V]", "Разрешить навык V в ротации", "SelectedSkillV")

-- ----------------------------------------------------------------------------
-- ВКЛАДКА 4: FRUIT (Сканер фруктов на карте и инвентарь)
-- ----------------------------------------------------------------------------
CreateSectionHeader(FruitPage, "Fruit", "Мониторинг и поиск фруктов")

local FruitRadarLabel = Create("TextLabel", {
    Size = UDim2.new(1, 0, 0, 22),
    BackgroundTransparency = 1,
    Text = "На карте сейчас: фрукты не обнаружены",
    TextColor3 = Theme.AccentGlow,
    Font = Enum.Font.GothamSemibold,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = FruitPage,
})

local function ScanWorkspaceFruits(): { Instance }
    local found = {}
    for _, obj in ipairs(workspace:GetChildren()) do
        local nameLower = string.lower(obj.Name)
        if string.find(nameLower, "fruit", 1, true) and (obj:IsA("Tool") or obj:IsA("Model")) then
            table.insert(found, obj)
        end
    end
    return found
end

CreateButton(FruitPage, "Fruit", "Сканировать карту на наличие фруктов", "Проверить Workspace на заспавненные плоды", function()
    local fruits = ScanWorkspaceFruits()
    if #fruits == 0 then
        FruitRadarLabel.Text = "На карте сейчас: фрукты не обнаружены"
        FruitRadarLabel.TextColor3 = Theme.TextSecondary
    else
        local names = {}
        for _, f in ipairs(fruits) do
            table.insert(names, f.Name)
        end
        FruitRadarLabel.Text = "Найдено (" .. tostring(#fruits) .. "): " .. table.concat(names, ", ")
        FruitRadarLabel.TextColor3 = Theme.Success
    end
end)

CreateToggle(
    FruitPage,
    "Fruit",
    "Уведомлять о спавне фрукта",
    "Показывать статус при появлении фрукта в Workspace",
    "NotifyFruitSpawn"
)

CreateDropdown(
    FruitPage,
    "Fruit",
    "Целевой фрукт (Sniper Filter)",
    { "Kitsune", "Dragon", "Leopard", "Dough", "T-Rex", "Buddha", "Portal" },
    "TargetSniperFruit"
)

-- ----------------------------------------------------------------------------
-- ВКЛАДКА 5: MOVEMENT (Параметры Humanoid)
-- ----------------------------------------------------------------------------
CreateSectionHeader(MovementPage, "Movement", "Настройки передвижения персонажа")

CreateToggle(
    MovementPage,
    "Movement",
    "Изменять скорость ходьбы (WalkSpeed)",
    "Применять пользовательское значение скорости к Humanoid",
    "CustomWalkSpeedEnabled"
)

CreateSlider(MovementPage, "Movement", "Значение WalkSpeed", 16, 120, 2, "WalkSpeedValue", " ws")

CreateToggle(
    MovementPage,
    "Movement",
    "Изменять силу прыжка (JumpPower)",
    "Применять пользовательское значение прыжка к Humanoid",
    "CustomJumpPowerEnabled"
)

CreateSlider(MovementPage, "Movement", "Значение JumpPower", 50, 200, 5, "JumpPowerValue", " jp")

-- ----------------------------------------------------------------------------
-- ВКЛАДКА 6: VISUALS (ESP на BillboardGui, FOV, Освещение)
-- ----------------------------------------------------------------------------
CreateSectionHeader(VisualsPage, "Visuals", "Подсветка объектов (ESP)")

local function ClearAllESP()
    for _, gui in pairs(State.ESPObjects) do
        if gui and gui.Parent then
            gui:Destroy()
        end
    end
    table.clear(State.ESPObjects)
end

CreateToggle(VisualsPage, "Visuals", "ESP на Фрукты (Fruit ESP)", "Отображать маркер и дистанцию до фруктов", "FruitESP", function(val)
    if not val then
        ClearAllESP()
    end
end)

CreateToggle(VisualsPage, "Visuals", "ESP на Сундуки (Chest ESP)", "Подсвечивать сундуки с Бели на локации", "ChestESP", function(val)
    if not val then
        ClearAllESP()
    end
end)

CreateToggle(VisualsPage, "Visuals", "ESP на Игроков (Player ESP)", "Показывать никнейм и дистанцию до игроков", "PlayerESP", function(val)
    if not val then
        ClearAllESP()
    end
end)

CreateSectionHeader(VisualsPage, "Visuals", "Камера и освещение")

CreateToggle(VisualsPage, "Visuals", "Пользовательский угол обзора (FOV)", "Изменить FieldOfView камеры", "CustomFOVEnabled", function(val)
    if not val and Camera then
        Camera.FieldOfView = 70
    end
end)

CreateSlider(VisualsPage, "Visuals", "Поле зрения (FOV)", 50, 120, 2, "FOVValue", "°", function(val)
    if State.Config.CustomFOVEnabled and Camera then
        Camera.FieldOfView = val
    end
end)

local DefaultAmbient = Lighting.Ambient
local DefaultBrightness = Lighting.Brightness

CreateToggle(VisualsPage, "Visuals", "Максимальная яркость (Fullbright)", "Убрать тёмные тени и ночное затемнение", "Fullbright", function(val)
    if val then
        Lighting.Brightness = 2
        Lighting.Ambient = Color3.fromRGB(200, 200, 200)
    else
        Lighting.Brightness = DefaultBrightness
        Lighting.Ambient = DefaultAmbient
    end
end)

-- ----------------------------------------------------------------------------
-- ВКЛАДКА 7: MISC (Оптимизация FPS, Anti-AFK, Статистика)
-- ----------------------------------------------------------------------------
CreateSectionHeader(MiscPage, "Misc", "Стабильность и производительность")

CreateToggle(
    MiscPage,
    "Misc",
    "Защита от кика за бездействие (Anti-AFK)",
    "Предотвращать отключение при длительном простое",
    "AntiAFK"
)

CreateToggle(
    MiscPage,
    "Misc",
    "Режим пониженной графики (FPS Boost)",
    "Отключать декоративные частицы и снижать качество материалов",
    "LowGraphicsMode",
    function(val)
        if val then
            for _, desc in ipairs(workspace:GetDescendants()) do
                if desc:IsA("ParticleEmitter") or desc:IsA("Trail") then
                    desc.Enabled = false
                elseif desc:IsA("BasePart") then
                    desc.Material = Enum.Material.SmoothPlastic
                end
            end
        end
    end
)

local PerfLabel = Create("TextLabel", {
    Size = UDim2.new(1, 0, 0, 22),
    BackgroundTransparency = 1,
    Text = "FPS: -- | Ping: -- ms",
    TextColor3 = Theme.TextSecondary,
    Font = Enum.Font.Code,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = MiscPage,
})

-- ============================================================================
-- 7. ПОИСК ПО ФУНКЦИЯМ (REAL-TIME SEARCH)
-- ============================================================================

SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    local query = string.lower(string.gsub(SearchBox.Text, "^%s*(.-)%s*$", "%1"))
    State.SearchQuery = query

    if query == "" then
        -- Возврат в обычный режим вкладок
        for _, item in ipairs(SearchableItems) do
            item.Frame.Visible = true
        end
        SelectTab(State.ActiveTab)
        return
    end

    -- Показываем все совпадающие элементы во всех вкладках на текущей активной странице
    -- Для удобства переключаем видимость страниц так, чтобы отображалась первая вкладка с совпадениями
    local firstMatchedTab: string? = nil
    for _, item in ipairs(SearchableItems) do
        local matched = string.find(item.Keywords, query, 1, true) ~= nil
        item.Frame.Visible = matched
        if matched and not firstMatchedTab then
            firstMatchedTab = item.TabName
        end
    end

    if firstMatchedTab and firstMatchedTab ~= State.ActiveTab then
        for name, tab in pairs(Tabs) do
            local isMatch = (name == firstMatchedTab)
            tab.Page.Visible = isMatch
            tab.Button.BackgroundColor3 = isMatch and Theme.Card or Theme.Sidebar
            tab.Button.TextColor3 = isMatch and Theme.TextPrimary or Theme.TextSecondary
            tab.Indicator.BackgroundTransparency = isMatch and 0 or 1
        end
    end
end)

-- ============================================================================
-- 8. ФОНОВЫЕ ЦИКЛЫ И ОБРАБОТЧИКИ СОБЫТИЙ
-- ============================================================================

-- Anti-AFK через событие Idled
table.insert(State.Connections, LocalPlayer.Idled:Connect(function()
    if State.Config.AntiAFK then
        local virtualUser = game:GetService("VirtualUser")
        pcall(function()
            virtualUser:CaptureController()
            virtualUser:ClickButton2(Vector2.zero)
        end)
    end
end))

-- Уведомление при появлении фрукта в Workspace
table.insert(State.Connections, workspace.ChildAdded:Connect(function(child)
    if State.Config.NotifyFruitSpawn then
        local nameLower = string.lower(child.Name)
        if string.find(nameLower, "fruit", 1, true) then
            FruitRadarLabel.Text = "Новый спавн: " .. child.Name
            FruitRadarLabel.TextColor3 = Theme.Success
        end
    end
end))

-- Горячая клавиша скрытия/показа интерфейса (RightControl)
table.insert(State.Connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.RightControl then
        SetHubVisible(not State.IsOpen)
    end
end))

-- Вспомогательная функция отрисовки BillboardGui для ESP
local function AttachESP(target: Instance, adornee: BasePart, text: string, color: Color3)
    local gui = State.ESPObjects[target]
    if not gui or not gui.Parent then
        gui = Create("BillboardGui", {
            Name = "RadmanESP",
            Adornee = adornee,
            Size = UDim2.new(0, 160, 0, 32),
            StudsOffset = Vector3.new(0, 2.5, 0),
            AlwaysOnTop = true,
            Parent = ScreenGui,
        }, {
            Create("TextLabel", {
                Name = "Label",
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = text,
                TextColor3 = color,
                TextStrokeTransparency = 0.3,
                Font = Enum.Font.GothamBold,
                TextSize = 11,
            }),
        })
        State.ESPObjects[target] = gui
    else
        local lbl = gui:FindFirstChild("Label") :: TextLabel?
        if lbl then
            lbl.Text = text
            lbl.TextColor3 = color
        end
    end
end

-- Основной цикл обновления (каждые 0.25 сек для экономии FPS)
local accumulator = 0
local frameCounter = 0
local lastFpsTime = os.clock()

table.insert(State.Connections, RunService.Heartbeat:Connect(function(dt)
    frameCounter += 1
    accumulator += dt

    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?

    -- Применение параметров передвижения
    if hum then
        if State.Config.CustomWalkSpeedEnabled then
            hum.WalkSpeed = State.Config.WalkSpeedValue
        end
        if State.Config.CustomJumpPowerEnabled then
            hum.UseJumpPower = true
            hum.JumpPower = State.Config.JumpPowerValue
        end
    end

    if State.Config.CustomFOVEnabled and Camera then
        Camera.FieldOfView = State.Config.FOVValue
    end

    if accumulator < 0.25 then
        return
    end
    accumulator = 0

    -- Обновление FPS и Ping
    local now = os.clock()
    local fps = math.floor(frameCounter / math.max(now - lastFpsTime, 0.001))
    frameCounter = 0
    lastFpsTime = now

    local pingOk, pingVal = pcall(function()
        return math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
    end)
    PerfLabel.Text = string.format("FPS: %d | Ping: %s ms", fps, pingOk and tostring(pingVal) or "N/A")

    -- Обновление динамических приоритетов (Hallow Scythe / Pirate Raid / Soul Reaper)
    UpdatePriorityDisplay()

    -- Авто-экипировка выбранного оружия при включении
    if State.Config.AutoEquipWeapon and char and hum then
        local equipped = char:FindFirstChildOfClass("Tool")
        local targetTip = State.Config.SelectedWeapon
        if not equipped or equipped.ToolTip ~= targetTip then
            local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
            if backpack then
                for _, tool in ipairs(backpack:GetChildren()) do
                    if tool:IsA("Tool") and tool.ToolTip == targetTip then
                        hum:EquipTool(tool)
                        break
                    end
                end
            end
        end
    end

    -- Обновление ESP
    local activeTargets: { [Instance]: boolean } = {}

    if root then
        if State.Config.FruitESP then
            for _, fruit in ipairs(ScanWorkspaceFruits()) do
                local handle = fruit:FindFirstChild("Handle") :: BasePart? or fruit:FindFirstChildWhichIsA("BasePart")
                if handle then
                    activeTargets[fruit] = true
                    local dist = math.floor((handle.Position - root.Position).Magnitude)
                    AttachESP(fruit, handle, string.format("[Fruit] %s (%dm)", fruit.Name, dist), Theme.AccentGlow)
                end
            end
        end

        if State.Config.ChestESP then
            for _, obj in ipairs(workspace:GetChildren()) do
                if obj:IsA("BasePart") and string.find(string.lower(obj.Name), "chest", 1, true) then
                    activeTargets[obj] = true
                    local dist = math.floor((obj.Position - root.Position).Magnitude)
                    AttachESP(obj, obj, string.format("[Chest] %dm", dist), Theme.Warning)
                end
            end
        end

        if State.Config.PlayerESP then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer and plr.Character then
                    local pRoot = plr.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
                    if pRoot then
                        activeTargets[plr.Character] = true
                        local dist = math.floor((pRoot.Position - root.Position).Magnitude)
                        AttachESP(plr.Character, pRoot, string.format("%s [%dm]", plr.Name, dist), Theme.Success)
                    end
                end
            end
        end
    end

    -- Удаление устаревших ESP маркеров
    for target, gui in pairs(State.ESPObjects) do
        if not activeTargets[target] or not target.Parent then
            if gui and gui.Parent then
                gui:Destroy()
            end
            State.ESPObjects[target] = nil
        end
    end
end))

-- Очистка соединений при удалении GUI
ScreenGui.Destroying:Connect(function()
    for _, conn in ipairs(State.Connections) do
        if conn.Connected then
            conn:Disconnect()
        end
    end
    ClearAllESP()
end)

-- ============================================================================
-- 9. ИНИЦИАЛИЗАЦИЯ ПРИ ЗАПУСКЕ
-- ============================================================================

ConfigManager.LoadFromDisk()
UIScaleObj.Scale = State.Config.UIScale
for _, refresh in ipairs(ConfigRefreshCallbacks) do
    refresh()
end
UpdatePriorityDisplay()
SelectTab("Main")

-- Плавная анимация появления при первом запуске
MainFrame.Size = UDim2.new(0, 620, 0, 0)
Tween(MainFrame, 0.32, { Size = UDim2.new(0, 620, 0, 400) })
