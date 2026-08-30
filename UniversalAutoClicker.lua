-- LocalScript 客户端脚本｜手机端
-- 原理：调用UI按钮的Activated，本地执行按钮自身的代码，不是直接FireServer远程
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

-- =========配置=========
local CLICK_DELAY = 0.3 -- 间隔秒，建议0.3‑0.5，和人手点击速度接近
local autoActive = false
local targetButton -- 存放 bite点击按钮对象
-- ======================

-- 等待 bite UI按钮加载，你需要自己核对按钮路径，如果找不到，打印GUI列表调试
local function findBiteButton()
    -- 遍历所有GUI寻找按钮；你可以打印PlayerGui:GetChildren()看层级
    for _, gui in ipairs(PlayerGui:GetChildren()) do
        if gui:IsA("ScreenGui") then
            -- 递归查找TextButton / ImageButton
            local function scan(parent)
                for _,v in ipairs(parent:GetChildren()) do
                    if (v:IsA("TextButton") or v:IsA("ImageButton")) then
                        -- 你可以在这里改判断条件，匹配你的按钮，比如按钮Name/Text
                        -- print(v.Name, v.ClassName) -- 取消注释，控制台看所有按钮名字
                        -- 这里假设按钮名称包含 Bite，根据你游戏实际修改！
                        if string.find(v.Name:lower(),"bite") or (v.Text and string.find(v.Text:lower(),"bite")) then
                            return v
                        end
                    end
                    if #v:GetChildren()>0 then
                        local res = scan(v)
                        if res then return res end
                    end
                end
                return nil
            end
            local btn = scan(gui)
            if btn then
                return btn
            end
        end
    end
    return nil
end

-- 自动循环：触发按钮 Activated（本地点击，执行按钮自身全部逻辑，不是伪造remote）
local function autoClickLoop()
    while autoActive do
        task.wait(CLICK_DELAY)
        if not autoActive then break end
        if targetButton and targetButton:IsDescendantOf(game) then
            -- 🔑 模拟本地UI激活，等价人手点击按钮
            targetButton.Activated:Fire()
        else
            -- 按钮丢失，重新查找
            targetButton = findBiteButton()
            if not targetButton then
                warn("未找到Bite按钮，等待加载……")
                task.wait(0.5)
            end
        end
    end
end

-- 简单手机端切换按钮UI
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoLocalClick"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = PlayerGui

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0,150,0,65)
toggleBtn.Position = UDim2.new(0.01,0,0.65,0)
toggleBtn.BackgroundColor3 = Color3.new(0,0.7,0.2)
toggleBtn.Text = "启动本地点击"
toggleBtn.TextColor3 = Color3.new(1,1,1)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 14
toggleBtn.Parent = ScreenGui

toggleBtn.MouseButton1Click:Connect(function()
    autoActive = not autoActive
    if autoActive then
        toggleBtn.Text = "停止本地点击"
        toggleBtn.BackgroundColor3 = Color3.new(0.8,0.1,0.1)
        targetButton = findBiteButton()
        task.spawn(autoClickLoop)
    else
        toggleBtn.Text = "启动本地点击"
        toggleBtn.BackgroundColor3 = Color3.new(0,0.7,0.2)
    end
end)

-- 启动预查找按钮
task.spawn(function()
    repeat
        targetButton = findBiteButton()
        task.wait(1)
    until targetButton ~= nil
    print("✅成功找到Bite按钮：",targetButton.Name)
end)
