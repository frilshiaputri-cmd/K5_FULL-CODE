--========================================================--
-- IRON SOUL - DEMAND-DRIVEN SMART CAVE PLANNER V61.30
--
-- Paid Cave selection stays progression-demand driven, but stage selection is
-- now intentionally more aggressive for our validated headless controller:
--   * server-unlocked stage is mandatory;
--   * recommended LEVEL is a hard gate;
--   * POWER may be about 22% below recommendation (78% floor);
--   * highest eligible currently-unlocked Cave stage wins.
--
-- This reflects the user's real live behavior: Cave is a one-room arena, our
-- movement/combat is much faster/safer than normal play, and exact 100% power
-- recommendation was unnecessarily conservative.
--========================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Planner = {}

Planner.VERSION = "V61.30"
Planner.TICKET_RESERVE = 5
Planner.COOLDOWN_SECONDS = 360
Planner.POWER_READY_RATIO = 0.78
Planner.PENDING_FILE = "IronSoul_CavePending_V61_17.txt"
Planner.STATE_FILE = "IronSoul_CavePlanner_V61_18.txt"
Planner.DEMAND_FILE = "IronSoul_UpgradeDemand_V61_23.txt"
Planner.DECISION_FILE = "IronSoul_CavePlannerDecision_V61_30.txt"

Planner.CAVES = {
    Cave1 = {WorldId="Cave1", Name="Cave of Crystal", RewardKind="CrystalShards"},
    Cave2 = {WorldId="Cave2", Name="Cave of Runes", RewardKind="EnchantedStone"},
    Cave3 = {WorldId="Cave3", Name="Abandoned Courtyard", RewardKind="WholeDragonScale"},
}

local function status(text)
    local fn = getgenv().IronSoulStatus
    if type(fn) == "function" then
        pcall(fn, "Cave smart | " .. tostring(text))
    end
    print("[IronSoul Cave Planner V61.30]", tostring(text))
end

local function parse(text)
    local out = {}
    for line in string.gmatch(tostring(text or ""), "[^\r\n]+") do
        local k, v = string.match(line, "^([^=]+)=(.*)$")
        if k then out[k] = v end
    end
    return out
end

local function serialize(t)
    local keys = {}
    for k in pairs(t) do table.insert(keys, k) end
    table.sort(keys)
    local rows = {}
    for _, k in ipairs(keys) do
        table.insert(rows, tostring(k) .. "=" .. tostring(t[k]))
    end
    return table.concat(rows, "\n")
end

local function readFile(path)
    if type(readfile) ~= "function" then return nil end
    if type(isfile) == "function" and not isfile(path) then return nil end
    local ok, text = pcall(readfile, path)
    return ok and type(text) == "string" and text or nil
end

local function readState()
    local text = readFile(Planner.STATE_FILE)
    return text and parse(text) or {}
end

local function readDemand()
    local text = readFile(Planner.DEMAND_FILE)
    return text and parse(text) or {}
end

local function writeState(row)
    if type(writefile) == "function" then
        pcall(writefile, Planner.STATE_FILE, serialize(row))
    end
end

local function writePending(row)
    if type(writefile) == "function" then
        pcall(writefile, Planner.PENDING_FILE, serialize(row))
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
    if type(DataUtil) ~= "table" or type(DataUtil.GetPlayerData) ~= "function" then return nil end
    local ok, value = pcall(function() return DataUtil:GetPlayerData(LocalPlayer) end)
    return ok and type(value) == "table" and value or nil
end

local function count(t)
    local n = 0
    if type(t) == "table" then
        for _ in pairs(t) do n += 1 end
    end
    return n
end

local function level(data)
    return tonumber(LocalPlayer:GetAttribute("LG_Level"))
        or (data and data.LevelData and tonumber(data.LevelData.Level))
        or 0
end

local function power()
    return tonumber(LocalPlayer:GetAttribute("LG_PowerNew1")) or 0
end

local function tickets(data)
    return data and data.Currency and tonumber(data.Currency.Ticket1) or 0
end

local function rewardValue(data, kind)
    if kind == "CrystalShards" then
        return data and data.Crystals and tonumber(data.Crystals.CrystalShards) or 0
    elseif kind == "WholeDragonScale" then
        return data and data.Crystals and tonumber(data.Crystals.WholeDragonScale) or 0
    elseif kind == "EnchantedStone" then
        return count(data and data.EnchantedStone and data.EnchantedStone.Owned)
    end
    return 0
end

local function boolValue(v)
    return tostring(v) == "true"
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

local function allRoundConfigs()
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

local ROUND_CONFIGS = allRoundConfigs()

local function ticketInfo(cfg)
    local id = cfg and cfg.NeedTicket
    local amount = tonumber(cfg and cfg.TicketCount) or 0
    if id == nil or id == "" or amount <= 0 then
        return nil, 0
    end
    return tostring(id), amount
end

local function highestReadyCaveCfg(worldId, data)
    local rows = {}
    local lv = level(data)
    local pw = power()

    for _, cfg in ipairs(ROUND_CONFIGS) do
        if tostring(cfg.WorldId) == tostring(worldId)
            and tostring(cfg.Style) == "Normal"
        then
            local diff = tonumber(cfg.DiffLevel)
            local ticketId, ticketCost = ticketInfo(cfg)
            local ticketCompatible = ticketId == nil or ticketId == "Ticket1"
            local recLv = tonumber(cfg.RecPlayerLv) or 0
            local recPower = tonumber(cfg.RecBattlePower) or 0
            local minPower = recPower > 0
                and math.ceil(recPower * Planner.POWER_READY_RATIO)
                or 0

            if diff
                and ticketCompatible
                and isUnlocked(worldId, diff)
                and lv >= recLv
                and (recPower <= 0 or pw >= minPower)
                and tickets(data) - ticketCost >= Planner.TICKET_RESERVE
            then
                table.insert(rows, {
                    Cfg = cfg,
                    Diff = diff,
                    RecLevel = recLv,
                    RecPower = recPower,
                    MinPower = minPower,
                    TicketId = ticketId,
                    TicketCost = ticketCost,
                })
            end
        end
    end

    table.sort(rows, function(a,b) return a.Diff > b.Diff end)
    return rows[1]
end

local function hasPet(data)
    return count(data and data.Pets and data.Pets.Owned) > 0
end

local function hasEgg(data)
    return count(data and data.PetHatch and data.PetHatch.Egg) > 0
end

local function choose(data)
    local demand = readDemand()
    local candidates = {}

    local function addCandidate(worldId, score, reason, deficit, current, target, minimumDiff)
        local cave = Planner.CAVES[worldId]
        local ready = cave and highestReadyCaveCfg(worldId, data)
        if not ready then return end
        if minimumDiff and ready.Diff < minimumDiff then return end

        table.insert(candidates, {
            Cave = cave,
            Cfg = ready.Cfg,
            Diff = ready.Diff,
            RecLevel = ready.RecLevel,
            RecPower = ready.RecPower,
            MinPower = ready.MinPower,
            TicketCost = ready.TicketCost,
            Current = current or 0,
            Deficit = deficit or 1,
            Target = target or ((current or 0) + (deficit or 1)),
            Score = score,
            Reason = reason,
        })
    end

    local missingShards = tonumber(demand.CrystalShardsMissing or 0) or 0
    if missingShards > 0 then
        local current = rewardValue(data, "CrystalShards")
        addCandidate(
            "Cave1",
            1000 + math.min(missingShards, 200),
            "FORTIFY_CRYSTAL_BLOCKER",
            missingShards,
            current,
            current + missingShards
        )
    end

    if not hasPet(data) and not hasEgg(data) then
        addCandidate(
            "Cave3",
            850,
            "PET_EGG_BLOCKER",
            1,
            0,
            1,
            2
        )
    end

    local cave2Needed = boolValue(demand.Cave2Needed)
    local enchantMissing = tonumber(demand.EnchantStoneMissing or 0) or 0
    local eligibleEmpty = tonumber(demand.EnchantEligibleEmptySlots or 0) or 0
    if cave2Needed and enchantMissing > 0 and eligibleEmpty > 0 then
        local current = rewardValue(data, "EnchantedStone")
        addCandidate(
            "Cave2",
            700 + math.min(eligibleEmpty, 50),
            "ENCHANT_STONE_BLOCKER",
            1,
            current,
            current + 1
        )
    end

    table.sort(candidates, function(a,b)
        if a.Score ~= b.Score then return a.Score > b.Score end
        if a.Diff ~= b.Diff then return a.Diff > b.Diff end
        return a.Cave.WorldId < b.Cave.WorldId
    end)

    return candidates[1], candidates, demand
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
    local preferred = {}
    local fallback = {}
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

local function auditDecision(data, candidate, candidates, reason, demand)
    if type(writefile) ~= "function" then return end

    local rows = {
        "Version=" .. Planner.VERSION,
        "Reason=" .. tostring(reason),
        "Level=" .. tostring(level(data)),
        "Power=" .. tostring(power()),
        "PowerReadyRatio=" .. tostring(Planner.POWER_READY_RATIO),
        "Ticket1=" .. tostring(tickets(data)),
        "Reserve=" .. tostring(Planner.TICKET_RESERVE),
        "Cooldown=" .. tostring(Planner.COOLDOWN_SECONDS),
        "CrystalShards=" .. tostring(rewardValue(data, "CrystalShards")),
        "EnchantedStones=" .. tostring(rewardValue(data, "EnchantedStone")),
        "OwnedPets=" .. tostring(count(data and data.Pets and data.Pets.Owned)),
        "OwnedEggs=" .. tostring(count(data and data.PetHatch and data.PetHatch.Egg)),
        "FortifyCrystalMissing=" .. tostring(demand and demand.CrystalShardsMissing or 0),
        "EnchantEligibleEmptySlots=" .. tostring(demand and demand.EnchantEligibleEmptySlots or 0),
        "EnchantUsableStones=" .. tostring(demand and demand.EnchantUsableStones or 0),
        "EnchantStoneMissing=" .. tostring(demand and demand.EnchantStoneMissing or 0),
        "Cave2Needed=" .. tostring(demand and demand.Cave2Needed or false),
        "Cave3EggNeeded=" .. tostring(not hasPet(data) and not hasEgg(data)),
        "Chosen=" .. tostring(candidate and candidate.Cave.WorldId or "none"),
        "ChosenDiff=" .. tostring(candidate and candidate.Diff or "none"),
    }

    for i, row in ipairs(candidates or {}) do
        table.insert(rows,
            "Candidate" .. tostring(i)
                .. "=" .. tostring(row.Cave.WorldId)
                .. ",Diff=" .. tostring(row.Diff)
                .. ",Reason=" .. tostring(row.Reason)
                .. ",RecLv=" .. tostring(row.RecLevel)
                .. ",RecPower=" .. tostring(row.RecPower)
                .. ",MinPower78=" .. tostring(row.MinPower)
                .. ",TicketCost=" .. tostring(row.TicketCost)
                .. ",Current=" .. tostring(row.Current)
                .. ",Target=" .. tostring(row.Target)
                .. ",Deficit=" .. tostring(row.Deficit)
                .. ",Score=" .. string.format("%.3f", row.Score)
        )
    end

    pcall(writefile, Planner.DECISION_FILE, table.concat(rows, "\n"))
end

function Planner.Run()
    local config = getgenv().IronSoulConfig or {}
    if tostring(config.TICKETS or "SMART") ~= "SMART" or config.CAVE_AUTO == false then
        return false, "DISABLED"
    end

    local data = pdata()
    if not data or not WorldUtil or not WorldUtil.RemoteEvent or not GameMatchRE or not ResWorldRound then
        return false, "MISSING_DATA_OR_REMOTES"
    end

    local ticketCount = tickets(data)
    local state = readState()
    local last = tonumber(state.LastCaveUnix or 0) or 0
    local cooldownLeft = math.max(0, Planner.COOLDOWN_SECONDS - (os.time() - last))
    local candidate, all, demand = choose(data)

    if ticketCount <= Planner.TICKET_RESERVE then
        auditDecision(data, candidate, all, "TICKET_RESERVE", demand)
        return false, "TICKET_RESERVE"
    end

    if cooldownLeft > 0 then
        auditDecision(data, candidate, all, "COOLDOWN_" .. tostring(cooldownLeft), demand)
        return false, "COOLDOWN"
    end

    if not candidate then
        auditDecision(data, nil, all, "NO_VALID_UPGRADE_DEMAND", demand)
        return false, "NO_NEED"
    end

    if ticketCount - (tonumber(candidate.TicketCost) or 0) < Planner.TICKET_RESERVE then
        auditDecision(data, candidate, all, "TICKET_RESERVE_AFTER_COST", demand)
        return false, "TICKET_RESERVE"
    end

    auditDecision(data, candidate, all, "START_CAVE", demand)

    local room
    local existing = enteredRoomId()
    if existing and existing ~= "" then
        room = roomById(existing)
    else
        room = findFreeRoom()
        if not room then return false, "NO_FREE_ROOM" end
        if not enterRoom(room) then return false, "ROOM_ENTER_FAILED" end
    end

    local roomId = enteredRoomId()
    if not roomId or roomId == "" then return false, "ENTER_ROOM_ID_MISSING" end

    local cave = candidate.Cave
    local queueBootstrap = getgenv().IronSoulQueueBootstrap
    if type(queueBootstrap) ~= "function"
        or not queueBootstrap("smart cave -> " .. cave.WorldId .. " D" .. tostring(candidate.Diff))
    then
        return false, "QUEUE_FAILED"
    end

    local pending = {
        Version = Planner.VERSION,
        Resolved = "false",
        StartedUnix = tostring(os.time()),
        WorldId = cave.WorldId,
        Name = cave.Name,
        Diff = tostring(candidate.Diff),
        RewardKind = cave.RewardKind,
        RewardBefore = tostring(candidate.Current),
        TicketBeforeEntry = tostring(ticketCount),
        PlannerReason = tostring(candidate.Reason),
        PlannerTarget = tostring(candidate.Target),
        PlannerDeficit = tostring(candidate.Deficit),
        RecPower = tostring(candidate.RecPower),
        MinPower78 = tostring(candidate.MinPower),
    }
    writePending(pending)

    writeState({
        LastCaveUnix = tostring(os.time()),
        LastWorldId = cave.WorldId,
        LastDiff = tostring(candidate.Diff),
        LastReason = tostring(candidate.Reason),
    })

    status(
        "START " .. cave.Name
            .. " | D" .. tostring(candidate.Diff)
            .. " | " .. tostring(candidate.Reason)
            .. " | power=" .. tostring(power()) .. "/min=" .. tostring(candidate.MinPower)
            .. " | ticket=" .. tostring(candidate.TicketCost)
    )

    WorldUtil.RemoteEvent:FireServer("SelectWorld", cave.WorldId, candidate.Diff)
    task.wait(0.18)
    GameMatchRE:FireServer("CreatRoom", cave.WorldId, candidate.Diff, 1)

    return true, cave.WorldId .. " D" .. tostring(candidate.Diff)
end

getgenv().IronSoulCavePlanner = Planner
return Planner
