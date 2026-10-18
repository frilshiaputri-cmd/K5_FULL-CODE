--========================================================--
-- IRON SOUL - HELL-FIRST PROGRESSION PLANNER V61.30
--
-- IMPORTANT UI / CONFIG MAPPING:
--   Normal: internal Diff 1..5 = Trial/Challenge/Penitent/Torment/Inferno
--   Hell:   internal Diff 6..10 = Trial/Challenge/Penitent/Torment/Inferno
--
-- So internal Diff=6 is NOT a sixth visible stage. It is Hell Trial.
--
-- Policy:
--   1) Hell is the default repeat/farm mode because its ore pool is better.
--   2) Normal is used only as a one-clear UNLOCK BRIDGE when clearing the
--      corresponding Normal stage will unlock the next Hell stage.
--   3) After that bridge, the next Lobby cycle returns to Hell.
--   4) Level recommendation is a hard gate.
--   5) Power is intentionally aggressive: 78% of the matching Normal stage's
--      recommended power is accepted. Our validated headless controller is
--      stronger/safer than ordinary play, while this still avoids blind jumps.
--========================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Hell = {}

Hell.VERSION = "V61.30"
Hell.LOG_FILE = "IronSoul_HellPlanner_V61_30.txt"
Hell.POWER_READY_RATIO = 0.78
Hell.SUPPORTED_WORLDS = {
    World1 = 1,
    World2 = 2,
}
Hell.STAGE_NAMES = {
    [1] = "Trial",
    [2] = "Challenge",
    [3] = "Penitent",
    [4] = "Torment",
    [5] = "Inferno",
}

local function status(text)
    local fn = getgenv().IronSoulStatus
    if type(fn) == "function" then
        pcall(fn, "Hell | " .. tostring(text))
    end
    print("[IronSoul Hell V61.30]", tostring(text))
end

local function write(lines)
    if type(writefile) == "function" then
        pcall(writefile, Hell.LOG_FILE, table.concat(lines, "\n"))
    end
end

local function findByName(root, wanted, className)
    for _, obj in ipairs(root:GetDescendants()) do
        if obj.Name == wanted and (not className or obj:IsA(className)) then
            return obj
        end
    end
end

local function req(name)
    local module = findByName(ReplicatedStorage, name, "ModuleScript")
    if not module then return nil end
    local ok, value = pcall(require, module)
    return ok and value or nil
end

local DataUtil = req("DataUtil")
local WorldUtil = req("WorldUtil")
local ResWorldRound = req("ResWorldRound")
local GameMatchRE = findByName(ReplicatedStorage, "GameMatchRE", "RemoteEvent")

local function pdata()
    if type(DataUtil) ~= "table" or type(DataUtil.GetPlayerData) ~= "function" then
        return nil
    end
    local ok, value = pcall(function()
        return DataUtil:GetPlayerData(LocalPlayer)
    end)
    return ok and type(value) == "table" and value or nil
end

local function level(data)
    return tonumber(LocalPlayer:GetAttribute("LG_Level"))
        or (data and data.LevelData and tonumber(data.LevelData.Level))
        or 0
end

local function power()
    return tonumber(LocalPlayer:GetAttribute("LG_PowerNew1")) or 0
end

local function clearData(data)
    if type(WorldUtil) == "table" and type(WorldUtil.GetClearData) == "function" then
        local ok, value = pcall(function()
            return WorldUtil:GetClearData(LocalPlayer)
        end)
        if ok and type(value) == "table" then return value end
    end
    return data and data.Worlds and data.Worlds.ClearWolrds or {}
end

local function isCleared(data, worldId, diff)
    local clear = clearData(data)
    return type(clear[worldId]) == "table"
        and clear[worldId]["Diff_" .. tostring(diff)] ~= nil
end

local function isUnlocked(worldId, diff)
    if type(WorldUtil) ~= "table" or type(WorldUtil.IsUnlockWorld) ~= "function" then
        return false
    end
    local ok, value = pcall(function()
        return WorldUtil:IsUnlockWorld(LocalPlayer, worldId, diff)
    end)
    return ok and value == true
end

local function allRounds()
    local out = {}
    if type(ResWorldRound) ~= "table" then return out end

    local function add(cfg)
        if type(cfg) == "table" and cfg.WorldId and cfg.DiffLevel then
            table.insert(out, cfg)
        end
    end

    if type(ResWorldRound.__index) == "table" then
        for _, key in ipairs(ResWorldRound.__index) do add(ResWorldRound[key]) end
    else
        for _, cfg in pairs(ResWorldRound) do add(cfg) end
    end
    return out
end

local function normalSibling(rounds, worldId, stage)
    for _, cfg in ipairs(rounds) do
        if tostring(cfg.WorldId) == tostring(worldId)
            and tostring(cfg.Style) == "Normal"
            and tonumber(cfg.DiffLevel) == tonumber(stage)
        then
            return cfg
        end
    end
end

local function stageName(stage)
    return Hell.STAGE_NAMES[tonumber(stage)] or ("Stage" .. tostring(stage))
end

local function minPowerFor(cfg)
    local rec = tonumber(cfg and cfg.RecBattlePower) or 0
    if rec <= 0 then return 0 end
    return math.ceil(rec * Hell.POWER_READY_RATIO)
end

local function hellCandidate(data, rounds, lines)
    local lv = level(data)
    local pw = power()
    local worlds = data and data.Worlds or {}
    if worlds.OpenHell ~= true then
        table.insert(lines, "OpenHell=false")
        return nil
    end

    local rows = {}
    for _, cfg in ipairs(rounds) do
        local worldOrder = Hell.SUPPORTED_WORLDS[cfg.WorldId]
        local internalDiff = tonumber(cfg.DiffLevel) or 0
        local stage = internalDiff - 5

        if worldOrder
            and tostring(cfg.Style) == "Hell"
            and stage >= 1 and stage <= 5
            and isUnlocked(cfg.WorldId, internalDiff)
        then
            local sibling = normalSibling(rounds, cfg.WorldId, stage)
            local proxyRecPower = sibling and tonumber(sibling.RecBattlePower) or 0
            local minPower = sibling and minPowerFor(sibling) or 0
            local needLv = tonumber(cfg.RecPlayerLv) or 0
            local levelReady = lv >= needLv
            local powerReady = proxyRecPower <= 0 or pw >= minPower

            table.insert(lines,
                "HellCandidate=" .. tostring(cfg.WorldId)
                    .. ",Stage=" .. tostring(stage)
                    .. ",StageName=" .. stageName(stage)
                    .. ",InternalDiff=" .. tostring(internalDiff)
                    .. ",NeedLv=" .. tostring(needLv)
                    .. ",ProxyNormalPower=" .. tostring(proxyRecPower)
                    .. ",MinPower78=" .. tostring(minPower)
                    .. ",LevelReady=" .. tostring(levelReady)
                    .. ",PowerReady=" .. tostring(powerReady)
            )

            if levelReady and powerReady then
                table.insert(rows, {
                    Cfg = cfg,
                    WorldOrder = worldOrder,
                    Stage = stage,
                    InternalDiff = internalDiff,
                    MinPower = minPower,
                })
            end
        end
    end

    table.sort(rows, function(a, b)
        if a.WorldOrder ~= b.WorldOrder then return a.WorldOrder > b.WorldOrder end
        return a.Stage > b.Stage
    end)

    return rows[1]
end

local function bridgeCandidate(data, rounds, lines)
    local lv = level(data)
    local pw = power()
    local rows = {}

    -- A Hell stage is unlocked by the corresponding Normal clear key:
    -- Hell Trial -> World|1, Hell Challenge -> World|2, etc.
    -- Therefore Normal is used only when it can unlock a currently locked
    -- higher Hell stage.
    for _, hellCfg in ipairs(rounds) do
        local worldOrder = Hell.SUPPORTED_WORLDS[hellCfg.WorldId]
        local internalDiff = tonumber(hellCfg.DiffLevel) or 0
        local stage = internalDiff - 5

        if worldOrder
            and tostring(hellCfg.Style) == "Hell"
            and stage >= 2 and stage <= 5
            and not isUnlocked(hellCfg.WorldId, internalDiff)
        then
            local normalCfg = normalSibling(rounds, hellCfg.WorldId, stage)
            if normalCfg then
                local normalUnlocked = isUnlocked(hellCfg.WorldId, stage)
                local normalCleared = isCleared(data, hellCfg.WorldId, stage)
                local needLv = tonumber(normalCfg.RecPlayerLv) or 0
                local recPower = tonumber(normalCfg.RecBattlePower) or 0
                local minPower = minPowerFor(normalCfg)
                local levelReady = lv >= needLv
                local powerReady = recPower <= 0 or pw >= minPower

                table.insert(lines,
                    "BridgeCandidate=" .. tostring(hellCfg.WorldId)
                        .. ",UnlockHellStage=" .. tostring(stage)
                        .. ",StageName=" .. stageName(stage)
                        .. ",NormalInternalDiff=" .. tostring(stage)
                        .. ",HellInternalDiff=" .. tostring(internalDiff)
                        .. ",NormalUnlocked=" .. tostring(normalUnlocked)
                        .. ",NormalCleared=" .. tostring(normalCleared)
                        .. ",NeedLv=" .. tostring(needLv)
                        .. ",RecPower=" .. tostring(recPower)
                        .. ",MinPower78=" .. tostring(minPower)
                        .. ",LevelReady=" .. tostring(levelReady)
                        .. ",PowerReady=" .. tostring(powerReady)
                )

                if normalUnlocked
                    and not normalCleared
                    and levelReady
                    and powerReady
                then
                    table.insert(rows, {
                        Cfg = normalCfg,
                        WorldOrder = worldOrder,
                        Stage = stage,
                        HellInternalDiff = internalDiff,
                        MinPower = minPower,
                    })
                end
            end
        end
    end

    table.sort(rows, function(a, b)
        if a.WorldOrder ~= b.WorldOrder then return a.WorldOrder > b.WorldOrder end
        -- Unlock the next missing visible stage in order, not a later skip.
        return a.Stage < b.Stage
    end)

    return rows[1]
end

local function roomContainer()
    return Workspace:FindFirstChild("MatchRoom")
end

local function enteredRoomId()
    return LocalPlayer:GetAttribute("EnterRoomId")
end

local function roomById(id)
    local c = roomContainer()
    return c and id and c:FindFirstChild(tostring(id))
end

local function isFreeRoom(room)
    local owner = tonumber(room:GetAttribute("HomeownerId"))
    return not owner or owner == 0 or owner == LocalPlayer.UserId
end

local function findFreeRoom()
    local deadline = os.clock() + 5
    while os.clock() < deadline do
        local c = roomContainer()
        if c then
            local rooms = {}
            for _, room in ipairs(c:GetChildren()) do
                if (room:IsA("Model") or room:IsA("Folder")) and isFreeRoom(room) then
                    table.insert(rooms, room)
                end
            end
            table.sort(rooms, function(a,b) return a.Name < b.Name end)
            if rooms[1] then return rooms[1] end
        end
        task.wait(0.10)
    end
end

local function getRoot()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart", 8)
end

local function touchParts(room)
    local preferred, fallback = {}, {}
    for _, obj in ipairs(room:GetDescendants()) do
        if obj:IsA("BasePart") then
            local low = string.lower(obj.Name)
            local touch = obj:FindFirstChildOfClass("TouchTransmitter") ~= nil
            if touch
                or string.find(low, "enter", 1, true)
                or string.find(low, "trigger", 1, true)
                or string.find(low, "touch", 1, true)
            then
                table.insert(preferred, obj)
            else
                table.insert(fallback, obj)
            end
        end
    end
    return #preferred > 0 and preferred or fallback
end

local function waitRoom(timeout)
    local deadline = os.clock() + (timeout or 1)
    while os.clock() < deadline do
        local id = enteredRoomId()
        if id and id ~= "" then return tostring(id) end
        task.wait(0.05)
    end
end

local function enterRoom(room)
    local existing = enteredRoomId()
    if existing and existing ~= "" then return true end

    local root = getRoot()
    if not root then return false end
    local original = root.CFrame
    local parts = touchParts(room)

    if type(firetouchinterest) == "function" then
        for _, part in ipairs(parts) do
            pcall(function()
                firetouchinterest(root, part, 0)
                task.wait(0.04)
                firetouchinterest(root, part, 1)
            end)
            if waitRoom(0.45) then return true end
        end
    end

    for _, part in ipairs(parts) do
        root.CFrame = part.CFrame * CFrame.new(0, 2.5, 0)
        if waitRoom(0.65) then return true end
    end

    if room:IsA("Model") then
        root.CFrame = room:GetPivot() * CFrame.new(0, 3, 0)
        if waitRoom(1.2) then return true end
    end

    root.CFrame = original
    return false
end

local function ensureRoom(lines)
    local room
    local existing = enteredRoomId()
    if existing and existing ~= "" then
        room = roomById(existing)
    else
        room = findFreeRoom()
        if not room then
            table.insert(lines, "Result=NO_FREE_ROOM")
            write(lines)
            return false
        end
        if not enterRoom(room) then
            table.insert(lines, "Result=ROOM_ENTER_FAILED")
            write(lines)
            return false
        end
    end

    local roomId = enteredRoomId()
    if not roomId or roomId == "" then
        table.insert(lines, "Result=ENTER_ROOM_ID_MISSING")
        write(lines)
        return false
    end
    return true
end

local function startMatch(cfg, modeLabel, lines, detail)
    if not ensureRoom(lines) then return false, "ROOM_FAILED" end

    local queueBootstrap = getgenv().IronSoulQueueBootstrap
    if type(queueBootstrap) ~= "function"
        or not queueBootstrap(modeLabel)
    then
        table.insert(lines, "Result=QUEUE_FAILED")
        write(lines)
        return false, "QUEUE_FAILED"
    end

    table.insert(lines, "Chosen=" .. detail)
    table.insert(lines, "Result=START_" .. modeLabel)
    write(lines)

    WorldUtil.RemoteEvent:FireServer("SelectWorld", cfg.WorldId, cfg.DiffLevel)
    task.wait(0.18)
    GameMatchRE:FireServer("CreatRoom", cfg.WorldId, cfg.DiffLevel, 1)
    return true, detail
end

function Hell.Run()
    local config = getgenv().IronSoulConfig or {}
    if config.HELL_AUTO == false then return false, "DISABLED" end

    local data = pdata()
    if not data or not WorldUtil or not WorldUtil.RemoteEvent or not GameMatchRE then
        return false, "MISSING_DATA_OR_REMOTES"
    end

    local rounds = allRounds()
    local lines = {
        "Version=" .. Hell.VERSION,
        "StartedUnix=" .. tostring(os.time()),
        "Level=" .. tostring(level(data)),
        "Power=" .. tostring(power()),
        "OpenHell=" .. tostring(data.Worlds and data.Worlds.OpenHell),
        "PowerReadyRatio=" .. tostring(Hell.POWER_READY_RATIO),
        "Policy=HELL_DEFAULT_NORMAL_ONLY_UNLOCK_BRIDGE",
    }

    if not (data.Worlds and data.Worlds.OpenHell == true) then
        table.insert(lines, "Result=HELL_NOT_OPEN")
        write(lines)
        return false, "HELL_NOT_OPEN"
    end

    local bestHell = hellCandidate(data, rounds, lines)
    local bridge = bridgeCandidate(data, rounds, lines)

    -- Use a one-clear Normal bridge only when it unlocks a higher Hell stage in
    -- the same/higher world than the Hell stage we would otherwise farm.
    if bridge then
        local shouldBridge = not bestHell
            or bridge.WorldOrder > bestHell.WorldOrder
            or (bridge.WorldOrder == bestHell.WorldOrder and bridge.Stage > bestHell.Stage)

        if shouldBridge then
            local cfg = bridge.Cfg
            local label = stageName(bridge.Stage)
            local detail = tostring(cfg.WorldId)
                .. "_NORMAL_UNLOCK_BRIDGE_" .. label
                .. "_InternalDiff" .. tostring(cfg.DiffLevel)
                .. "_UnlocksHellInternalDiff" .. tostring(bridge.HellInternalDiff)

            status("UNLOCK BRIDGE " .. tostring(cfg.WorldId) .. " Normal " .. label
                .. " | power=" .. tostring(power()) .. "/min=" .. tostring(bridge.MinPower))

            return startMatch(
                cfg,
                "NORMAL_UNLOCK_BRIDGE",
                lines,
                detail
            )
        end
    end

    if not bestHell then
        table.insert(lines, "Result=NO_READY_HELL")
        write(lines)
        return false, "NO_READY_HELL"
    end

    local cfg = bestHell.Cfg
    local label = stageName(bestHell.Stage)
    local detail = tostring(cfg.WorldId)
        .. "_HELL_" .. label
        .. "_InternalDiff" .. tostring(bestHell.InternalDiff)

    status("START " .. tostring(cfg.WorldId) .. " Hell " .. label
        .. " | internalDiff=" .. tostring(bestHell.InternalDiff)
        .. " | power=" .. tostring(power()) .. "/min=" .. tostring(bestHell.MinPower))

    return startMatch(
        cfg,
        "HELL_DEFAULT",
        lines,
        detail
    )
end

getgenv().IronSoulHellPlanner = Hell
return Hell
