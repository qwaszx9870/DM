-- ============================================================
--  通用智能自动连点器 v6.0 - Velvet UI
--  __namecall 元表钩子: 拦截所有 FireServer/InvokeServer
--  最底层方案，self 一定是真正的 Remote 实例
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

-- ==================== 全局 Remote 查找表 ====================
local RemoteByName = {}

local function findRemoteByName(name)
    if RemoteByName[name] then return RemoteByName[name] end
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
    ActiveRemote = nil,      -- {Name, Type, Args, Object}
    AllRemotes = {},
    _LastError = nil,
}

-- ==================== 配置 ====================
local CONFIG = {
    ClickSpeed = 10,
}

-- ==================== 扫描所有 Remote ====================
local function registerRemote(child)
    RemoteByName[child.Name] = child
    for _, r in ipairs(State.AllRemotes) do
        if r.Name == child.Name and r.Type == child.ClassName then return end
    end
    table.insert(State.AllRemotes, {
        Name = child.Name,
        Type = child.ClassName,
        Path = pcall(function() return child:GetFullName() end) and child:GetFullName() or child.Name,
    })
end

local function scanAllRemotes()
    local all = game:GetDescendants()
    for _, child in ipairs(all) do
        if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
            registerRemote(child)
        end
    end
end

pcall(scanAllRemotes)
pcall(function()
    game.DescendantAdded:Connect(function(child)
        if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
            registerRemote(child)
        end
    end)
end)

-- ==================== __namecall 元表钩子 (最底层) ====================
local function autoStartClicking()
    if State.IsRunning then return end
    if not State.ActiveRemote then return end

    local remoteInfo = State.ActiveRemote

    -- 验证 Object
    if not remoteInfo.Object then
        remoteInfo.Object = RemoteByName[remoteInfo.Name] or findRemoteByName(remoteInfo.Name)
    end
    if not remoteInfo.Object then
        warn("[AutoClicker] 启动失败: 找不到 Remote:", remoteInfo.Name)
        return
    end

    State.IsRunning = true
    State.StartTime = os.clock()
    State.TotalClicks = 0
    State._LastError = nil

    Velvet:Notify({
        Title = "自动启动",
        Content = string.format("使用: %s\n速度: %d 次/秒", remoteInfo.Name, CONFIG.ClickSpeed),
        Duration = 3,
        Type = "success",
    })
    print("[AutoClicker] 自动启动! Remote:", remoteInfo.Name, "速度:", CONFIG.ClickSpeed, "次/秒")

    while State.IsRunning do
        local now = os.clock()
        local obj = remoteInfo.Object or RemoteByName[remoteInfo.Name] or findRemoteByName(remoteInfo.Name)
        if not obj then
            warn("[AutoClicker] Remote 丢失:", remoteInfo.Name)
            State.IsRunning = false
            break
        end
        remoteInfo.Object = obj

        for i = 1, CONFIG.ClickSpeed do
            local ok, err
            local args = remoteInfo.Args or {}
            if remoteInfo.Type == "RemoteEvent" then
                if #args > 0 then
                    ok, err = pcall(function() obj:FireServer(unpack(args)) end)
                else
                    ok, err = pcall(function() obj:FireServer() end)
                end
            else
                if #args > 0 then
                    ok, err = pcall(function() obj:InvokeServer(unpack(args)) end)
                else
                    ok, err = pcall(function() obj:InvokeServer() end)
                end
            end
            if not ok then
                if #args > 0 then
                    if remoteInfo.Type == "RemoteEvent" then
                        ok, err = pcall(function() obj:FireServer() end)
                    else
                        ok, err = pcall(function() obj:InvokeServer() end)
                    end
                end
                if not ok then
                    local errMsg = tostring(err)
                    if State._LastError ~= errMsg then
                        State._LastError = errMsg
                        warn("[AutoClicker] 调用失败:", remoteInfo.Name, errMsg)
                    end
                else
                    remoteInfo.Args = {}
                    State.TotalClicks = State.TotalClicks + 1
                end
            else
                State.TotalClicks = State.TotalClicks + 1
            end
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

-- __namecall: 拦截所有 FireServer / InvokeServer 调用
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    if method == "FireServer" or method == "InvokeServer" then
        if (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) and State.IsLearning then
            local args = {...}
            State.ActiveRemote = {
                Name = self.Name,
                Object = self,        -- __namecall 的 self 是真正的 Remote 实例
                Type = self.ClassName,
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
            print("[RemoteSpy] 捕获:", self.ClassName, self.Name, "参数:", argsStr)

            task.spawn(autoStartClicking)
        end
    end
    return oldNamecall(self, ...)
end)

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

-- ==================== Velvet UI ====================
local Window = Velvet:CreateWindow({
    Title = "Smart Auto Clicker",
    SubTitle = "v6.0 · __namecall",
    ToggleKey = Enum.KeyCode.RightShift,
})

-- ---------- Tab 1: 主控 ----------
local MainTab = Window:AddTab("主控", "play")

local ToggleSection = MainTab:AddSection("运行控制")

ToggleSection:AddToggle("RunToggle", {
    Text = "自动连点",
    Default = false,
    Callback = function(v)
        if v then
            if State.IsRunning then return end
            if not State.ActiveRemote then
                Velvet:Notify({ Title = "未学习", Content = "请先在游戏里点一下", Duration = 3, Type = "error" })
                return
            end
            task.spawn(autoStartClicking)
        else
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

-- ---------- Tab 2: RemoteSpy ----------
local SpyTab = Window:AddTab("RemoteSpy", "search")

local SpySection = SpyTab:AddSection("已扫描 Remote")
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

-- ---------- Tab 3: 信息 ----------
local InfoTab = Window:AddTab("信息", "info")

InfoTab:AddSection("使用说明"):AddParagraph({
    Title = "__namecall 元表钩子 v6.0",
    Content = "换用 hookmetamethod + __namecall，\n" ..
        "直接拦截所有 FireServer/InvokeServer 调用。\n\n" ..
        "使用方法:\n" ..
        "  1. 执行脚本\n" ..
        "  2. 在游戏里点一下 → 自动开始连点\n\n" ..
        "v6.0 改进:\n" ..
        "  - 放弃 hookfunction，改用 __namecall\n" ..
        "  - self 一定是真正的 Remote 实例\n" ..
        "  - 不再依赖闭包/名字查表/全局搜索\n\n" ..
        "UI: Velvet Library\n" ..
        "按 RightShift 打开/关闭",
})

-- ==================== 启动 ====================
Velvet:Notify({
    Title = "Smart Auto Clicker v6.0",
    Content = "__namecall 模式！在游戏里点一下即可",
    Duration = 6,
    Type = "success",
})

print("========================================")
print(" Smart Auto Clicker v6.0 - __namecall")
print(" 已扫描 Remote 数量:", #State.AllRemotes)
print("========================================")
print(" 全自动: 在游戏里点一下 → 自动连点")
print(" 技术: hookmetamethod + __namecall")
print("========================================")

-- 自动进入学习模式
task.delay(1, function()
    State.IsLearning = true
    print("[RemoteSpy] 自动学习已开启，在游戏里点击一次...")
    task.delay(120, function()
        if State.IsLearning then
            State.IsLearning = false
            warn("[RemoteSpy] 超时: 120 秒未检测到点击")
        end
    end)
end)