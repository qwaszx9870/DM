-- Pirate Ship 自动咬人脚本（无参 Bite Remote 版）
-- 原理：日志确认 Bite 是 RemoteEvent，FireServer 无需参数
-- 找到 Bite Remote 后循环 FireServer 即可触发训练（力量增长）

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    return
end

-- 找 Bite Remote
local function getBiteRemote()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then
        return nil
    end
    local bite = remotes:FindFirstChild("Bite")
    if bite and bite:IsA("RemoteEvent") then
        return bite
    end
    -- 兜底：递归找
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

-- 配置
local enabled = false
local interval = 0.05  -- 秒，可调

-- 自动循环
local conn
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

-- UI 切换按钮（绿色开 / 红色关）
local userInputService = game:GetService("UserInputService")
if userInputService.TouchEnabled or userInputService.MouseEnabled then
    task.spawn(function()
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "AutoBite"
        screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 160, 0, 50)
        btn.Position = UDim2.new(0.5, -80, 0.05, 0)
        btn.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
        btn.Text = "自动咬人：关"
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.TextSize = 20
        btn.Parent = screenGui

        local function updateUI()
            if enabled then
                btn.BackgroundColor3 = Color3.fromRGB(40, 180, 60)
                btn.Text = "自动咬人：开"
            else
                btn.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
                btn.Text = "自动咬人：关"
            end
        end

        btn.MouseButton1Click:Connect(function()
            enabled = not enabled
            updateUI()
        end)

        btn.Activated:Connect(function()
            enabled = not enabled
            updateUI()
        end)
    end)
end

print("[连点器] 脚本已加载，点击左上角按钮开启自动咬人")
