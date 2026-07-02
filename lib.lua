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

        registerFlag(opts.Flag, function() return element.Value end, ... (36 KB kaldı)
