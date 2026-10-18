-- IRON SOUL - V61.23 24/7 LOBBY PREFLIGHT
--
-- Fresh-account PlayerData readiness + post-Cave audit.
-- Upgrade-driven Cave planning now runs AFTER historical Forge/EquipBest via
-- the small post-forge hook, so Cave decisions use current equipment/material
-- demand instead of stale pre-maintenance reserve counts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local BASE = "https://raw.githubusercontent.com/MUshihara/ironsoulkaitun/main/"

local function status(text)
    text = tostring(text or "")
    local fn = getgenv().IronSoulStatus
    if type(fn) == "function" then
        pcall(fn, text)
    end
    print("[IronSoul Lobby V61.23]", text)
end

local function writeReadiness(text)
    if type(writefile) == "function" then
        pcall(writefile, "IronSoul_LobbyReadiness_V61_18.txt", tostring(text or ""))
    end
end

local DataUtilModule
local DataUtil

local function getDataUtil()
    if type(DataUtil) == "table" then
        return DataUtil
    end

    if not DataUtilModule or not DataUtilModule.Parent then
        for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
            if obj:IsA("ModuleScript") and obj.Name == "DataUtil" then
                DataUtilModule = obj
                break
            end
        end
    end

    if not DataUtilModule then
        return nil, "DataUtil module missing"
    end

    local ok, value = pcall(require, DataUtilModule)
    if not ok or type(value) ~= "table" then
        return nil, "DataUtil require failed"
    end

    DataUtil = value
    return DataUtil
end

local function readiness()
    local missing = {}
    local data

    local util, utilErr = getDataUtil()
    if not util then
        table.insert(missing, utilErr or "DataUtil unavailable")
    elseif type(util.GetPlayerData) ~= "function" then
        table.insert(missing, "DataUtil.GetPlayerData missing")
    else
        local ok, value = pcall(function()
            return util:GetPlayerData(LocalPlayer)
        end)

        if ok and type(value) == "table" then
            data = value
        else
            table.insert(missing, "PlayerData table unavailable")
        end
    end

    local loadedAttr = LocalPlayer:GetAttribute("Loaded")
    local levelAttr = tonumber(LocalPlayer:GetAttribute("LG_Level"))
    local dataLevel = data and type(data.LevelData) == "table" and tonumber(data.LevelData.Level) or nil
    local resolvedLevel = levelAttr or dataLevel
    local powerAttr = tonumber(LocalPlayer:GetAttribute("LG_PowerNew1"))

    if loadedAttr == false then
        table.insert(missing, "Loaded=false")
    end
    if resolvedLevel == nil then
        table.insert(missing, "Level unavailable")
    end
    if powerAttr == nil then
        table.insert(missing, "LG_PowerNew1=nil")
    end

    return #missing == 0 and data ~= nil,
        table.concat(missing, ", "),
        data,
        loadedAttr,
        resolvedLevel,
        levelAttr and "LG_Level" or (dataLevel and "PlayerData.LevelData.Level" or "none"),
        powerAttr
end

local started = os.clock()
local lastReport = -math.huge
local stableReady = 0
local finalLevel
local finalLevelSource

while stableReady < 4 do
    local ready, missing, data, loadedAttr, level, levelSource, power = readiness()

    if ready then
        stableReady += 1
        finalLevel = level
        finalLevelSource = levelSource
    else
        stableReady = 0
    end

    local elapsed = os.clock() - started
    if os.clock() - lastReport >= 2 or ready then
        lastReport = os.clock()

        writeReadiness(table.concat({
            "Version=V61.23",
            "Elapsed=" .. string.format("%.2f", elapsed),
            "Ready=" .. tostring(ready),
            "StableChecks=" .. tostring(stableReady) .. "/4",
            "Loaded=" .. tostring(loadedAttr),
            "ResolvedLevel=" .. tostring(level),
            "LevelSource=" .. tostring(levelSource),
            "LG_PowerNew1=" .. tostring(power),
            "PlayerData=" .. tostring(type(data)),
            "Missing=" .. tostring(missing),
        }, "\n"))

        if ready then
            status("Lobby data stabilizing | " .. stableReady .. "/4 | Lv" .. tostring(level) .. " via " .. tostring(levelSource))
        else
            status("Lobby waiting for data | " .. (missing ~= "" and missing or "unknown") .. " | " .. string.format("%.1fs", elapsed))
        end
    end

    if stableReady < 4 then
        task.wait(0.25)
    end
end

getgenv().IronSoulResolvedLevel = finalLevel
getgenv().IronSoulResolvedLevelSource = finalLevelSource

if LocalPlayer:GetAttribute("LG_Level") == nil and tonumber(finalLevel) then
    pcall(LocalPlayer.SetAttribute, LocalPlayer, "LG_Level", tonumber(finalLevel))
    status("Fresh level compatibility | LG_Level=" .. tostring(finalLevel) .. " from " .. tostring(finalLevelSource))
end

status("Lobby PlayerData ready | Lv" .. tostring(finalLevel) .. " via " .. tostring(finalLevelSource))

-- Resolve any Cave material delta after authoritative Lobby PlayerData readiness.
do
    local loadRaw = getgenv().IronSoulLoadRaw
    if type(loadRaw) == "function" then
        local okAudit, auditResult = loadRaw("systems/cave_audit.lua")
        if not okAudit then
            status("Cave audit deferred | " .. tostring(auditResult))
        end
    end
end

-- Every cross-place continuation goes through the stable entry so 24/7 sessions
-- automatically pick up future fixes instead of remaining pinned to an old boot.
do
    local queue = rawget(getgenv(), "queue_on_teleport")
    if type(queue) == "function" then
        getgenv().IronSoulQueueBootstrap = function(reason)
            local config = getgenv().IronSoulConfig or {}
            local payload = string.format([[
task.wait(1.35)
getgenv().IronSoulConfig = getgenv().IronSoulConfig or {
    FPS_CAP = %s,
    FARM = %q,
    TICKETS = %q,
    HEADLESS = %s,
    DEBUG_LOGS = %s,
}
loadstring(game:HttpGet(%q .. "?t=" .. tostring(os.time())))()
]],
                tostring(tonumber(config.FPS_CAP) or 8),
                tostring(config.FARM or "NEWBIE"),
                tostring(config.TICKETS or "SMART"),
                tostring(config.HEADLESS ~= false),
                tostring(config.DEBUG_LOGS == true),
                BASE .. "bootstrap.lua"
            )

            local ok, result = pcall(queue, payload)
            if ok then
                status("Queued stable bootstrap | " .. tostring(reason or "next teleport"))
                return true
            end

            status("ERROR | stable queue failed | " .. tostring(result))
            return false
        end
    end
end

local function getPatcher()
    local loadRaw = getgenv().IronSoulLoadRaw
    if type(loadRaw) == "function" then
        local ok, patcher = loadRaw("systems/patch_loader.lua")
        if ok and type(patcher) == "function" then
            return patcher
        end
    end

    local source = game:HttpGet(BASE .. "systems/patch_loader.lua?t=" .. tostring(os.time()))
    local fn, err = loadstring(source)
    assert(fn, err)
    local patcher = fn()
    assert(type(patcher) == "function", "V61.23 lobby patch loader unavailable")
    return patcher
end

return getPatcher()({
    repository = "MUshihara/ironsoulkaitun",
    base_commit = "1d47f7f50ec8ecd92bca691b17d586d6bdecfa55",
    path = "systems/lobby.lua",
    patch_paths = {
        "systems/patches/lobby_v61_6.patch",
        "systems/patches/lobby_v61_7_reserve_best_ore.patch",
        "systems/patches/lobby_v61_8_forge_metrics.patch",
    },
})