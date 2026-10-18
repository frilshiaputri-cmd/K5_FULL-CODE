--========================================================--
-- IRON SOUL - LIVE DUNGEON ROUTE MAPPER V61.15
--
-- Goal:
--   Discover the route from the LIVE place instead of assuming fixed room
--   coordinates. Each Roblox Place has its own Workspace tree, so knowledge is
--   keyed by PlaceId/WorldId/Diff and derived from live RoundWakeTouch, Door,
--   Portal*, server GameRound, and streamed objective state.
--
-- World1: active smooth-tween recovery.
-- World2+: discovery/logging only until explicitly validated.
--
-- Safety:
--   * never treats raw displacement as progression proof;
--   * never follows a wrong-round historical gate/portal;
--   * only probes beyond the last server-valid open gate after GameRound has
--     already advanced and the current round has not streamed yet;
--   * exact local Portal* touch is allowed only for RoundNum == GameRound-1;
--   * bounded failure -> Lobby rebuild instead of an infinite 24/7 stall.
--========================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local Mapper = {}

Mapper.VERSION = "V61.15"
Mapper.PROBE_DISTANCES = {65, 95, 130, 175, 230, 300}
Mapper.PROBE_WAIT = 0.24
Mapper.PORTAL_SETTLE = 0.60
Mapper.MAX_SWEEPS = 2
Mapper.WORLD1_ACTIVE = true
Mapper.WORLD2_ACTIVE = false

local Cache = {
    Wakes = {},
    Doors = setmetatable({}, {__mode = "k"}),
    Portals = setmetatable({}, {__mode = "k"}),
    LastFrontier = nil,
    Attempts = {},
    LastSnapshotAt = -math.huge,
}

local Motion = getgenv().IronSoulWorld1Motion

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

local function worldId()
    local cfg = gameRoundCfg()
    local value = cfg and cfg:GetAttribute("WorldId")
    if value ~= nil then
        return tostring(value)
    end
    return tostring(Workspace:GetAttribute("WorldName") or "?")
end

local function diffLevel()
    local cfg = gameRoundCfg()
    return cfg and tonumber(cfg:GetAttribute("DiffLevel")) or nil
end

local function root()
    local character = LocalPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function roundFromWake(obj)
    if not obj or not obj:IsA("BasePart") then
        return nil
    end

    local n = tonumber(string.match(tostring(obj.Name), "^Round(%d+)$"))
    if not n then
        return nil
    end

    local parent = obj.Parent
    if parent and tostring(parent.Name) == "RoundWakeTouch" then
        return n
    end
end

local function portalName(obj)
    if not obj or not obj.Parent then
        return nil
    end

    if obj:IsA("BasePart")
        and obj.Name == "Root"
        and string.sub(tostring(obj.Parent.Name), 1, 6) == "Portal"
    then
        return tostring(obj.Parent.Name)
    end
end

local function doorRoot(obj)
    return obj
        and obj:IsA("BasePart")
        and obj.Name == "Root"
        and obj.Parent
        and obj.Parent.Name == "Door"
end

local function capture(obj)
    local wakeRound = roundFromWake(obj)
    if wakeRound then
        Cache.Wakes[wakeRound] = {
            Instance = obj,
            CFrame = obj.CFrame,
            Size = obj.Size,
            SeenAt = os.clock(),
        }
        return
    end

    if doorRoot(obj) then
        Cache.Doors[obj] = true
        return
    end

    if portalName(obj) then
        Cache.Portals[obj] = true
    end
end

local function scan()
    local worldEnemies = Workspace:FindFirstChild("WorldEnemys")
    local wakeFolder = worldEnemies and worldEnemies:FindFirstChild("RoundWakeTouch")
    if wakeFolder then
        for _, obj in ipairs(wakeFolder:GetChildren()) do
            capture(obj)
        end
    end

    local roundDoor = Workspace:FindFirstChild("RoundDoor")
    if roundDoor then
        for _, obj in ipairs(roundDoor:GetDescendants()) do
            if obj:IsA("BasePart") and obj.Name == "Root" then
                capture(obj)
            end
        end
    end
end

scan()
Workspace.DescendantAdded:Connect(capture)

local function liveWake(roundNum)
    local worldEnemies = Workspace:FindFirstChild("WorldEnemys")
    local wakeFolder = worldEnemies and worldEnemies:FindFirstChild("RoundWakeTouch")
    local wake = wakeFolder and wakeFolder:FindFirstChild("Round" .. tostring(roundNum))

    if wake and wake:IsA("BasePart") then
        capture(wake)
        return wake
    end
end

local function boxDistance(cf, size, point)
    local p = cf:PointToObjectSpace(point)
    local half = size * 0.5
    local dx = math.max(math.abs(p.X) - half.X, 0)
    local dy = math.max(math.abs(p.Y) - half.Y, 0)
    local dz = math.max(math.abs(p.Z) - half.Z, 0)
    return Vector3.new(dx, dy, dz).Magnitude
end

local function wakeDistance(wake, point)
    return boxDistance(wake.CFrame, wake.Size, point)
end

local function normalizedHorizontal(v)
    local h = Vector3.new(v.X, 0, v.Z)
    if h.Magnitude < 0.1 then
        return Vector3.new(1, 0, 0)
    end
    return h.Unit
end

local function currentObjectives()
    local worldEnemies = Workspace:FindFirstChild("WorldEnemys")
    if not worldEnemies then
        return 0
    end

    local n = 0
    for _, obj in ipairs(worldEnemies:GetDescendants()) do
        if obj:IsA("Humanoid")
            and obj.Health > 0
            and (not LocalPlayer.Character or not obj:IsDescendantOf(LocalPlayer.Character))
        then
            n += 1
        end
    end
    return n
end

local function validCurrentPortal(maxDistance)
    local r = root()
    local roundNum = currentRound()
    if not r or not roundNum then
        return nil
    end

    local best, bestDist
    for portal in pairs(Cache.Portals) do
        if portal and portal.Parent then
            local pr = tonumber(portal:GetAttribute("RoundNum"))
            if pr == roundNum - 1 then
                local dist = (portal.Position - r.Position).Magnitude
                if dist <= (maxDistance or 120)
                    and (not bestDist or dist < bestDist)
                then
                    best = portal
                    bestDist = dist
                end
            end
        end
    end

    return best, bestDist
end

local function exactTouch(r, portal)
    if type(firetouchinterest) ~= "function"
        or not r
        or not portal
        or not portal.Parent
    then
        return false
    end

    local a = pcall(firetouchinterest, r, portal, 0)
    task.wait(0.035)
    local b = pcall(firetouchinterest, r, portal, 1)
    return a or b
end

local function ensureMotion()
    if type(Motion) == "table" and type(Motion.MoveToPosition) == "function" then
        return Motion
    end

    Motion = getgenv().IronSoulWorld1Motion
    if type(Motion) == "table" and type(Motion.MoveToPosition) == "function" then
        return Motion
    end
end

local function targetInsideWake(wake, fromPos)
    local localPoint = wake.CFrame:PointToObjectSpace(fromPos)
    local half = wake.Size * 0.5
    local hx = math.max(3, half.X - 14)
    local hz = math.max(3, half.Z - 14)

    local x = math.clamp(localPoint.X, -hx, hx)
    local z = math.clamp(localPoint.Z, -hz, hz)

    if localPoint.X > hx then x = hx - 6 end
    if localPoint.X < -hx then x = -hx + 6 end
    if localPoint.Z > hz then z = hz - 6 end
    if localPoint.Z < -hz then z = -hz + 6 end

    return wake.CFrame:PointToWorldSpace(Vector3.new(x, 0, z))
end

local function moveToWake(roundNum, reason)
    local r = root()
    local wake = liveWake(roundNum)
    local motion = ensureMotion()

    if not r or not wake or not motion then
        return false
    end

    local dist = wakeDistance(wake, r.Position)
    if dist <= 8 then
        return true
    end

    local target = targetInsideWake(wake, r.Position)
    target = Vector3.new(target.X, r.Position.Y, target.Z)

    emit(
        "ROUTE_MAP_WAKE_MOVE_START",
        "round=" .. tostring(roundNum)
            .. " reason=" .. tostring(reason)
            .. " distance=" .. string.format("%.1f", dist)
            .. " target=" .. tostring(target)
    )

    local okMove, kind, studs, elapsed = motion.MoveToPosition(
        r,
        target,
        Vector3.new(wake.Position.X, r.Position.Y, wake.Position.Z),
        {
            Speed = tonumber(motion.FAR_SPEED) or 260,
            MaxTime = 2.60,
        }
    )

    task.wait(0.14)

    if okMove and liveWake(roundNum) and wakeDistance(wake, r.Position) <= 10 then
        emit(
            "ROUTE_MAP_WAKE_MOVE_SUCCESS",
            "round=" .. tostring(roundNum)
                .. " kind=" .. tostring(kind)
                .. " studs=" .. string.format("%.1f", tonumber(studs) or 0)
                .. " time=" .. string.format("%.2f", tonumber(elapsed) or 0)
        )
        return true
    end

    return false
end

local function snapshot(reason, force)
    if type(writefile) ~= "function" then
        return
    end

    if not force and os.clock() - Cache.LastSnapshotAt < 4 then
        return
    end

    Cache.LastSnapshotAt = os.clock()
    scan()

    local r = root()
    local lines = {
        "Version=" .. Mapper.VERSION,
        "Reason=" .. tostring(reason),
        "PlaceId=" .. tostring(game.PlaceId),
        "JobId=" .. tostring(game.JobId),
        "WorldId=" .. tostring(worldId()),
        "Diff=" .. tostring(diffLevel()),
        "GameRound=" .. tostring(currentRound()),
        "PlayerPos=" .. tostring(r and r.Position),
        "Objectives=" .. tostring(currentObjectives()),
        "",
        "WAKES:",
    }

    local wakeNums = {}
    for n in pairs(Cache.Wakes) do
        table.insert(wakeNums, n)
    end
    table.sort(wakeNums)

    for _, n in ipairs(wakeNums) do
        local row = Cache.Wakes[n]
        local inst = row.Instance
        table.insert(
            lines,
            "Round" .. tostring(n)
                .. " live=" .. tostring(inst and inst.Parent ~= nil)
                .. " pos=" .. tostring(row.CFrame.Position)
                .. " size=" .. tostring(row.Size)
                .. " dist=" .. tostring(r and boxDistance(row.CFrame, row.Size, r.Position))
        )
    end

    table.insert(lines, "")
    table.insert(lines, "DOORS:")
    for door in pairs(Cache.Doors) do
        if door and door.Parent then
            table.insert(
                lines,
                "Round=" .. tostring(door:GetAttribute("RoundNum"))
                    .. " Switch=" .. tostring(door:GetAttribute("Switch"))
                    .. " pos=" .. tostring(door.Position)
                    .. " dist=" .. tostring(r and (door.Position - r.Position).Magnitude)
            )
        end
    end

    table.insert(lines, "")
    table.insert(lines, "PORTALS:")
    for portal in pairs(Cache.Portals) do
        if portal and portal.Parent then
            table.insert(
                lines,
                tostring(portal.Parent.Name)
                    .. " Round=" .. tostring(portal:GetAttribute("RoundNum"))
                    .. " pos=" .. tostring(portal.Position)
                    .. " dist=" .. tostring(r and (portal.Position - r.Position).Magnitude)
            )
        end
    end

    pcall(
        writefile,
        "IronSoul_DungeonRouteMap_V61_15.txt",
        table.concat(lines, "\n")
    )
end

local function queueLobbyRebuild(reason)
    emit("ROUTE_MAP_REBUILD_LOBBY", tostring(reason))
    snapshot("REBUILD_LOBBY_" .. tostring(reason), true)

    local queue = getgenv().IronSoulQueueBootstrap
    if type(queue) == "function" then
        pcall(queue, "route mapper recovery -> lobby")
    end

    local worldUtilModule
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("ModuleScript") and obj.Name == "WorldUtil" then
            worldUtilModule = obj
            break
        end
    end

    if worldUtilModule then
        local okReq, worldUtil = pcall(require, worldUtilModule)
        if okReq and type(worldUtil) == "table" and worldUtil.RemoteEvent then
            pcall(function()
                worldUtil.RemoteEvent:FireServer("BackLobby")
            end)
        end
    end

    task.delay(2.2, function()
        if game.PlaceId ~= 117533937949084 then
            pcall(function()
                TeleportService:Teleport(117533937949084, LocalPlayer)
            end)
        end
    end)
end

function Mapper:Snapshot(reason, force)
    snapshot(reason, force)
end

function Mapper:RecoverCurrentRound(reason)
    scan()

    if worldId() ~= "World1" or not self.WORLD1_ACTIVE then
        snapshot("DISCOVERY_ONLY_" .. tostring(reason), false)
        return false
    end

    local roundNum = currentRound()
    if not roundNum then
        return false
    end

    return moveToWake(roundNum, reason)
end

function Mapper:AdvanceFromOpenGate(door, doorPos, outward, oldRegion, beforeRound)
    scan()
    snapshot("OPEN_GATE_FRONTIER", false)

    if worldId() ~= "World1" or not self.WORLD1_ACTIVE then
        return false
    end

    local r = root()
    local motion = ensureMotion()
    local roundNum = currentRound()

    if not r or not motion or not roundNum or not door or not door.Parent then
        return false
    end

    -- If the server-current round has already streamed, use it directly.
    if liveWake(roundNum) then
        return moveToWake(roundNum, "OPEN_GATE_CURRENT_WAKE")
    end

    -- Only probe from the exact previous-round frontier after the server has
    -- already advanced. Example: GameRound7 + open Round6 gate.
    local doorRound = tonumber(door:GetAttribute("RoundNum"))
    if doorRound ~= roundNum - 1 then
        return false
    end

    local dir = normalizedHorizontal(outward)
    local anchor = r.CFrame
    local key = table.concat({
        tostring(game.PlaceId),
        tostring(diffLevel()),
        tostring(roundNum),
        tostring(math.floor(door.Position.X / 5)),
        tostring(math.floor(door.Position.Z / 5)),
    }, "|")

    Cache.LastFrontier = {
        Door = door,
        DoorPos = doorPos,
        Outward = dir,
        Round = roundNum,
        Anchor = anchor,
    }

    Cache.Attempts[key] = (Cache.Attempts[key] or 0) + 1

    emit(
        "ROUTE_MAP_FRONTIER_START",
        "round=" .. tostring(roundNum)
            .. " doorRound=" .. tostring(doorRound)
            .. " sweep=" .. tostring(Cache.Attempts[key])
            .. " door=" .. tostring(doorPos)
            .. " dir=" .. tostring(dir)
    )

    local initialObjectives = currentObjectives()

    for _, distance in ipairs(self.PROBE_DISTANCES) do
        if not r.Parent or not door.Parent then
            return false
        end

        local target = doorPos + dir * distance
        target = Vector3.new(target.X, r.Position.Y, target.Z)

        motion.MoveToPosition(
            r,
            target,
            target + dir * 10,
            {
                Speed = tonumber(motion.DEFAULT_SPEED) or 210,
                MaxTime = math.min(0.75, math.max(0.16, distance / 260)),
            }
        )

        emit(
            "ROUTE_MAP_FRONTIER_PROBE",
            "round=" .. tostring(roundNum)
                .. " distance=" .. tostring(distance)
                .. " pos=" .. tostring(r.Position)
        )

        task.wait(self.PROBE_WAIT)
        scan()

        local nowRound = currentRound()
        if nowRound and nowRound ~= roundNum then
            emit(
                "ROUTE_MAP_FRONTIER_SUCCESS",
                "result=GAME_ROUND_CHANGED " .. tostring(roundNum) .. "->" .. tostring(nowRound)
            )
            return true
        end

        if liveWake(roundNum) then
            if moveToWake(roundNum, "FRONTIER_WAKE_STREAMED") then
                emit(
                    "ROUTE_MAP_FRONTIER_SUCCESS",
                    "result=WAKE_STREAMED round=" .. tostring(roundNum)
                )
                return true
            end
        end

        if currentObjectives() > initialObjectives then
            emit(
                "ROUTE_MAP_FRONTIER_SUCCESS",
                "result=OBJECTIVE_APPEARED round=" .. tostring(roundNum)
            )
            return true
        end

        local portal = validCurrentPortal(95)
        if portal then
            emit(
                "ROUTE_MAP_FRONTIER_PORTAL",
                "round=" .. tostring(roundNum)
                    .. " name=" .. tostring(portal.Parent.Name)
                    .. " pos=" .. tostring(portal.Position)
            )

            local preDir = normalizedHorizontal(r.Position - portal.Position)
            local pre = portal.Position + preDir * 9
            pre = Vector3.new(pre.X, r.Position.Y, pre.Z)

            motion.MoveToPosition(
                r,
                pre,
                Vector3.new(portal.Position.X, r.Position.Y, portal.Position.Z),
                {Speed = tonumber(motion.DEFAULT_SPEED) or 210, MaxTime = 0.45}
            )

            task.wait(self.PORTAL_SETTLE)
            exactTouch(r, portal)

            local beyond = portal.Position - preDir * 14
            beyond = Vector3.new(beyond.X, r.Position.Y, beyond.Z)
            motion.MoveToPosition(
                r,
                beyond,
                Vector3.new(portal.Position.X, r.Position.Y, portal.Position.Z),
                {Speed = tonumber(motion.DEFAULT_SPEED) or 210, MaxTime = 0.28}
            )
            exactTouch(r, portal)

            local deadline = os.clock() + 1.1
            while os.clock() < deadline do
                task.wait(0.08)
                scan()

                if currentRound() ~= roundNum
                    or liveWake(roundNum)
                    or currentObjectives() > initialObjectives
                then
                    emit(
                        "ROUTE_MAP_FRONTIER_SUCCESS",
                        "result=LOCAL_PORTAL_TRIGGERED round=" .. tostring(roundNum)
                    )
                    return true
                end
            end
        end
    end

    -- Return to the known frontier after a failed sweep. Do not leave the
    -- character stranded in an arbitrary probe coordinate.
    if r.Parent then
        motion.Move(r, anchor, {
            Speed = tonumber(motion.FAR_SPEED) or 260,
            MaxTime = 1.10,
        })
    end

    emit(
        "ROUTE_MAP_FRONTIER_FAIL",
        "round=" .. tostring(roundNum)
            .. " sweep=" .. tostring(Cache.Attempts[key])
    )

    snapshot("FRONTIER_FAIL", true)

    if Cache.Attempts[key] >= self.MAX_SWEEPS then
        queueLobbyRebuild("ROUND_" .. tostring(roundNum) .. "_FRONTIER_EXHAUSTED")
    end

    return false
end

-- Generic place-aware map remains available in World2 even while active
-- movement is frozen there. This lets future logs teach us its different
-- doors/PortalD/blockers without sharing World1 coordinates.
getgenv().IronSoulDungeonRouteMapper = Mapper
snapshot("LOAD", true)

return Mapper
