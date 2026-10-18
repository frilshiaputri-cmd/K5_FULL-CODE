-- IRON SOUL - V61.21 COMBAT ENTRY

-- HARD LEVEL CAP: do not start or continue dungeon combat at the configured level limit (default 40).
-- bootstrap_v61_11 also monitors this while the dungeon is running.
do
    if getgenv().IronSoulLevelStopReached then
        return false
    end

    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local player = Players.LocalPlayer
    local cap = tonumber((getgenv().IronSoulConfig or {}).LEVEL_STOP) or 40
    local level = tonumber(player:GetAttribute("LG_Level"))

    if not level then
        for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
            if obj:IsA("ModuleScript") and obj.Name == "DataUtil" then
                local ok, util = pcall(require, obj)
                if ok and type(util) == "table" and type(util.GetPlayerData) == "function" then
                    local okData, data = pcall(function()
                        return util:GetPlayerData(player)
                    end)
                    if okData and type(data) == "table" and type(data.LevelData) == "table" then
                        level = tonumber(data.LevelData.Level)
                    end
                end
                if level then break end
            end
        end
    end

    if cap > 0 and level and level >= cap then
        getgenv().IronSoulLevelStopReached = true
        getgenv().IronSoulLevelStopLevel = level
        if type(getgenv().IronSoulConfig) == "table" then
            getgenv().IronSoulConfig.FARM = "OFF"
        end
        -- Do not kick here: the lobby reward handler must run first.
        return false
    end
end

--
-- World1 V61.15 remains frozen/stable. Validated Cave PlaceIds redirect once
-- through systems/cave.lua, which owns one-run Cave settlement/ticket policy
-- while reusing this proven combat body internally. World2 remains frozen.
--
-- V61.21: before the historical combat controller starts, synchronize the
-- effective Skill1/Skill2/SkillU loadout to the weapon that Lobby actually left
-- equipped. This lives outside the giant patched combat chunk.

if not getgenv().IronSoulInsideCaveCombat
    and (
        game.PlaceId == 91584731222940
        or game.PlaceId == 119524374829397
        or game.PlaceId == 132445869992129
    )
then
    local caveLoader = getgenv().IronSoulLoadRaw
    assert(type(caveLoader) == "function", "V61.21 Cave loader unavailable")

    local caveOk, caveResult = caveLoader("systems/cave.lua")
    if not caveOk then
        error(caveResult)
    end

    return caveResult
end

-- K5-HUB V1 explicitly enables the same native V2 combat Auto Skill chain.
do
    local env = getgenv()
    env.IronSoulConfig = env.IronSoulConfig or {}
    env.IronSoulConfig.AutoSkill = true
    env.K5V1NativeAutoSkill = true
end

-- Auto Skill dijalankan oleh sistem native V2 di combat patch chain di bawah.
-- Hindari modul systems/auto_skill.lua (input keyboard Q/E/R) agar tidak duplikat.
local originalLoadRaw = getgenv().IronSoulLoadRaw

local function getPatcher()
    local loadRaw = originalLoadRaw

    if type(loadRaw) == "function" then
        local ok, patcher = loadRaw("systems/patch_loader.lua")
        if ok and type(patcher) == "function" then
            return patcher
        end
    end

    local source = game:HttpGet(
        "https://raw.githubusercontent.com/frilshiaputri-cmd/Ironsoulkaitun/main/systems/patch_loader.lua?t="
            .. tostring(os.time())
    )

    local fn, err = loadstring(source)
    assert(fn, err)

    local patcher = fn()
    assert(type(patcher) == "function", "V61.21 combat patch loader unavailable")
    return patcher
end

-- Preload helpers OUTSIDE the giant historical combat chunk. This avoids
-- local-register pressure inside patched combat.lua.
if type(originalLoadRaw) == "function" then
    pcall(function()
        originalLoadRaw("systems/world1_motion.lua")
        originalLoadRaw("systems/world1_round_recovery.lua")
        originalLoadRaw("systems/dungeon_route_mapper.lua")
    end)
end

-- Weapon-aware skill loadout is deliberately after Lobby/EquipBest has already
-- completed and before combat initialization. Cave V61.19 chase remains armed
-- but motionless until the combat controller later announces readiness, so this
-- bounded maintenance cannot recreate the old pre-controller Cave death race.
if type(originalLoadRaw) == "function" then
    pcall(function()
        local okLoadout, manager = originalLoadRaw("systems/skill_loadout_manager.lua")
        if okLoadout and type(manager) == "table" and type(manager.Run) == "function" then
            local okRun, runOk, detail = pcall(manager.Run)
            if not okRun then
                local status = getgenv().IronSoulStatus
                if type(status) == "function" then
                    pcall(status, "Loadout failed closed | " .. tostring(runOk))
                end
            elseif runOk ~= true then
                local status = getgenv().IronSoulStatus
                if type(status) == "function" then
                    pcall(status, "Loadout kept existing | " .. tostring(detail))
                end
            end
        end
    end)
end

-- Keep an unredirected loader available to the wrappers so they can reuse the
-- proven underlying transition/watchdog modules without recursion.
getgenv().IronSoulDependencyBaseLoadRaw = originalLoadRaw

local function routedLoadRaw(path)
    if path == "systems/transition.lua" then
        path = "systems/transition_nowalk.lua"
    elseif path == "systems/transition_watchdog.lua" then
        path = "systems/transition_watchdog_nowalk.lua"
    end

    if type(originalLoadRaw) == "function" then
        return originalLoadRaw(path)
    end

    local source = game:HttpGet(
        "https://raw.githubusercontent.com/frilshiaputri-cmd/Ironsoulkaitun/main/"
            .. tostring(path)
            .. "?t="
            .. tostring(os.time())
    )

    local fn, err = loadstring(source)
    if not fn then
        return false, err
    end

    local ok, result = pcall(fn)
    return ok, result
end

getgenv().IronSoulLoadRaw = routedLoadRaw

local skillStatus = getgenv().IronSoulStatus
if type(skillStatus) == "function" then
    pcall(skillStatus, "V1 Auto Skill | applying native V2 combat patches")
end

local ok, result = pcall(function()
    return getPatcher()({
        repository = "frilshiaputri-cmd/Ironsoulkaitun",
        base_repository = "MUshihara/ironsoulkaitun",
        base_commit = "1d47f7f50ec8ecd92bca691b17d586d6bdecfa55",
        path = "systems/combat.lua",
        patch_paths = {
            "systems/patches/combat_v61_7_boss_safe.patch",
            "systems/patches/combat_v61_8_burst_safe.patch",
            "systems/patches/combat_v61_8_skill_telemetry.patch",
            "systems/patches/combat_v61_8_learned_transition.patch",
            "systems/patches/combat_v61_9_unknown_objective.patch",
            "systems/patches/combat_v61_10_objective_scope_hotfix.patch",
            "systems/patches/combat_v61_11_1_region_egg_bridge.patch",
            "systems/patches/combat_v61_14_world1_tween_open_gate.patch",
            "systems/patches/combat_v61_14_far_traversal_tween.patch",
            "systems/patches/combat_v61_14_3_fast_settlement.patch",
            "systems/patches/combat_v61_15_skill_input_fallback.patch",
            "systems/patches/combat_v61_22_skill_no_local_level_gate.patch",
            "systems/patches/combat_v61_23_auto_skill_u.patch",
            "systems/patches/combat_v61_24_force_auto_skill_cycle.patch",
            "systems/patches/combat_v61_25_unblock_auto_skill_attempts.patch",
            "systems/patches/combat_v61_26_refresh_skill_button_detection.patch",
        },
    })
end)

getgenv().IronSoulLoadRaw = originalLoadRaw

if not ok then
    -- Never silently run the unpatched upstream combat: that build does not
    -- include the V1-connected native V2 Auto Skill chain.
    local status = getgenv().IronSoulStatus
    if type(status) == "function" then
        pcall(status, "ERROR | native Auto Skill patch chain failed | " .. tostring(result))
    end
    error("K5-HUB V1 native Auto Skill patch chain failed: " .. tostring(result))
end

local status = getgenv().IronSoulStatus
if type(status) == "function" then
    pcall(status, "V1 Auto Skill | native V2 combat patches active")
end

return result
