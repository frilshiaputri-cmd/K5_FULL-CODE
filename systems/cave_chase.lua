--========================================================--
-- IRON SOUL - CAVE ONE-ROOM CHASE V61.19
--
-- Cave1/Cave2/Cave3 are one-room resource activities.
-- Critical startup rule:
--   NEVER move the player toward enemies before the proven combat controller
--   has initialized. V61.18 could tween into the pack while combat.lua was
--   still fetching/patching/compiling, causing deaths before headless attacks.
--
-- V61.19:
--   * capture the pre-combat telemetry file as a baseline;
--   * wait for THIS run to publish "START | controller initialized";
--   * wait for a living/stable character after any startup death;
--   * only then tween toward distant Cave enemies;
--   * preserve a real append-style timeline for future diagnostics.
--========================================================--

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Chase = {}

Chase.VERSION = "V61.19"
Chase.ENGAGE_DISTANCE = 45
Chase.STANDOFF = 7.5
Chase.HEIGHT = 8.5
Chase.SPEED = 300
Chase.MAX_MOVE_TIME = 0.78
Chase.IDLE_STEP = 0.12
Chase.NO_ENEMY_WAKE_DELAY = 0.90

Chase.READY_TIMEOUT = 45
Chase.POST_READY_SETTLE = 0.35
Chase.RESPAWN_STABLE = 0.35
Chase.TELEMETRY_FILE = "IronSoul_Telemetry_V61_6.txt"
Chase.LOG_FILE = "IronSoul_CaveChase_V61_19.txt"

local CAVE_PLACES = {
    [91584731222940] = true,
    [119524374829397] = true,
    [132445869992129] = true,
}

local Running = false
local Active = false
local StartedAt = 0
local LastEnemySeenAt = os.clock()
local LastMoveAt = -math.huge
local TelemetryBaseline = ""
local LastWaitLogAt = -math.huge

local function readText(path)
    if type(readfile) ~= "function" then
        return nil
    end

    if type(isfile) == "function" and not isfile(path) then
        return nil
    end

    local ok, text = pcall(readfile, path)
    if ok and type(text) == "string" then
        return text
    end

    return nil
end

local function appendLog(text)
    if type(writefile) ~= "function" then
        return
    end

    local line = string.format(
        "[%.2f] %s\n",
        os.clock(),
        tostring(text or "")
    )

    if type(appendfile) == "function" then
        pcall(appendfile, Chase.LOG_FILE, line)
        return
    end

    local old = readText(Chase.LOG_FILE) or ""
    pcall(writefile, Chase.LOG_FILE, old .. line)
end

local function status(text)
    text = tostring(text or "")

    local fn = getgenv().IronSoulStatus
    if type(fn) == "function" then
        pcall(fn, "Cave chase | " .. text)
    end

    print("[IronSoul Cave Chase V61.19]", text)
    appendLog(text)
end

local function root()
    local character = LocalPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function livingCharacter()
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local r = character and character:FindFirstChild("HumanoidRootPart")

    if not character or not humanoid or not r or humanoid.Health <= 0 then
        return nil
    end

    return character, humanoid, r
end

local function enemyRoot(model)
    if not model then return nil end
    return model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart")
end

local function nearestEnemy(r)
    local folder = Workspace:FindFirstChild("EnemyNpc")
    if not folder or not r then return nil end

    local bestModel
    local bestRoot
    local bestDist = math.huge

    for _, obj in ipairs(folder:GetChildren()) do
        if obj:IsA("Model") then
            local hum = obj:FindFirstChildOfClass("Humanoid")
            local er = hum and hum.Health > 0 and enemyRoot(obj) or nil

            if er then
                local dist = (er.Position - r.Position).Magnitude
                if dist < bestDist then
                    bestDist = dist
                    bestModel = obj
                    bestRoot = er
                end
            end
        end
    end

    return bestModel, bestRoot, bestDist
end

local function round1Wake()
    local worldEnemies = Workspace:FindFirstChild("WorldEnemys")
    local wakeFolder = worldEnemies and worldEnemies:FindFirstChild("RoundWakeTouch")
    return wakeFolder and wakeFolder:FindFirstChild("Round1")
end

local function boxDistance(part, point)
    if not part or not part:IsA("BasePart") then return math.huge end
    local localPoint = part.CFrame:PointToObjectSpace(point)
    local half = part.Size * 0.5
    local dx = math.max(math.abs(localPoint.X) - half.X, 0)
    local dy = math.max(math.abs(localPoint.Y) - half.Y, 0)
    local dz = math.max(math.abs(localPoint.Z) - half.Z, 0)
    return Vector3.new(dx, dy, dz).Magnitude
end

local function motion()
    local existing = getgenv().IronSoulWorld1Motion
    if type(existing) == "table" and type(existing.MoveToPosition) == "function" then
        return existing
    end

    local loadRaw = getgenv().IronSoulLoadRaw
    if type(loadRaw) == "function" then
        local ok, value = loadRaw("systems/world1_motion.lua")
        if ok and type(value) == "table" and type(value.MoveToPosition) == "function" then
            return value
        end
    end
end

local function nearEnemyPosition(r, er)
    local away = Vector3.new(r.Position.X - er.Position.X, 0, r.Position.Z - er.Position.Z)
    if away.Magnitude < 0.1 then
        away = Vector3.new(1, 0, 0)
    end
    away = away.Unit

    return er.Position
        + away * Chase.STANDOFF
        + Vector3.new(0, Chase.HEIGHT, 0)
end

local function moveNearEnemy(r, model, er, dist)
    if not Active then
        return false
    end

    local _, humanoid, liveRoot = livingCharacter()
    if not humanoid or liveRoot ~= r then
        return false
    end

    local m = motion()
    if not m then return false end

    local target = nearEnemyPosition(r, er)
    local look = er.Position + Vector3.new(0, 2.5, 0)

    status(
        "ENEMY_TWEEN_START name=" .. tostring(model.Name)
            .. " dist=" .. string.format("%.1f", dist)
            .. " hp=" .. string.format("%.0f", humanoid.Health)
    )

    local ok, mode, moved, elapsed = m.MoveToPosition(
        r,
        target,
        look,
        {
            Speed = Chase.SPEED,
            MaxTime = Chase.MAX_MOVE_TIME,
            MinTime = 0.08,
        }
    )

    LastMoveAt = os.clock()

    status(
        "ENEMY_TWEEN_RESULT ok=" .. tostring(ok)
            .. " mode=" .. tostring(mode)
            .. " moved=" .. tostring(moved)
            .. " elapsed=" .. tostring(elapsed)
    )

    return ok
end

local function moveIntoWake(r, wake)
    if not Active then
        return false
    end

    local _, humanoid, liveRoot = livingCharacter()
    if not humanoid or liveRoot ~= r then
        return false
    end

    local m = motion()
    if not m or not wake or not wake:IsA("BasePart") then return false end

    local target = wake.Position + Vector3.new(0, 5.5, 0)
    local horizontal = Vector3.new(r.Position.X - wake.Position.X, 0, r.Position.Z - wake.Position.Z)
    if horizontal.Magnitude > 0.1 then
        target = target + horizontal.Unit * math.min(10, wake.Size.X * 0.15)
    end

    status(
        "WAKE_TWEEN_START dist="
            .. string.format("%.1f", boxDistance(wake, r.Position))
            .. " hp=" .. string.format("%.0f", humanoid.Health)
    )

    local ok = m.MoveToPosition(
        r,
        target,
        wake.Position,
        {
            Speed = Chase.SPEED,
            MaxTime = Chase.MAX_MOVE_TIME,
            MinTime = 0.08,
        }
    )

    LastMoveAt = os.clock()
    return ok == true
end

local function combatTelemetryReady()
    -- Explicit external readiness flag is supported if the combat controller
    -- exposes one in a future version.
    if getgenv().IronSoulCombatControllerReady == true then
        return true, "GLOBAL_FLAG"
    end

    local current = readText(Chase.TELEMETRY_FILE)
    if type(current) ~= "string" or current == "" then
        return false
    end

    -- The file may be rewritten from scratch on controller initialization or
    -- extended from a previous snapshot. It must differ from the pre-combat
    -- baseline, otherwise an old run's START line must never arm the chaser.
    if current == TelemetryBaseline then
        return false
    end

    if string.find(current, "START | controller initialized", 1, true) then
        return true, "CURRENT_TELEMETRY_START"
    end

    -- TARGET/WAVE/HEARTBEAT are even stronger evidence that the live controller
    -- is already processing this Cave run.
    if string.find(current, "TARGET |", 1, true)
        or string.find(current, "WAVE_SPAWN", 1, true)
        or string.find(current, "HEARTBEAT state=COMBAT", 1, true)
    then
        return true, "CURRENT_TELEMETRY_ACTIVE"
    end

    return false
end

local function waitForLivingStable(deadline)
    local stableSince
    local lastCharacter

    while Running and os.clock() < deadline do
        local character, humanoid, r = livingCharacter()

        if character and humanoid and r then
            if character ~= lastCharacter then
                lastCharacter = character
                stableSince = os.clock()
                status(
                    "LIVING_CHARACTER_FOUND hp="
                        .. string.format("%.0f/%.0f", humanoid.Health, humanoid.MaxHealth)
                )
            elseif stableSince and os.clock() - stableSince >= Chase.RESPAWN_STABLE then
                return true
            end
        else
            stableSince = nil
            lastCharacter = LocalPlayer.Character
        end

        task.wait(0.08)
    end

    return false
end

local function waitForCombatReady()
    local deadline = os.clock() + Chase.READY_TIMEOUT

    while Running and os.clock() < deadline do
        local ready, why = combatTelemetryReady()
        if ready then
            status("COMBAT_READY evidence=" .. tostring(why))

            if not waitForLivingStable(deadline) then
                return false, "NO_LIVING_CHARACTER"
            end

            task.wait(Chase.POST_READY_SETTLE)

            if not livingCharacter() then
                return false, "CHARACTER_LOST_DURING_SETTLE"
            end

            return true, why
        end

        if os.clock() - LastWaitLogAt >= 2 then
            LastWaitLogAt = os.clock()
            local character, humanoid = livingCharacter()
            status(
                "WAIT_COMBAT_READY elapsed="
                    .. string.format("%.1f", os.clock() - StartedAt)
                    .. " alive=" .. tostring(character ~= nil)
                    .. " hp=" .. tostring(humanoid and math.floor(humanoid.Health) or nil)
            )
        end

        task.wait(0.10)
    end

    return false, "READY_TIMEOUT"
end

function Chase.Start()
    if Running or not CAVE_PLACES[game.PlaceId] then
        return Running
    end

    Running = true
    Active = false
    StartedAt = os.clock()
    LastEnemySeenAt = os.clock()
    LastMoveAt = -math.huge
    LastWaitLogAt = -math.huge
    TelemetryBaseline = readText(Chase.TELEMETRY_FILE) or ""

    if type(writefile) == "function" then
        pcall(
            writefile,
            Chase.LOG_FILE,
            "Version=V61.19\nPlaceId=" .. tostring(game.PlaceId)
                .. "\nStartedAt=" .. tostring(os.time())
                .. "\nBaselineTelemetryBytes=" .. tostring(#TelemetryBaseline)
                .. "\n"
        )
    end

    status("ARMED | movement disabled until combat controller ready")

    task.spawn(function()
        local ready, reason = waitForCombatReady()

        if not ready then
            status("FAIL_CLOSED | no movement | reason=" .. tostring(reason))
            Running = false
            Active = false
            return
        end

        Active = true
        LastEnemySeenAt = os.clock()
        status("ACTIVE | combat ready -> Cave chase enabled")

        while Running and Active and CAVE_PLACES[game.PlaceId] do
            if LocalPlayer:GetAttribute("Settlement") == true then
                break
            end

            local _, humanoid, r = livingCharacter()
            if r and humanoid then
                local model, er, dist = nearestEnemy(r)

                if model and er and dist then
                    LastEnemySeenAt = os.clock()

                    if dist > Chase.ENGAGE_DISTANCE
                        and os.clock() - LastMoveAt > 0.18
                    then
                        moveNearEnemy(r, model, er, dist)
                    end
                elseif os.clock() - LastEnemySeenAt >= Chase.NO_ENEMY_WAKE_DELAY
                    and os.clock() - LastMoveAt > 0.50
                then
                    local wake = round1Wake()
                    if wake and boxDistance(wake, r.Position) > 10 then
                        moveIntoWake(r, wake)
                    end
                end
            end

            task.wait(Chase.IDLE_STEP)
        end

        Active = false
        Running = false
        status("STOP elapsed=" .. string.format("%.2f", os.clock() - StartedAt))
    end)

    return true
end

function Chase.Stop()
    Active = false
    Running = false
end

function Chase.IsActive()
    return Running and Active
end

getgenv().IronSoulCaveChase = Chase
return Chase
