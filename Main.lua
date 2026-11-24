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
