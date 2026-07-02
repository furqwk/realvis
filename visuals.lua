--[[
    Spawner — PanelUI port of the WindUI spawner script.
    Save panelui.lua next to this file, then run.

    Only the setup (loader + window) was added; the spawner logic is unchanged.
    RightControl hides/shows the UI.
]]

local WindUI = loadstring(readfile("panelui.lua"))()

local Window = WindUI:CreateWindow({
    Title = "Spawner",
    Author = "bird",
    Theme = "Aurora",
    ToggleKey = Enum.KeyCode.RightControl,
    Acrylic = false,
})

-- ===== original script below (unchanged) =====================================

local spawner = Window:Tab({
    Title = "Spawner",
    Icon = "bird", -- optional
    Locked = false,
})

itemdatabase = require(game:GetService("ReplicatedStorage").Database.Sync).Weapons

-- defaults so a Spawn click works before the Input callbacks have fired
-- (Input callbacks only run on edit/defocus, not on load)
getgenv().count = getgenv().count or 1
getgenv().newValue = getgenv().newValue or nil

local function spawnWeapon(name, count)
    local PlayerData = require(game:GetService("ReplicatedStorage").Modules.ProfileData)
    local newOwned = PlayerData.Weapons.Owned
    newOwned[name] = count + (newOwned[name] or 0)

    game:GetService("RunService"):BindToRenderStep("InventoryUpdate", 0, function()
        PlayerData.Weapons.Owned = newOwned
    end)
    WindUI:Notify({
        Title = "Reset",
        Content = "Reseting character for bypass to work.",
        Duration = 3,
        Icon = "bird",
    })
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

drop = spawner:Dropdown({
    Title = "Items Found",
    Desc = "",
    Values = { "None" },
    Value = "None",
    Callback = function(option)
        getgenv().newValue = getrawnamebyrealname(option)
    end,
})

spawner:Input({
    Title = "Item Name",
    Desc = "",
    Value = "Harvester",
    InputIcon = "bird",
    Type = "Input", -- or "Textarea"
    Placeholder = "Enter item name",
    Callback = function(input)
        if input ~= "" then
            eee = gettable(input)
            wait(1)
            drop:Refresh(eee, true)
            -- auto-select so getgenv().newValue is set without an extra tap:
            -- prefer an exact name match, otherwise the first result
            if #eee > 0 then
                local chosen = eee[1]
                for _, name in ipairs(eee) do
                    if name:lower() == input:lower() then
                        chosen = name
                        break
                    end
                end
                drop:Select(chosen)
            end
        end
    end,
})

spawner:Input({
    Title = "Item Amount",
    Desc = "",
    Value = "1",
    InputIcon = "bird",
    Type = "Input",
    Placeholder = "Enter how much item you wanna",
    Callback = function(input)
        local num = tonumber(input)
        if num then
            getgenv().count = num
            WindUI:Notify({
                Title = "Item Amount",
                Content = "Amount is now set to " .. tostring(num),
                Duration = 3,
                Icon = "bird",
            })
        else
            WindUI:Notify({
                Title = "Invalid Input",
                Content = "Please enter a valid number.",
                Duration = 3,
                Icon = "bird",
            })
        end
    end,
})

local isWaiting = false

spawner:Button({
    Title = "Spawn Item",
    Desc = "click to spawn item",
    Locked = false,
    Callback = function()
        if isWaiting then
            WindUI:Notify({
                Title = "On cooldown",
                Content = "Please wait until bypass (around ~15 sec).",
                Duration = 3,
                Icon = "bird",
            })
            return
        end

        -- validate before firing so we never do arithmetic on nil
        if not getgenv().newValue then
            WindUI:Notify({
                Title = "No item selected",
                Content = "Type an item name, then pick a result from 'Items Found'.",
                Duration = 4,
                Icon = "bird",
            })
            return
        end
        if not tonumber(getgenv().count) then
            getgenv().count = 1
        end

        isWaiting = true
        opencrate(getgenv().newValue, tonumber(getgenv().count))

        task.wait(math.random(12, 18))
        isWaiting = false
    end,
})
