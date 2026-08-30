-- ============================================================
--  通用智能自动连点器 v5.0 - Velvet UI
--  内置 RemoteSpy: 你点一下，脚本自动学会
--  名字查表法: 不依赖 hookfunction 的 self 引用
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
local LocalPlayer = Players.LocalPlayer

-- ==================== 全局 Remote 查找表 ====================
-- 按名字找 Remote 对象，不依赖 hook 的 self
local RemoteByName = {}
local RemoteCache = {}  -- 名字 → {Object, Type, Args} 缓存

local function findRemoteByName(name)
    -- 先查缓存
    if RemoteByName[name] then
        return RemoteByName[name]
    end
    -- 全局搜索
    local all = game:GetDescendants()
    for _, child in ipairs(all) do
        if child.Name == name and (child:IsA("RemoteEvent") or child:IsA("RemoteFunction")) then
            RemoteByName[name] = child
            return child
        end
    end
    return nil
end

-- ==================== 状态 ====================
local State = {
    IsRunning = false,
    IsLearning = false,
    TotalClicks = 0,
    StartTime = 0,
    ClicksPerSecond = 0,
    ActiveRemote = nil,            -- {Name, Type, Args}
    AllRemotes = {},               -- 所有检测到的 Remote 列表
    CapturedRemote = nil,          -- 学习到的
    _LastError = nil,
}

-- ==================== 配置 ====================
local CONFIG = {
    ClickSpeed = 10,
    AutoMode = true,  -- 自动模式: 学习后自动启动
}

-- ==================== 注册 Remote 到查找表 ====================
local function registerRemote(child)
    RemoteByName[child.Name] = child
    local entry = {
        Name = child.Name,
        Type = child.ClassName,
        Path = pcall(function() return child:GetFullName() end) and child:GetFullName() or child.Name,
    }
    -- 避免重复
    for _, r in ipairs(State.AllRemotes) do
        if r.Name == child.Name and r.Type == child.ClassName then
            return
        end
    end
    table.insert(State.AllRemotes, entry)
end

local function scanAllRemotes()
    -- 全局扫描: 用 GetDescendants 一次性扫所有
    local all = game:GetDescendants()
    for _, child in ipairs(all) do
        if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
            registerRemote(child)
        end
    end
end

-- 初始扫描
pcall(scanAllRemotes)

-- 持续监听: 监听 game 全局
pcall(function()
    game.DescendantAdded:Connect(function(child)
        if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
            registerRemote(child)
        end
    end)
end)

-- ==================== 内置 RemoteSpy: Hook 所有 Remote ====================
local function autoStartClicking()
    if not CONFIG.AutoMode then return end
    if State.IsRunning then return end
    if not State.CapturedRemote then return end

    State.ActiveRemote = State.CapturedRemote

    -- 验证 Remote: 先用闭包引用，再用名字查表
    local real = State.ActiveRemote.Object
    if not real or not pcall(function() return real.Parent end) or not real.Parent then
        real = RemoteByName[State.ActiveRemote.Name]
        if real and not pcall(function() return real.Parent end) or not real.Parent then
            real = findRemoteByName(State.ActiveRemote.Name)
        end
    end
    if not real then
        warn("[AutoClicker] 自动启动失败: 找不到 Remote:", State.ActiveRemote.Name)
        return
    end
    State.ActiveRemote.Object = real
    RemoteByName[State.ActiveRemote.Name] = real

    State.IsRunning = true
    State.StartTime = os.clock()
    State.TotalClicks = 0
    State._LastError = nil

    Velvet:Notify({
        Title = "自动启动",
        Content = string.format("使用: %s\n速度: %d 次/秒", State.ActiveRemote.Name, CONFIG.ClickSpeed),
        Duration = 3,
        Type = "success",
    })
    print("[AutoClicker] 自动启动! Remote:", State.ActiveRemote.Name, "速度:", CONFIG.ClickSpeed, "次/秒")

    local active = State.ActiveRemote
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

local function hookRemoteEvent(remoteEvent)
    local name = remoteEvent.Name
    local realObject = remoteEvent  -- 闭包引用，可靠
    local oldFireServer
    oldFireServer = hookfunction(remoteEvent.FireServer, function(self, ...)
        if State.IsLearning then
            local args = {...}
            State.CapturedRemote = {
                Name = name,
                Object = realObject,  -- 闭包引用，不是 hook 的 self
                Type = "RemoteEvent",
                Args = args,
            }
            State.IsLearning = false

            local argsStr = "无参数"
            if #args > 0 then
                local parts = {}
                for i, v in ipairs(args) do
                    table.insert(parts, tostring(v))
                end
                argsStr = table.concat(parts, ", ")
            end
            print("[RemoteSpy] 捕获 RemoteEvent:", name, "参数:", argsStr)
            
            if CONFIG.AutoMode then
                task.spawn(autoStartClicking)
            end
        end
        return oldFireServer(self, ...)
    end)
end

local function hookRemoteFunction(remoteFunction)
    local name = remoteFunction.Name
    local realObject = remoteFunction  -- 闭包引用，可靠
    local oldInvoke
    oldInvoke = hookfunction(remoteFunction.InvokeServer, function(self, ...)
        if State.IsLearning then
            local args = {...}
            State.CapturedRemote = {
                Name = name,
                Object = realObject,  -- 闭包引用，不是 hook 的 self
                Type = "RemoteFunction",
                Args = args,
            }
            State.IsLearning = false

            local argsStr = "无参数"
            if #args > 0 then
                local parts = {}
                for i, v in ipairs(args) do
                    table.insert(parts, tostring(v))
                end
                argsStr = table.concat(parts, ", ")
            end
            print("[RemoteSpy] 捕获 RemoteFunction:", name, "参数:", argsStr)
            
            if CONFIG.AutoMode then
                task.spawn(autoStartClicking)
            end
        end
        return oldInvoke(self, ...)
    end)
end

local function hookAllRemotes(parent, depth)
    depth = depth or 0
    if depth > 6 then return end
    for _, child in ipairs(parent:GetChildren()) do
        if child:IsA("RemoteEvent") then
            pcall(function() hookRemoteEvent(child) end)
        elseif child:IsA("RemoteFunction") then
            pcall(function() hookRemoteFunction(child) end)
        end
        pcall(function()
            for _, sub in ipairs(child:GetChildren()) do
                if sub:IsA("Folder") or sub:IsA("Model") or sub:IsA("Configuration") then
                    hookAllRemotes(sub, depth + 1)
                end
            end
        end)
    end
end

pcall(function() hookAllRemotes(ReplicatedStorage) end)
pcall(function()
    for _, child in ipairs(workspace:GetChildren()) do
        hookAllRemotes(child)
    end
end)

-- 新 Remote 也 hook
pcall(function()
    ReplicatedStorage.DescendantAdded:Connect(function(child)
        if child:IsA("RemoteEvent") then pcall(function() hookRemoteEvent(child) end) end
        if child:IsA("RemoteFunction") then pcall(function() hookRemoteFunction(child) end) end
    end)
end)

-- ==================== 核心点击 (闭包引用优先 + 名字查表兜底) ====================
local function fireRemoteClick(remoteInfo)
    -- 1️⃣ 优先用闭包引用 (Object)
    local realRemote = remoteInfo.Object

    -- 2️⃣ 验证闭包引用还活着
    if realRemote then
        if not pcall(function() return realRemote.Parent end) or not realRemote.Parent then
            realRemote = nil
        end
    end

    -- 3️⃣ 闭包引用失效，用名字查表
    if not realRemote then
        realRemote = RemoteByName[remoteInfo.Name]
        if realRemote then
            if not pcall(function() return realRemote.Parent end) or not realRemote.Parent then
                RemoteByName[remoteInfo.Name] = nil
                realRemote = nil
            end
        end
    end

    -- 4️⃣ 名字查表也失效，全局搜索
    if not realRemote then
        realRemote = findRemoteByName(remoteInfo.Name)
    end

    -- 5️⃣ 全找不到，放弃
    if not realRemote then
        warn("[AutoClicker] 找不到 Remote:", remoteInfo.Name, "| 闭包和搜索都失败")
        return
    end

    -- 更新闭包引用 (下次直接用)
    remoteInfo.Object = realRemote
    RemoteByName[remoteInfo.Name] = realRemote

    local ok, err
    local args = remoteInfo.Args or {}

    if remoteInfo.Type == "RemoteEvent" then
        if #args > 0 then
            ok, err = pcall(function() realRemote:FireServer(unpack(args)) end)
        else
            ok, err = pcall(function() realRemote:FireServer() end)
        end
    elseif remoteInfo.Type == "RemoteFunction" then
        if #args > 0 then
            ok, err = pcall(function() realRemote:InvokeServer(unpack(args)) end)
        else
            ok, err = pcall(function() realRemote:InvokeServer() end)
        end
    end

    if not ok then
        if #args > 0 then
            if remoteInfo.Type == "RemoteEvent" then
                ok, err = pcall(function() realRemote:FireServer() end)
            else
                ok, err = pcall(function() realRemote:InvokeServer() end)
            end
        end
        if not ok then
            local errMsg = tostring(err)
            if State._LastError ~= errMsg then
                State._LastError = errMsg
                warn("[AutoClicker] 调用失败:", remoteInfo.Name, errMsg)
            end
            return
        end
        remoteInfo.Args = {}
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

-- ==================== 学习模式 ====================
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
    State._LastError = nil

    Velvet:Notify({
        Title = "学习模式",
        Content = "请在游戏里点击一次！",
        Duration = 10,
        Type = "info",
    })
    print("[RemoteSpy] 学习模式已开启，在游戏里点击一次...")

    task.delay(60, function()
        if State.IsLearning then
            State.IsLearning = false
            Velvet:Notify({
                Title = "超时",
                Content = "60 秒内未检测到点击",
                Duration = 4,
                Type = "error",
            })
        end
    end)
end

-- ==================== 主循环 ====================
local function mainLoop()
    if not State.ActiveRemote then
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

    -- 启动前验证 Remote 存在
    local real = State.ActiveRemote.Object
    if not real or not pcall(function() return real.Parent end) or not real.Parent then
        real = RemoteByName[State.ActiveRemote.Name]
        if real and not pcall(function() return real.Parent end) or not real.Parent then
            real = findRemoteByName(State.ActiveRemote.Name)
        end
    end
    if not real then
        Velvet:Notify({
            Title = "Remote 丢失",
            Content = string.format("找不到 %s，请重新学习", State.ActiveRemote.Name),
            Duration = 4,
            Type = "error",
        })
        State.IsRunning = false
        State.ActiveRemote = nil
        return
    end
    State.ActiveRemote.Object = real
    RemoteByName[State.ActiveRemote.Name] = real

    State.IsRunning = true
    State.StartTime = os.clock()
    State.TotalClicks = 0
    State._LastError = nil

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
    SubTitle = "v5.1 · 全自动",
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
local activeArgs = "无参数"
if State.ActiveRemote and State.ActiveRemote.Args and #State.ActiveRemote.Args > 0 then
    local parts = {}
    for i, v in ipairs(State.ActiveRemote.Args) do
        table.insert(parts, tostring(v))
    end
    activeArgs = table.concat(parts, ", ")
end

local StatsSection = MainTab:AddSection("实时数据")
StatsSection:AddParagraph({
    Title = "状态",
    Content = string.format(
        "⚡ CPS: 0/s\n" ..
        "👆 总点击: 0\n" ..
        "⏱ 运行: 0s\n" ..
        "🔧 Remote: %s (%s)\n" ..
        "📦 参数: %s",
        activeName, activeType, activeArgs
    ),
})

-- ---------- Tab 2: 已监控 Remote ----------
local SpyTab = Window:AddTab("RemoteSpy", "search")

local SpySection = SpyTab:AddSection("已监控的 Remote")
local totalCount = #State.AllRemotes
local spyTitle = string.format("已扫描 %d 个 Remote", totalCount)
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
        RemoteByName = {}
        pcall(scanAllRemotes)
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
        if #State.AllRemotes == 0 then
            Velvet:Notify({ Title = "无 Remote", Content = "未扫描到任何 Remote", Duration = 3, Type = "error" })
            return
        end
        -- 把第一个设为当前
        State.ActiveRemote = {
            Name = State.AllRemotes[1].Name,
            Type = State.AllRemotes[1].Type,
            Args = {},
        }
        State.CapturedRemote = State.ActiveRemote
        Velvet:Notify({
            Title = "已设置",
            Content = string.format("使用: %s", State.AllRemotes[1].Name),
            Duration = 3,
            Type = "success",
        })
    end,
})

-- ---------- Tab 3: 信息 ----------
local InfoTab = Window:AddTab("信息", "info")

local InfoSection = InfoTab:AddSection("使用说明")
InfoSection:AddParagraph({
    Title = "全自动模式 v5.1",
    Content = "执行脚本后自动运行，无需手动操作。\n\n" ..
        "自动流程:\n" ..
        "  1. 执行脚本 → 扫描所有 Remote\n" ..
        "  2. 自动进入学习模式 → 等待你点击\n" ..
        "  3. 在游戏里点一下 → 自动捕获 Remote\n" ..
        "  4. 自动开始连点！\n\n" ..
        "你只需要做一件事: 在游戏里点一下。\n\n" ..
        "换游戏:\n" ..
        "  重新执行脚本 → 点一下 → 自动连点\n\n" ..
        "UI: Velvet Library\n" ..
        "按 RightShift 打开/关闭",
})

-- ==================== 启动 ====================
Velvet:Notify({
    Title = "Smart Auto Clicker v5.1",
    Content = "全自动模式！在游戏里点一下即可开始",
    Duration = 6,
    Type = "success",
})

print("========================================")
print(" Smart Auto Clicker v5.1 - Fully Auto")
print(" 已扫描 Remote 数量:", #State.AllRemotes)
print("========================================")
print(" 全自动模式: 在游戏里点一下 → 自动连点")
print("========================================")

-- 自动进入学习模式
task.delay(1, function()
    State.IsLearning = true
    print("[RemoteSpy] 自动学习模式已开启，在游戏里点击一次...")
    task.delay(120, function()
        if State.IsLearning then
            State.IsLearning = false
            warn("[RemoteSpy] 超时: 120 秒内未检测到点击")
        end
    end)
end)