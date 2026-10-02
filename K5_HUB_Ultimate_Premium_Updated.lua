local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Player = Players.LocalPlayer
local CodeRE = ReplicatedStorage.Framework.Systems.CodesSystem.CodeRE

-- Ganti dengan ID gambar logo SALIMA HUB yang sudah di-upload ke Roblox
local LOGO_IMAGE = ""

local CODE_COOLDOWN = 8.6
local BUFFER = 8.5
local REDEEM_DELAY = CODE_COOLDOWN + BUFFER

local Codes = {
    "Locko_SS",
    "MAS ACENG",
    "Aimyoungs",
    "GRAYWOLF",
    "Astral",
    "Ahjughh",
    "AAM",
    "ARES",
    "ARKANGHEL",
    "ERIKSM",
    "reiley",
    "BERLINHERE23",
    "Giovanni_GG",
    "CA2",
    "SIGURIH",
    "MERGIXS",
    "druscxlla",
    "MAHAFEY",
    "ToadPlaysGamesTTV",
    "luknojo",
    "Ghifa",
    "Luthador2121",
    "RIKUSOULS",
    "T3nsei",
    "Dray28",
    "Sukunay",
    "Maple",
    "LALAGANG",
    "Uzi",
    "runekify",
    "Zeny",
    "HELOS",
    "LezoCr",
    "Fujiesane",
    "Laplace",
    "Nyxaria",
    "FannTzy",
    "Deco",
    "dasher",
    "Nothing",
    "ProfGab",
    "SUB2BLAZESTARS",
    "Dism",
    "SUPER MBUD",
    "Marcell",
    "DrekathSenpai",
    "Darkfeniks",
    "Sneptuno",
    "Markbhatra",
    "LZZ_019BEST",
    "Bebek",
    "NisardHelpOnlyWoman",
    "TT_oratttt",
    "Izumi_Senpai",
    "Les",
    "SEYUnever",
    "Shan",
    "Freca",
    "Ryokenn",
    "ReyPomuchi",
    "Gryffin",
    "DEI_Yumeko",
    "Chrisss",
    "tony_vt",
    "Ryu",
    "Clipz7112",
    "PaPaX",
    "Kiota2",
    "Lulzsec",
    "smiley",
    "Sine",
    "GT_HANNI",
    "Erijero",
    "DanoNano",
    "WettySNK",
    "obe",
    "Dekday",
    "Qyuu",
    "Gwynne",
    "PapiJoy",
    "Taalonely",
    "Darren",
    "MADUNN",
    "PepCalcot",
    "Shirooo0312_IRONSOUL",
    "Monarch",
    "Lifauzi",
    "TT_Mentally_ill_K.N",
    "RaykorBR",
    "ZARGAKSTONE",
    "Heso",
    "Ghelayyy",
    "EJ(YURU)",
    "IronReaper",
    "Skywinter86",
    "ALLWAONIRONSOUL",
    "IRONWEEKENDGIFT26",
}

--==================================================
-- STATE
--==================================================

local AutoRedeem = false
local IsRedeeming = false
local claimedCodes = {}

local totalCodes = #Codes
local successCount = 0

--==================================================
-- COLORS
--==================================================

local BG = Color3.fromRGB(19, 13, 42)
local PANEL = Color3.fromRGB(29, 20, 58)
local PANEL_LIGHT = Color3.fromRGB(39, 27, 73)

local PURPLE = Color3.fromRGB(145, 75, 255)
local PURPLE_DARK = Color3.fromRGB(91, 45, 170)

local WHITE = Color3.fromRGB(240, 237, 255)
local GREY = Color3.fromRGB(165, 157, 190)

local GREEN = Color3.fromRGB(75, 220, 130)
local RED = Color3.fromRGB(230, 75, 90)

--==================================================
-- SCREEN GUI
--==================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "K5HubIronSoulCode"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = Player:WaitForChild("PlayerGui")

--==================================================
-- MAIN
--==================================================

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0, 440, 0, 300)
Main.ClipsDescendants = true
Main.AnchorPoint = Vector2.new(0.5, 0.5)
Main.Position = UDim2.new(0.5, 0, 0.5, 0)
Main.BackgroundColor3 = BG
Main.BorderSizePixel = 0
Main.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 12)
MainCorner.Parent = Main

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = PURPLE_DARK
MainStroke.Thickness = 2
MainStroke.Transparency = 0.2
MainStroke.Parent = Main

--==================================================
-- HEADER
--==================================================

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 50)
Header.BackgroundColor3 = PANEL
Header.BorderSizePixel = 0
Header.Parent = Main

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 12)
HeaderCorner.Parent = Header

local HeaderFix = Instance.new("Frame")
HeaderFix.Position = UDim2.new(0, 0, 1, -16)
HeaderFix.Size = UDim2.new(1, 0, 0, 16)
HeaderFix.BackgroundColor3 = PANEL
HeaderFix.BorderSizePixel = 0
HeaderFix.Parent = Header

--==================================================
-- DRAGGABLE PANEL
--==================================================

local dragging = false
local dragStart = nil
local startPosition = nil

local function updateDrag(input)
    local delta = input.Position - dragStart
    Main.Position = UDim2.new(
        startPosition.X.Scale,
        startPosition.X.Offset + delta.X,
        startPosition.Y.Scale,
        startPosition.Y.Offset + delta.Y
    )
end

Header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPosition = Main.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and (
        input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
    ) then
        updateDrag(input)
    end
end)

--==================================================
-- CLOSE BUTTON
--==================================================

local CloseButton = Instance.new("TextButton")
CloseButton.Name = "CloseButton"
CloseButton.Position = UDim2.new(0, 8, 0, 8)
CloseButton.Size = UDim2.new(0, 28, 0, 28)
CloseButton.BackgroundColor3 = Color3.fromRGB(55, 38, 82)
CloseButton.Text = "×"
CloseButton.TextColor3 = WHITE
CloseButton.TextSize = 20
CloseButton.Font = Enum.Font.GothamBold
CloseButton.AutoButtonColor = false
CloseButton.BorderSizePixel = 0
CloseButton.ZIndex = 5
CloseButton.Parent = Header

CloseButton.MouseEnter:Connect(function()
    TweenService:Create(CloseButton, TweenInfo.new(0.12), {BackgroundColor3 = RED}):Play()
end)

CloseButton.MouseLeave:Connect(function()
    TweenService:Create(CloseButton, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(55, 38, 82)}):Play()
end)

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(1, 0)
CloseCorner.Parent = CloseButton

-- Logo
local Icon = Instance.new("TextLabel")
Icon.Name = "Logo"
Icon.Position = UDim2.new(0, 40, 0.5, -15)
Icon.Size = UDim2.new(0, 34, 0, 30)
Icon.BackgroundColor3 = PURPLE_DARK
Icon.BackgroundTransparency = 0
Icon.BorderSizePixel = 0
Icon.Text = "K5"
Icon.TextColor3 = WHITE
Icon.TextSize = 15
Icon.Font = Enum.Font.GothamBlack
Icon.TextXAlignment = Enum.TextXAlignment.Center
Icon.TextYAlignment = Enum.TextYAlignment.Center
Icon.Parent = Header

local IconCorner = Instance.new("UICorner")
IconCorner.CornerRadius = UDim.new(0, 6)
IconCorner.Parent = Icon

local IconStroke = Instance.new("UIStroke")
IconStroke.Color = PURPLE
IconStroke.Thickness = 1
IconStroke.Parent = Icon

-- Title
local Title = Instance.new("TextLabel")
Title.Position = UDim2.new(0, 84, 0, 6)
Title.Size = UDim2.new(1, -125, 0, 18)
Title.BackgroundTransparency = 1
Title.Text = "K5-HUB  •  IRON SOUL"
Title.TextColor3 = WHITE
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.TextSize = 15
Title.Font = Enum.Font.GothamBold
Title.Parent = Header

local Version = Instance.new("TextLabel")
Version.Name = "Version"
Version.Position = UDim2.new(1, -98, 0, 12)
Version.Size = UDim2.new(0, 58, 0, 22)
Version.BackgroundColor3 = PURPLE_DARK
Version.BackgroundTransparency = 0.15
Version.Text = "K5 • HUB"
Version.TextColor3 = WHITE
Version.TextSize = 9
Version.Font = Enum.Font.GothamBold
Version.TextXAlignment = Enum.TextXAlignment.Center
Version.TextYAlignment = Enum.TextYAlignment.Center
Version.BorderSizePixel = 0
Version.ZIndex = 4
Version.Parent = Header

local VersionCorner = Instance.new("UICorner")
VersionCorner.CornerRadius = UDim.new(1, 0)
VersionCorner.Parent = Version

local Subtitle = Instance.new("TextLabel")
Subtitle.Position = UDim2.new(0, 84, 0, 25)
Subtitle.Size = UDim2.new(1, -125, 0, 14)
Subtitle.BackgroundTransparency = 1
Subtitle.Text = "CODE REDEEM SYSTEM"
Subtitle.TextColor3 = GREY
Subtitle.TextXAlignment = Enum.TextXAlignment.Left
Subtitle.TextSize = 8
Subtitle.Font = Enum.Font.Gotham
Subtitle.Parent = Header

--==================================================
-- CONTENT
--==================================================

local Content = Instance.new("Frame")
Content.Position = UDim2.new(0, 14, 0, 62)
Content.Size = UDim2.new(1, -28, 1, -76)
Content.BackgroundTransparency = 1
Content.Parent = Main

--==================================================
-- MINIMIZED LOGO
--==================================================

local FloatingLogo = Instance.new("TextButton")
FloatingLogo.Name = "FloatingLogo"
FloatingLogo.Size = UDim2.new(0, 58, 0, 58)
FloatingLogo.AnchorPoint = Vector2.new(0.5, 0.5)
FloatingLogo.Position = UDim2.new(0.5, 0, 0.5, 0)
FloatingLogo.BackgroundColor3 = BG
FloatingLogo.Text = "K5"
FloatingLogo.TextColor3 = WHITE
FloatingLogo.TextSize = 24
FloatingLogo.Font = Enum.Font.GothamBlack
FloatingLogo.AutoButtonColor = false
FloatingLogo.BorderSizePixel = 0
FloatingLogo.Visible = false
FloatingLogo.ZIndex = 20
FloatingLogo.Parent = ScreenGui

local FloatingCorner = Instance.new("UICorner")
FloatingCorner.CornerRadius = UDim.new(0, 17)
FloatingCorner.Parent = FloatingLogo

local FloatingStroke = Instance.new("UIStroke")
FloatingStroke.Color = PURPLE
FloatingStroke.Thickness = 2
FloatingStroke.Parent = FloatingLogo

local FloatingScale = Instance.new("UIScale")
FloatingScale.Scale = 1
FloatingScale.Parent = FloatingLogo

local floatingDragging = false
local floatingDragStart = nil
local floatingStartPosition = nil

FloatingLogo.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        floatingDragging = true
        floatingDragStart = input.Position
        floatingStartPosition = FloatingLogo.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                floatingDragging = false
            end
        end)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if floatingDragging and (
        input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
    ) then
        local delta = input.Position - floatingDragStart
        FloatingLogo.Position = UDim2.new(
            floatingStartPosition.X.Scale,
            floatingStartPosition.X.Offset + delta.X,
            floatingStartPosition.Y.Scale,
            floatingStartPosition.Y.Offset + delta.Y
        )
    end
end)

FloatingLogo.MouseEnter:Connect(function()
    TweenService:Create(FloatingScale, TweenInfo.new(0.12), {Scale = 1.08}):Play()
end)

FloatingLogo.MouseLeave:Connect(function()
    TweenService:Create(FloatingScale, TweenInfo.new(0.12), {Scale = 1}):Play()
end)

local MainScale = Instance.new("UIScale")
MainScale.Scale = 1
MainScale.Parent = Main

local OPEN_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function minimizePanel()
    CloseButton.Active = false
    FloatingLogo.Visible = true

    TweenService:Create(MainScale, CLOSE_TWEEN, {Scale = 0.08}):Play()
    local fade = TweenService:Create(Main, CLOSE_TWEEN, {BackgroundTransparency = 1})
    fade:Play()
    FloatingLogo.BackgroundTransparency = 1
    TweenService:Create(FloatingLogo, OPEN_TWEEN, {BackgroundTransparency = 0}):Play()

    fade.Completed:Wait()
    Main.Visible = false
    Main.BackgroundTransparency = 0
    MainScale.Scale = 0.08
    CloseButton.Active = true
end

local function restorePanel()
    FloatingLogo.Visible = false
    Main.Visible = true
    MainScale.Scale = 0.08

    TweenService:Create(MainScale, OPEN_TWEEN, {Scale = 1}):Play()
end

--==================================================
-- AUTO REDEEM BOX
--==================================================

local AutoBox = Instance.new("Frame")
AutoBox.Size = UDim2.new(1, 0, 0, 48)
AutoBox.BackgroundColor3 = PANEL_LIGHT
AutoBox.BorderSizePixel = 0
AutoBox.Parent = Content

local AutoCorner = Instance.new("UICorner")
AutoCorner.CornerRadius = UDim.new(0, 8)
AutoCorner.Parent = AutoBox

local AutoStroke = Instance.new("UIStroke")
AutoStroke.Color = Color3.fromRGB(65, 45, 105)
AutoStroke.Thickness = 1
AutoStroke.Parent = AutoBox

local AutoTitle = Instance.new("TextLabel")
AutoTitle.Position = UDim2.new(0, 14, 0, 8)
AutoTitle.Size = UDim2.new(1, -80, 0, 20)
AutoTitle.BackgroundTransparency = 1
AutoTitle.Text = "Auto Redeem"
AutoTitle.TextColor3 = WHITE
AutoTitle.TextXAlignment = Enum.TextXAlignment.Left
AutoTitle.TextSize = 12
AutoTitle.Font = Enum.Font.GothamMedium
AutoTitle.Parent = AutoBox

local AutoStatus = Instance.new("TextLabel")
AutoStatus.Position = UDim2.new(0, 14, 0, 29)
AutoStatus.Size = UDim2.new(1, -80, 0, 16)
AutoStatus.BackgroundTransparency = 1
AutoStatus.Text = "Automatically redeem all codes"
AutoStatus.TextColor3 = GREY
AutoStatus.TextXAlignment = Enum.TextXAlignment.Left
AutoStatus.TextSize = 9
AutoStatus.Font = Enum.Font.Gotham
AutoStatus.Parent = AutoBox

--==================================================
-- TOGGLE
--==================================================

local Toggle = Instance.new("TextButton")
Toggle.Position = UDim2.new(1, -60, 0.5, -13)
Toggle.Size = UDim2.new(0, 46, 0, 26)
Toggle.BackgroundColor3 = Color3.fromRGB(65, 58, 80)
Toggle.Text = ""
Toggle.AutoButtonColor = false
Toggle.BorderSizePixel = 0
Toggle.Parent = AutoBox

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(1, 0)
ToggleCorner.Parent = Toggle

local Knob = Instance.new("Frame")
Knob.Size = UDim2.new(0, 20, 0, 20)
Knob.Position = UDim2.new(0, 3, 0.5, -10)
Knob.BackgroundColor3 = Color3.fromRGB(220, 215, 230)
Knob.BorderSizePixel = 0
Knob.Parent = Toggle

local KnobCorner = Instance.new("UICorner")
KnobCorner.CornerRadius = UDim.new(1, 0)
KnobCorner.Parent = Knob

--==================================================
-- STATISTICS
--==================================================

local Stats = Instance.new("Frame")
Stats.Position = UDim2.new(0, 0, 0, 56)
Stats.Size = UDim2.new(1, 0, 0, 64)
Stats.BackgroundTransparency = 1
Stats.Parent = Content

-- Total Codes
local TotalBox = Instance.new("Frame")
TotalBox.Size = UDim2.new(0.5, -5, 1, 0)
TotalBox.BackgroundColor3 = PANEL_LIGHT
TotalBox.BorderSizePixel = 0
TotalBox.Parent = Stats

local TotalCorner = Instance.new("UICorner")
TotalCorner.CornerRadius = UDim.new(0, 8)
TotalCorner.Parent = TotalBox

local TotalTitle = Instance.new("TextLabel")
TotalTitle.Position = UDim2.new(0, 12, 0, 10)
TotalTitle.Size = UDim2.new(1, -24, 0, 18)
TotalTitle.BackgroundTransparency = 1
TotalTitle.Text = "JUMLAH KODE"
TotalTitle.TextColor3 = GREY
TotalTitle.TextXAlignment = Enum.TextXAlignment.Left
TotalTitle.TextSize = 10
TotalTitle.Font = Enum.Font.GothamBold
TotalTitle.Parent = TotalBox

local TotalValue = Instance.new("TextLabel")
TotalValue.Position = UDim2.new(0, 12, 0, 28)
TotalValue.Size = UDim2.new(1, -24, 0, 35)
TotalValue.BackgroundTransparency = 1
TotalValue.Text = tostring(totalCodes)
TotalValue.TextColor3 = WHITE
TotalValue.TextXAlignment = Enum.TextXAlignment.Left
TotalValue.TextSize = 18
TotalValue.Font = Enum.Font.GothamBold
TotalValue.Parent = TotalBox

-- Success Codes
local SuccessBox = Instance.new("Frame")
SuccessBox.Position = UDim2.new(0.5, 5, 0, 0)
SuccessBox.Size = UDim2.new(0.5, -5, 1, 0)
SuccessBox.BackgroundColor3 = PANEL_LIGHT
SuccessBox.BorderSizePixel = 0
SuccessBox.Parent = Stats

local SuccessCorner = Instance.new("UICorner")
SuccessCorner.CornerRadius = UDim.new(0, 8)
SuccessCorner.Parent = SuccessBox

local SuccessTitle = Instance.new("TextLabel")
SuccessTitle.Position = UDim2.new(0, 12, 0, 10)
SuccessTitle.Size = UDim2.new(1, -24, 0, 18)
SuccessTitle.BackgroundTransparency = 1
SuccessTitle.Text = "DIPROSES"
SuccessTitle.TextColor3 = GREY
SuccessTitle.TextXAlignment = Enum.TextXAlignment.Left
SuccessTitle.TextSize = 10
SuccessTitle.Font = Enum.Font.GothamBold
SuccessTitle.Parent = SuccessBox

local SuccessValue = Instance.new("TextLabel")
SuccessValue.Position = UDim2.new(0, 12, 0, 28)
SuccessValue.Size = UDim2.new(1, -24, 0, 35)
SuccessValue.BackgroundTransparency = 1
SuccessValue.Text = "0"
SuccessValue.TextColor3 = GREEN
SuccessValue.TextXAlignment = Enum.TextXAlignment.Left
SuccessValue.TextSize = 18
SuccessValue.Font = Enum.Font.GothamBold
SuccessValue.Parent = SuccessBox

--==================================================
-- FOOTER STATUS
--==================================================

local Status = Instance.new("TextLabel")
Status.Position = UDim2.new(0, 4, 0, 126)
Status.Size = UDim2.new(1, -8, 0, 22)
Status.BackgroundTransparency = 1
Status.Text = "●  Auto Redeem OFF"
Status.TextColor3 = RED
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.TextSize = 9
Status.Font = Enum.Font.GothamMedium
Status.Parent = Content

--==================================================
-- UPDATE UI
--==================================================

local function -- Phone responsive scaling
local function updatePhoneScale()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    local scale = math.min(1, viewport.X / 500, viewport.Y / 360)
    MainScale.Scale = math.max(scale, 0.72)
end

updatePhoneScale()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    task.defer(updatePhoneScale)
end)

updateUI()
    TotalValue.Text = tostring(totalCodes)
    SuccessValue.Text = tostring(successCount)

    if AutoRedeem then

        Status.Text = "●  Auto Redeem ON"
        Status.TextColor3 = GREEN

        Toggle.BackgroundColor3 = PURPLE

        Knob.Position = UDim2.new(1, -23, 0.5, -10)
        Knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)

    else

        Status.Text = "●  Auto Redeem OFF"
        Status.TextColor3 = RED

        Toggle.BackgroundColor3 = Color3.fromRGB(65, 58, 80)

        Knob.Position = UDim2.new(0, 3, 0.5, -10)
        Knob.BackgroundColor3 = Color3.fromRGB(220, 215, 230)

    end
end

updateUI()


--==================================================
-- OPEN / CLOSE
--==================================================

CloseButton.MouseButton1Click:Connect(function()
    minimizePanel()
end)

FloatingLogo.MouseButton1Click:Connect(function()
    restorePanel()
end)

--==================================================
-- REDEEM
--==================================================

local function startRedeem()

    if IsRedeeming then
        return
    end

    IsRedeeming = true

    for index, code in ipairs(Codes) do

        if not AutoRedeem then
            break
        end

        if not claimedCodes[code] then

            print(("[K5-HUB] Redeeming [%d/%d]: %s")
                :format(index, totalCodes, code))

            CodeRE:FireServer({
                event = "usecode",
                code = code
            })

            -- Menandai code yang sudah dikirim
            claimedCodes[code] = true

            -- Menghitung code yang sudah dikirim ke server
            successCount += 1

            updateUI()

            if index < totalCodes then
                task.wait(REDEEM_DELAY)
            end

        else

            print("[K5-HUB] Already claimed:", code)

        end
    end

    IsRedeeming = false

    print("[K5-HUB] Redeem process finished")

end

--==================================================
-- TOGGLE BUTTON
--==================================================

Toggle.MouseButton1Click:Connect(function()

    AutoRedeem = not AutoRedeem

    updateUI()

    if AutoRedeem then
        task.spawn(startRedeem)
    else
        print("[K5-HUB] Auto Redeem OFF")
    end

end)
