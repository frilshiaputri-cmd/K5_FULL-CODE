--========================================================--
-- IRON SOUL - POST-LOBBY READY MAINTENANCE V61.20
--
-- This module is loaded by systems/lobby.lua only AFTER authoritative Lobby
-- PlayerData readiness. Keep free/idempotent maintenance here so the historical
-- Lobby body and its proven patch chain remain untouched.
--
-- Order:
--   1) weapon-aware SkillTree activation for server-unlocked branches;
--   2) reconcile any pending Cave reward/ticket baseline.
--
-- Cave audit itself remains read-only. Skill activation spends no currency and
-- never invents unlocks; it only activates branches already granted by server.
--========================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PENDING_FILE = "IronSoul_CavePending_V61_17.txt"
local AUDIT_FILE = "IronSoul_CaveAudit_V61_17.txt"

local function status(text)
    local fn = getgenv().IronSoulStatus
    if type(fn) == "function" then
        pcall(fn, tostring(text or ""))
    end
end

--========================================================--
-- FREE SKILL MAINTENANCE
--========================================================--

do
    local loadRaw = getgenv().IronSoulLoadRaw

    if type(loadRaw) == "function" then
        local okSkill, manager = loadRaw("systems/skill_manager.lua")

        if okSkill
            and type(manager) == "table"
            and type(manager.Run) == "function"
        then
            local okRun, handled, detail = pcall(manager.Run)

            if not okRun then
                status("Skill manager failed closed | " .. tostring(handled))
            elseif handled == true then
                status("Skill maintenance complete")
            else
                status("Skill maintenance skipped | " .. tostring(detail or handled))
            end
        elseif not okSkill then
            status("Skill manager unavailable | " .. tostring(manager))
        end
    end
end

--========================================================--
-- CAVE POST-LOBBY AUDIT
--========================================================--

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

local function readPending()
    if type(readfile) ~= "function" then return nil end
    if type(isfile) == "function" and not isfile(PENDING_FILE) then return nil end

    local ok, text = pcall(readfile, PENDING_FILE)
    if not ok or type(text) ~= "string" or text == "" then return nil end
    return parse(text)
end

local function findModule(name)
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("ModuleScript") and obj.Name == name then return obj end
    end
end

local DataUtil
local module = findModule("DataUtil")
if module then
    local ok, value = pcall(require, module)
    if ok and type(value) == "table" then DataUtil = value end
end

local function pdata()
    if type(DataUtil) ~= "table" or type(DataUtil.GetPlayerData) ~= "function" then return nil end
    local ok, value = pcall(function() return DataUtil:GetPlayerData(LocalPlayer) end)
    return ok and type(value) == "table" and value or nil
end

local function crystal(data, id)
    return data and data.Crystals and tonumber(data.Crystals[id]) or 0
end

local function enchantedCount(data)
    local owned = data and data.EnchantedStone and data.EnchantedStone.Owned
    if type(owned) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(owned) do n += 1 end
    return n
end

local function rewardValue(data, kind)
    if kind == "CrystalShards" then
        return crystal(data, "CrystalShards")
    elseif kind == "WholeDragonScale" then
        return crystal(data, "WholeDragonScale")
    elseif kind == "EnchantedStone" then
        return enchantedCount(data)
    end
    return 0
end

local function ticket1(data)
    return data and data.Currency and tonumber(data.Currency.Ticket1) or nil
end

local pending = readPending()
if type(pending) ~= "table" or pending.Resolved == "true" then
    return false
end

-- Give normal Lobby replication a tiny bounded settle after preflight. This is
-- intentionally outside Cave so it does not hold the player on Victory.
local data
for _ = 1, 8 do
    data = pdata()
    if data then break end
    task.wait(0.10)
end

if not data then
    return false
end

task.wait(0.25)
data = pdata() or data

local kind = pending.RewardKind or "Unknown"
local beforeReward = tonumber(pending.RewardBefore)
local afterReward = rewardValue(data, kind)
local ticketNow = ticket1(data)
local ticketAtCaveStart = tonumber(pending.TicketAtCaveStart)
local ticketBeforeEntry = tonumber(pending.TicketBeforeEntry)

local rows = {
    "Version=V61.20",
    "Resolved=true",
    "PlaceId=" .. tostring(pending.PlaceId),
    "WorldId=" .. tostring(pending.WorldId),
    "Name=" .. tostring(pending.Name),
    "Diff=" .. tostring(pending.Diff),
    "Result=" .. tostring(pending.Result or "CAVE_RETURN"),
    "StartedUnix=" .. tostring(pending.StartedUnix),
    "RewardKind=" .. tostring(kind),
    "RewardBefore=" .. tostring(beforeReward),
    "RewardAfterLobby=" .. tostring(afterReward),
    "RewardDelta=" .. tostring(beforeReward and (afterReward - beforeReward) or nil),
    "TicketAtCaveStart=" .. tostring(ticketAtCaveStart),
    "TicketAfterLobby=" .. tostring(ticketNow),
    "TicketDeltaFromCaveStart=" .. tostring(
        ticketAtCaveStart and ticketNow and (ticketNow - ticketAtCaveStart) or nil
    ),
    "TicketBeforeEntry=" .. tostring(ticketBeforeEntry),
    "EntryTicketDelta=" .. tostring(
        ticketBeforeEntry and ticketNow and (ticketNow - ticketBeforeEntry) or nil
    ),
    "Note=EntryTicketDelta is authoritative only when Lobby planner wrote TicketBeforeEntry before CreatRoom.",
}

if type(writefile) == "function" then
    pcall(writefile, AUDIT_FILE, table.concat(rows, "\n"))

    pending.Resolved = "true"
    pending.ResolvedUnix = tostring(os.time())
    pending.RewardAfterLobby = tostring(afterReward)
    pending.TicketAfterLobby = tostring(ticketNow)
    pcall(writefile, PENDING_FILE, serialize(pending))
end

status(
    "Cave audit | "
        .. tostring(pending.WorldId)
        .. " | "
        .. tostring(kind)
        .. " +"
        .. tostring(beforeReward and (afterReward - beforeReward) or "?")
)

return true
