-- IRON SOUL - V61.21 COMBAT ENTRY
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
        "https://raw.githubusercontent.com/MUshihara/ironsoulkaitun/main/systems/patch_loader.lua?t="
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

--========================================================--
-- AUTO SKILL (ported from IronForge AutoSkill behavior)
-- Automatically sends E, Q, R while an alive NPC target is nearby.
-- Runs once per client session and only from the Dungeon combat route.
--========================================================--
do
    local env = getgenv()
    if not env.IronSoulAutoSkillWorker then
        env.IronSoulAutoSkillWorker = true

        task.spawn(function()
            local Players = game:GetService("Players")
            local VirtualInputManager = game:GetService("VirtualInputManager")
            local LocalPlayer = Players.LocalPlayer
            local keys = {
                {Name = "E", Cooldown = 0.70},
                {Name = "Q", Cooldown = 0.70},
                {Name = "R", Cooldown = 1.50},
            }
            local nextUse = {E = 0, Q = 0, R = 0}
            local lastCycle = 0

            local function findTarget()
                local character = LocalPlayer and LocalPlayer.Character
                local originPart = character and character:FindFirstChild("HumanoidRootPart")
                if not originPart then return nil end

                local best, bestDistance = nil, 600
                for _, object in ipairs(workspace:GetDescendants()) do
                    if object:IsA("Model")
                        and object ~= character
                        and Players:GetPlayerFromCharacter(object) == nil
                    then
                        local humanoid = object:FindFirstChildOfClass("Humanoid")
                        local root = object:FindFirstChild("HumanoidRootPart") or object.PrimaryPart
                        if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
                            local distance = (originPart.Position - root.Position).Magnitude
                            if distance < bestDistance then
                                best, bestDistance = object, distance
                            end
                        end
                    end
                end
                return best
            end

            local function pressSkill(name)
                local keyCode = Enum.KeyCode[name]
                if not keyCode then return false end
                local ok = pcall(function()
                    VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
                    task.wait(0.025)
                    VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
                end)
                return ok
            end

            local status = env.IronSoulStatus
            if type(status) == "function" then
                pcall(status, "Auto Skill | enabled (E/Q/R)")
            end

            while env.IronSoulAutoSkillWorker and LocalPlayer and LocalPlayer.Parent do
                local now = os.clock()
                if now - lastCycle >= 2.5 and findTarget() then
                    lastCycle = now
                    for _, skill in ipairs(keys) do
                        now = os.clock()
                        if now >= (nextUse[skill.Name] or 0) then
                            if pressSkill(skill.Name) then
                                nextUse[skill.Name] = now + skill.Cooldown
                            end
                            task.wait(0.12)
                        end
                    end
                end
                task.wait(0.20)
            end
        end)
    end
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
        "https://raw.githubusercontent.com/MUshihara/ironsoulkaitun/main/"
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

local ok, result = pcall(function()
    return getPatcher()({
        repository = "MUshihara/ironsoulkaitun",
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
        },
    })
end)

getgenv().IronSoulLoadRaw = originalLoadRaw

if not ok then
    error(result)
end

return result
