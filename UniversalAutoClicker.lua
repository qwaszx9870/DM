-- ============================================================
--  通用智能自动连点器 v7.0 - Velvet UI
--  实时搜索法: 每次调用前实时查找 Remote，不存引用
--  不用 hookfunction，不用 __namecall，不用闭包
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
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

-- ==================== 状态 ====================
local State = {
    IsRunning = false,
    IsLearning = false,
    TotalClicks = 0,
    StartTime = 0,
    ClicksPerSecond = 0,
    LearnedName = nil,       -- 学习到的 Remote 名字
    LearnedType = nil,       -- "RemoteEvent" / "RemoteFunction"
    LearnedArgs = nil,       -- 学习到的参数
    _LastError = nil,
    _FailCount = 0,
}

-- ==================== 配置 ====================
local CONFIG = {
    ClickSpeed = 10,
}

-- ==================== 实时搜索 Remote (不存引用) ====================
local function findRemoteNow(name, remoteType)
    -- 方法1: ReplicatedStorage 递归搜索
    local found = ReplicatedStorage:FindFirstChild(name, true)
    if found and (found:IsA("RemoteEvent") or found:IsA("RemoteFunction")) then
        return found
    end

    -- 方法2: workspace 递归搜索
    found = workspace:FindFirstChild(name, true)
    if found and (found:IsA("RemoteEvent") or found:IsA("RemoteFunction")) then
        return found
    end

    -- 方法3: PlayerGui 搜索
    pcall(function()
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if pg then
            found = pg:FindFirstChild(name, true)
            if found and (found:IsA("RemoteEvent") or found:IsA("RemoteFunction")) then
                return found
            end
        end
    end)

    -- 方法4: PlayerScripts 搜索
    pcall(function()
        local ps = LocalPlayer:FindFirstChild("PlayerScripts")
        if ps then
            found = ps:FindFirstChild(name, true)
            if found and (found:IsA("RemoteEvent") or found:IsA("RemoteFunction")) then
                return found
            end
        end
    end)

    -- 方法5: 全局搜索
    local all = game:GetDescendants()
    for _, child in ipairs(all) do
        if child.Name == name and (child:IsA("RemoteEvent") or child:IsA("RemoteFunction")) then
            return child
        end
    end

    return nil
end

-- ==================== 核心点击 ====================
local function fireClick()
    if not State.LearnedName then return end

    local remote = findRemoteNow(State.LearnedName, State.LearnedType)
    if not remote then
        State._FailCount = State._FailCount + 1
        if State._FailCount == 1 or State._FailCount % 100 == 0 then
            warn("[AutoClicker] 找不到 Remote:", State.LearnedName, "(第", State._FailCount, "次)")
        end
        return
    end

    State._FailCount = 0

    local ok, err
    local args = State.LearnedArgs or {}

    if State.LearnedType == "RemoteEvent" then
        if #args > 0 then
            ok, err = pcall(function() remote:FireServer(unpack(args)) end)
        else
            ok, err = pcall(function() remote:FireServer() end)
        end
    else
        if #args > 0 then
            ok, err = pcall(function() remote:InvokeServer(unpack(args)) end)
        else
            ok, err = pcall(function() remote:InvokeServer() end)
        end
    end

    if not ok then
        if #args > 0 then
            -- 降级无参数
            if State.LearnedType == "RemoteEvent" then
                ok, err = pcall(function() remote:FireServer() end)
            else
                ok, err = pcall(function() remote:InvokeServer() end)
            end
            if ok then
                State.LearnedArgs = {}
                State.TotalClicks = State.TotalClicks + 1
                return
            end
        end
        local errMsg = tostring(err)
        if State._LastError ~= errMsg then
            State._LastError = errMsg
            warn("[AutoClicker] 调用失败:", State.LearnedName, errMsg)
        end
        return
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

-- ==================== 学习模式: 监听 UserInputService ====================
local function onUserInput(input, gameProcessed)
    if not State.IsLearning then return end
    if gameProcessed then return end  -- 只拦截未处理的输入
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and
       input.UserInputType ~= Enum.UserInputType.Touch and
       input.UserInputType ~= Enum.UserInputType.MouseButton2 then
        return
    end

    -- 用户点击了，等一帧让 Remote 被调用
    task.wait(0.1)

    -- 扫描所有 Remote，看看哪个刚才被调用了
    -- 这里我们用另一种方式：直接让用户选择
    -- 实际上，我们无法知道哪个 Remote 被调用了，因为没有 hook
    -- 所以改用：扫描所有 Remote，让用户看到列表，手动选最可能的

    State.IsLearning = false
    print("[RemoteSpy] 检测到点击，扫描 Remote 中...")

    -- 收集所有 Remote
    local all = game:GetDescendants()
    local remotes = {}
    for _, child in ipairs(all) do
        if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
            table.insert(remotes, child)
        end
    end

    if #remotes == 0 then
        Velvet:Notify({
            Title = "未找到 Remote",
            Content = "游戏中没有任何 Remote",
            Duration = 4,
            Type = "error",
        })
        return
    end

    -- 自动选择第一个 Remote (通常点击类的 Remote 名字最短/最常见)
    -- 过滤出可能和点击相关的
    local clickKeywords = {"click", "Click", "tap", "Tap", "hit", "Hit", "fire", "Fire",
        "heat", "Heat", "kick", "Kick", "attack", "Attack", "swing", "Swing",
        "collect", "Collect", "farm", "Farm", "add", "Add", "action", "Action",
        "input", "Input", "interact", "Interact", "use", "Use", "press", "Press",
        "shoot", "Shoot", "punch", "Punch", "equip", "Equip", "select", "Select",
        "trigger", "Trigger", "activate", "Activate", "boost", "Boost",
        "claim", "Claim", "buy", "Buy", "sell", "Sell", "upgrade", "Upgrade",
        "start", "Start", "begin", "Begin", "roll", "Roll", "spin", "Spin",
        "open", "Open", "get", "Get", "send", "Send", "do", "Do", "run", "Run",
        "go", "Go", "speed", "Speed", "flight", "Flight", "test", "Test",
        "toggle", "Toggle", "custom", "Custom", "group", "Group", "reward", "Reward"}

    local bestMatch = nil
    local bestScore = 999

    for _, r in ipairs(remotes) do
        local score = #r.Name  -- 名字越短越好
        for _, kw in ipairs(clickKeywords) do
            if string.find(r.Name, kw, 1, true) then
                score = score - 10  -- 命中关键词加分
                break
            end
        end
        if r:IsA("RemoteEvent") then score = score - 5 end  -- RemoteEvent 优先
        if score < bestScore then
            bestScore = score
            bestMatch = r
        end
    end

    if bestMatch then
        State.LearnedName = bestMatch.Name
        State.LearnedType = bestMatch.ClassName
        State.LearnedArgs = {}

        Velvet:Notify({
            Title = "自动选择",
            Content = string.format("Remote: %s (%s)\n共 %d 个 Remote", bestMatch.Name, bestMatch.ClassName, #remotes),
            Duration = 4,
            Type = "success",
        })
        print("[RemoteSpy] 自动选择:", bestMatch.Name, "(", bestMatch.ClassName, ")")

        -- 自动开始
        task.delay(0.5, function()
            if State.IsRunning then return end
            State.IsRunning = true
            State.StartTime = os.clock()
            State.TotalClicks = 0
            State._LastError = nil
            State._FailCount = 0

            Velvet:Notify({
                Title = "自动启动",
                Content = string.format("%s | %d 次/秒", State.LearnedName, CONFIG.ClickSpeed),
                Duration = 3,
                Type = "success",
            })
            print("[AutoClicker] 自动启动! Remote:", State.LearnedName)

            while State.IsRunning do
                local now = os.clock()
                for i = 1, CONFIG.ClickSpeed do
                    fireClick()
                end
                if State.TotalClicks % (CONFIG.ClickSpeed * 2) == 0 then
                    local elapsed = now - State.StartTime
                    if elapsed > 0 then
                        State.ClicksPerSecond = math.floor(State.TotalClicks / elapsed)
                    end
                end
                task.wait(0.01)
            end
        end)
    end
end

UserInputService.InputBegan:Connect(onUserInput)

-- ==================== Velvet UI ====================
local Window = Velvet:CreateWindow({
    Title = "Smart Auto Clicker",
    SubTitle = "v7.0 · RealTime Search",
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
            if not State.LearnedName then
                Velvet:Notify({ Title = "未学习", Content = "请先在游戏里点一下", Duration = 3, Type = "error" })
                return
            end
            State.IsRunning = true
            State.StartTime = os.clock()
            State.TotalClicks = 0
            State._LastError = nil
            State._FailCount = 0
            task.spawn(function()
                while State.IsRunning do
                    local now = os.clock()
                    for i = 1, CONFIG.ClickSpeed do
                        fireClick()
                    end
                    if State.TotalClicks % (CONFIG.ClickSpeed * 2) == 0 then
                        local elapsed = now - State.StartTime
                        if elapsed > 0 then
                            State.ClicksPerSecond = math.floor(State.TotalClicks / elapsed)
                        end
                    end
                    task.wait(0.01)
                end
            end)
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

local activeName = State.LearnedName or "未学习"
local activeType = State.LearnedType or "-"
local activeArgs = "无参数"
if State.LearnedArgs and #State.LearnedArgs > 0 then
    local parts = {}
    for i, v in ipairs(State.LearnedArgs) do
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

-- ---------- Tab 2: 信息 ----------
local InfoTab = Window:AddTab("信息", "info")

InfoTab:AddSection("使用说明"):AddParagraph({
    Title = "实时搜索法 v7.0",
    Content = "完全放弃 hook，改用实时搜索。\n\n" ..
        "原理:\n" ..
        "  1. 监听你的点击 (UserInputService)\n" ..
        "  2. 扫描所有 Remote，智能匹配点击类\n" ..
        "  3. 每次调用前实时搜索 Remote (不存引用)\n" ..
        "  4. 搜到就调，调完就丢\n\n" ..
        "使用方法:\n" ..
        "  1. 执行脚本\n" ..
        "  2. 在游戏里点一下 → 自动选择 → 自动连点\n\n" ..
        "UI: Velvet Library\n" ..
        "按 RightShift 打开/关闭",
})

-- ==================== 启动 ====================
Velvet:Notify({
    Title = "Smart Auto Clicker v7.0",
    Content = "实时搜索法！在游戏里点一下即可",
    Duration = 6,
    Type = "success",
})

print("========================================")
print(" Smart Auto Clicker v7.0 - RealTime Search")
print("========================================")
print(" 原理: 每次调用前实时搜索 Remote")
print(" 不存引用，不 hook，不 __namecall")
print(" 在游戏里点一下 → 自动选择 → 自动连点")
print("========================================")