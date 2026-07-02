--[[
    PanelUI v3 — WindUI-compatible API, rendered as floating category panels.

    Drop-in: scripts written for WindUI run unchanged (see panel_example.lua,
    which is the WindUI example with only the loader line swapped).

    v3:
      • rebuilt row layout (vertical stacks) — no more overlapping desc/controls
      • REAL acrylic blur (glass parts + depth-of-field; needs graphics ~8+)
      • 14 themes, fully recolorable live
      • smooth animations: expanding dropdowns & colorpickers, hover states,
        modal scale-in, notification fades, sliding window open/close,
        rotating chevrons, animated checkboxes
]]

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

-- // constants -----------------------------------------------------------------
local PANEL_WIDTH = 240
local HEADER_HEIGHT = 42
local CORNER = 14
local ROW_CORNER = 8
local PADDING = 8
local GAP = 6
local FONT = "rbxasset://fonts/families/GothamSSm.json"
local MONO = "rbxasset://fonts/families/RobotoMono.json"

local function fontFace(weight)
    return Font.new(FONT, weight or Enum.FontWeight.Medium)
end

-- // themes ----------------------------------------------------------------------
local function makeTheme(name, bg, header, text, sub, element, accentA, accentB, accentText)
    return {
        Name = name,
        PanelBackground = Color3.fromHex(bg),
        HeaderText = Color3.fromHex(header),
        Text = Color3.fromHex(text),
        SubText = Color3.fromHex(sub),
        Element = Color3.fromHex(element),
        AccentA = Color3.fromHex(accentA),
        AccentB = Color3.fromHex(accentB),
        AccentText = Color3.fromHex(accentText),
    }
end

local Themes = {
    Aurora      = makeTheme("Aurora",      "#0E1018", "#F2F3FA", "#E7E9F5", "#9AA0C0", "#FFFFFF", "#6366F1", "#A855F7", "#FFFFFF"),
    Dark        = makeTheme("Dark",        "#0A0A0E", "#F5F6FA", "#EDEDF2", "#84858F", "#FFFFFF", "#6366F1", "#818CF8", "#FFFFFF"),
    Light       = makeTheme("Light",       "#F3F4FA", "#15151D", "#26262F", "#6B6D7E", "#14141C", "#6366F1", "#8B5CF6", "#FFFFFF"),
    Midnight    = makeTheme("Midnight",    "#0B0F1E", "#EDF1FF", "#DCE3F7", "#7C87AC", "#FFFFFF", "#3B82F6", "#60A5FA", "#FFFFFF"),
    Indigo      = makeTheme("Indigo",      "#0D0D1F", "#EEEEFC", "#DEDEF4", "#8585B0", "#FFFFFF", "#4F46E5", "#6366F1", "#FFFFFF"),
    Violet      = makeTheme("Violet",      "#120B1E", "#F4EDFC", "#E8DCF7", "#9982B8", "#FFFFFF", "#8B5CF6", "#C084FC", "#FFFFFF"),
    Sapphire    = makeTheme("Sapphire",    "#081120", "#EAF3FF", "#D6E6FA", "#7793B8", "#FFFFFF", "#0EA5E9", "#38BDF8", "#06222E"),
    Aqua        = makeTheme("Aqua",        "#06151A", "#E8FBFF", "#D2F3FA", "#6FA3AF", "#FFFFFF", "#06B6D4", "#22D3EE", "#04222A"),
    Emerald     = makeTheme("Emerald",     "#0A1410", "#EFFCF5", "#DDF5E8", "#86AE9B", "#FFFFFF", "#10B981", "#34D399", "#06281B"),
    Amber       = makeTheme("Amber",       "#171106", "#FDF7EA", "#F7ECD2", "#B0A37E", "#FFFFFF", "#F59E0B", "#FBBF24", "#2A1C02"),
    Rose        = makeTheme("Rose",        "#170B12", "#FCEFF4", "#F7DEE8", "#B0879A", "#FFFFFF", "#F43F5E", "#FB7185", "#FFFFFF"),
    Crimson     = makeTheme("Crimson",     "#160808", "#FBEDED", "#F4D9D9", "#AC7F7F", "#FFFFFF", "#DC2626", "#F87171", "#FFFFFF"),
    Mocha       = makeTheme("Mocha",       "#140F0B", "#F8F1EB", "#EEE2D6", "#A99681", "#FFFFFF", "#B45309", "#D97706", "#FFFFFF"),
    CottonCandy = makeTheme("CottonCandy", "#151019", "#FBF2FA", "#F3E1F0", "#AC8FA8", "#FFFFFF", "#F472B6", "#A5B4FC", "#2A0E22"),
}

-- // library state -----------------------------------------------------------------
local PanelUI = {
    Themes = Themes,
    Theme = Themes.Aurora,
    Window = nil,
    Transparent = true,
    PanelTransparency = 0.25,
    OutlineSpeed = 60,
    _themed = {},
    _accents = {},
    _refresh = {},
    _spin = {},
    _flags = {},
    _connections = {},
}

local function accentSequence()
    local t = PanelUI.Theme
    return ColorSequence.new({
        ColorSequenceKeypoint.new(0, t.AccentA),
        ColorSequenceKeypoint.new(0.5, t.AccentB),
        ColorSequenceKeypoint.new(1, t.AccentA),
    })
end

-- // helpers ----------------------------------------------------------------------
local function create(class, props, children)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do
        inst[k] = v
    end
    for _, child in ipairs(children or {}) do
        child.Parent = inst
    end
    return inst
end

local function tween(inst, time, props, style)
    local t = TweenService:Create(inst,
        TweenInfo.new(time, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props)
    t:Play()
    return t
end

local function themed(inst, props)
    table.insert(PanelUI._themed, { Object = inst, Props = props })
    for prop, field in pairs(props) do
        inst[prop] = PanelUI.Theme[field]
    end
    return inst
end

local function accentGradient(props)
    local grad = create("UIGradient", props or {})
    grad.Color = accentSequence()
    table.insert(PanelUI._accents, grad)
    return grad
end

local function track(connection)
    table.insert(PanelUI._connections, connection)
    return connection
end

local function safeCallback(fn, ...)
    if fn then
        task.spawn(fn, ...)
    end
end

-- // sounds -----------------------------------------------------------------------
local SoundService = game:GetService("SoundService")
PanelUI.Sounds = {
    Enabled = true,
    Volume = 0.35,
    Ids = {
        open   = "rbxassetid://9119713951",
        close  = "rbxassetid://9119714587",
        click  = "rbxassetid://9119713951",
        toggle = "rbxassetid://9043488043",
        hover  = "rbxassetid://9118823104",
        notify = "rbxassetid://9046853980",
    },
    _pool = {},
}

function PanelUI.playSound(name)
    local bank = PanelUI.Sounds
    if not bank.Enabled then return end
    local id = bank.Ids[name]
    if not id then return end
    local sound = bank._pool[name]
    if not sound or not sound.Parent then
        sound = Instance.new("Sound")
        sound.Name = "PanelUI_" .. name
        sound.SoundId = id
        sound.Volume = bank.Volume
        sound.Parent = SoundService
        bank._pool[name] = sound
    end
    sound.Volume = bank.Volume
    sound.TimePosition = 0
    pcall(function() sound:Play() end)
end

function PanelUI:SetSoundsEnabled(state)
    PanelUI.Sounds.Enabled = state and true or false
end

function PanelUI:SetSoundVolume(v)
    PanelUI.Sounds.Volume = math.clamp(v, 0, 1)
end

local function uiScale()
    return math.max(PanelUI._uiscale and PanelUI._uiscale.Scale or 1, 0.01)
end

-- glyph-safe chevron: a rotated ">" (GothamSSm has no ▾/▴ glyphs)
local function makeChevron(parent, rightReserve)
    local chev = themed(create("TextLabel", {
        Size = UDim2.new(0, 14, 0, 14),
        Position = UDim2.new(1, -(rightReserve or 0) - 14, 0.5, -7),
        BackgroundTransparency = 1,
        Text = ">",
        TextSize = 13,
        Rotation = 90,
        FontFace = fontFace(Enum.FontWeight.Bold),
        Parent = parent,
    }), { TextColor3 = "SubText" })
    return chev
end

-- // acrylic blur (clean full-scene BlurEffect — no rectangular halo) --------------
local Acrylic = { Enabled = false, MaxSize = 18 }

local function acrylicBlur()
    if Acrylic.Blur and Acrylic.Blur.Parent then
        return Acrylic.Blur
    end
    local blur = Lighting:FindFirstChild("PanelUIAcrylicBlur")
    if not blur then
        blur = create("BlurEffect", {
            Name = "PanelUIAcrylicBlur",
            Size = 0,
            Enabled = false,
            Parent = Lighting,
        })
    end
    Acrylic.Blur = blur
    return blur
end

local function acrylicAttach(_frame)
    -- no per-panel parts in the blur approach; kept for call-site compatibility
end

local function acrylicSetEnabled(state)
    Acrylic.Enabled = state and true or false
    local blur = acrylicBlur()
    blur.Enabled = Acrylic.Enabled
    blur.Size = Acrylic.Enabled and Acrylic.MaxSize or 0
end

-- ease the blur strength up/down, used on open/close
local function acrylicFade(show, time)
    if not Acrylic.Enabled then return end
    local blur = acrylicBlur()
    if show then
        blur.Enabled = true
        tween(blur, time or 0.25, { Size = Acrylic.MaxSize })
    else
        tween(blur, time or 0.2, { Size = 0 })
    end
end

local function acrylicCleanup()
    if Acrylic.Blur then
        Acrylic.Blur:Destroy()
        Acrylic.Blur = nil
    end
    Acrylic.Enabled = false
end

-- // base gui --------------------------------------------------------------------
local function ensureGui()
    if PanelUI.Gui and PanelUI.Gui.Parent then
        return PanelUI.Gui
    end
    local gui = create("ScreenGui", {
        Name = "PanelUI",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 999,
    })
    local ok = pcall(function()
        gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
    end)
    if not ok then
        gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
    end

    PanelUI._uiscale = create("UIScale", { Scale = 1, Parent = gui })

    PanelUI.PanelLayer = create("Frame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Name = "Panels",
        Parent = gui,
    })
    PanelUI.ModalLayer = create("Frame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        ZIndex = 50,
        Name = "Modals",
        Parent = gui,
    })
    PanelUI.NotifyLayer = create("Frame", {
        Size = UDim2.new(0, 300, 1, -32),
        Position = UDim2.new(1, -316, 0, 16),
        BackgroundTransparency = 1,
        ZIndex = 80,
        Name = "Notifications",
        Parent = gui,
    }, {
        create("UIListLayout", {
            Padding = UDim.new(0, 8),
            SortOrder = Enum.SortOrder.LayoutOrder,
            VerticalAlignment = Enum.VerticalAlignment.Bottom,
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
        }),
    })

    local rotation = 0
    track(RunService.Heartbeat:Connect(function(dt)
        if #PanelUI._spin == 0 then return end
        rotation = (rotation + dt * (PanelUI.OutlineSpeed or 60)) % 360
        for _, grad in ipairs(PanelUI._spin) do
            grad.Rotation = rotation
        end
    end))

    PanelUI.Gui = gui
    return gui
end

-- // theme application --------------------------------------------------------------
function PanelUI.ApplyTheme()
    for _, entry in ipairs(PanelUI._themed) do
        if entry.Object and entry.Object.Parent ~= nil then
            for prop, field in pairs(entry.Props) do
                entry.Object[prop] = PanelUI.Theme[field]
            end
        end
    end
    local seq = accentSequence()
    for _, grad in ipairs(PanelUI._accents) do
        grad.Color = seq
    end
    for _, fn in ipairs(PanelUI._refresh) do
        pcall(fn)
    end
end

function PanelUI:SetTheme(name)
    local theme = Themes[name]
    if not theme then return false end
    PanelUI.Theme = theme
    PanelUI.ApplyTheme()
    return true
end

function PanelUI:GetThemes() return Themes end
function PanelUI:GetCurrentTheme() return PanelUI.Theme.Name end

function PanelUI:Gradient(stops, props)
    local colorKeys, transKeys = {}, {}
    for offset, stop in pairs(stops or {}) do
        local alpha = math.clamp((tonumber(offset) or 0) / 100, 0, 1)
        table.insert(colorKeys, ColorSequenceKeypoint.new(alpha, stop.Color or Color3.new(1, 1, 1)))
        table.insert(transKeys, NumberSequenceKeypoint.new(alpha, stop.Transparency or 0))
    end
    table.sort(colorKeys, function(a, b) return a.Time < b.Time end)
    table.sort(transKeys, function(a, b) return a.Time < b.Time end)
    local out = {
        Color = ColorSequence.new(colorKeys),
        Transparency = NumberSequence.new(transKeys),
    }
    for k, v in pairs(props or {}) do
        out[k] = v
    end
    return out
end

function PanelUI:ToggleAcrylic(state)
    acrylicSetEnabled(state)
end

function PanelUI:SetNotificationLower(state)
    if PanelUI.NotifyLayer then
        PanelUI.NotifyLayer.Size = state and UDim2.new(0, 300, 0.5, -32) or UDim2.new(0, 300, 1, -32)
        PanelUI.NotifyLayer.Position = state and UDim2.new(1, -316, 0.5, 16) or UDim2.new(1, -316, 0, 16)
    end
end

-- // shared action button ---------------------------------------------------------
local function makeActionButton(cfg, parent, height)
    local variant = cfg.Variant or "Primary"
    local row = create("TextButton", {
        Size = UDim2.new(1, 0, 0, height or 30),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = variant == "Tertiary" and 1 or (variant == "Primary" and 0.15 or 0.88),
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
        ZIndex = parent.ZIndex or 1,
        Parent = parent,
    }, {
        create("UICorner", { CornerRadius = UDim.new(0, ROW_CORNER) }),
    })
    if variant == "Primary" then
        accentGradient({ Rotation = 45, Parent = row })
    end
    local label = create("TextLabel", {
        Size = UDim2.new(1, -12, 1, 0),
        Position = UDim2.fromOffset(6, 0),
        BackgroundTransparency = 1,
        Text = cfg.Title or "Button",
        TextSize = 13,
        ZIndex = row.ZIndex,
        FontFace = fontFace(Enum.FontWeight.SemiBold),
        Parent = row,
    })
    themed(label, { TextColor3 = variant == "Primary" and "AccentText" or "Text" })

    local baseTransparency = row.BackgroundTransparency
    row.MouseEnter:Connect(function()
        tween(row, 0.1, { BackgroundTransparency = math.max(baseTransparency - 0.08, 0) })
    end)
    row.MouseLeave:Connect(function()
        tween(row, 0.1, { BackgroundTransparency = baseTransparency })
    end)
    return row
end

-- // modal (Dialog / Popup) ----------------------------------------------------------
local function makeModal(cfg)
    ensureGui()
    local overlay = create("TextButton", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 50,
        Parent = PanelUI.ModalLayer,
    })
    tween(overlay, 0.18, { BackgroundTransparency = 0.45 })

    local panel = themed(create("Frame", {
        Size = UDim2.fromOffset(320, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 51,
        Parent = overlay,
    }, {
        create("UICorner", { CornerRadius = UDim.new(0, CORNER) }),
        create("UIPadding", {
            PaddingTop = UDim.new(0, 14),
            PaddingBottom = UDim.new(0, 14),
            PaddingLeft = UDim.new(0, 14),
            PaddingRight = UDim.new(0, 14),
        }),
        create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
    }), { BackgroundColor3 = "PanelBackground" })
    tween(panel, 0.18, { BackgroundTransparency = 0.04 })

    -- scale-in
    local popScale = create("UIScale", { Scale = 0.9, Parent = panel })
    tween(popScale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)

    local stroke = create("UIStroke", {
        Thickness = 2,
        Transparency = 1,
        Color = Color3.new(1, 1, 1),
        Parent = panel,
    })
    tween(stroke, 0.25, { Transparency = 0.35 })
    accentGradient({ Rotation = 45, Parent = stroke })

    local title = themed(create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Text = cfg.Title or "",
        TextSize = 16,
        TextTransparency = 1,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        FontFace = fontFace(Enum.FontWeight.SemiBold),
        ZIndex = 52,
        LayoutOrder = 1,
        Parent = panel,
    }), { TextColor3 = "HeaderText" })
    tween(title, 0.25, { TextTransparency = 0 })

    if cfg.Content and cfg.Content ~= "" then
        local body = themed(create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Text = cfg.Content,
            TextSize = 13,
            TextTransparency = 1,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            FontFace = fontFace(Enum.FontWeight.Regular),
            ZIndex = 52,
            LayoutOrder = 2,
            Parent = panel,
        }), { TextColor3 = "SubText" })
        tween(body, 0.25, { TextTransparency = 0 })
    end

    local closed = false
    local function close()
        if closed then return end
        closed = true
        tween(popScale, 0.15, { Scale = 0.92 })
        tween(overlay, 0.15, { BackgroundTransparency = 1 })
        tween(panel, 0.15, { BackgroundTransparency = 1 })
        for _, d in ipairs(panel:GetDescendants()) do
            if d:IsA("TextLabel") then
                tween(d, 0.12, { TextTransparency = 1 })
            elseif d:IsA("TextButton") then
                tween(d, 0.12, { BackgroundTransparency = 1 })
            elseif d:IsA("UIStroke") then
                tween(d, 0.12, { Transparency = 1 })
            end
        end
        task.delay(0.16, function()
            overlay:Destroy()
        end)
    end

    local buttons = cfg.Buttons or {}
    if #buttons > 0 then
        local rowHolder = create("Frame", {
            Size = UDim2.new(1, 0, 0, 32),
            BackgroundTransparency = 1,
            ZIndex = 52,
            LayoutOrder = 3,
            Parent = panel,
        }, {
            create("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                Padding = UDim.new(0, 8),
                SortOrder = Enum.SortOrder.LayoutOrder,
            }),
        })
        local width = 1 / #buttons
        for _, bcfg in ipairs(buttons) do
            local btn = makeActionButton(bcfg, rowHolder, 32)
            btn.ZIndex = 53
            btn.Size = UDim2.new(width, -math.floor(8 * (#buttons - 1) / #buttons), 1, 0)
            btn.MouseButton1Click:Connect(function()
                close()
                safeCallback(bcfg.Callback)
            end)
        end
    else
        overlay.MouseButton1Click:Connect(close)
    end

    return { Close = close }
end

function PanelUI:Popup(cfg)
    return makeModal(cfg or {})
end

-- // notifications --------------------------------------------------------------------
function PanelUI:Notify(cfg)
    cfg = cfg or {}
    ensureGui()
    PanelUI.playSound("notify")

    local toast = themed(create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 81,
        Parent = PanelUI.NotifyLayer,
    }, {
        create("UICorner", { CornerRadius = UDim.new(0, 12) }),
        create("UIPadding", {
            PaddingTop = UDim.new(0, 10),
            PaddingBottom = UDim.new(0, 10),
            PaddingLeft = UDim.new(0, 12),
            PaddingRight = UDim.new(0, 12),
        }),
        create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
    }), { BackgroundColor3 = "PanelBackground" })
    tween(toast, 0.25, { BackgroundTransparency = 0.06 })

    local stroke = create("UIStroke", {
        Thickness = 1.5,
        Transparency = 1,
        Color = Color3.new(1, 1, 1),
        Parent = toast,
    })
    tween(stroke, 0.3, { Transparency = 0.45 })
    accentGradient({ Rotation = 45, Parent = stroke })

    local function fadeInLabel(label)
        label.TextTransparency = 1
        tween(label, 0.3, { TextTransparency = 0 })
        return label
    end

    fadeInLabel(themed(create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Text = cfg.Title or "Notification",
        TextSize = 14,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        FontFace = fontFace(Enum.FontWeight.SemiBold),
        ZIndex = 82,
        LayoutOrder = 1,
        Parent = toast,
    }), { TextColor3 = "HeaderText" }))

    if cfg.Content and cfg.Content ~= "" then
        fadeInLabel(themed(create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Text = cfg.Content,
            TextSize = 13,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            FontFace = fontFace(Enum.FontWeight.Regular),
            ZIndex = 82,
            LayoutOrder = 2,
            Parent = toast,
        }), { TextColor3 = "SubText" }))
    end

    local closed = false
    local function close()
        if closed then return end
        closed = true
        tween(toast, 0.22, { BackgroundTransparency = 1 })
        for _, child in ipairs(toast:GetDescendants()) do
            if child:IsA("TextLabel") or child:IsA("TextButton") then
                tween(child, 0.22, { TextTransparency = 1, BackgroundTransparency = 1 })
            elseif child:IsA("UIStroke") then
                tween(child, 0.22, { Transparency = 1 })
            end
        end
        task.delay(0.24, function()
            toast:Destroy()
        end)
    end

    if cfg.Buttons and #cfg.Buttons > 0 then
        local holder = create("Frame", {
            Size = UDim2.new(1, 0, 0, 28),
            BackgroundTransparency = 1,
            ZIndex = 82,
            LayoutOrder = 3,
            Parent = toast,
        }, {
            create("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                Padding = UDim.new(0, 8),
                SortOrder = Enum.SortOrder.LayoutOrder,
            }),
        })
        local width = 1 / #cfg.Buttons
        for _, bcfg in ipairs(cfg.Buttons) do
            local btn = makeActionButton({ Title = bcfg.Title, Variant = bcfg.Variant or "Secondary" }, holder, 28)
            btn.ZIndex = 83
            btn.Size = UDim2.new(width, -math.floor(8 * (#cfg.Buttons - 1) / #cfg.Buttons), 1, 0)
            btn.MouseButton1Click:Connect(function()
                safeCallback(bcfg.Callback)
                close()
            end)
        end
    end

    task.delay(cfg.Duration or 5, close)
    return { Close = close }
end

-- // config system -----------------------------------------------------------------------
local function encodeValue(v)
    if typeof(v) == "Color3" then
        return { __type = "Color3", hex = v:ToHex() }
    elseif typeof(v) == "EnumItem" then
        return { __type = "KeyCode", name = v.Name }
    end
    return v
end

local function decodeValue(v)
    if typeof(v) == "table" and v.__type == "Color3" then
        return Color3.fromHex(v.hex)
    elseif typeof(v) == "table" and v.__type == "KeyCode" then
        return Enum.KeyCode[v.name]
    end
    return v
end

local ConfigManager = {}
ConfigManager.__index = ConfigManager

function ConfigManager:CreateConfig(name)
    if not name or name == "" then
        return false, "invalid name"
    end
    local config = {}
    config.Path = self.Folder .. "/" .. name .. ".json"

    function config:Save()
        local data = { __version = 1, __elements = {} }
        for flag, handlers in pairs(PanelUI._flags) do
            data.__elements[flag] = encodeValue(handlers.Get())
        end
        if writefile then
            writefile(config.Path, HttpService:JSONEncode(data))
        end
        return config.Path
    end

    function config:Load()
        if isfile and not isfile(config.Path) then
            error("Config file does not exist")
        end
        local data = HttpService:JSONDecode(readfile(config.Path))
        local elements = data.__elements or data
        for flag, value in pairs(elements) do
            local handlers = PanelUI._flags[flag]
            if handlers then
                pcall(handlers.Set, decodeValue(value))
            end
        end
        return true
    end

    return config
end

function ConfigManager:AllConfigs()
    local names = {}
    if listfiles then
        for _, path in ipairs(listfiles(self.Folder)) do
            local name = path:match("([^/\\]+)%.json$")
            if name then
                table.insert(names, name)
            end
        end
    end
    table.sort(names)
    return names
end

local function registerFlag(flag, getFn, setFn)
    if flag then
        PanelUI._flags[flag] = { Get = getFn, Set = setFn }
    end
end

-- // element construction ------------------------------------------------------------------
-- attachElements(target, host): gives `target` the WindUI element methods.
-- host = { Parent = frame, OnAdd = fn(child) | nil, Compact = bool }
local function attachElements(target, host)

    -- row = frame { Stack (vertical list: headline, desc, body...) ; overlays }
    local function baseRow(opts, rightReserve)
        local hasDesc = opts.Desc and opts.Desc ~= "" and not host.Compact

        local row = create("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = PanelUI.Theme.Element,
            BackgroundTransparency = 0.94,
            BorderSizePixel = 0,
            Parent = host.Parent,
        }, {
            create("UICorner", { CornerRadius = UDim.new(0, ROW_CORNER) }),
        })
        themed(row, { BackgroundColor3 = "Element" })

        local stack = create("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Name = "Stack",
            Parent = row,
        }, {
            create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
            create("UIPadding", {
                PaddingTop = UDim.new(0, 7),
                PaddingBottom = UDim.new(0, 7),
                PaddingLeft = UDim.new(0, 10),
                PaddingRight = UDim.new(0, 10),
            }),
        })

        local headLine = create("Frame", {
            Size = UDim2.new(1, 0, 0, 22),
            BackgroundTransparency = 1,
            Name = "HeadLine",
            LayoutOrder = 1,
            Parent = stack,
        })

        local titleLabel = themed(create("TextLabel", {
            Size = UDim2.new(1, -(rightReserve or 0), 1, 0),
            BackgroundTransparency = 1,
            Text = opts.Title or "",
            TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            FontFace = fontFace(Enum.FontWeight.Medium),
            Parent = headLine,
        }), { TextColor3 = "Text" })

        local descLabel
        if hasDesc then
            descLabel = themed(create("TextLabel", {
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                Text = opts.Desc,
                TextSize = 12,
                TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left,
                FontFace = fontFace(Enum.FontWeight.Regular),
                LayoutOrder = 2,
                Parent = stack,
            }), { TextColor3 = "SubText" })
        end

        if host.OnAdd then
            host.OnAdd(row)
        end
        return row, stack, headLine, titleLabel, descLabel
    end

    local function clickArea(row)
        return create("TextButton", {
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 3,
            Parent = row,
        })
    end

    local function addHover(row, btn, isActive)
        btn.MouseEnter:Connect(function()
            if not isActive() then
                tween(row, 0.1, { BackgroundTransparency = 0.88 })
            end
        end)
        btn.MouseLeave:Connect(function()
            if not isActive() then
                tween(row, 0.1, { BackgroundTransparency = 0.94 })
            end
        end)
    end

    -- expandable container under a row (dropdown lists, colorpicker editors)
    local function makeExpandable()
        local holder = create("Frame", {
            Size = UDim2.new(1, -10, 0, 0),
            BackgroundTransparency = 1,
            ClipsDescendants = true,
            Visible = false,
            Parent = host.Parent,
        })
        local inner = create("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Parent = holder,
        }, {
            create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
        })
        if host.OnAdd then host.OnAdd(holder) end

        local layout = inner:FindFirstChildOfClass("UIListLayout")
        local box = { Opened = false, Content = inner }

        local function measure()
            return layout.AbsoluteContentSize.Y / uiScale()
        end
        function box:Open()
            box.Opened = true
            holder.Visible = true
            tween(holder, 0.3, { Size = UDim2.new(1, -10, 0, measure()) })
        end
        function box:Close()
            box.Opened = false
            tween(holder, 0.25, { Size = UDim2.new(1, -10, 0, 0) })
            task.delay(0.19, function()
                if not box.Opened then
                    holder.Visible = false
                end
            end)
        end
        function box:Toggle()
            if box.Opened then box:Close() else box:Open() end
        end
        function box:Sync()
            if box.Opened then
                holder.Size = UDim2.new(1, -10, 0, measure())
            end
        end
        layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            box:Sync()
        end)
        return box
    end

    local function makeElement(row, titleLabel, descLabel)
        local element = { Locked = false }

        local lockOverlay = create("TextButton", {
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundColor3 = Color3.new(0, 0, 0),
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            Visible = false,
            ZIndex = 10,
            Parent = row,
        }, {
            create("UICorner", { CornerRadius = UDim.new(0, ROW_CORNER) }),
        })

        function element:SetTitle(text)
            if titleLabel then titleLabel.Text = text end
        end
        function element:SetDesc(text)
            if descLabel then descLabel.Text = text end
        end
        function element:Lock()
            element.Locked = true
            lockOverlay.Visible = true
            tween(lockOverlay, 0.15, { BackgroundTransparency = 0.55 })
        end
        function element:Unlock()
            element.Locked = false
            tween(lockOverlay, 0.15, { BackgroundTransparency = 1 })
            task.delay(0.16, function()
                if not element.Locked then lockOverlay.Visible = false end
            end)
        end
        function element:Highlight()
            local stroke = create("UIStroke", {
                Thickness = 2,
                Transparency = 0,
                Color = Color3.new(1, 1, 1),
                Parent = row,
            })
            accentGradient({ Rotation = 45, Parent = stroke })
            tween(stroke, 0.8, { Transparency = 1 })
            task.delay(0.85, function() stroke:Destroy() end)
        end
        function element:Destroy()
            row:Destroy()
        end

        element.__row = row
        return element
    end

    -- // Section -----------------------------------------------------------------
    function target:Section(opts)
        opts = opts or {}
        local label = themed(create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 18),
            BackgroundTransparency = 1,
            Text = string.upper(opts.Title or "Section"),
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            FontFace = fontFace(Enum.FontWeight.Bold),
            Parent = host.Parent,
        }, {
            create("UIPadding", { PaddingLeft = UDim.new(0, 4) }),
        }), { TextColor3 = "SubText" })
        if host.OnAdd then host.OnAdd(label) end
        return label
    end

    -- // Divider -----------------------------------------------------------------
    function target:Divider()
        local line = themed(create("Frame", {
            Size = UDim2.new(1, -8, 0, 1),
            BackgroundTransparency = 0.85,
            BorderSizePixel = 0,
            Parent = host.Parent,
        }), { BackgroundColor3 = "SubText" })
        if host.OnAdd then host.OnAdd(line) end
        return line
    end

    -- // Paragraph ----------------------------------------------------------------
    function target:Paragraph(opts)
        opts = opts or {}
        local row, stack, headLine, titleLabel, descLabel = baseRow(opts, 0)
        titleLabel.FontFace = fontFace(Enum.FontWeight.SemiBold)
        local element = makeElement(row, titleLabel, descLabel)

        if opts.Buttons and #opts.Buttons > 0 then
            local holder = create("Frame", {
                Size = UDim2.new(1, 0, 0, #opts.Buttons * 34 - 4),
                BackgroundTransparency = 1,
                LayoutOrder = 5,
                Parent = stack,
            }, {
                create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
            })
            for _, bcfg in ipairs(opts.Buttons) do
                local btn = makeActionButton({ Title = bcfg.Title, Variant = "Secondary" }, holder, 30)
                btn.ZIndex = 4
                btn.MouseButton1Click:Connect(function()
                    safeCallback(bcfg.Callback)
                end)
            end
        end
        return element
    end

    -- // Code --------------------------------------------------------------------
    function target:Code(opts)
        opts = opts or {}
        local row = create("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = Color3.fromHex("#000000"),
            BackgroundTransparency = 0.45,
            BorderSizePixel = 0,
            Parent = host.Parent,
        }, {
            create("UICorner", { CornerRadius = UDim.new(0, ROW_CORNER) }),
        })
        local stack = create("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Parent = row,
        }, {
            create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
            create("UIPadding", {
                PaddingTop = UDim.new(0, 8),
                PaddingBottom = UDim.new(0, 8),
                PaddingLeft = UDim.new(0, 10),
                PaddingRight = UDim.new(0, 10),
            }),
        })
        local code = opts.Code or ""
        local titleLabel = themed(create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 14),
            BackgroundTransparency = 1,
            Text = (opts.Title or "code") .. "  (click to copy)",
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            FontFace = fontFace(Enum.FontWeight.Bold),
            LayoutOrder = 1,
            Parent = stack,
        }), { TextColor3 = "SubText" })
        local codeLabel = themed(create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Text = code,
            TextSize = 12,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            FontFace = Font.new(MONO),
            LayoutOrder = 2,
            Parent = stack,
        }), { TextColor3 = "Text" })

        local btn = clickArea(row)
        btn.MouseButton1Click:Connect(function()
            local copy = setclipboard or toclipboard
            if copy then
                pcall(copy, code)
                titleLabel.Text = (opts.Title or "code") .. "  (copied!)"
                task.delay(1.2, function()
                    titleLabel.Text = (opts.Title or "code") .. "  (click to copy)"
                end)
            end
        end)

        if host.OnAdd then host.OnAdd(row) end
        local element = makeElement(row, titleLabel, nil)
        function element:Set(newCode)
            code = newCode
            codeLabel.Text = newCode
        end
        return element
    end

    -- // Button ---------------------------------------------------------------------
    function target:Button(opts)
        opts = opts or {}
        local row, _, _, titleLabel, descLabel = baseRow(opts, 0)
        local element = makeElement(row, titleLabel, descLabel)
        local btn = clickArea(row)
        addHover(row, btn, function() return false end)
        btn.MouseButton1Click:Connect(function()
            if element.Locked then return end
            PanelUI.playSound("click")
            local grad = accentGradient({ Rotation = 45, Parent = row })
            local prevColor = row.BackgroundColor3
            row.BackgroundColor3 = Color3.new(1, 1, 1)
            row.BackgroundTransparency = 0.3
            tween(row, 0.35, { BackgroundTransparency = 0.94 })
            task.delay(0.36, function()
                local idx = table.find(PanelUI._accents, grad)
                if idx then table.remove(PanelUI._accents, idx) end
                grad:Destroy()
                row.BackgroundColor3 = PanelUI.Theme.Element
            end)
            safeCallback(opts.Callback)
        end)
        return element
    end

    -- // Toggle ---------------------------------------------------------------------
    function target:Toggle(opts)
        opts = opts or {}
        local isCheckbox = opts.Type == "Checkbox"
        local row, _, headLine, titleLabel, descLabel = baseRow(opts, isCheckbox and 30 or 0)
        local element = makeElement(row, titleLabel, descLabel)
        element.Value = opts.Value or false

        local grad = accentGradient({ Rotation = 45, Enabled = false, Parent = row })

        local boxFill
        if isCheckbox then
            local box = create("Frame", {
                Size = UDim2.new(0, 18, 0, 18),
                Position = UDim2.new(1, 0, 0.5, 0),
                AnchorPoint = Vector2.new(1, 0.5),
                BackgroundColor3 = Color3.new(1, 1, 1),
                BackgroundTransparency = 0.8,
                BorderSizePixel = 0,
                Parent = headLine,
            }, {
                create("UICorner", { CornerRadius = UDim.new(0, 5) }),
            })
            boxFill = create("Frame", {
                Size = UDim2.new(0, 0, 0, 0),
                Position = UDim2.new(0.5, 0, 0.5, 0),
                AnchorPoint = Vector2.new(0.5, 0.5),
                BackgroundColor3 = Color3.new(1, 1, 1),
                BorderSizePixel = 0,
                Parent = box,
            }, {
                create("UICorner", { CornerRadius = UDim.new(0, 3) }),
            })
            accentGradient({ Rotation = 45, Parent = boxFill })
        end

        local function render(animTime)
            if element.Value then
                grad.Enabled = true
                row.BackgroundColor3 = Color3.new(1, 1, 1)
                tween(row, animTime, { BackgroundTransparency = 0.25 })
                tween(titleLabel, animTime, { TextColor3 = PanelUI.Theme.AccentText })
                if boxFill then
                    tween(boxFill, animTime, { Size = UDim2.new(1, -6, 1, -6) }, Enum.EasingStyle.Back)
                end
            else
                grad.Enabled = false
                row.BackgroundColor3 = PanelUI.Theme.Element
                tween(row, animTime, { BackgroundTransparency = 0.94 })
                tween(titleLabel, animTime, { TextColor3 = PanelUI.Theme.Text })
                if boxFill then
                    tween(boxFill, animTime, { Size = UDim2.new(0, 0, 0, 0) })
                end
            end
        end
        table.insert(PanelUI._refresh, function() render(0) end)

        function element:Set(value)
            element.Value = value and true or false
            render(0.15)
            safeCallback(opts.Callback, element.Value)
        end

        local btn = clickArea(row)
        addHover(row, btn, function() return element.Value end)
        btn.MouseButton1Click:Connect(function()
            if element.Locked then return end
            PanelUI.playSound("toggle")
            element:Set(not element.Value)
        end)

        registerFlag(opts.Flag, function() return element.Value end, function(v) element:Set(v) end)
        if element.Value then
            render(0)
            safeCallback(opts.Callback, true)
        end
        return element
    end

    -- // Slider ---------------------------------------------------------------------
    function target:Slider(opts)
        opts = opts or {}
        local v = opts.Value or {}
        local min, max = v.Min or 0, v.Max or 100
        local step = opts.Step or 1
        local startValue = math.clamp(v.Default or min, min, max)

        local row, stack, headLine, titleLabel, descLabel = baseRow(opts, 66)
        local element = makeElement(row, titleLabel, descLabel)
        element.Value = startValue

        local valueLabel = themed(create("TextLabel", {
            Size = UDim2.new(0, 60, 1, 0),
            Position = UDim2.new(1, 0, 0, 0),
            AnchorPoint = Vector2.new(1, 0),
            BackgroundTransparency = 1,
            Text = "",
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Right,
            FontFace = fontFace(Enum.FontWeight.Medium),
            Parent = headLine,
        }), { TextColor3 = "SubText" })

        local barHolder = create("Frame", {
            Size = UDim2.new(1, 0, 0, 12),
            BackgroundTransparency = 1,
            LayoutOrder = 5,
            Parent = stack,
        })
        local bar = create("Frame", {
            Size = UDim2.new(1, 0, 0, 6),
            Position = UDim2.new(0, 0, 0.5, -3),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BackgroundTransparency = 0.85,
            BorderSizePixel = 0,
            Parent = barHolder,
        }, {
            create("UICorner", { CornerRadius = UDim.new(1, 0) }),
        })
        themed(bar, { BackgroundColor3 = "Element" })
        local fill = create("Frame", {
            Size = UDim2.new(0, 0, 1, 0),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            Parent = bar,
        }, {
            create("UICorner", { CornerRadius = UDim.new(1, 0) }),
        })
        accentGradient({ Rotation = 0, Parent = fill })

        local function format(value)
            if step % 1 == 0 then
                return tostring(math.floor(value + 0.5))
            end
            return string.format("%.2f", value)
        end
        local function render(animated)
            local alpha = (element.Value - min) / math.max(max - min, 1e-9)
            if animated then
                tween(fill, 0.06, { Size = UDim2.new(alpha, 0, 1, 0) })
            else
                fill.Size = UDim2.new(alpha, 0, 1, 0)
            end
            valueLabel.Text = format(element.Value)
        end

        function element:Set(value)
            value = math.clamp(value, min, max)
            value = min + math.floor((value - min) / step + 0.5) * step
            value = math.clamp(value, min, max)
            local changed = value ~= element.Value
            element.Value = value
            render(true)
            if changed then
                safeCallback(opts.Callback, value)
            end
        end

        local sliding = false
        local function applyFromX(x)
            local alpha = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
            element:Set(min + alpha * (max - min))
        end
        local grab = clickArea(row)
        addHover(row, grab, function() return sliding end)
        grab.InputBegan:Connect(function(input)
            if element.Locked then return end
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                sliding = true
                applyFromX(input.Position.X)
            end
        end)
        grab.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                sliding = false
            end
        end)
        track(UserInputService.InputChanged:Connect(function(input)
            if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
                applyFromX(input.Position.X)
            end
        end))

        registerFlag(opts.Flag, function() return element.Value end, function(value) element:Set(value) end)
        render(false)
        return element
    end

    -- // Input ----------------------------------------------------------------------
    function target:Input(opts)
        opts = opts or {}
        local isArea = opts.Type == "Textarea"
        local row, stack, headLine, titleLabel, descLabel = baseRow(opts, isArea and 0 or 120)
        local element = makeElement(row, titleLabel, descLabel)
        element.Value = opts.Value or ""

        local box
        if isArea then
            box = create("TextBox", {
                Size = UDim2.new(1, 0, 0, 58),
                MultiLine = true,
                TextWrapped = true,
                TextYAlignment = Enum.TextYAlignment.Top,
                LayoutOrder = 5,
                Parent = stack,
            })
        else
            box = create("TextBox", {
                Size = UDim2.new(0, 114, 0, 22),
                Position = UDim2.new(1, 0, 0.5, 0),
                AnchorPoint = Vector2.new(1, 0.5),
                Parent = headLine,
            })
        end
        box.BackgroundColor3 = Color3.new(1, 1, 1)
        box.BackgroundTransparency = 0.9
        box.Text = element.Value
        box.PlaceholderText = opts.Placeholder or ""
        box.TextSize = 13
        box.TextTruncate = isArea and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd
        box.ClearTextOnFocus = opts.ClearTextOnFocus or false
        box.FontFace = fontFace(Enum.FontWeight.Medium)
        box.ZIndex = 4
        themed(box, { TextColor3 = "Text", PlaceholderColor3 = "SubText" })
        create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = box })
        create("UIPadding", {
            PaddingLeft = UDim.new(0, 6),
            PaddingRight = UDim.new(0, 6),
            PaddingTop = UDim.new(0, isArea and 4 or 0),
            Parent = box,
        })

        box.Focused:Connect(function()
            tween(box, 0.1, { BackgroundTransparency = 0.82 })
        end)
        box.FocusLost:Connect(function()
            tween(box, 0.1, { BackgroundTransparency = 0.9 })
            if element.Locked then
                box.Text = element.Value
                return
            end
            element.Value = box.Text
            safeCallback(opts.Callback, box.Text)
        end)

        function element:Set(text)
            element.Value = text
            box.Text = text
            safeCallback(opts.Callback, text)
        end

        registerFlag(opts.Flag, function() return element.Value end, function(value) element:Set(value) end)
        return element
    end

    -- // Keybind --------------------------------------------------------------------
    function target:Keybind(opts)
        opts = opts or {}
        local row, _, headLine, titleLabel, descLabel = baseRow(opts, 96)
        local element = makeElement(row, titleLabel, descLabel)
        element.Value = opts.Value or "None"

        local keyLabel = themed(create("TextLabel", {
            Size = UDim2.new(0, 90, 1, 0),
            Position = UDim2.new(1, 0, 0, 0),
            AnchorPoint = Vector2.new(1, 0),
            BackgroundTransparency = 1,
            Text = element.Value,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Right,
            FontFace = fontFace(Enum.FontWeight.Medium),
            Parent = headLine,
        }), { TextColor3 = "SubText" })

        local listening = false
        local btn = clickArea(row)
        addHover(row, btn, function() return listening end)
        btn.MouseButton1Click:Connect(function()
            if element.Locked then return end
            listening = true
            keyLabel.Text = "..."
            keyLabel.TextColor3 = PanelUI.Theme.AccentB
        end)

        track(UserInputService.InputBegan:Connect(function(input, _processed)
            if listening and input.UserInputType == Enum.UserInputType.Keyboard then
                listening = false
                element.Value = input.KeyCode.Name
                keyLabel.Text = element.Value
                keyLabel.TextColor3 = PanelUI.Theme.SubText
                if opts.OnChange then
                    safeCallback(opts.OnChange, element.Value)
                end
                return
            end
            -- fire on the bound key; ignore `gameProcessed` (Roblox marks many keys
            -- like F as processed, which would block the hotkey), but skip while
            -- the user is typing in a text box
            if not listening and input.UserInputType == Enum.UserInputType.Keyboard
                and input.KeyCode.Name == element.Value
                and not UserInputService:GetFocusedTextBox() then
                safeCallback(opts.Callback, element.Value)
            end
        end))

        function element:Set(key)
            element.Value = key
            keyLabel.Text = key
        end

        registerFlag(opts.Flag, function() return element.Value end, function(value) element:Set(value) end)
        return element
    end

    -- // Dropdown (expands inline, animated) -------------------------------------------
    function target:Dropdown(opts)
        opts = opts or {}
        local row, _, headLine, titleLabel, descLabel = baseRow(opts, 120)
        local element = makeElement(row, titleLabel, descLabel)
        element.Values = opts.Values or {}
        element.Multi = opts.Multi or false
        element.Opened = false
        if element.Multi then
            element.Value = opts.Value or {}
        else
            element.Value = opts.Value or element.Values[1]
        end

        local valueLabel = themed(create("TextLabel", {
            Size = UDim2.new(0, 96, 1, 0),
            Position = UDim2.new(1, -22, 0, 0),
            AnchorPoint = Vector2.new(1, 0),
            BackgroundTransparency = 1,
            Text = "",
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Right,
            TextTruncate = Enum.TextTruncate.AtEnd,
            FontFace = fontFace(Enum.FontWeight.Medium),
            Parent = headLine,
        }), { TextColor3 = "SubText" })
        local chevron = makeChevron(headLine, 0)

        local listBox = makeExpandable()

        local function isSelected(value)
            if element.Multi then
                return table.find(element.Value, value) ~= nil
            end
            return element.Value == value
        end

        local function displayText()
            if element.Multi then
                return #element.Value > 0 and table.concat(element.Value, ", ") or "..."
            end
            return tostring(element.Value or "...")
        end

        local optionRows = {}
        local function renderOptions()
            for _, opt in ipairs(optionRows) do
                local selected = isSelected(opt.Value)
                opt.Gradient.Enabled = selected
                opt.Row.BackgroundColor3 = selected and Color3.new(1, 1, 1) or PanelUI.Theme.Element
                tween(opt.Row, 0.12, { BackgroundTransparency = selected and 0.3 or 0.95 })
                tween(opt.Label, 0.12, {
                    TextColor3 = selected and PanelUI.Theme.AccentText or PanelUI.Theme.SubText,
                })
            end
            valueLabel.Text = displayText()
        end
        table.insert(PanelUI._refresh, renderOptions)

        local function pick(value)
            if element.Multi then
                local idx = table.find(element.Value, value)
                if idx then
                    if #element.Value > 1 or opts.AllowNone then
                        table.remove(element.Value, idx)
                    end
                else
                    table.insert(element.Value, value)
                end
            else
                element.Value = value
            end
            renderOptions()
            safeCallback(opts.Callback, element.Value)
        end

        local function buildOptions()
            for _, opt in ipairs(optionRows) do
                opt.Row:Destroy()
            end
            optionRows = {}
            for _, value in ipairs(element.Values) do
                local optRow = create("Frame", {
                    Size = UDim2.new(1, 0, 0, 26),
                    BackgroundColor3 = PanelUI.Theme.Element,
                    BackgroundTransparency = 0.95,
                    BorderSizePixel = 0,
                    Parent = listBox.Content,
                }, {
                    create("UICorner", { CornerRadius = UDim.new(0, ROW_CORNER - 2) }),
                })
                local optGrad = accentGradient({ Rotation = 45, Enabled = false, Parent = optRow })
                local optLabel = create("TextLabel", {
                    Size = UDim2.new(1, -20, 1, 0),
                    Position = UDim2.fromOffset(10, 0),
                    BackgroundTransparency = 1,
                    Text = tostring(value),
                    TextSize = 13,
                    TextColor3 = PanelUI.Theme.SubText,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    FontFace = fontFace(Enum.FontWeight.Medium),
                    Parent = optRow,
                })
                local optBtn = clickArea(optRow)
                optBtn.MouseEnter:Connect(function()
                    if not isSelected(value) then
                        tween(optRow, 0.1, { BackgroundTransparency = 0.88 })
                    end
                end)
                optBtn.MouseLeave:Connect(function()
                    if not isSelected(value) then
                        tween(optRow, 0.1, { BackgroundTransparency = 0.95 })
                    end
                end)
                optBtn.MouseButton1Click:Connect(function()
                    if not element.Locked then pick(value) end
                end)
                table.insert(optionRows, { Row = optRow, Label = optLabel, Gradient = optGrad, Value = value })
            end
            renderOptions()
            listBox:Sync()
        end

        function element:Select(value)
            if element.Multi and typeof(value) == "table" then
                element.Value = value
            elseif element.Multi then
                element.Value = { value }
            else
                element.Value = value
            end
            renderOptions()
            safeCallback(opts.Callback, element.Value)
        end
        element.Set = element.Select

        function element:Refresh(values)
            element.Values = values or {}
            if element.Multi then
                local kept = {}
                for _, val in ipairs(element.Value) do
                    if table.find(element.Values, val) then
                        table.insert(kept, val)
                    end
                end
                element.Value = kept
            elseif not table.find(element.Values, element.Value) then
                element.Value = element.Values[1]
            end
            buildOptions()
        end

        local btn = clickArea(row)
        addHover(row, btn, function() return false end)
        btn.MouseButton1Click:Connect(function()
            if element.Locked then return end
            PanelUI.playSound("click")
            element.Opened = not element.Opened
            listBox:Toggle()
            tween(chevron, 0.2, { Rotation = element.Opened and -90 or 90 })
        end)

        registerFlag(opts.Flag, function() return element.Value end, function(value) element:Select(value) end)
        buildOptions()
        return element
    end

    -- // Colorpicker (inline RGB sliders, animated expand) -------------------------------
    function target:Colorpicker(opts)
        opts = opts or {}
        local hasAlpha = opts.Transparency ~= nil
        local row, _, headLine, titleLabel, descLabel = baseRow(opts, 40)
        local element = makeElement(row, titleLabel, descLabel)
        element.Value = opts.Default or Color3.new(1, 1, 1)
        element.Transparency = opts.Transparency or 0

        local swatch = create("Frame", {
            Size = UDim2.new(0, 26, 0, 16),
            Position = UDim2.new(1, 0, 0.5, 0),
            AnchorPoint = Vector2.new(1, 0.5),
            BackgroundColor3 = element.Value,
            BackgroundTransparency = element.Transparency,
            BorderSizePixel = 0,
            Parent = headLine,
        }, {
            create("UICorner", { CornerRadius = UDim.new(0, 5) }),
            create("UIStroke", { Thickness = 1, Transparency = 0.6, Color = Color3.new(1, 1, 1) }),
        })

        local editor = makeExpandable()
        local channels = hasAlpha and { "R", "G", "B", "A" } or { "R", "G", "B" }

        local function getChannel(name)
            if name == "R" then return element.Value.R end
            if name == "G" then return element.Value.G end
            if name == "B" then return element.Value.B end
            return 1 - element.Transparency
        end
        local function setChannel(name, alpha)
            local r, g, b = element.Value.R, element.Value.G, element.Value.B
            if name == "R" then r = alpha
            elseif name == "G" then g = alpha
            elseif name == "B" then b = alpha
            else element.Transparency = 1 - alpha end
            element.Value = Color3.new(r, g, b)
        end

        local channelBars = {}
        local function renderAll(animated)
            swatch.BackgroundColor3 = element.Value
            swatch.BackgroundTransparency = element.Transparency
            for _, ch in ipairs(channelBars) do
                if animated then
                    tween(ch.Fill, 0.06, { Size = UDim2.new(getChannel(ch.Name), 0, 1, 0) })
                else
                    ch.Fill.Size = UDim2.new(getChannel(ch.Name), 0, 1, 0)
                end
            end
        end

        local function fire()
            if hasAlpha then
                safeCallback(opts.Callback, element.Value, element.Transparency)
            else
                safeCallback(opts.Callback, element.Value)
            end
        end

        for _, name in ipairs(channels) do
            local chRow = create("Frame", {
                Size = UDim2.new(1, 0, 0, 20),
                BackgroundTransparency = 1,
                Parent = editor.Content,
            })
            themed(create("TextLabel", {
                Size = UDim2.new(0, 16, 1, 0),
                BackgroundTransparency = 1,
                Text = name,
                TextSize = 11,
                FontFace = fontFace(Enum.FontWeight.Bold),
                Parent = chRow,
            }), { TextColor3 = "SubText" })
            local bar = create("Frame", {
                Size = UDim2.new(1, -24, 0, 6),
                Position = UDim2.new(0, 22, 0.5, -3),
                BackgroundColor3 = Color3.new(1, 1, 1),
                BackgroundTransparency = 0.85,
                BorderSizePixel = 0,
                Parent = chRow,
            }, {
                create("UICorner", { CornerRadius = UDim.new(1, 0) }),
            })
            themed(bar, { BackgroundColor3 = "Element" })
            local fill = create("Frame", {
                Size = UDim2.new(getChannel(name), 0, 1, 0),
                BackgroundColor3 = name == "R" and Color3.fromRGB(244, 96, 96)
                    or name == "G" and Color3.fromRGB(96, 220, 130)
                    or name == "B" and Color3.fromRGB(96, 140, 248)
                    or Color3.fromRGB(220, 220, 230),
                BorderSizePixel = 0,
                Parent = bar,
            }, {
                create("UICorner", { CornerRadius = UDim.new(1, 0) }),
            })
            table.insert(channelBars, { Name = name, Fill = fill })

            local sliding = false
            local function applyFromX(x)
                local alpha = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
                setChannel(name, alpha)
                renderAll(true)
                fire()
            end
            local grabBtn = create("TextButton", {
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = "",
                AutoButtonColor = false,
                Parent = chRow,
            })
            grabBtn.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                    sliding = true
                    applyFromX(input.Position.X)
                end
            end)
            grabBtn.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                    sliding = false
                end
            end)
            track(UserInputService.InputChanged:Connect(function(input)
                if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement
                    or input.UserInputType == Enum.UserInputType.Touch) then
                    applyFromX(input.Position.X)
                end
            end))
        end

        local btn = clickArea(row)
        addHover(row, btn, function() return false end)
        btn.MouseButton1Click:Connect(function()
            if element.Locked then return end
            PanelUI.playSound("click")
            editor:Toggle()
        end)

        function element:Set(color, transparency)
            element.Value = color or element.Value
            if transparency ~= nil then
                element.Transparency = transparency
            end
            renderAll(true)
            fire()
        end
        element.Update = element.Set

        registerFlag(opts.Flag,
            function()
                return { __type = "Color3", hex = element.Value:ToHex(), t = element.Transparency }
            end,
            function(value)
                if typeof(value) == "table" and value.hex then
                    element:Set(Color3.fromHex(value.hex), value.t)
                elseif typeof(value) == "Color3" then
                    element:Set(value)
                end
            end)
        renderAll(false)
        return element
    end

    -- // HStack ------------------------------------------------------------------------
    function target:HStack(opts)
        opts = opts or {}
        local container = create("Frame", {
            Size = UDim2.new(1, 0, 0, 36),
            BackgroundTransparency = 1,
            Parent = host.Parent,
        })
        if host.OnAdd then host.OnAdd(container) end

        local children = {}
        local function rebalance()
            local n = #children
            if n == 0 then return end
            local width = 1 / n
            local tallest = 36
            for i, child in ipairs(children) do
                child.Position = UDim2.new(width * (i - 1), (i - 1) * 2, 0, 0)
                child.Size = UDim2.new(width, -math.ceil(GAP * (n - 1) / n), child.Size.Y.Scale, child.Size.Y.Offset)
                tallest = math.max(tallest, math.floor(child.AbsoluteSize.Y / uiScale() + 0.5))
            end
            container.Size = UDim2.new(1, 0, 0, tallest)
        end

        local stack = {}
        attachElements(stack, {
            Parent = container,
            Compact = true,
            OnAdd = function(child)
                table.insert(children, child)
                child:GetPropertyChangedSignal("AbsoluteSize"):Connect(rebalance)
                rebalance()
                task.defer(rebalance)
            end,
        })
        return stack
    end
end

-- // window ----------------------------------------------------------------------------
function PanelUI:CreateWindow(cfg)
    cfg = cfg or {}
    ensureGui()

    if cfg.Theme and Themes[cfg.Theme] then
        PanelUI.Theme = Themes[cfg.Theme]
    end
    PanelUI.Transparent = cfg.Transparent ~= false
    PanelUI.OutlineAnimated = cfg.OutlineAnimated or false
    PanelUI.OutlineSpeed = cfg.OutlineSpeed or 60
    PanelUI.OutlineThickness = cfg.OutlineThickness or 2
    PanelUI.OutlineTransparency = cfg.OutlineTransparency or 0.25

    local window = {
        Title = cfg.Title or "Window",
        Author = cfg.Author or "",
        Folder = cfg.Folder or "PanelUI",
        ToggleKey = cfg.ToggleKey or Enum.KeyCode.K,
        Opened = true,
        Tabs = {},
        _panels = {},
        _restorePos = {},
        _fadeSnap = {},
        _panelBgHidden = false,
        _onOpen = {}, _onClose = {}, _onDestroy = {},
        _nextX = 16,
        _rowY = 16,
    }
    PanelUI.Window = window

    if makefolder and isfolder and not isfolder(window.Folder) then
        pcall(makefolder, window.Folder)
    end
    window.ConfigManager = setmetatable({ Folder = window.Folder }, ConfigManager)

    local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1366, 768)

    -- // title chip ----------------------------------------------------------------
    local chip = themed(create("Frame", {
        Size = UDim2.fromOffset(0, 56),
        AutomaticSize = Enum.AutomaticSize.X,
        Position = UDim2.fromOffset(16, 16),
        BackgroundTransparency = PanelUI.Transparent and PanelUI.PanelTransparency or 0,
        BorderSizePixel = 0,
        Parent = PanelUI.PanelLayer,
    }, {
        create("UICorner", { CornerRadius = UDim.new(0, CORNER) }),
        create("UIPadding", {
            PaddingLeft = UDim.new(0, 14),
            PaddingRight = UDim.new(0, 14),
            PaddingTop = UDim.new(0, 9),
        }),
    }), { BackgroundColor3 = "PanelBackground" })
    table.insert(window._panels, chip)
    acrylicAttach(chip)

    local chipStroke = create("UIStroke", {
        Thickness = PanelUI.OutlineThickness,
        Transparency = PanelUI.OutlineTransparency,
        Color = Color3.new(1, 1, 1),
        LineJoinMode = Enum.LineJoinMode.Round,
        Parent = chip,
    })
    local chipGrad = accentGradient({ Rotation = 45, Parent = chipStroke })
    if PanelUI.OutlineAnimated then
        table.insert(PanelUI._spin, chipGrad)
    end

    local chipTitle = themed(create("TextLabel", {
        Size = UDim2.new(0, 0, 0, 22),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Text = window.Title,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
        FontFace = fontFace(Enum.FontWeight.SemiBold),
        Parent = chip,
    }), { TextColor3 = "HeaderText" })
    local chipAuthor = themed(create("TextLabel", {
        Size = UDim2.new(0, 0, 0, 16),
        AutomaticSize = Enum.AutomaticSize.X,
        Position = UDim2.fromOffset(0, 24),
        BackgroundTransparency = 1,
        Text = window.Author,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        FontFace = fontFace(Enum.FontWeight.Regular),
        Parent = chip,
    }), { TextColor3 = "SubText" })
    local tagHolder = create("Frame", {
        Size = UDim2.new(0, 0, 0, 18),
        AutomaticSize = Enum.AutomaticSize.X,
        Position = UDim2.fromOffset(0, 2),
        BackgroundTransparency = 1,
        Parent = chip,
    }, {
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
    })
    local function placeTags()
        tagHolder.Position = UDim2.fromOffset(chipTitle.AbsoluteSize.X / uiScale() + 10, 2)
    end
    chipTitle:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeTags)
    task.defer(placeTags)

    -- // drag + click helper -----------------------------------------------------------
    local function makeDraggable(frame, handle, onClick)
        local dragging, moved, dragStart, startPos = false, false, nil, nil
        handle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging, moved = true, false
                dragStart = input.Position
                startPos = frame.Position
            end
        end)
        handle.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
                if not moved and onClick then
                    onClick()
                end
            end
        end)
        track(UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = input.Position - dragStart
                if math.abs(delta.X) + math.abs(delta.Y) > 4 then
                    moved = true
                end
                local scale = uiScale()
                frame.Position = UDim2.fromOffset(
                    startPos.X.Offset + delta.X / scale,
                    startPos.Y.Offset + delta.Y / scale
                )
            end
        end))
    end

    local chipHandle = create("TextButton", {
        Size = UDim2.new(1, 28, 1, 9),
        Position = UDim2.fromOffset(-14, -9),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Parent = chip,
    })
    makeDraggable(chip, chipHandle, nil)

    -- // Tab -> floating panel --------------------------------------------------------
    local function createPanel(opts)
        opts = opts or {}
        local tab = { Title = opts.Title or "Tab", Collapsed = false }

        if window._nextX + PANEL_WIDTH > viewport.X - 16 then
            window._nextX = 16
            window._rowY = window._rowY + 340
        end

        local maxHeight = math.floor(viewport.Y * 0.7)
        local frame = themed(create("Frame", {
            Size = UDim2.fromOffset(PANEL_WIDTH, HEADER_HEIGHT),
            Position = UDim2.fromOffset(window._nextX, window._rowY + (window._rowY == 16 and 72 or 0)),
            BackgroundTransparency = PanelUI.Transparent and PanelUI.PanelTransparency or 0,
            BorderSizePixel = 0,
            ClipsDescendants = true,
            Parent = PanelUI.PanelLayer,
        }, {
            create("UICorner", { CornerRadius = UDim.new(0, CORNER) }),
        }), { BackgroundColor3 = "PanelBackground" })
        window._nextX = window._nextX + PANEL_WIDTH + 14
        table.insert(window._panels, frame)
        tab.Frame = frame
        acrylicAttach(frame)

        local stroke = create("UIStroke", {
            Thickness = PanelUI.OutlineThickness,
            Transparency = PanelUI.OutlineTransparency,
            Color = Color3.new(1, 1, 1),
            LineJoinMode = Enum.LineJoinMode.Round,
            Parent = frame,
        })
        local strokeGrad = accentGradient({ Rotation = 45, Parent = stroke })
        if PanelUI.OutlineAnimated then
            table.insert(PanelUI._spin, strokeGrad)
        end

        local header = themed(create("TextButton", {
            Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
            BackgroundTransparency = 1,
            Text = tab.Title,
            TextSize = 16,
            FontFace = fontFace(Enum.FontWeight.SemiBold),
            AutoButtonColor = false,
            Parent = frame,
        }), { TextColor3 = "HeaderText" })

        local content = create("ScrollingFrame", {
            Position = UDim2.fromOffset(0, HEADER_HEIGHT),
            Size = UDim2.new(1, 0, 1, -HEADER_HEIGHT),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 2,
            ScrollBarImageTransparency = 0.5,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Parent = frame,
        }, {
            create("UIListLayout", {
                Padding = UDim.new(0, GAP),
                FillDirection = Enum.FillDirection.Vertical,
                HorizontalAlignment = Enum.HorizontalAlignment.Center,
                SortOrder = Enum.SortOrder.LayoutOrder,
            }),
            create("UIPadding", {
                PaddingTop = UDim.new(0, 2),
                PaddingLeft = UDim.new(0, PADDING),
                PaddingRight = UDim.new(0, PADDING),
                PaddingBottom = UDim.new(0, PADDING),
            }),
        })
        themed(content, { ScrollBarImageColor3 = "AccentA" })
        local layout = content:FindFirstChildOfClass("UIListLayout")

        local function updateHeight()
            if tab.Collapsed then
                tween(frame, 0.32, { Size = UDim2.fromOffset(PANEL_WIDTH, HEADER_HEIGHT) })
                return
            end
            local wanted = HEADER_HEIGHT + layout.AbsoluteContentSize.Y / uiScale() + PADDING + 4
            tween(frame, 0.32, { Size = UDim2.fromOffset(PANEL_WIDTH, math.min(wanted, maxHeight)) })
        end
        layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateHeight)

        -- header hover highlight
        header.MouseEnter:Connect(function()
            tween(header, 0.15, { TextColor3 = PanelUI.Theme.AccentB })
        end)
        header.MouseLeave:Connect(function()
            tween(header, 0.15, { TextColor3 = PanelUI.Theme.HeaderText })
        end)

        makeDraggable(frame, header, function()
            tab.Collapsed = not tab.Collapsed
            updateHeight()
        end)

        attachElements(tab, { Parent = content })
        table.insert(window.Tabs, tab)
        return tab
    end

    function window:Tab(opts)
        return createPanel(opts)
    end

    function window:Section(opts)
        local section = {}
        function section:Tab(tabOpts)
            return createPanel(tabOpts)
        end
        function section:Open() end
        function section:Close() end
        return section
    end

    function window:Divider() end
    function window:SelectTab(_n) end
    function window:ToggleFullscreen() end
    function window:EditOpenButton(_opts) end

    function window:Tag(opts)
        opts = opts or {}
        local pill = create("Frame", {
            Size = UDim2.new(0, 0, 0, 18),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = typeof(opts.Color) == "Color3" and opts.Color or Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            Parent = tagHolder,
        }, {
            create("UICorner", { CornerRadius = UDim.new(1, 0) }),
            create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
        })
        local textColor = Color3.new(1, 1, 1)
        if typeof(opts.Color) == "table" then
            local grad = create("UIGradient", { Parent = pill })
            for prop, value in pairs(opts.Color) do
                grad[prop] = value
            end
        elseif typeof(opts.Color) == "Color3" then
            local _, _, value = opts.Color:ToHSV()
            textColor = value > 0.6 and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
        end
        create("TextLabel", {
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            Text = opts.Title or "",
            TextColor3 = textColor,
            TextSize = 11,
            FontFace = fontFace(Enum.FontWeight.Bold),
            Parent = pill,
        })
        return pill
    end

    function window:Dialog(opts)
        return makeModal(opts or {})
    end

    function window:OnOpen(fn) table.insert(window._onOpen, fn) end
    function window:OnClose(fn) table.insert(window._onClose, fn) end
    function window:OnDestroy(fn) table.insert(window._onDestroy, fn) end

    function window:SetTitle(text)
        window.Title = text
        chipTitle.Text = text
    end
    function window:SetAuthor(text)
        window.Author = text
        chipAuthor.Text = text
    end
    function window:SetToggleKey(keycode)
        window.ToggleKey = keycode
    end
    function window:SetUIScale(scale)
        PanelUI._uiscale.Scale = math.clamp(scale, 0.5, 2)
    end

    local function panelTransparency()
        if window._panelBgHidden then return 1 end
        return PanelUI.Transparent and PanelUI.PanelTransparency or 0
    end
    local function refreshPanelBackgrounds()
        for _, panel in ipairs(window._panels) do
            tween(panel, 0.15, { BackgroundTransparency = panelTransparency() })
        end
    end
    function window:ToggleTransparency(state)
        PanelUI.Transparent = state and true or false
        refreshPanelBackgrounds()
    end
    function window:SetPanelBackground(hidden)
        window._panelBgHidden = hidden and true or false
        refreshPanelBackgrounds()
    end

    -- smooth open/close: snapshot resting transparencies, fade all together (no CanvasGroup,
    -- so text stays crisp), restore exact values on reopen
    local fadeProps = {
        TextLabel = { "TextTransparency", "TextStrokeTransparency" },
        TextButton = { "TextTransparency", "BackgroundTransparency" },
        TextBox = { "TextTransparency", "BackgroundTransparency" },
        ImageLabel = { "ImageTransparency", "BackgroundTransparency" },
        ImageButton = { "ImageTransparency", "BackgroundTransparency" },
        Frame = { "BackgroundTransparency" },
        ScrollingFrame = { "BackgroundTransparency", "ScrollBarImageTransparency" },
        UIStroke = { "Transparency" },
    }

    local function snapshotPanel(panel)
        local snap = {}
        local function consider(obj)
            local props = fadeProps[obj.ClassName]
            if props then
                local entry = {}
                for _, prop in ipairs(props) do
                    local ok, value = pcall(function() return obj[prop] end)
                    if ok then entry[prop] = value end
                end
                snap[obj] = entry
            end
        end
        consider(panel)
        for _, obj in ipairs(panel:GetDescendants()) do
            consider(obj)
        end
        return snap
    end

    local function fadePanel(panel, snap, hidden, time)
        for obj, entry in pairs(snap) do
            if obj.Parent then
                for prop, rest in pairs(entry) do
                    tween(obj, time, { [prop] = hidden and 1 or rest })
                end
            end
        end
    end

    function window:Open()
        if window.Opened then return end
        window.Opened = true
        PanelUI.PanelLayer.Visible = true
        acrylicFade(true, 0.3)
        for _, panel in ipairs(window._panels) do
            local snap = window._fadeSnap[panel]
            if snap then
                fadePanel(panel, snap, false, 0.28)
            end
            local restore = window._restorePos[panel]
            if restore then
                panel.Position = restore + UDim2.fromOffset(0, 18)
                tween(panel, 0.34, { Position = restore }, Enum.EasingStyle.Back)
            end
        end
        PanelUI.playSound("open")
        for _, fn in ipairs(window._onOpen) do safeCallback(fn) end
    end

    function window:Close()
        if not window.Opened then return end
        window.Opened = false
        acrylicFade(false, 0.24)
        for _, panel in ipairs(window._panels) do
            local snap = snapshotPanel(panel)
            window._fadeSnap[panel] = snap
            fadePanel(panel, snap, true, 0.24)
            window._restorePos[panel] = panel.Position
            tween(panel, 0.28, { Position = panel.Position + UDim2.fromOffset(0, 18) })
        end
        task.delay(0.32, function()
            if not window.Opened then
                PanelUI.PanelLayer.Visible = false
                for _, panel in ipairs(window._panels) do
                    local restore = window._restorePos[panel]
                    if restore then
                        panel.Position = restore
                    end
                end
            end
        end)
        PanelUI.playSound("close")
        for _, fn in ipairs(window._onClose) do safeCallback(fn) end
    end
    function window:Toggle()
        if window.Opened then window:Close() else window:Open() end
    end
    function window:Destroy()
        for _, fn in ipairs(window._onDestroy) do safeCallback(fn) end
        for _, connection in ipairs(PanelUI._connections) do
            connection:Disconnect()
        end
        PanelUI._connections = {}
        acrylicCleanup()
        if PanelUI.Gui then
            PanelUI.Gui:Destroy()
            PanelUI.Gui = nil
        end
        PanelUI.Window = nil
    end

    track(UserInputService.InputBegan:Connect(function(input, _processed)
        if input.KeyCode == window.ToggleKey and not UserInputService:GetFocusedTextBox() then
            window:Toggle()
        end
    end))

    if cfg.Acrylic then
        acrylicSetEnabled(true)
    end

    PanelUI.ApplyTheme()
    return window
end

return PanelUI
