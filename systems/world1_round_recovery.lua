--========================================================--
-- IRON SOUL - WORLD1 CURRENT-ROUND ROUTE RECOVERY V61.14.5
--
-- Purpose:
--   Some World1 multi-section layouts replicate the NEXT round's wake/enemies
--   hundreds of studs away before the generic section Portal is safe to use.
--   A stale/reused Portal can send the character to a later boss section while
--   GameRound is still behind. This helper follows ONLY the authoritative
--   current GameRound wake and therefore cannot intentionally skip rounds.
--
-- Movement style: smooth CFrame tween/floating via world1_motion.lua.
-- No Humanoid MoveTo. No GUI clicking. No portal RF.
--========================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TeleportService = game:GetService("TeleportService")

local LocalPlayer = Players.LocalPlayer
local Motion = getgenv().IronSoulWorld1Motion

local Recovery = {}
local Cache = {}

local LOBBY_PLACE_ID = 117533937949084

Recovery.MIN_ROUTE_DISTANCE = 180
Recovery.MAX_ROUTE_DISTANCE = 5000
Recovery.EDGE_MARGIN = 14

local function emit(name, detail)
    local telemetry = getgenv().IronSoulTelemetry
    if telemetry and type(telemetry.Event) == "function" then
        pcall(function()
            telemetry:Event(name, detail)
        end)
    end

    local trace = getgenv().IronSoulNavTrace
    if type(trace) == "function" then
        pcall(trace, tostring(name) .. " " .. tostring(detail or ""))
    end
end

local function gameRoundCfg()
    return ReplicatedStorage:FindFirstChild("GameRoundCfg")
end

local function currentRound()
    local cfg = gameRoundCfg()
    return cfg and tonumber(cfg:GetAttribute("GameRound")) or nil
end

local function isWorld1()
    local cfg = gameRoundCfg()
    if cfg then
        local id = cfg:GetAttribute("WorldId")
        if id ~= nil then
            return tostring(id) == "World1"
        end
    end

    return tostring(Workspace:GetAttribute("WorldName")) == "World1"
end

local function playerRoot()
    local character = LocalPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function findModule(name)
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("ModuleScript") and obj.Name == name then
            return obj
        end
    end
end

local function emergencyLobby(reason)
    emit(
        "CURRENT_ROUND_ROUTE_FAIL_CLOSED",
        "reason=" .. tostring(reason)
            .. " GameRound=" .. tostring(currentRound())
    )

    local queue = getgenv().IronSoulQueueBootstrap
    if type(queue) == "function" then
        pcall(queue, "World1 impossible future-region mismatch -> Lobby")
    end

    local sent = false
    local module = findModule("WorldUtil")

    if module then
        local okRequire, worldUtil = pcall(require, module)
        if okRequire
            and type(worldUtil) == "table"
            and worldUtil.RemoteEvent
        then
            sent = pcall(function()
                worldUtil.RemoteEvent:FireServer("BackLobby")
            end)
        end
    end

    if sent then
        local deadline = os.clock() + 1.25
        while os.clock() < deadline do
            local target = LocalPlayer:GetAttribute("IsTeleporting")
            if target ~= nil and target ~= false then
                return true
            end
            task.wait(0.08)
        end
    end

    pcall(function()
        TeleportService:Teleport(LOBBY_PLACE_ID, LocalPlayer)
    end)

    return true
end

local function regionRound(region)
    if not region then
        return nil
    end

    return tonumber(
        string.match(
            tostring(region.Name),
            "^Round(%d+)$"
        )
    )
end

local function roundNumberFromWake(obj)
    if not obj or not obj:IsA("BasePart") then
        return nil
    end

    local n = tonumber(string.match(tostring(obj.Name), "^Round(%d+)$"))
    if not n then
        return nil
    end

    local parent = obj.Parent
    if not parent or tostring(parent.Name) ~= "RoundWakeTouch" then
        return nil
    end

    return n
end

local function capture(obj)
    local n = roundNumberFromWake(obj)
    if not n then
        return
    end

    Cache[n] = {
        CFrame = obj.CFrame,
        Size = obj.Size,
        SeenAt = os.clock(),
        Instance = obj,
    }
end

local function scanWakes()
    local worldEnemies = Workspace:FindFirstChild("WorldEnemys")
    local folder = worldEnemies and worldEnemies:FindFirstChild("RoundWakeTouch")
    if not folder then
        return
    end

    for _, obj in ipairs(folder:GetChildren()) do
        capture(obj)
    end
end

scanWakes()

Workspace.DescendantAdded:Connect(function(obj)
    capture(obj)
end)

local function liveWake(roundNum)
    local worldEnemies = Workspace:FindFirstChild("WorldEnemys")
    local folder = worldEnemies and worldEnemies:FindFirstChild("RoundWakeTouch")
    local wake = folder and folder:FindFirstChild("Round" .. tostring(roundNum))

    if wake and wake:IsA("BasePart") then
        capture(wake)
        return wake
    end
end

local function boxDistance(cf, size, point)
    local localPoint = cf:PointToObjectSpace(point)
    local half = size * 0.5

    local dx = math.max(math.abs(localPoint.X) - half.X, 0)
    local dy = math.max(math.abs(localPoint.Y) - half.Y, 0)
    local dz = math.max(math.abs(localPoint.Z) - half.Z, 0)

    return Vector3.new(dx, dy, dz).Magnitude
end

local function targetInside(cf, size, rootPos)
    local localPoint = cf:PointToObjectSpace(rootPos)
    local half = size * 0.5
    local margin = Recovery.EDGE_MARGIN

    local hx = math.max(2, half.X - margin)
    local hy = math.max(2, half.Y - 6)
    local hz = math.max(2, half.Z - margin)

    local x = math.clamp(localPoint.X, -hx, hx)
    local y = math.clamp(localPoint.Y, -hy, hy)
    local z = math.clamp(localPoint.Z, -hz, hz)

    -- If we are outside, place the target a little deeper than the closest
    -- boundary so streaming/region ownership has room to settle.
    if localPoint.X > hx then x = hx - 6 end
    if localPoint.X < -hx then x = -hx + 6 end
    if localPoint.Z > hz then z = hz - 6 end
    if localPoint.Z < -hz then z = -hz + 6 end

    return cf:PointToWorldSpace(Vector3.new(x, y, z))
end

local function wakeData(roundNum)
    local wake = liveWake(roundNum)
    if wake then
        return wake.CFrame, wake.Size, wake, "LIVE"
    end

    local cached = Cache[roundNum]
    if cached then
        return cached.CFrame, cached.Size, nil, "CACHE"
    end
end

function Recovery:RecoverIfNeeded(oldRegion, reason)
    if not isWorld1() then
        return false
    end

    if type(Motion) ~= "table" or type(Motion.MoveToPosition) ~= "function" then
        Motion = getgenv().IronSoulWorld1Motion
        if type(Motion) ~= "table" or type(Motion.MoveToPosition) ~= "function" then
            return false
        end
    end

    local roundNum = currentRound()
    local root = playerRoot()

    if not roundNum or not root or not root.Parent then
        return false
    end

    local expectedName = "Round" .. tostring(roundNum)

    -- Already owned by the server-current wake: no section portal needed.
    if oldRegion and tostring(oldRegion.Name) == expectedName then
        return false
    end

    local cf, size, wake, source = wakeData(roundNum)
    if not cf or not size then
        -- Impossible authoritative mismatch: physically two or more rounds
        -- ahead with no way to recover the real current wake. Do not hang in an
        -- empty future boss arena; rebuild the solo run through Lobby.
        local physicalRound = regionRound(oldRegion)
        if physicalRound and physicalRound >= roundNum + 2 then
            return emergencyLobby(
                "FUTURE_REGION_R"
                    .. tostring(physicalRound)
                    .. "_SERVER_R"
                    .. tostring(roundNum)
            )
        end

        return false
    end

    local distance = boxDistance(cf, size, root.Position)

    if distance <= 8 then
        emit(
            "CURRENT_ROUND_ROUTE_SUCCESS",
            "round=" .. tostring(roundNum)
                .. " source=" .. tostring(source)
                .. " result=ALREADY_INSIDE"
        )
        return true
    end

    -- Only replace the ambiguous cross-section portal path. Nearby normal
    -- door/portal transitions keep their already-proven native handshake.
    if distance < Recovery.MIN_ROUTE_DISTANCE
        or distance > Recovery.MAX_ROUTE_DISTANCE
    then
        return false
    end

    local target = targetInside(cf, size, root.Position)

    emit(
        "CURRENT_ROUND_ROUTE_START",
        "round=" .. tostring(roundNum)
            .. " source=" .. tostring(source)
            .. " reason=" .. tostring(reason)
            .. " distance=" .. string.format("%.1f", distance)
            .. " target=" .. tostring(target)
    )

    local okMove, moveKind, studs, elapsed = Motion.MoveToPosition(
        root,
        target,
        cf.Position,
        {
            Speed = tonumber(Motion.FAR_SPEED) or 260,
            MaxTime = 2.40,
        }
    )

    if not okMove then
        emit(
            "CURRENT_ROUND_ROUTE_FAIL",
            "round=" .. tostring(roundNum)
                .. " result=" .. tostring(moveKind)
        )
        return false
    end

    task.wait(0.16)

    -- GameRound advancing while we move is authoritative success too.
    local nowRound = currentRound()
    if nowRound and nowRound ~= roundNum then
        emit(
            "CURRENT_ROUND_ROUTE_SUCCESS",
            "round=" .. tostring(roundNum)
                .. " result=GAME_ROUND_CHANGED_TO_" .. tostring(nowRound)
        )
        return true
    end

    local nowWake = liveWake(roundNum)
    if nowWake and boxDistance(nowWake.CFrame, nowWake.Size, root.Position) <= 8 then
        emit(
            "CURRENT_ROUND_ROUTE_SUCCESS",
            "round=" .. tostring(roundNum)
                .. " result=WAKE_REACHED"
                .. " kind=" .. tostring(moveKind)
                .. " studs=" .. string.format("%.1f", tonumber(studs) or 0)
                .. " time=" .. string.format("%.2f", tonumber(elapsed) or 0)
        )
        return true
    end

    -- Give streaming a short bounded chance to materialize the exact wake
    -- after reaching a cached location.
    local deadline = os.clock() + 0.80
    while os.clock() < deadline do
        task.wait(0.08)

        nowWake = liveWake(roundNum)
        if nowWake and boxDistance(nowWake.CFrame, nowWake.Size, root.Position) <= 8 then
            emit(
                "CURRENT_ROUND_ROUTE_SUCCESS",
                "round=" .. tostring(roundNum)
                    .. " result=WAKE_STREAMED"
            )
            return true
        end

        nowRound = currentRound()
        if nowRound and nowRound ~= roundNum then
            return true
        end
    end

    emit(
        "CURRENT_ROUND_ROUTE_FAIL",
        "round=" .. tostring(roundNum)
            .. " result=NO_AUTHORITATIVE_WAKE_AFTER_MOVE"
    )

    return false
end

function Recovery:GetCachedRound(roundNum)
    return Cache[tonumber(roundNum)]
end

getgenv().IronSoulWorld1RoundRecovery = Recovery

return Recovery
