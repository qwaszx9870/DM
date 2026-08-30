-- ============================================================
--  通用智能自动连点器 v3.0 - Velvet UI
--  自动检测 Remote → 直接调 Remote 点击 (非模拟鼠标)
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
local LocalPlayer = Players.LocalPlayer

-- ==================== 状态 ====================
local State = {
    IsRunning = false,
    TotalClicks = 0,
    StartTime = 0,
    ClicksPerSecond = 0,
    DetectedRemotes = {},
    ActiveRemote = nil, -- 当前使用的 Remote
    DetectionDone = false,
}

-- ==================== 配置 ====================
local CONFIG = {
    ClickSpeed = 10,
}

-- ==================== Remote 自动检测 ====================
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
    "activate", "Activate", "ACTIVATE",
    "trigger", "Trigger", "TRIGGER",
    "press", "Press", "PRESS",
    "hold", "Hold", "HOLD",
    "boost", "Boost", "BOOST",
    "claim", "Claim", "CLAIM",
    "buy", "Buy", "BUY",
    "sell", "Sell", "SELL",
    "upgrade", "Upgrade", "UPGRADE",
    "equip", "Equip", "EQUIP",
    "select", "Select", "SELECT",
    "submit", "Submit", "SUBMIT",
    "confirm", "Confirm", "CONFIRM",
    "start", "Start", "START",
    "begin", "Begin", "BEGIN",
    "roll", "Roll", "ROLL",
    "spin", "Spin", "SPIN",
    "open", "Open", "OPEN",
    "grab", "Grab", "GRAB",
    "pick", "Pick", "PICK",
    "get", "Get", "GET",
    "send", "Send", "SEND",
    "do", "Do", "DO",
    "run", "Run", "RUN",
    "go", "Go", "GO",
}

local function isClickRelated(name)
    for _, kw in ipairs(CLICK_KEYWORDS) do
        if string.find(name, kw, 1, true) then return true end
    end
    return false
end

local function scanForRemotes(parent, depth)
    depth = depth or 0
    if depth > 6 then return {} end
    local found = {}
    for _, child in ipairs(parent:GetChildren()) do
        if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
            if isClickRelated(child.Name) then
                table.insert(found, {
                    Name = child.Name,
                    Object = child,
                    Type = child.ClassName,
                    Path = child:GetFullName(),
                    Score = #child.Name,
                })
            end
        end
        -- 递归搜索子目录
        pcall(function()
            for _, sub in ipairs(child:GetChildren()) do
                if sub:IsA("Folder") or sub:IsA("Model") or sub:IsA("Configuration") then
                    local nested = scanForRemotes(sub, depth + 1)
                    for _, n in ipairs(nested) do table.insert(found, n) end
                end
            end
        end)
    end
    return found
end

local function detectAndSortRemotes()
    local all = {}
    pcall(function()
        local rsRemotes = scanForRemotes(ReplicatedStorage)
        for _, r in ipairs(rsRemotes) do table.insert(all, r) end
    end)
    pcall(function()
        for _, child in ipairs(workspace:GetChildren()) do
            local sub = scanForRemotes(child)
            for _, s in ipairs(sub) do table.insert(all, s) end
        end
    end)

    -- 排序: RemoteEvent 优先于 RemoteFunction，名字越短越优先
    table.sort(all, function(a, b)
        if a.Type == "RemoteEvent" and b.Type == "RemoteFunction" then return true end
        if b.Type == "RemoteEvent" and a.Type == "RemoteFunction" then return false end
        return a.Score < b.Score
    end)

    return all
end

-- ==================== 核心点击 ====================
local function fireRemoteClick(remote)
    if remote.Type == "RemoteEvent" then
        pcall(function() remote.Object:FireServer() end)
    elseif remote.Type == "RemoteFunction" then
        pcall(function() remote.Object:InvokeServer() end)
    end
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
    if not State.ActiveRemote then
        Velvet:Notify({
            Title = "错误",
            Content = "未检测到可用 Remote，请先检测",
            Duration = 3,
            Type = "error",
        })
        State.IsRunning = false
        return
    end

    State.IsRunning = true
    State.StartTime = os.clock()
    State.TotalClicks = 0

    local activeRemote = State.ActiveRemote

    Velvet:Notify({
        Title = "启动",
        Content = string.format("使用 Remote: %s 开始连点", activeRemote.Name),
        Duration = 2,
        Type = "success",
    })

    while State.IsRunning do
        local now = os.clock()

        for i = 1, CONFIG.ClickSpeed do
            fireRemoteClick(activeRemote)
        end

        if State.TotalClicks % (CONFIG.ClickSpeed * 2) == 0 then
            local elapsed = now - State.StartTime
            if elapsed > 0 then
                State.ClicksPerSecond = math.floor(State.TotalClicks / elapsed)
            end
        end

        task.wait(0.01)
    end
end

-- ==================== 检测并选择 Remote ====================
local function runDetection()
    State.DetectedRemotes = detectAndSortRemotes()

    if #State.DetectedRemotes > 0 then
        -- 测试第一个 Remote 是否可用
        local best = State.DetectedRemotes[1]
        local ok, err = pcall(function()
            if best.Type == "RemoteEvent" then
                best.Object:FireServer()
            else
                best.Object:InvokeServer()
            end
        end)

        if ok then
            State.ActiveRemote = best
            Velvet:Notify({
                Title = "检测成功",
                Content = string.format("使用: %s (%s)", best.Name, best.Type),
                Duration = 3,
                Type = "success",
            })
            return true
        else
            -- 尝试下一个
            for i = 2, #State.DetectedRemotes do
                local alt = State.DetectedRemotes[i]
                local ok2 = pcall(function()
                    if alt.Type == "RemoteEvent" then
                        alt.Object:FireServer()
                    else
                        alt.Object:InvokeServer()
                    end
                end)
                if ok2 then
                    State.ActiveRemote = alt
                    Velvet:Notify({
                        Title = "检测成功",
                        Content = string.format("使用: %s (%s)", alt.Name, alt.Type),
                        Duration = 3,
                        Type = "success",
                    })
                    return true
                end
            end
        end
    end

    -- 全失败
    Velvet:Notify({
        Title = "检测失败",
        Content = "未找到可用 Remote，请手动抓包",
        Duration = 4,
        Type = "error",
    })
    return false
end

-- 首次检测
State.DetectionDone = runDetection()

-- ==================== Velvet UI ====================
local Window = Velvet:CreateWindow({
    Title = "Smart Auto Clicker",
    SubTitle = "v3.0 · Remote Click",
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
            if not State.ActiveRemote then
                Velvet:Notify({
                    Title = "无法启动",
                    Content = "未检测到可用 Remote，请先检测",
                    Duration = 3,
                    Type = "error",
                })
                return
            end
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
    Callback = function(v) CONFIG.ClickSpeed = v end,
})

local activeName = State.ActiveRemote and State.ActiveRemote.Name or "无"
local activeType = State.ActiveRemote and State.ActiveRemote.Type or "-"

local StatsSection = MainTab:AddSection("实时数据")
StatsSection:AddParagraph({
    Title = "状态",
    Content = string.format(
        "⚡ CPS: 0/s\n" ..
        "👆 总点击: 0\n" ..
        "⏱ 运行: 0s\n" ..
        "🔧 Remote: %s (%s)",
        activeName, activeType
    ),
})

-- ---------- Tab 2: 检测 ----------
local DetectTab = Window:AddTab("检测", "search")

local DetectSection = DetectTab:AddSection("Remote 检测结果")
local detectCount = #State.DetectedRemotes
local detectTitle = detectCount > 0
    and string.format("检测到 %d 个 Remote", detectCount)
    or "未检测到可用 Remote"

local detectContent = ""
if detectCount > 0 then
    local items = {}
    for i, r in ipairs(State.DetectedRemotes) do
        local marker = (State.ActiveRemote == r) and " ✅" or ""
        table.insert(items, string.format("  %d. %s (%s)%s", i, r.Name, r.Type, marker))
        if i >= 10 then break end
    end
    detectContent = table.concat(items, "\n")
else
    detectContent = "请用 RemoteSpy 抓取点击操作的 Remote，\n将名称加入脚本关键词列表"
end

DetectSection:AddParagraph({
    Title = detectTitle,
    Content = detectContent,
})

DetectSection:AddDivider()

DetectSection:AddButton({
    Text = "重新检测",
    Callback = function()
        local ok = runDetection()
        if ok and State.ActiveRemote then
            Velvet:Notify({
                Title = "检测完成",
                Content = string.format("使用: %s (%s)", State.ActiveRemote.Name, State.ActiveRemote.Type),
                Duration = 3,
                Type = "success",
            })
        end
    end,
})

-- ---------- Tab 3: 信息 ----------
local InfoTab = Window:AddTab("信息", "info")

local InfoSection = InfoTab:AddSection("关于脚本")
InfoSection:AddParagraph({
    Title = "智能自动连点器 v3.0",
    Content = "纯 Remote 调用，非模拟鼠标。\n\n" ..
        "工作流程:\n" ..
        "  1. 扫描游戏中的 RemoteEvent/RemoteFunction\n" ..
        "  2. 匹配 40+ 点击关键词\n" ..
        "  3. 测试可用性\n" ..
        "  4. 直接 FireServer/InvokeServer 调用\n\n" ..
        "不模拟鼠标，不模拟触摸，直接调 Remote。\n\n" ..
        "UI: Velvet Library\n" ..
        "按 RightShift 打开/关闭",
})

InfoSection:AddDivider()

InfoSection:AddParagraph({
    Title = "操作说明",
    Content = "1. 执行脚本 → 自动检测\n" ..
        "2. 按 RightShift 打开面板\n" ..
        "3. 去「检测」标签页确认结果\n" ..
        "4. 回「主控」开启连点\n\n" ..
        "如果检测不到，说明游戏 Remote 命名\n" ..
        "不在关键词列表里，需要抓包分析",
})

-- ==================== 启动 ====================
local methodInfo = State.ActiveRemote
    and string.format("Remote: %s (%s)", State.ActiveRemote.Name, State.ActiveRemote.Type)
    or "未检测到"

Velvet:Notify({
    Title = "Smart Auto Clicker",
    Content = string.format("v3.0 已加载！%s", methodInfo),
    Duration = 5,
    Type = State.ActiveRemote and "success" or "warning",
})

print("========================================")
print(" Smart Auto Clicker v3.0 - Remote Click")
print(" 纯 Remote 调用，不模拟鼠标")
print("========================================")
print(" 检测结果:", methodInfo)
if #State.DetectedRemotes > 0 then
    for i, r in ipairs(State.DetectedRemotes) do
        local active = (State.ActiveRemote == r) and " ← 当前使用" or ""
        print(string.format("  %d. %s (%s) - %s%s", i, r.Name, r.Type, r.Path, active))
        if i >= 10 then break end
    end
else
    print("  未检测到可用 Remote，请用 RemoteSpy 抓包")
end
print("========================================")
print(" 操作: 按 RightShift 打开面板")
print("========================================")