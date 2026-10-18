--========================================================--
-- IRON SOUL V61.11 - MOBILE-SAFE TUTORIAL / STARTER
--
-- Fresh account:
--   Sword -> real Skip Tutorial button signal -> verify teleport -> Lobby
-- Uses real executor queue capability status from bootstrap_v61_11.
--========================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
local LOBBY_PLACE_ID = 117533937949084

local function status(text)
    local fn = getgenv().IronSoulStatus
    if type(fn) == "function" then
        pcall(fn, "Tutorial | " .. tostring(text))
    end
end

local function findByName(root, wanted, className)
    for _, obj in ipairs(root:GetDescendants()) do
        if obj.Name == wanted
            and (
                not className
                or obj:IsA(className)
            )
        then
            return obj
        end
    end
end

local function req(name)
    local obj = findByName(
        ReplicatedStorage,
        name,
        "ModuleScript"
    )

    if not obj then
        return nil
    end

    local ok, value = pcall(require, obj)
    return ok and value or nil
end

local teleportStarted = false
local teleportConn = LocalPlayer.OnTeleport:Connect(
    function(state, placeId)
        if string.find(
            tostring(state),
            "Failed",
            1,
            true
        ) == nil
        then
            teleportStarted = true
            status(
                "teleport started | "
                    .. tostring(state)
                    .. " | place="
                    .. tostring(placeId)
            )
        end
    end
)

local function waitTeleport(timeout)
    local deadline = os.clock() + (timeout or 4)

    while os.clock() < deadline do
        if teleportStarted
            or game.PlaceId == LOBBY_PLACE_ID
        then
            return true
        end

        task.wait(0.08)
    end

    return false
end

-- Queue the next bootstrap when the executor genuinely supports it. The
-- compatibility helper may also save a manual payload, but we report that
-- truthfully instead of pretending it is native persistence.
local queueBootstrap = getgenv().IronSoulQueueBootstrap

if type(queueBootstrap) == "function" then
    pcall(queueBootstrap, "tutorial -> lobby")
end

if getgenv().IronSoulTeleportQueueAvailable == true then
    status("native teleport persistence ready")
else
    status("no native teleport queue | re-execute loader once in Lobby")
end

--========================================================--
-- STARTER SWORD
--========================================================--

local UnForgeUtil = req("UnForgeUtil")

if UnForgeUtil
    and LocalPlayer:GetAttribute(
        "Equipment.GetDefaultWeapon"
    ) ~= true
    and type(UnForgeUtil.SelectDefaultWeapon) == "function"
then
    status("selecting starter Sword")

    local ok, err = pcall(function()
        UnForgeUtil:SelectDefaultWeapon(
            LocalPlayer,
            1
        )
    end)

    if not ok then
        status("Sword select failed | " .. tostring(err))
    end
elseif UnForgeUtil then
    status("starter weapon already selected")
else
    status("weapon helper unavailable | still attempting Skip Tutorial")
end

-- Give starter selection a moment to replicate server-side before skip.
task.wait(0.65)

if waitTeleport(0.20) then
    return
end

--========================================================--
-- SKIP TUTORIAL
--========================================================--

local function effectivelyVisible(obj)
    if not obj then
        return false
    end

    local current = obj

    while current
        and current ~= LocalPlayer
    do
        if current:IsA("GuiObject")
            and current.Visible == false
        then
            return false
        elseif current:IsA("ScreenGui")
            and current.Enabled == false
        then
            return false
        end

        if current == LocalPlayer.PlayerGui then
            break
        end

        current = current.Parent
    end

    return true
end

local function looksLikeSkip(button)
    if not button or not button:IsA("GuiButton") then
        return false
    end

    local texts = {
        tostring(button.Name or ""),
    }

    if button:IsA("TextButton") then
        table.insert(texts, tostring(button.Text or ""))
    end

    for _, child in ipairs(button:GetDescendants()) do
        if child:IsA("TextLabel")
            or child:IsA("TextButton")
        then
            table.insert(
                texts,
                tostring(child.Text or "")
            )
        end
    end

    for _, text in ipairs(texts) do
        local low = string.lower(text)

        if low == "skip"
            or string.find(
                low,
                "skip tutorial",
                1,
                true
            )
            or string.find(
                low,
                "skiptutorial",
                1,
                true
            )
        then
            return true
        end
    end

    return false
end

local function findSkipButton(timeout)
    local deadline = os.clock() + (timeout or 4.5)

    while os.clock() < deadline do
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")

        if pg then
            local hidden = nil

            for _, obj in ipairs(pg:GetDescendants()) do
                if looksLikeSkip(obj) then
                    if effectivelyVisible(obj) then
                        return obj
                    end
                    hidden = hidden or obj
                end
            end

            if hidden then
                return hidden
            end
        end

        task.wait(0.12)
    end
end

local function fireSignal(signal)
    if not signal then
        return false
    end

    if type(firesignal) == "function"
        and pcall(firesignal, signal)
    then
        return true
    end

    if type(getconnections) == "function" then
        local ok, connections = pcall(getconnections, signal)

        if ok and type(connections) == "table" then
            for _, conn in ipairs(connections) do
                if type(conn.Function) == "function"
                    and pcall(conn.Function)
                then
                    return true
                end

                if type(conn.Fire) == "function"
                    and pcall(conn.Fire, conn)
                then
                    return true
                end
            end
        end
    end

    return false
end

local function virtualClick(button)
    if not button then
        return false
    end

    local pos = button.AbsolutePosition
    local size = button.AbsoluteSize
    local x = math.floor(pos.X + size.X * 0.5)
    local y = math.floor(pos.Y + size.Y * 0.5)

    return pcall(function()
        VirtualInputManager:SendMouseMoveEvent(x, y, game)
        task.wait(0.04)
        VirtualInputManager:SendMouseButtonEvent(
            x, y, 0, true, game, 0
        )
        task.wait(0.05)
        VirtualInputManager:SendMouseButtonEvent(
            x, y, 0, false, game, 0
        )
    end)
end

local function activateSkip(button)
    if not button then
        return false, "NO_BUTTON"
    end

    status(
        "Skip Tutorial found | "
            .. tostring(button:GetFullName())
    )

    if fireSignal(button.Activated) then
        return true, "ACTIVATED"
    end

    if fireSignal(button.MouseButton1Click) then
        return true, "MOUSE_CLICK_SIGNAL"
    end

    if fireSignal(button.MouseButton1Down) then
        return true, "MOUSE_DOWN_SIGNAL"
    end

    if virtualClick(button) then
        return true, "VIRTUAL_CLICK"
    end

    return false, "NO_SUPPORTED_TRIGGER"
end

local skip = findSkipButton(4.5)

if skip then
    local sent, route = activateSkip(skip)

    status(
        "Skip sent="
            .. tostring(sent)
            .. " via="
            .. tostring(route)
    )

    if sent and waitTeleport(5.0) then
        return
    end
else
    status("Skip button not found | direct Lobby fallback")
end

--========================================================--
-- CLIENT LOBBY FALLBACK
--========================================================--

local errors = {}

for attempt = 1, 2 do
    status(
        "direct Lobby teleport | attempt "
            .. tostring(attempt)
    )

    local ok, err = pcall(function()
        TeleportService:Teleport(
            LOBBY_PLACE_ID,
            LocalPlayer
        )
    end)

    if not ok then
        table.insert(errors, tostring(err))
    end

    if ok and waitTeleport(4.0) then
        return
    end

    task.wait(0.45)
end

status(
    "STUCK | Lobby teleport did not start | "
        .. table.concat(errors, " | ")
)

warn(
    "[IronSoul V61.11] Tutorial could not start Lobby teleport: "
        .. table.concat(errors, " | ")
)

pcall(function()
    teleportConn:Disconnect()
end)
