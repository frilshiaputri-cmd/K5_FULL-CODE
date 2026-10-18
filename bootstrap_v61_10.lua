--========================================================--
-- IRON SOUL KAITUN - CONTINUOUS V61.10 MOBILE BOOTSTRAP
--========================================================--

getgenv().IronSoulConfig =
    getgenv().IronSoulConfig
    or {
        FPS_CAP = 8,
        FARM = "NEWBIE",
        TICKETS = "SMART",
        HEADLESS = true,
    }

local Config = getgenv().IronSoulConfig
local VERSION = "61.10"
local BASE =
    "https://raw.githubusercontent.com/"
    .. "MUshihara/ironsoulkaitun/main/"

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

local TUTORIAL_PLACE_ID = 76701861705540
local LOBBY_PLACE_ID = 117533937949084

-- Ignore near-simultaneous queued copies in one server.
do
    local key =
        tostring(game.PlaceId)
        .. "|"
        .. tostring(game.JobId)

    local old = getgenv().IronSoulBootstrapGuard

    if type(old) == "table"
        and old.Key == key
        and os.clock() - tonumber(old.At or 0) < 5
    then
        return
    end

    getgenv().IronSoulBootstrapGuard = {
        Key = key,
        At = os.clock(),
    }
end

if type(setfpscap) == "function"
    and tonumber(Config.FPS_CAP)
then
    pcall(setfpscap, tonumber(Config.FPS_CAP))
end

local function executorName()
    if type(identifyexecutor) == "function" then
        local ok, a, b = pcall(identifyexecutor)
        if ok then
            return tostring(a or b or "Unknown")
        end
    end

    if type(getexecutorname) == "function" then
        local ok, value = pcall(getexecutorname)
        if ok then
            return tostring(value or "Unknown")
        end
    end

    return "Unknown"
end

local function findTeleportQueue()
    local env = getgenv()

    local candidates = {
        {"queue_on_teleport", env.queue_on_teleport},
        {"queueonteleport", env.queueonteleport},
        {"queue_on_tp", env.queue_on_tp},
        {"queueontp", env.queueontp},
    }

    if type(syn) == "table" then
        table.insert(
            candidates,
            {"syn.queue_on_teleport", syn.queue_on_teleport}
        )
    end

    if type(fluxus) == "table" then
        table.insert(
            candidates,
            {"fluxus.queue_on_teleport", fluxus.queue_on_teleport}
        )
    end

    for _, row in ipairs(candidates) do
        if type(row[2]) == "function" then
            return row[2], row[1]
        end
    end

    return nil, "none"
end

local queueFunction, queueName =
    findTeleportQueue()

local Caps = {
    Version = "V61.10",
    Executor = executorName(),
    Touch = UserInputService.TouchEnabled == true,
    Queue = type(queueFunction) == "function",
    QueueName = queueName,
    WriteFile = type(writefile) == "function",
    ReadFile = type(readfile) == "function",
    MakeFolder = type(makefolder) == "function",
    FireSignal = type(firesignal) == "function",
    GetConnections = type(getconnections) == "function",
    FirePrompt = type(fireproximityprompt) == "function",
    FireTouch = type(firetouchinterest) == "function",
}

getgenv().IronSoulExecutorCaps = Caps
getgenv().IronSoulTeleportQueueAvailable = Caps.Queue

local statusGui = nil
local statusLabel = nil

local function ensureStatusGui()
    if statusLabel and statusLabel.Parent then
        return statusLabel
    end

    if not Caps.Touch
        and Config.MOBILE_STATUS ~= true
    then
        return nil
    end

    local pg =
        LocalPlayer:FindFirstChildOfClass("PlayerGui")
        or LocalPlayer:WaitForChild("PlayerGui", 5)

    if not pg then
        return nil
    end

    local old = pg:FindFirstChild("IronSoulMobileStatus")
    if old then
        pcall(function()
            old:Destroy()
        end)
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "IronSoulMobileStatus"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = false
    gui.DisplayOrder = 999999

    local label = Instance.new("TextLabel")
    label.Name = "Status"
    label.Active = false
    label.Selectable = false
    label.Size = UDim2.new(0, 340, 0, 46)
    label.Position = UDim2.new(0, 8, 0, 8)
    label.BackgroundTransparency = 0.28
    label.BorderSizePixel = 0
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.TextWrapped = true
    label.TextSize = 12
    label.Font = Enum.Font.Code
    label.Text = "IronSoul V61.10 | booting"
    label.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = label

    gui.Parent = pg

    statusGui = gui
    statusLabel = label
    return label
end

local function status(text)
    text = tostring(text or "")

    local line =
        "IronSoul V61.10 | " .. text

    local label = ensureStatusGui()
    if label then
        pcall(function()
            label.Text = line
        end)
    end

    if type(writefile) == "function" then
        pcall(
            writefile,
            "IronSoul_MobileStatus_V61_10.txt",
            table.concat({
                "Version=V61.10",
                "Executor=" .. tostring(Caps.Executor),
                "Touch=" .. tostring(Caps.Touch),
                "Queue=" .. tostring(Caps.Queue),
                "QueueName=" .. tostring(Caps.QueueName),
                "WriteFile=" .. tostring(Caps.WriteFile),
                "ReadFile=" .. tostring(Caps.ReadFile),
                "FireSignal=" .. tostring(Caps.FireSignal),
                "GetConnections=" .. tostring(Caps.GetConnections),
                "FirePrompt=" .. tostring(Caps.FirePrompt),
                "FireTouch=" .. tostring(Caps.FireTouch),
                "PlaceId=" .. tostring(game.PlaceId),
                "Status=" .. text,
            }, "\n")
        )
    end
end

getgenv().IronSoulStatus = status

status(
    "Boot | "
        .. tostring(Caps.Executor)
        .. " | queue="
        .. tostring(Caps.Queue)
)

local fetchCounter = 0

local function cacheBust(path)
    fetchCounter += 1

    return BASE
        .. path
        .. "?isv=" .. VERSION
        .. "&n=" .. tostring(fetchCounter)
        .. "&t=" .. tostring(os.time())
end

local function normalizeSource(source)
    if type(source) ~= "string" then
        return nil, "source is not a string"
    end

    if string.sub(source, 1, 3) == "\239\187\191" then
        source = string.sub(source, 4)
    end

    local b1 = string.byte(source, 1)
    local b2 = string.byte(source, 2)

    if (b1 == 255 and b2 == 254)
        or (b1 == 254 and b2 == 255)
    then
        return nil, "UTF-16 source received"
    end

    local prefixes = {
        "\226\128\139",
        "\226\128\140",
        "\226\128\141",
        "\226\129\160",
    }

    local changed = true
    while changed do
        changed = false

        for _, prefix in ipairs(prefixes) do
            if string.sub(source, 1, #prefix) == prefix then
                source = string.sub(source, #prefix + 1)
                changed = true
            end
        end
    end

    return source
end

local function sourceHead(source)
    local head = string.sub(tostring(source or ""), 1, 140)
    head = string.gsub(head, "\r", "\\r")
    head = string.gsub(head, "\n", "\\n")
    return head
end

local function shortError(err)
    local text = tostring(err or "unknown")
    if #text > 180 then
        text = string.sub(text, 1, 180) .. "..."
    end
    return text
end

local function loadRaw(path)
    status("Loading | " .. tostring(path))

    local ok, source =
        pcall(
            game.HttpGet,
            game,
            cacheBust(path)
        )

    if not ok or type(source) ~= "string" then
        local err =
            "HTTP load failed | "
            .. tostring(path)
            .. " | "
            .. tostring(source)

        warn("[IronSoul V61.10] " .. err)
        status("ERROR | " .. shortError(err))
        return false
    end

    local normalized, normalizeErr =
        normalizeSource(source)

    if not normalized then
        local err =
            "Source normalization failed | "
            .. tostring(path)
            .. " | "
            .. tostring(normalizeErr)

        warn("[IronSoul V61.10] " .. err)
        status("ERROR | " .. shortError(err))
        return false
    end

    local fn, err = loadstring(normalized)

    if not fn then
        local message =
            "Compile failed | "
            .. tostring(path)
            .. " | "
            .. tostring(err)

        warn("[IronSoul V61.10] " .. message)
        warn(
            "[IronSoul V61.10] SOURCE_HEAD="
                .. sourceHead(normalized)
        )
        status("ERROR | " .. shortError(message))
        return false
    end

    local runOk, result = pcall(fn)

    if not runOk then
        local message =
            "Runtime failed | "
            .. tostring(path)
            .. " | "
            .. tostring(result)

        warn("[IronSoul V61.10] " .. message)
        status("ERROR | " .. shortError(message))
        return false
    end

    return true, result
end

local function queueBootstrap(reason)
    local queue, detectedName =
        findTeleportQueue()

    getgenv().IronSoulTeleportQueueAvailable =
        type(queue) == "function"

    if type(queue) ~= "function" then
        status(
            "Queue unavailable | "
                .. tostring(reason)
                .. " | re-execute after teleport"
        )

        warn(
            "[IronSoul V61.10] teleport queue unavailable: "
                .. tostring(reason)
        )
        return false
    end

    Caps.Queue = true
    Caps.QueueName = detectedName

    local payload = string.format([[
task.wait(1.35)
getgenv().IronSoulConfig = getgenv().IronSoulConfig or {
    FPS_CAP = %s,
    FARM = %q,
    TICKETS = %q,
    HEADLESS = %s,
}
loadstring(game:HttpGet(
    %q .. "?isv=61.10&t=" .. tostring(os.time())
))()
]],
        tostring(tonumber(Config.FPS_CAP) or 8),
        tostring(Config.FARM or "NEWBIE"),
        tostring(Config.TICKETS or "SMART"),
        tostring(Config.HEADLESS ~= false),
        BASE .. "bootstrap_v61_10.lua"
    )

    local ok, err = pcall(queue, payload)

    if not ok then
        status(
            "Queue failed | "
                .. tostring(reason)
                .. " | "
                .. shortError(err)
        )
        warn(
            "[IronSoul V61.10] queue failed: "
                .. tostring(reason)
                .. " | "
                .. tostring(err)
        )
        return false
    end

    status(
        "Queued next teleport | "
            .. tostring(detectedName)
    )
    return true
end

getgenv().IronSoulBaseURL = BASE
getgenv().IronSoulQueueBootstrap = queueBootstrap
getgenv().IronSoulLoadRaw = loadRaw

local function looksLikeDungeon()
    local rs = game:GetService("ReplicatedStorage")

    local hasRound =
        rs:FindFirstChild("GameRoundCfg") ~= nil

    local hasCombatWorld =
        workspace:FindFirstChild("RoundDoor")
        or workspace:FindFirstChild("EnemyNpc")
        or workspace:FindFirstChild("WorldEnemys")

    return hasRound and hasCombatWorld
end

local route

if game.PlaceId == TUTORIAL_PLACE_ID then
    route = "systems/tutorial.lua"

elseif game.PlaceId == LOBBY_PLACE_ID
    or workspace:GetAttribute("WorldName") == "Lobby"
then
    route = "systems/lobby.lua"

elseif looksLikeDungeon() then
    route = "systems/combat.lua"
else
    local message =
        "Unknown place | "
        .. tostring(game.PlaceId)
        .. " | WorldName="
        .. tostring(workspace:GetAttribute("WorldName"))

    warn("[IronSoul V61.10] " .. message)
    status(message)
    return
end

getgenv().IronSoulRuntime = {
    Version = "V61.10",
    Route = route,
    PlaceId = game.PlaceId,
    StartedAt = os.clock(),
}

local routeName =
    route == "systems/lobby.lua"
        and "Lobby"
        or (
            route == "systems/combat.lua"
            and "Dungeon"
            or "Tutorial"
        )

print("[IronSoul V61.10]", routeName)
status(routeName .. " | starting")

loadRaw(route)
