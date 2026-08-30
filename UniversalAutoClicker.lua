-- ============================================================
--  通用智能自动连点器 v2.0 - Velvet UI
--  自动检测 Remote → 优先调 Remote → 兜底模拟鼠标
--  执行即用，无需配置
--  UI: Velvet Library (github.com/DexCodeSX/Velvet)
-- ============================================================

-- ==================== Velvet UI 加载 ====================
local repo = "https://raw.githubusercontent.com/DexCodeSX/Velvet/main/"
local Velvet = loadstring(game:HttpGet(repo .. "Library.lua"))()
local Icons = loadstring(game:HttpGet(repo .. "addons/Icons.lua"))()
Velvet:SetIcons(Icons)

-- ==================== 核心引用 ====================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")
local LocalPlayer = Players.LocalPlayer

-- ==================== 状态 ====================
local State = {
    IsRunning = false,
    TotalClicks = 0,
    StartTime = 0,
    ClicksPerSecond = 0,
    DetectionDone = false,
    DetectedRemotes = {},
    ClickMethod = "unknown", -- "remote" | "mouse" | "touch"
}

-- ==================== 配置 ====================
local CONFIG = {
    ClickSpeed = 10,
    ClickDelay = 0.01,
}

-- ==================== Remote 自动检测 ====================
-- 常见点击类 Remote 关键词
local CLICK_KEYWORDS = {
    "click", "Click", "CLICK",
    "tap", "Tap", "TAP",
    "hit", "Hit", "HIT",
    "kick", "Kick", "KICK",
    "fire", "Fire", "FIRE",
    "punch", "Punch", "PUNCH",
    "attack", "Attack", "ATTACK",
    "shoot", "Shoot", "SHOOT",
    "swing", "Swing", "SWING",
    "collect", "Collect", "COLLECT",
    "farm", "Farm", "FARM",
    "heat", "Heat", "HEAT",
    "add", "Add", "ADD",
    "action", "Action", "ACTION",
    "input", "Input", "INPUT",
    "interact", "Interact", "INTERACT",
    "use", "Use", "USE",
}

local function isClickRelated(name)
    for _, kw in ipairs(CLICK_KEYWORDS) do
        if string.find(name, kw) then return true end
    end
    return false
end

local function scanForRemotes(parent, depth)
    depth = depth or 0
    if depth > 5 then return {} end

    local found = {}

    for _, child in ipairs(parent:GetChildren()) do
        -- 检测 RemoteEvent / RemoteFunction
        if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
            if isClickRelated(child.Name) then
                table.insert(found, {
                    Name = child.Name,
                    Object = child,
                    Type = child.ClassName,
                    Path = child:GetFullName(),
                    Score = #child.Name, -- 越短越可能是核心 Remote
                })
            end
        end

        -- 递归搜索子目录
        if child:IsA("Folder") or child:IsA("Model") or child:IsA("Configuration") then
            local sub = scanForRemotes(child, depth + 1)
            for _, s in ipairs(sub) do
                table.insert(found, s)
            end
        end
    end

    return found
end

local function detectAndSortRemotes()
    local all = {}

    -- 扫描 ReplicatedStorage
    local rsRemotes = scanForRemotes(ReplicatedStorage)
    for _, r in ipairs(rsRemotes) do table.insert(all, r) end

    -- 也扫描 workspace 下的脚本
    pcall(function()
        for _, child in ipairs(workspace:GetChildren()) do
            local sub = scanForRemotes(child)
            for _, s in ipairs(sub) do table.insert(all, s) end
        end
    end)

    -- 按分数排序 (越短越优先，优先 RemoteEvent)
    table.sort(all, function(a, b)
        if a.Type == "RemoteEvent" and b.Type == "RemoteFunction" then return true end
        if b.Type == "RemoteEvent" and a.Type == "RemoteFunction" then return false end
        return a.Score < b.Score
    end)

    return all
end

-- ==================== 点击方法 ====================
local function clickViaRemote(remote)
    if remote.Type == "RemoteEvent" then
        pcall(function() remote.Object:FireServer() end)
    elseif remote.Type == "RemoteFunction" then
        pcall(function() remote.Object:InvokeServer() end)
    end
    State.TotalClicks = State.TotalClicks + 1
end

local function clickViaMouse()
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, nil, 0)
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, nil, 0)
    State.TotalClicks = State.TotalClicks + 1
end

local function clickViaTouch()
    local cam = workspace.CurrentCamera
    local size = cam.ViewportSize
    VirtualInputManager:SendTouchEvent(size.X / 2, size.Y / 2, 0, Enum.UserInputState.Begin, nil)
    VirtualInputManager:SendTouchEvent(size.X / 2, size.Y / 2, 0, Enum.UserInputState.End, nil)
    State.TotalClicks = State.TotalClicks + 1
end

-- ==================== 格式 ====================
local function formatNumber(num)
    if num >= 1e15 then return string.format("%.2fQ", num / 1e15)
    elseif num >= 1e12 then return string.format("%.2fT", num / 1e12)
    elseif num >= 1e9 then return string.format("%.2fB", num / 1e9)
    elseif num >= 1e6 then return string.format("%.2fM", num / 1e6)
    elseif num >= 1e3 then return string.format("%.2fK", num / 1e3)
    else return tostring(num) end
end

local function formatTime(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    if h > 0 then return string.format("%dh %dm %ds", h, m, s)
    elseif m > 0 then return string.format("%dm %ds", m, s)
    else return string.format("%ds", s) end
end

-- ==================== 主循环 ====================
local function mainLoop()
    State.IsRunning = true
    State.StartTime = os.clock()
    State.TotalClicks = 0

    -- 选择点击方法
    local clickMethod = clickViaMouse -- 默认
    local detectedInfo = "未检测到 Remote，使用鼠标模拟"

    if #State.DetectedRemotes > 0 then
        local best = State.DetectedRemotes[1]
        -- 测试 Remote 是否可用
        local ok, err = pcall(function()
            if best.Type == "RemoteEvent" then
                best.Object:FireServer()
            else
                best.Object:InvokeServer()
            end
        end)

        if ok then
            clickMethod = clickViaRemote
            State.ClickMethod = "remote"
            detectedInfo = string.format("检测到 Remote: %s (%s)", best.Name, best.Type)
            Velvet:Notify({
                Title = "检测成功",
                Content = string.format("使用 Remote 点击: %s", best.Name),
                Duration = 3,
                Type = "success",
            })
        else
            detectedInfo = string.format("Remote %s 不可用，降级为鼠标模拟", best.Name)
            Velvet:Notify({
                Title = "降级",
                Content = detectedInfo,
                Duration = 3,
                Type = "warning",
            })
        end
    else
        Velvet:Notify({
            Title = "检测结果",
            Content = "未检测到点击 Remote，使用鼠标模拟",
            Duration = 3,
            Type = "info",
        })
    end

    Velvet:Notify({ Title = "启动", Content = "自动连点已启动！", Duration = 2, Type = "success" })

    while State.IsRunning do
        local now = os.clock()

        for i = 1, CONFIG.ClickSpeed do
            clickMethod(State.DetectedRemotes[1])
        end

        -- 更新 CPS
        if State.TotalClicks % (CONFIG.ClickSpeed * 2) == 0 then
            local elapsed = now - State.StartTime
            if elapsed > 0 then
                State.ClicksPerSecond = math.floor(State.TotalClicks / elapsed)
            end
        end

        task.wait(0.01)
    end
end

-- ==================== 检测并构建 UI ====================
State.DetectedRemotes = detectAndSortRemotes()

local detectedText = "未检测到 Remote"
local remoteList = ""
if #State.DetectedRemotes > 0 then
    detectedText = string.format("检测到 %d 个 Remote", #State.DetectedRemotes)
    local items = {}
    for i, r in ipairs(State.DetectedRemotes) do
        table.insert(items, string.format("  %d. %s (%s)", i, r.Name, r.Type))
        if i >= 5 then break end
    end
    remoteList = table.concat(items, "\n")
end

State.DetectionDone = true

-- ==================== Velvet UI ====================
local Window = Velvet:CreateWindow({
    Title = "Smart Auto Clicker",
    SubTitle = "v2.0 · Auto Detect",
    ToggleKey = Enum.KeyCode.RightShift,
})

-- ---------- Tab 1: 主控 ----------
local MainTab = Window:AddTab("主控", "play")
local isRunning = false

local ToggleSection = MainTab:AddSection("运行控制")

ToggleSection:AddToggle("RunToggle", {
    Text = "自动连点",
    Default = false,
    Callback = function(v)
        if v and not isRunning then
            isRunning = true
            task.spawn(function() mainLoop() end)
        elseif not v then
            isRunning = false
            State.IsRunning = false
            Velvet:Notify({ Title = "暂停", Content = "已暂停", Duration = 2, Type = "warning" })
        end
    end,
})

ToggleSection:AddSlider("ClickSpeed", {
    Text = "点击速度",
    Min = 1, Max = 100, Default = 10,
    Suffix = "次/秒",
    Callback = function(v)
        CONFIG.ClickSpeed = v
        CONFIG.ClickDelay = 1 / v
    end,
})

local StatsSection = MainTab:AddSection("实时数据")
StatsSection:AddParagraph({
    Title = "状态",
    Content = string.format(
        "⚡ CPS: 0/s\n" ..
        "👆 总点击: 0\n" ..
        "⏱ 运行: 0s\n" ..
        "🔧 方式: %s",
        #State.DetectedRemotes > 0 and "Remote 调用" or "鼠标模拟"
    ),
})

-- ---------- Tab 2: 检测结果 ----------
local DetectTab = Window:AddTab("检测", "search")

local DetectSection = DetectTab:AddSection("Remote 检测结果")
DetectSection:AddParagraph({
    Title = detectedText,
    Content = remoteList ~= "" and remoteList or "将使用 VirtualInputManager 模拟鼠标点击",
})

DetectSection:AddDivider()

DetectSection:AddButton({
    Text = "重新检测",
    Callback = function()
        State.DetectedRemotes = detectAndSortRemotes()
        local count = #State.DetectedRemotes
        if count > 0 then
            local names = {}
            for i, r in ipairs(State.DetectedRemotes) do
                table.insert(names, r.Name)
                if i >= 5 then break end
            end
            Velvet:Notify({
                Title = "重新检测",
                Content = string.format("找到 %d 个 Remote: %s", count, table.concat(names, ", ")),
                Duration = 4,
                Type = "success",
            })
        else
            Velvet:Notify({
                Title = "重新检测",
                Content = "未找到点击 Remote，将使用鼠标模拟",
                Duration = 3,
                Type = "info",
            })
        end
    end,
})

-- ---------- Tab 3: 信息 ----------
local InfoTab = Window:AddTab("信息", "info")

local InfoSection = InfoTab:AddSection("关于脚本")
InfoSection:AddParagraph({
    Title = "智能自动连点器 v2.0",
    Content = "执行即用，无需配置。\n\n" ..
        "工作流程:\n" ..
        "  1. 自动扫描游戏中的 Remote\n" ..
        "  2. 匹配点击类关键词\n" ..
        "  3. 测试 Remote 可用性\n" ..
        "  4. 优先调 Remote，兜底模拟鼠标\n\n" ..
        "检测关键词: click/tap/hit/kick/fire/\n" ..
        "  punch/attack/shoot/swing/collect/\n" ..
        "  farm/heat/add/action/input/interact\n\n" ..
        "UI: Velvet Library\n" ..
        "按 RightShift 打开/关闭",
})

InfoSection:AddDivider()

InfoSection:AddParagraph({
    Title = "操作说明",
    Content = "1. 执行脚本 → 自动检测\n" ..
        "2. 按 RightShift 打开面板\n" ..
        "3. 查看「检测」标签页看结果\n" ..
        "4. 回到「主控」开启连点",
})

-- ==================== 启动 ====================
local methodLabel = #State.DetectedRemotes > 0
    and string.format("Remote: %s", State.DetectedRemotes[1].Name)
    or "鼠标模拟"

Velvet:Notify({
    Title = "Smart Auto Clicker",
    Content = string.format("v2.0 已加载！检测结果: %s", methodLabel),
    Duration = 5,
    Type = "success",
})

print("========================================")
print(" Smart Auto Clicker v2.0 - Velvet UI")
print(" 自动检测 + 智能点击")
print("========================================")
print(" 检测结果:", methodLabel)
if #State.DetectedRemotes > 0 then
    for i, r in ipairs(State.DetectedRemotes) do
        print(string.format("  %d. %s (%s) - %s", i, r.Name, r.Type, r.Path))
        if i >= 10 then break end
    end
end
print("========================================")
print(" 操作: 按 RightShift 打开面板")
print("========================================")