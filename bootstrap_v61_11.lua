--========================================================--
-- IRON SOUL KAITUN - CONTINUOUS V61.11 MOBILE/STABLE BOOT
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
local VERSION = "61.11"
local BASE =
    "https://raw.githubusercontent.com/"
    .. "MUshihara/ironsoulkaitun/main/"

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

local TUTORIAL_PLACE_ID = 76701861705540
local LOBBY_PLACE_ID = 117533937949084

-- Prevent duplicate queued copies in the same server/job.
do
    local key = tostring(game.PlaceId) .. "|" .. tostring(game.JobId)
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

-- IMPORTANT: discover the REAL executor queue before installing any
-- compatibility alias. This prevents our manual fallback from masquerading
-- as a native persistent queue capability.
local function findRealTeleportQueue()
    local env = getgenv()
    local candidates = {
        {"queue_on_teleport", env.queue_on_teleport},
        {"queueonteleport", env.queueonteleport},
        {"queue_on_tp", env.queue_on_tp},
        {"queueontp", env.queueontp},
    }

    if type(syn) == "table" then
        table.insert(candidates, {
            "syn.queue_on_teleport",
            syn.queue_on_teleport,
        })
    end

    if type(fluxus) == "table" then
        table.insert(candidates, {
            "fluxus.queue_on_teleport",
            fluxus.queue_on_teleport,
        })
    end

    for _, row in ipairs(candidates) do
        if type(row[2]) == "function" then
            return row[2], row[1]
        end
    end

    return nil, "none"
end

local RealQueue, RealQueueName = findRealTeleportQueue()

local Caps = {
    Version = "V61.11",
    Executor = executorName(),
    Touch = UserInputService.TouchEnabled == true,
    Queue = type(RealQueue) == "function",
    QueueName = RealQueueName,
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
getgenv().IronSoulManualQueueMode = not Caps.Queue

local statusLabel = nil
local stickyError = false

local function ensureStatusGui()
    if statusLabel and statusLabel.Parent then
        return statusLabel
    end

    if not Caps.Touch and Config.MOBILE_STATUS ~= true then
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
        pcall(function() old:Destroy() end)
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
    label.Size = UDim2.new(0, 350, 0, 50)
    label.Position = UDim2.new(0, 8, 0, 8)
    label.BackgroundTransparency = 0.25
    label.BorderSizePixel = 0
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.TextWrapped = true
    label.TextSize = 12
    label.Font = Enum.Font.Code
    label.Text = "IronSoul V61.11 | booting"
    label.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = label

    gui.Parent = pg
    statusLabel = label
    return label
end

local function status(text)
    text = tostring(text or "")

    if string.sub(text, 1, 5) == "ERROR"
        or string.sub(text, 1, 5) == "STUCK"
    then
        stickyError = true
    elseif stickyError
        and string.sub(text, 1, 5) ~= "RESET"
    then
        return
    end

    local line = "IronSoul V61.11 | " .. text
    local label = ensureStatusGui()

    if label then
        pcall(function() label.Text = line end)
    end

    if type(writefile) == "function" then
        pcall(
            writefile,
            "IronSoul_MobileStatus_V61_11.txt",
            table.concat({
                "Version=V61.11",
                "Executor=" .. tostring(Caps.Executor),
                "Touch=" .. tostring(Caps.Touch),
                "NativeQueue=" .. tostring(Caps.Queue),
                "QueueName=" .. tostring(Caps.QueueName),
                "ManualQueueMode=" .. tostring(not Caps.Queue),
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
        .. " | nativeQueue="
        .. tostring(Caps.Queue)
)

--========================================================--
-- TELEPORT QUEUE COMPATIBILITY
--
-- Proven lobby V60/V61 expects a global queue_on_teleport symbol. Mobile
-- executors often expose a different alias. Normalize that here BEFORE
-- lobby.lua loads instead of patching the lobby's early environment block.
--
-- If there is no native queue at all, the compatibility function stores the
-- payload so lobby progression can still continue. The user then re-executes
-- the normal loader after teleport. We keep NativeQueue=false in diagnostics.
--========================================================--

local function compatibilityQueue(payload)
    payload = tostring(payload or "")

    if type(RealQueue) == "function" then
        local ok, err = pcall(RealQueue, payload)

        if ok then
            return true
        end

        status("ERROR | native teleport queue failed | " .. tostring(err))
        return false
    end

    getgenv().IronSoulManualQueuedPayload = payload

    if type(writefile) == "function" then
        pcall(
            writefile,
            "IronSoul_Reexecute_AfterTeleport_V61_11.lua",
            payload
        )
    end

    -- Return success to the historical lobby so it does not abort. This does
    -- NOT claim native persistence; IronSoulTeleportQueueAvailable remains
    -- false and the HUD/status file explicitly says ManualQueueMode=true.
    status(
        "Manual persistence | re-execute loader after teleport"
    )

    return true
end

-- Normalize the name expected by the proven lobby script.
pcall(function()
    rawset(
        getgenv(),
        "queue_on_teleport",
        compatibilityQueue
    )
end)

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

local function shortError(err)
    local text = tostring(err or "unknown")
    if #text > 190 then
        text = string.sub(text, 1, 190) .. "..."
    end
    return text
end

local function loadRaw(path)
    status("Loading | " .. tostring(path))

    local ok, source =
        pcall(game.HttpGet, game, cacheBust(path))

    if not ok or type(source) ~= "string" then
        local message =
            "HTTP load failed | "
            .. tostring(path)
            .. " | "
            .. tostring(source)

        warn("[IronSoul V61.11] " .. message)
        status("ERROR | " .. shortError(message))
        return false
    end

    local normalized, normalizeErr = normalizeSource(source)

    if not normalized then
        local message =
            "Source normalization failed | "
            .. tostring(path)
            .. " | "
            .. tostring(normalizeErr)

        warn("[IronSoul V61.11] " .. message)
        status("ERROR | " .. shortError(message))
        return false
    end

    local fn, err = loadstring(normalized)

    if not fn then
        local message =
            "Compile failed | "
            .. tostring(path)
            .. " | "
            .. tostring(err)

        warn("[IronSoul V61.11] " .. message)
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

        warn("[IronSoul V61.11] " .. message)
        status("ERROR | " .. shortError(message))
        return false
    end

    return true, result
end

local function queueBootstrap(reason)
    local payload = string.format([[
task.wait(1.35)
getgenv().IronSoulConfig = getgenv().IronSoulConfig or {
    FPS_CAP = %s,
    FARM = %q,
    TICKETS = %q,
    HEADLESS = %s,
}
loadstring(game:HttpGet(
    %q .. "?isv=61.11&t=" .. tostring(os.time())
))()
]],
        tostring(tonumber(Config.FPS_CAP) or 8),
        tostring(Config.FARM or "NEWBIE"),
        tostring(Config.TICKETS or "SMART"),
        tostring(Config.HEADLESS ~= false),
        BASE .. "bootstrap_v61_11.lua"
    )

    local ok = compatibilityQueue(payload)

    if ok and Caps.Queue then
        status(
            "Queued next teleport | "
                .. tostring(Caps.QueueName)
        )
    elseif ok then
        status(
            "Manual persistence | "
                .. tostring(reason)
                .. " | re-execute after teleport"
        )
    end

    return ok
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
local routeName

if game.PlaceId == TUTORIAL_PLACE_ID then
    -- Explicit versioned tutorial: V61.10 created this mobile-safe path, but
    -- the previous bootstrap accidentally kept routing to the old file.
    route = "systems/tutorial_v61_10.lua"
    routeName = "Tutorial"

elseif game.PlaceId == LOBBY_PLACE_ID
    or workspace:GetAttribute("WorldName") == "Lobby"
then
    route = "systems/lobby.lua"
    routeName = "Lobby"

elseif looksLikeDungeon() then
    route = "systems/combat.lua"
    routeName = "Dungeon"
else
    local message =
        "Unknown place | "
        .. tostring(game.PlaceId)
        .. " | WorldName="
        .. tostring(workspace:GetAttribute("WorldName"))

    warn("[IronSoul V61.11] " .. message)
    status(message)
    return
end

getgenv().IronSoulRuntime = {
    Version = "V61.11",
    Route = route,
    PlaceId = game.PlaceId,
    StartedAt = os.clock(),
    NativeTeleportQueue = Caps.Queue,
}

print("[IronSoul V61.11]", routeName)
status(routeName .. " | starting")

loadRaw(route)
