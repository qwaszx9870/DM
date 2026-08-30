-- ============================================================
--  通用智能自动连点器 v4.0 - Velvet UI
--  内置 RemoteSpy: 你点一下，脚本自动学会
--  无需手动抓包，无需导出日志
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
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

-- ==================== 状态 ====================
local State = {
    IsRunning = false,
    IsLearning = false,          -- 学习模式
    TotalClicks = 0,
    StartTime = 0,
    ClicksPerSecond = 0,
    ActiveRemote = nil,           -- 当前使用的 Remote
    AllRemotes = {},              -- 所有检测到的 Remote
    CapturedRemote = nil,         -- 学习到的 Remote
    HookedRemotes = {},           -- 已 hook 的 Remote 引用
}

-- ==================== 配置 ====================
local CONFIG = {
    ClickSpeed = 10,
}

-- ==================== 内置 RemoteSpy: Hook 所有 Remote ====================
local function hookRemoteEvent(remoteEvent)
    local name = remoteEvent.Name
    local path = pcall(function() return remoteEvent:GetFullName() end) and remoteEvent:GetFullName() or name

    -- Hook FireServer
    local oldFireServer = hookfunction(remoteEvent.FireServer, function(self, ...)
        -- 学习模式下记录
        if State.IsLearning then
            State.CapturedRemote = {
                Name = name,
                Object = self,
                Type = "RemoteEvent",
                Path = path,
                Args = {...},
            }
            State.IsLearning = false
            Velvet:Notify({
                Title = "学习成功！",
                Content = string.format("捕获到 Remote: %s (RemoteEvent)", name),
                Duration = 4,
                Type = "success",
            })
            print("[RemoteSpy] 捕获 RemoteEvent:", name, "参数:", ...)
        end
        -- 正常调用
        return oldFireServer(self, ...)
    end)

    table.insert(State.HookedRemotes, { Object = remoteEvent, Name = name, Type = "RemoteEvent", Path = path })
end

local function hookRemoteFunction(remoteFunction)
    local name = remoteFunction.Name
    local path = pcall(function() return remoteFunction:GetFullName() end) and remoteFunction:GetFullName() or name

    local oldInvoke = hookfunction(remoteFunction.InvokeServer, function(self, ...)
        if State.IsLearning then
            State.CapturedRemote = {
                Name = name,
                Object = self,
                Type = "RemoteFunction",
                Path = path,
                Args = {...},
            }
            State.IsLearning = false
            Velvet:Notify({
                Title = "学习成功！",
                Content = string.format("捕获到 Remote: %s (RemoteFunction)", name),
                Duration = 4,
                Type = "success",
            })
            print("[RemoteSpy] 捕获 RemoteFunction:", name, "参数:", ...)
        end
        return oldInvoke(self, ...)
    end)

    table.insert(State.HookedRemotes, { Object = remoteFunction, Name = name, Type = "RemoteFunction", Path = path })
end

local function scanAndHookAllRemotes(parent, depth)
    depth = depth or 0
    if depth > 6 then return end
    for _, child in ipairs(parent:GetChildren()) do
        if child:IsA("RemoteEvent") then
            pcall(function() hookRemoteEvent(child) end)
            table.insert(State.AllRemotes, { Name = child.Name, Type = "RemoteEvent", Path = child:GetFullName() })
        elseif child:IsA("RemoteFunction") then
            pcall(function() hookRemoteFunction(child) end)
            table.insert(State.AllRemotes, { Name = child.Name, Type = "RemoteFunction", Path = child:GetFullName() })
        end
        pcall(function()
            for _, sub in ipairs(child:GetChildren()) do
                if sub:IsA("Folder") or sub:IsA("Model") or sub:IsA("Configuration") then
                    scanAndHookAllRemotes(sub, depth + 1)
                end
            end
        end)
    end
end

-- 扫描 ReplicatedStorage
pcall(function() scanAndHookAllRemotes(ReplicatedStorage) end)
-- 扫描 workspace
pcall(function()
    for _, child in ipairs(workspace:GetChildren()) do
        scanAndHookAllRemotes(child)
    end
end)

-- 持续监听新 Remote (游戏可能延迟加载)
local function watchForNewRemotes()
    local function onDescendantAdded(descendant)
        if descendant:IsA("RemoteEvent") then
            pcall(function() hookRemoteEvent(descendant) end)
            table.insert(State.AllRemotes, { Name = descendant.Name, Type = "RemoteEvent", Path = descendant:GetFullName() })
        elseif descendant:IsA("RemoteFunction") then
            pcall(function() hookRemoteFunction(descendant) end)
            table.insert(State.AllRemotes, { Name = descendant.Name, Type = "RemoteFunction", Path = descendant:GetFullName() })
        end
    end
    ReplicatedStorage.DescendantAdded:Connect(onDescendantAdded)
    pcall(function()
        workspace.DescendantAdded:Connect(function(descendant)
            if descendant:IsA("RemoteEvent") or descendant:IsA("RemoteFunction") then
                onDescendantAdded(descendant)
            end
        end)
    end)
end
pcall(watchForNewRemotes)

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

-- ==================== 学习模式: 等待用户点击 ====================
local function startLearning()
    if State.IsRunning then
        Velvet:Notify({
            Title = "请先停止",
            Content = "请先停止连点再学习",
            Duration = 3,
            Type = "warning",
        })
        return
    end

    State.IsLearning = true
    State.CapturedRemote = nil

    Velvet:Notify({
        Title = "学习模式",
        Content = "请在游戏里点击一次！",
        Duration = 10,
        Type = "info",
    })

    print("[RemoteSpy] 学习模式已开启，在游戏里点击一次...")

    -- 60 秒超时
    task.delay(60, function()
        if State.IsLearning then
            State.IsLearning = false
            Velvet:Notify({
                Title = "超时",
                Content = "60 秒内未检测到点击，请重试",
                Duration = 4,
                Type = "error",
            })
        end
    end)
end

-- ==================== 主循环 ====================
local function mainLoop()
    if not State.ActiveRemote then
        -- 尝试用学习到的
        if State.CapturedRemote then
            State.ActiveRemote = State.CapturedRemote
        else
            Velvet:Notify({
                Title = "未学习",
                Content = "请先点「学习」按钮，然后在游戏里点一下",
                Duration = 4,
                Type = "error",
            })
            State.IsRunning = false
            return
        end
    end

    State.IsRunning = true
    State.StartTime = os.clock()
    State.TotalClicks = 0

    local active = State.ActiveRemote

    Velvet:Notify({
        Title = "启动",
        Content = string.format("使用: %s 开始连点", active.Name),
        Duration = 2,
        Type = "success",
    })

    while State.IsRunning do
        local now = os.clock()

        for i = 1, CONFIG.ClickSpeed do
            fireRemoteClick(active)
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

-- ==================== Velvet UI ====================
local Window = Velvet:CreateWindow({
    Title = "Smart Auto Clicker",
    SubTitle = "v4.0 · 内置 RemoteSpy",
    ToggleKey = Enum.KeyCode.RightShift,
})

-- ---------- Tab 1: 主控 ----------
local MainTab = Window:AddTab("主控", "play")
local isRunning = false

local ToggleSection = MainTab:AddSection("运行控制")

ToggleSection:AddButton({
    Text = "🎯 学习: 在游戏里点一下",
    Callback = function() startLearning() end,
})

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
    Callback = function(v) CONFIG.ClickSpeed = v end,
})

local activeName = State.ActiveRemote and State.ActiveRemote.Name or "未学习"
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

-- ---------- Tab 2: 已监控 Remote ----------
local SpyTab = Window:AddTab("RemoteSpy", "search")

local SpySection = SpyTab:AddSection("已监控的 Remote")
local totalCount = #State.AllRemotes
local spyTitle = string.format("已 Hook %d 个 Remote (自动)", totalCount)

local spyContent = ""
if totalCount > 0 then
    local maxShow = math.min(totalCount, 15)
    local items = {}
    for i = 1, maxShow do
        local r = State.AllRemotes[i]
        local marker = ""
        if State.ActiveRemote and State.ActiveRemote.Name == r.Name then
            marker = " ← 当前使用"
        end
        if State.CapturedRemote and State.CapturedRemote.Name == r.Name then
            marker = " ← 已学习"
        end
        table.insert(items, string.format("  %d. %s (%s)%s", i, r.Name, r.Type, marker))
    end
    if totalCount > maxShow then
        table.insert(items, string.format("  ... 还有 %d 个", totalCount - maxShow))
    end
    spyContent = table.concat(items, "\n")
else
    spyContent = "正在扫描中..."
end

SpySection:AddParagraph({
    Title = spyTitle,
    Content = spyContent,
})

SpySection:AddDivider()

SpySection:AddButton({
    Text = "重新扫描",
    Callback = function()
        State.AllRemotes = {}
        State.HookedRemotes = {}
        pcall(function() scanAndHookAllRemotes(ReplicatedStorage) end)
        pcall(function()
            for _, child in ipairs(workspace:GetChildren()) do
                scanAndHookAllRemotes(child)
            end
        end)
        Velvet:Notify({
            Title = "扫描完成",
            Content = string.format("找到 %d 个 Remote", #State.AllRemotes),
            Duration = 3,
            Type = "success",
        })
    end,
})

SpySection:AddButton({
    Text = "手动设置 Remote",
    Callback = function()
        -- 列出所有 Remote 供选择
        local names = {}
        for _, r in ipairs(State.AllRemotes) do
            table.insert(names, string.format("%s (%s)", r.Name, r.Type))
        end
        if #names == 0 then
            Velvet:Notify({
                Title = "无 Remote",
                Content = "未扫描到任何 Remote",
                Duration = 3,
                Type = "error",
            })
            return
        end
        -- 用第一个作为默认
        if #State.AllRemotes > 0 then
            State.ActiveRemote = State.AllRemotes[1]
            Velvet:Notify({
                Title = "已设置",
                Content = string.format("使用: %s", State.AllRemotes[1].Name),
                Duration = 3,
                Type = "success",
            })
        end
    end,
})

-- ---------- Tab 3: 信息 ----------
local InfoTab = Window:AddTab("信息", "info")

local InfoSection = InfoTab:AddSection("使用说明")
InfoSection:AddParagraph({
    Title = "内置 RemoteSpy v4.0",
    Content = "完全自动化，无需手动抓包。\n\n" ..
        "使用方法:\n" ..
        "  1. 执行脚本\n" ..
        "  2. 点「学习」按钮\n" ..
        "  3. 在游戏里点一下（你正常点击）\n" ..
        "  4. 脚本自动捕获你点击的是哪个 Remote\n" ..
        "  5. 开启自动连点\n\n" ..
        "原理:\n" ..
        "  Hook 所有 Remote 的 FireServer/InvokeServer\n" ..
        "  你点击时脚本自动记录是哪个 Remote 被调用\n" ..
        "  然后疯狂调用它\n\n" ..
        "换游戏时:\n" ..
        "  重新点「学习」→ 在游戏里点一下 → 开连点\n" ..
        "  全程不需要抓包，不需要导出日志，不需要找我\n\n" ..
        "UI: Velvet Library\n" ..
        "按 RightShift 打开/关闭",
})

InfoSection:AddDivider()

InfoSection:AddParagraph({
    Title = "快捷操作",
    Content = "🔄 换游戏: 学习 → 点击 → 连点\n" ..
        "📋 换操作: 同上\n" ..
        "🛑 停止: 按 RightShift 打开面板关闭",
})

-- ==================== 启动 ====================
Velvet:Notify({
    Title = "Smart Auto Clicker v4.0",
    Content = "内置 RemoteSpy 已就绪！点「学习」→ 在游戏里点一下 → 开连点",
    Duration = 6,
    Type = "success",
})

print("========================================")
print(" Smart Auto Clicker v4.0 - 内置 RemoteSpy")
print("========================================")
print(" 已 Hook Remote 数量:", #State.AllRemotes)
print("")
print(" 使用方法:")
print("  1. 按 RightShift 打开面板")
print("  2. 点「学习」按钮")
print("  3. 在游戏里正常点击一次")
print("  4. 脚本自动捕获你点击的 Remote")
print("  5. 开启自动连点")
print("")
print(" 换游戏: 重新点「学习」→ 点一下 → 开连点")
print(" 全程不需要手动抓包！")
print("========================================")