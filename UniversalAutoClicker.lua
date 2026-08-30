-- Pirate Ship 自动咬人脚本（Velvet UI + 无参 Bite Remote）
-- 日志确认：ReplicatedStorage.Remotes.Bite 是 RemoteEvent，FireServer 无需参数

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    return
end

-- ============ 找 Bite Remote ============
local function getBiteRemote()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        local bite = remotes:FindFirstChild("Bite")
        if bite and bite:IsA("RemoteEvent") then
            return bite
        end
    end
    for _, v in ipairs(ReplicatedStorage:GetDescendants()) do
        if v.Name == "Bite" and v:IsA("RemoteEvent") then
            return v
        end
    end
    return nil
end

local biteRemote = getBiteRemote()
if not biteRemote then
    warn("[连点器] 未找到 Bite Remote，请确认已进入游戏")
    return
end
print("[连点器] 找到 Bite Remote:", biteRemote:GetFullName())

-- ============ 状态 ============
local enabled = false
local interval = 0.05

-- ============ 自动循环 ============
task.spawn(function()
    while true do
        if enabled then
            local ok, err = pcall(function()
                biteRemote:FireServer()
            end)
            if not ok then
                warn("[连点器] FireServer 报错:", err)
            end
        end
        task.wait(interval)
    end
end)

-- ============ Velvet UI ============
local repo = "https://raw.githubusercontent.com/DexCodeSX/Velvet/main/"
local Velvet = loadstring(game:HttpGet(repo .. "Library.lua"))()
local Icons = loadstring(game:HttpGet(repo .. "addons/Icons.lua"))()
Velvet:SetIcons(Icons)

local Window = Velvet:CreateWindow({
    Title = "自动咬人",
    SubTitle = "Pirate Ship",
    ToggleKey = Enum.KeyCode.RightShift,
})

local Tab = Window:AddTab("自动", "sparkles")
local Section = Tab:AddSection("咬人设置")

-- 总开关
Section:AddToggle("AutoToggle", {
    Text = "自动咬人",
    Default = false,
    Callback = function(v)
        enabled = v
        print("[连点器] 自动咬人:", enabled)
    end,
})

-- 间隔滑块
Section:AddSlider("IntervalSlider", {
    Text = "间隔(秒)",
    Min = 0.01, Max = 1, Default = 0.05,
    Suffix = "s",
    Callback = function(v)
        interval = v
    end,
})

Section:AddParagraph({
    Title = "说明",
    Content = "开启「自动咬人」后，会持续调用 Bite Remote 训练。间隔越小越快，建议不低于 0.05s 以免被服务器限制。",
})

Velvet:Notify({
    Title = "加载完成",
    Content = "找到 Bite Remote，可开始使用",
    Duration = 3,
    Type = "success",
})

print("[连点器] Velvet UI 加载完成")