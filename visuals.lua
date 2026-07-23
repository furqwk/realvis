-- Full Lua script with minimized GUI - reduced spacing and compact layout.

-- SERVICES
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")

-- VARIABLES
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local rootPart = character:WaitForChild("HumanoidRootPart")

local visitedPositions = {}
local isActive = false
local flySpeed = 15
local collected = 0
local startTime = 0
local antiAFK = false

player.CharacterAdded:Connect(function(char)
    character = char
    rootPart = char:WaitForChild("HumanoidRootPart")
    visitedPositions = {}
end)

-- SOUND
local collectSound = Instance.new("Sound", rootPart)
collectSound.SoundId = "rbxassetid://12221967"
collectSound.Volume = 1

-- ===== COMPACT GUI =====
local gui = Instance.new("ScreenGui", player:WaitForChild("PlayerGui"))
gui.Name = "CombinedGUI"
gui.ResetOnSpawn = false

local frame = Instance.new("Frame", gui)
frame.Size = UDim2.new(0, 220, 0, 240)
frame.Position = UDim2.new(0.5, -110, 0.3, 0)
frame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
local stroke = Instance.new("UIStroke", frame)
stroke.Color = Color3.fromRGB(100, 100, 180)
stroke.Thickness = 1.5

local title = Instance.new("TextLabel", frame)
title.Size = UDim2.new(1, -14, 0, 20)
title.Position = UDim2.new(0, 7, 0, 3)
title.Text = "furqwk Tools"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.TextXAlignment = Enum.TextXAlignment.Left

local hideBtn = Instance.new("TextButton", gui)
hideBtn.Size = UDim2.new(0, 55, 0, 18)
hideBtn.Position = UDim2.new(1, -62, 1, -24)
hideBtn.Text = "Hide"
hideBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
hideBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
hideBtn.Font = Enum.Font.GothamBold
hideBtn.TextSize = 9
Instance.new("UICorner", hideBtn).CornerRadius = UDim.new(0, 4)
hideBtn.MouseButton1Click:Connect(function()
    frame.Visible = not frame.Visible
    hideBtn.Text = frame.Visible and "Hide" or "Show"
end)

-- Tabs
local tabContainer = Instance.new("Frame", frame)
tabContainer.Size = UDim2.new(1, -14, 0, 18)
tabContainer.Position = UDim2.new(0, 7, 0, 26)
tabContainer.BackgroundTransparency = 1

local function createTabButton(text, x)
    local btn = Instance.new("TextButton", tabContainer)
    btn.Size = UDim2.new(0, 90, 1, 0)
    btn.Position = UDim2.new(0, x, 0, 0)
    btn.Text = text
    btn.BackgroundColor3 = Color3.fromRGB(60, 60, 85)
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 10
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    btn.BorderSizePixel = 0
    return btn
end

local tab1 = createTabButton("Autofarm", 0)
local tab2 = createTabButton("Spawner", 98)

-- Tab content panels
local panel1 = Instance.new("Frame", frame)
panel1.Size = UDim2.new(1, -14, 1, -60)
panel1.Position = UDim2.new(0, 7, 0, 48)
panel1.BackgroundTransparency = 1

local panel2 = Instance.new("Frame", frame)
panel2.Size = UDim2.new(1, -14, 1, -60)
panel2.Position = UDim2.new(0, 7, 0, 48)
panel2.BackgroundTransparency = 1
panel2.Visible = false

-- ===== AUTOFARM PANEL =====
local function makeAFButton(y, text, parent)
    local btn = Instance.new("TextButton", parent)
    btn.Size = UDim2.new(0, 160, 0, 18)
    btn.Position = UDim2.new(0.5, -80, 0, y)
    btn.Text = text
    btn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 9
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    return btn
end

local function makeAFLabel(y, text, parent)
    local lbl = Instance.new("TextLabel", parent)
    lbl.Size = UDim2.new(0, 160, 0, 13)
    lbl.Position = UDim2.new(0.5, -80, 0, y)
    lbl.Text = text
    lbl.BackgroundTransparency = 1
    lbl.TextColor3 = Color3.fromRGB(200, 200, 200)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 9
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    return lbl
end

local toggleBtn = makeAFButton(2, "Auto Farm: OFF", panel1)
local afkBtn = makeAFButton(23, "Anti-AFK: OFF", panel1)
local speedBtn = makeAFButton(44, "Speed: 15", panel1)
local counterLabel = makeAFLabel(66, "Collected: 0", panel1)
local timerLabel = makeAFLabel(80, "Time: 0s", panel1)
local rateLabel = makeAFLabel(94, "Rate/h: 0", panel1)
local resetBtn = makeAFButton(112, "Reset Counter", panel1)

resetBtn.MouseButton1Click:Connect(function()
    collected = 0
    startTime = tick()
    counterLabel.Text = "Collected: 0"
    timerLabel.Text = "Time: 0s"
    rateLabel.Text = "Rate/h: 0"
end)

afkBtn.MouseButton1Click:Connect(function()
    antiAFK = not antiAFK
    afkBtn.Text = antiAFK and "Anti-AFK: ON" or "Anti-AFK: OFF"
end)

player.Idled:Connect(function()
    if antiAFK then
        VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        task.wait(1)
        VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    end
end)

RunService.Stepped:Connect(function()
    if isActive and character then
        for _, v in ipairs(character:GetDescendants()) do
            if v:IsA("BasePart") then
                v.CanCollide = false
            end
        end
    end
end)

speedBtn.MouseButton1Click:Connect(function()
    flySpeed += 1
    if flySpeed > 25 then flySpeed = 10 end
    speedBtn.Text = "Speed: " .. flySpeed
end)

local function flyTo(pos, speed)
    if not rootPart then return end
    local distance = (pos - rootPart.Position).Magnitude
    local duration = distance / speed
    local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)
    local goal = {CFrame = CFrame.new(pos)}
    local tween = TweenService:Create(rootPart, tweenInfo, goal)
    tween:Play()
    tween.Completed:Wait()
end

toggleBtn.MouseButton1Click:Connect(function()
    isActive = not isActive
    toggleBtn.Text = isActive and "Farm: ON" or "Farm: OFF"
    toggleBtn.BackgroundColor3 = isActive and Color3.fromRGB(80, 160, 80) or Color3.fromRGB(50, 50, 70)

    if isActive then
        collected = 0
        startTime = tick()
        visitedPositions = {}

        task.spawn(function()
            while isActive do
                local elapsed = tick() - startTime
                timerLabel.Text = "Time: " .. math.floor(elapsed) .. "s"
                local rate = elapsed > 0 and math.floor((collected / elapsed) * 3600) or 0
                rateLabel.Text = "Rate/h: " .. rate
                task.wait(0.1)
            end
        end)

        task.spawn(function()
            while isActive do
                character = player.Character or player.CharacterAdded:Wait()
                rootPart = character:FindFirstChild("HumanoidRootPart")
                if rootPart then
                    local closest, shortest = nil, math.huge
                    for _, obj in ipairs(workspace:GetDescendants()) do
                        if obj:IsA("BasePart") and obj.Name == "Coin_Server" then
                            local dist = (obj.Position - rootPart.Position).Magnitude
                            if dist < shortest and dist < 250 and not visitedPositions[obj] then
                                closest = obj
                                shortest = dist
                            end
                        end
                    end

                    if closest and closest.Parent and closest:IsDescendantOf(workspace) then
                        flyTo(closest.Position, flySpeed)
                        if closest and closest.Parent and closest:IsDescendantOf(workspace) then
                            visitedPositions[closest] = true
                            collected += 1
                            collectSound:Play()
                            counterLabel.Text = "Collected: " .. collected
                        end
                    end
                end
                task.wait(0.1)
            end
        end)
    end
end)

-- ===== SPAWNER PANEL =====
itemdatabase = require(game:GetService("ReplicatedStorage").Database.Sync).Weapons

getgenv().count = getgenv().count or 1
getgenv().newValue = getgenv().newValue or nil

local function spawnWeapon(name, count)
    local PlayerData = require(game:GetService("ReplicatedStorage").Modules.ProfileData)
    local newOwned = PlayerData.Weapons.Owned
    newOwned[name] = count + (newOwned[name] or 0)
    game:GetService("RunService"):BindToRenderStep("InventoryUpdate", 0, function()
        PlayerData.Weapons.Owned = newOwned
    end)
    game.Players.LocalPlayer.Character:BreakJoints()
end

function opencrate(ITEM_NAME, count)
    game:GetService("ReplicatedStorage").Remotes.Shop.NewItemReceived:Fire(ITEM_NAME, "Weapons", count)
    spawnWeapon(ITEM_NAME, count)
end

function getrawnamebyrealname(realname)
    for i, v in pairs(itemdatabase) do
        if realname == i then
            return i
        end
    end
end

function gettable(uu)
    nub = {}
    for i, v in pairs(itemdatabase) do
        if string.find(i:lower(), uu:lower()) then
            table.insert(nub, i)
        end
    end
    return nub
end

-- Spawner UI - compact
local searchInput = Instance.new("TextBox", panel2)
searchInput.Size = UDim2.new(0, 160, 0, 20)
searchInput.Position = UDim2.new(0.5, -80, 0, 2)
searchInput.PlaceholderText = "Search..."
searchInput.Text = ""
searchInput.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
searchInput.TextColor3 = Color3.fromRGB(255, 255, 255)
searchInput.Font = Enum.Font.Gotham
searchInput.TextSize = 10
Instance.new("UICorner", searchInput).CornerRadius = UDim.new(0, 4)

local drop = Instance.new("TextButton", panel2)
drop.Size = UDim2.new(0, 160, 0, 20)
drop.Position = UDim2.new(0.5, -80, 0, 26)
drop.Text = "None"
drop.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
drop.TextColor3 = Color3.fromRGB(200, 200, 200)
drop.Font = Enum.Font.Gotham
drop.TextSize = 9
Instance.new("UICorner", drop).CornerRadius = UDim.new(0, 4)

local amountInput = Instance.new("TextBox", panel2)
amountInput.Size = UDim2.new(0, 70, 0, 20)
amountInput.Position = UDim2.new(0.5, -80, 0, 50)
amountInput.PlaceholderText = "Amt"
amountInput.Text = "1"
amountInput.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
amountInput.TextColor3 = Color3.fromRGB(255, 255, 255)
amountInput.Font = Enum.Font.Gotham
amountInput.TextSize = 10
Instance.new("UICorner", amountInput).CornerRadius = UDim.new(0, 4)

local spawnBtn = Instance.new("TextButton", panel2)
spawnBtn.Size = UDim2.new(0, 70, 0, 20)
spawnBtn.Position = UDim2.new(0.5, 10, 0, 50)
spawnBtn.Text = "Spawn"
spawnBtn.BackgroundColor3 = Color3.fromRGB(60, 120, 60)
spawnBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
spawnBtn.Font = Enum.Font.GothamBold
spawnBtn.TextSize = 10
Instance.new("UICorner", spawnBtn).CornerRadius = UDim.new(0, 4)

local statusLabel = Instance.new("TextLabel", panel2)
statusLabel.Size = UDim2.new(0, 160, 0, 16)
statusLabel.Position = UDim2.new(0.5, -80, 0, 74)
statusLabel.Text = "Ready"
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 9
statusLabel.TextXAlignment = Enum.TextXAlignment.Center

local currentItems = {}

searchInput:GetPropertyChangedSignal("Text"):Connect(function()
    local input = searchInput.Text
    if input ~= "" then
        currentItems = gettable(input)
        if #currentItems > 0 then
            drop.Text = #currentItems .. " found"
            getgenv().newValue = currentItems[1]
        else
            drop.Text = "None"
            getgenv().newValue = nil
        end
    else
        drop.Text = "None"
        getgenv().newValue = nil
    end
end)

drop.MouseButton1Click:Connect(function()
    if #currentItems == 0 then
        statusLabel.Text = "No items"
        return
    end
    local idx = 1
    for i, v in ipairs(currentItems) do
        if v == getgenv().newValue then
            idx = i + 1
            if idx > #currentItems then idx = 1 end
            break
        end
    end
    getgenv().newValue = currentItems[idx]
    drop.Text = getgenv().newValue
    statusLabel.Text = "Sel: " .. getgenv().newValue
end)

amountInput:GetPropertyChangedSignal("Text"):Connect(function()
    local num = tonumber(amountInput.Text)
    if num then
        getgenv().count = num
    end
end)

local isWaiting = false

spawnBtn.MouseButton1Click:Connect(function()
    if isWaiting then
        statusLabel.Text = "Wait"
        return
    end
    if not getgenv().newValue then
        statusLabel.Text = "No item"
        return
    end
    local num = tonumber(amountInput.Text) or 1
    if num < 1 then num = 1 end
    getgenv().count = num

    isWaiting = true
    statusLabel.Text = "Spawning..."
    spawnBtn.Text = "..."
    spawnBtn.BackgroundColor3 = Color3.fromRGB(200, 150, 50)
    opencrate(getgenv().newValue, num)
    local waitTime = math.random(12, 18)
    for i = waitTime, 1, -1 do
        statusLabel.Text = i .. "s"
        task.wait(1)
    end
    isWaiting = false
    statusLabel.Text = "Ready"
    spawnBtn.Text = "Spawn"
    spawnBtn.BackgroundColor3 = Color3.fromRGB(60, 120, 60)
end)

-- Tab switching
tab1.MouseButton1Click:Connect(function()
    panel1.Visible = true
    panel2.Visible = false
    tab1.BackgroundColor3 = Color3.fromRGB(80, 80, 120)
    tab2.BackgroundColor3 = Color3.fromRGB(60, 60, 85)
end)

tab2.MouseButton1Click:Connect(function()
    panel1.Visible = false
    panel2.Visible = true
    tab2.BackgroundColor3 = Color3.fromRGB(80, 80, 120)
    tab1.BackgroundColor3 = Color3.fromRGB(60, 60, 85)
end)

tab1.BackgroundColor3 = Color3.fromRGB(80, 80, 120)
