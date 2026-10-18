--========================================================--
-- IRON SOUL KAITUN - CONTINUOUS V61.9 BOOTSTRAP
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
local VERSION = "61.9"
local BASE =
    "https://raw.githubusercontent.com/"
    .. "MUshihara/ironsoulkaitun/main/"

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

local function loadRaw(path)
    local ok, source =
        pcall(
            game.HttpGet,
            game,
            cacheBust(path)
        )

    if not ok or type(source) ~= "string" then
        warn(
            "[IronSoul V61.9] HTTP load failed: "
                .. tostring(path)
                .. " | "
                .. tostring(source)
        )
        return false
    end

    local normalized, normalizeErr =
        normalizeSource(source)

    if not normalized then
        warn(
            "[IronSoul V61.9] Source normalization failed: "
                .. tostring(path)
                .. " | "
                .. tostring(normalizeErr)
        )
        return false
    end

    local fn, err = loadstring(normalized)

    if not fn then
        warn(
            "[IronSoul V61.9] Compile failed: "
                .. tostring(path)
                .. " | "
                .. tostring(err)
        )
        warn(
            "[IronSoul V61.9] SOURCE_HEAD="
                .. sourceHead(normalized)
        )
        return false
    end

    local runOk, result = pcall(fn)

    if not runOk then
        warn(
            "[IronSoul V61.9] Runtime failed: "
                .. tostring(path)
                .. " | "
                .. tostring(result)
        )
        return false
    end

    return true, result
end

local function queueBootstrap(reason)
    local queue =
        queue_on_teleport
        or (syn and syn.queue_on_teleport)

    if type(queue) ~= "function" then
        warn(
            "[IronSoul V61.9] queue_on_teleport unavailable: "
                .. tostring(reason)
        )
        return false
    end

    local payload = string.format([[
task.wait(1.35)
getgenv().IronSoulConfig = getgenv().IronSoulConfig or {
    FPS_CAP = %s,
    FARM = %q,
    TICKETS = %q,
    HEADLESS = %s,
}
loadstring(game:HttpGet(
    %q .. "?isv=61.9&t=" .. tostring(os.time())
))()
]],
        tostring(tonumber(Config.FPS_CAP) or 8),
        tostring(Config.FARM or "NEWBIE"),
        tostring(Config.TICKETS or "SMART"),
        tostring(Config.HEADLESS ~= false),
        BASE .. "bootstrap_v61_9.lua"
    )

    local ok, err = pcall(queue, payload)

    if not ok then
        warn(
            "[IronSoul V61.9] queue failed: "
                .. tostring(reason)
                .. " | "
                .. tostring(err)
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

if game.PlaceId == TUTORIAL_PLACE_ID then
    route = "systems/tutorial.lua"

elseif game.PlaceId == LOBBY_PLACE_ID
    or workspace:GetAttribute("WorldName") == "Lobby"
then
    route = "systems/lobby.lua"

elseif looksLikeDungeon() then
    route = "systems/combat.lua"
else
    warn(
        "[IronSoul V61.9] Unknown place; no action. PlaceId="
            .. tostring(game.PlaceId)
            .. " WorldName="
            .. tostring(workspace:GetAttribute("WorldName"))
    )
    return
end

getgenv().IronSoulRuntime = {
    Version = "V61.9",
    Route = route,
    PlaceId = game.PlaceId,
    StartedAt = os.clock(),
}

print(
    "[IronSoul V61.9]",
    route == "systems/lobby.lua"
        and "Lobby"
        or (
            route == "systems/combat.lua"
            and "Dungeon"
            or "Tutorial"
        )
)

loadRaw(route)
