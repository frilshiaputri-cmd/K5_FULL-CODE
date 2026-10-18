--========================================================--
-- IRON SOUL - WEAPON-AWARE BEST SKILL LOADOUT V61.21
--
-- Purpose:
--   Keep the actual combat skill loadout synchronized with the weapon that is
--   currently equipped after Lobby equipment maintenance.
--
-- Proven protocol (V43.1):
--   WeaponUtil.RemoteEvent:FireServer("EquipSkill", weaponId, slot, skillId)
--   WeaponUtil:GetWeaponSkillId(player, weaponId, slot) verifies effective slot.
--   WeaponUtil:CanEquipSkill(player, weaponId, slot, skillId) validates a choice.
--
-- Selection:
--   * read current equipped weapon class + ID from WeaponUtil;
--   * discover that class's base + activated level skills from ResSkillTree;
--   * Basic skills compete for Skill1 + Skill2;
--   * Ultimate skills compete for SkillU;
--   * score from live ResSkill / ResSkillStage combat data rather than skill
--     number/order: damage events, cooldown, action time, range, mitigation;
--   * only equip candidates that WeaponUtil itself says are valid for the slot;
--   * verify every mutation from the effective server-backed loadout getter.
--
-- This is intentionally external to the giant historical combat chunk.
--========================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Manager = {}

Manager.VERSION = "V61.21"
Manager.LOG_FILE = "IronSoul_SkillLoadout_V61_21.txt"
Manager.VERIFY_TIMEOUT = 2.5
Manager.MAX_UNLOCK_BRANCH = 7

local function status(text)
    text = tostring(text or "")
    local fn = getgenv().IronSoulStatus
    if type(fn) == "function" then
        pcall(fn, "Loadout | " .. text)
    end
    print("[IronSoul Loadout V61.21]", text)
end

local function findModule(name)
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("ModuleScript") and obj.Name == name then
            return obj
        end
    end
end

local function req(name)
    local module = findModule(name)
    if not module then return nil end
    local ok, value = pcall(require, module)
    return ok and value or nil
end

local DataUtil = req("DataUtil")
local WeaponUtil = req("WeaponUtil")
local ResSkillTree = req("ResSkillTree")
local ResSkill = req("ResSkill")
local ResSkillStage = req("ResSkillStage")

local function pdata()
    if type(DataUtil) ~= "table" or type(DataUtil.GetPlayerData) ~= "function" then
        return nil
    end
    local ok, value = pcall(function()
        return DataUtil:GetPlayerData(LocalPlayer)
    end)
    return ok and type(value) == "table" and value or nil
end

local function n(v, fallback)
    local value = tonumber(v)
    if value ~= nil then return value end
    return tonumber(fallback) or 0
end

local function waitUntil(fn, timeout)
    local deadline = os.clock() + (tonumber(timeout) or 2)
    while os.clock() < deadline do
        local ok, value = pcall(fn)
        if ok and value then return value end
        task.wait(0.08)
    end
end

local function equippedWeapon()
    if type(WeaponUtil) ~= "table" then return nil end

    local class
    local weaponId

    if type(WeaponUtil.GetEquippedWeaponClass) == "function" then
        pcall(function()
            class = WeaponUtil:GetEquippedWeaponClass(LocalPlayer)
        end)
    end

    if type(WeaponUtil.GetEquippedWeaponId) == "function" then
        pcall(function()
            weaponId = WeaponUtil:GetEquippedWeaponId(LocalPlayer)
        end)
    end

    if class and weaponId then
        return tostring(class), tostring(weaponId)
    end

    -- Conservative PlayerData fallback. The primary path above is the already
    -- validated live WeaponUtil getter.
    local d = pdata()
    local equipment = d and d.Equipment
    local slots = equipment and equipment.EquipSlots or {}
    local active = equipment and equipment.CurWeaponSlot or "Weapon"
    if active ~= "Weapon" and active ~= "Weapon2" then active = "Weapon" end

    local uuid = slots[active]
    local item = uuid and equipment and equipment.Owned and equipment.Owned[uuid]
    if type(item) == "table" then
        return item.Class and tostring(item.Class) or nil,
            item.ID and tostring(item.ID) or nil
    end
end

local function effectiveSlot(classId, weaponId, slot)
    if type(WeaponUtil) == "table"
        and type(WeaponUtil.GetWeaponSkillId) == "function"
    then
        local ok, value = pcall(function()
            return WeaponUtil:GetWeaponSkillId(LocalPlayer, weaponId, slot)
        end)
        if ok and type(value) == "string" and value ~= "" then
            return value
        end
    end

    local d = pdata()
    local equipped = d
        and d.WeaponSkill
        and d.WeaponSkill.Equipped
        and d.WeaponSkill.Equipped[classId]
    return type(equipped) == "table" and equipped[slot] or nil
end

local function canEquip(weaponId, slot, skillId)
    if type(skillId) ~= "string" or skillId == "" then return false end
    if type(WeaponUtil) ~= "table"
        or type(WeaponUtil.CanEquipSkill) ~= "function"
    then
        return false
    end

    local ok, value = pcall(function()
        return WeaponUtil:CanEquipSkill(LocalPlayer, weaponId, slot, skillId)
    end)
    return ok and value == true
end

local function activeBranch(data, classId, key)
    local active = data
        and data.SkillTree
        and data.SkillTree.Active
        and data.SkillTree.Active[classId]
    return type(active) == "table" and active[key] == true
end

local function unlockedBranch(data, classId, key)
    local unlock = data
        and data.SkillTree
        and data.SkillTree.Unlock
        and data.SkillTree.Unlock[classId]
    return type(unlock) == "table" and unlock[key] == true
end

local function candidateIds(classId, data)
    local cfg = type(ResSkillTree) == "table" and ResSkillTree[classId]
    if type(cfg) ~= "table" then return {} end

    local out = {}
    local seen = {}

    local function add(source, skillId)
        if type(skillId) == "string" and skillId ~= "" and not seen[skillId] then
            seen[skillId] = true
            table.insert(out, {ID = skillId, Source = source})
        end
    end

    -- Base skills are always part of the weapon's native loadout.
    add("BASE_SKILL1", cfg.Skill1)
    add("BASE_SKILL2", cfg.Skill2)
    add("BASE_SKILLU", cfg.SkillU)

    -- Level-tree skills must be both server-unlocked and active. This means the
    -- manager never bypasses SkillTree progression or invents eligibility.
    for i = 1, Manager.MAX_UNLOCK_BRANCH do
        local key = "UnlockSkill" .. tostring(i)
        if unlockedBranch(data, classId, key)
            and activeBranch(data, classId, key)
        then
            add(key, cfg[key])
        end
    end

    return out
end

local function stageMetric(stage)
    if type(stage) ~= "table" then
        return 0, 0, 0
    end

    local rate = n(stage.DamageRate)
    local times = math.max(1, n(stage.DamageTimes, 1))
    local bullets = math.max(1, n(stage.BulletCount, 1))
    local damage = rate > 0 and rate * times * bullets or 0

    local range = math.max(
        n(stage.DamageRange),
        n(stage.BulletDistance)
    )

    local action = math.max(
        n(stage.Time),
        n(stage.ActEndTime),
        n(stage.CtrlTime)
    )

    return damage, range, action
end

local function skillMetrics(skillId)
    local info = type(ResSkill) == "table" and ResSkill[skillId]
    if type(info) ~= "table" then return nil end

    local rawDamage = 0
    local maxRange = 0
    local actionTime = 0
    local stageCount = 0

    for i = 1, 10 do
        local stageId = info["Stage" .. tostring(i)]
        if type(stageId) == "string" and stageId ~= "" then
            stageCount += 1
            local stage = type(ResSkillStage) == "table" and ResSkillStage[stageId]
            local damage, range, action = stageMetric(stage)
            rawDamage += damage
            maxRange = math.max(maxRange, range)
            actionTime += action
        end
    end

    local cd = n(info.CD, 10)
    local effectiveCD = cd
    if type(WeaponUtil) == "table"
        and type(WeaponUtil.GetPlayerSkillCD) == "function"
    then
        pcall(function()
            local current = WeaponUtil:GetPlayerSkillCD(LocalPlayer, skillId)
            if tonumber(current) then effectiveCD = tonumber(current) end
        end)
    end

    if type(WeaponUtil) == "table"
        and type(WeaponUtil.GetSkillActionTime) == "function"
    then
        pcall(function()
            local current = WeaponUtil:GetSkillActionTime(skillId)
            if tonumber(current) and tonumber(current) > 0 then
                actionTime = tonumber(current)
            end
        end)
    end

    return {
        ID = skillId,
        Type = tostring(info.SkillType or ""),
        RawDamage = rawDamage,
        Range = maxRange,
        Action = actionTime,
        CD = math.max(0.1, effectiveCD),
        Charge = math.max(0, n(info.Charge)),
        Mitigation = math.max(0, n(info.DmgReduction)),
        StageCount = stageCount,
    }
end

local function score(metrics)
    if type(metrics) ~= "table" then return -math.huge end

    -- Damage is the primary factor. Basic skills are judged mostly by useful
    -- damage-per-cooldown; ultimates are judged by burst per charge, because
    -- their displayed CD is not the real limiting resource in combat.
    local damage = metrics.RawDamage
    local actionPenalty = 1 + math.max(0, metrics.Action) * 0.12
    local rangeBonus = math.min(metrics.Range, 120) * 0.012
    local defenseBonus = math.min(metrics.Mitigation, 1) * 0.35

    if metrics.Type == "Ultimate" then
        local charge = metrics.Charge > 0 and metrics.Charge or 70
        return (damage / actionPenalty) * (70 / charge)
            + rangeBonus
            + defenseBonus
    end

    return (damage / metrics.CD) * 10 / actionPenalty
        + rangeBonus
        + defenseBonus
end

local function buildCandidates(classId, weaponId, data, lines)
    local basics = {}
    local ults = {}

    for _, row in ipairs(candidateIds(classId, data)) do
        local metrics = skillMetrics(row.ID)
        if metrics then
            metrics.Source = row.Source
            metrics.Score = score(metrics)

            local validAnyBasic = canEquip(weaponId, "Skill1", row.ID)
                or canEquip(weaponId, "Skill2", row.ID)
            local validUlt = canEquip(weaponId, "SkillU", row.ID)

            table.insert(lines,
                "Candidate=" .. row.ID
                    .. " Source=" .. tostring(row.Source)
                    .. " Type=" .. tostring(metrics.Type)
                    .. " Score=" .. string.format("%.4f", metrics.Score)
                    .. " Damage=" .. string.format("%.3f", metrics.RawDamage)
                    .. " CD=" .. string.format("%.3f", metrics.CD)
                    .. " Action=" .. string.format("%.3f", metrics.Action)
                    .. " Range=" .. string.format("%.1f", metrics.Range)
                    .. " Charge=" .. string.format("%.1f", metrics.Charge)
                    .. " ValidBasic=" .. tostring(validAnyBasic)
                    .. " ValidUlt=" .. tostring(validUlt)
            )

            if metrics.Type == "Ultimate" and validUlt then
                table.insert(ults, metrics)
            elseif metrics.Type ~= "Ultimate" and validAnyBasic then
                table.insert(basics, metrics)
            end
        end
    end

    table.sort(basics, function(a,b)
        if a.Score ~= b.Score then return a.Score > b.Score end
        return a.ID < b.ID
    end)

    table.sort(ults, function(a,b)
        if a.Score ~= b.Score then return a.Score > b.Score end
        return a.ID < b.ID
    end)

    return basics, ults
end

local function bestBasicPair(weaponId, basics)
    local best

    -- Include nil choices so a weapon with only one currently valid Basic skill
    -- can still improve one slot without forcing a duplicate/invalid second slot.
    for i = 0, #basics do
        for j = 0, #basics do
            local a = i > 0 and basics[i] or nil
            local b = j > 0 and basics[j] or nil

            if not (a and b and a.ID == b.ID) then
                local validA = not a or canEquip(weaponId, "Skill1", a.ID)
                local validB = not b or canEquip(weaponId, "Skill2", b.ID)

                if validA and validB and (a or b) then
                    local pairScore = (a and a.Score or 0) + (b and b.Score or 0)
                    if not best or pairScore > best.Score then
                        best = {Skill1 = a, Skill2 = b, Score = pairScore}
                    end
                end
            end
        end
    end

    return best
end

local function equipSlot(classId, weaponId, slot, skillId, lines)
    if type(skillId) ~= "string" or skillId == "" then return true, "NO_CHANGE" end

    local before = effectiveSlot(classId, weaponId, slot)
    if before == skillId then
        table.insert(lines, slot .. "=KEEP " .. skillId)
        return true, "KEEP"
    end

    if not canEquip(weaponId, slot, skillId) then
        table.insert(lines, slot .. "=REJECT_INVALID " .. skillId)
        return false, "INVALID"
    end

    if type(WeaponUtil) ~= "table" or not WeaponUtil.RemoteEvent then
        table.insert(lines, slot .. "=REMOTE_MISSING")
        return false, "REMOTE_MISSING"
    end

    status("Equip " .. tostring(classId) .. " " .. slot .. " -> " .. skillId)

    local okFire, fireErr = pcall(function()
        WeaponUtil.RemoteEvent:FireServer("EquipSkill", weaponId, slot, skillId)
    end)

    local verified = okFire and waitUntil(function()
        return effectiveSlot(classId, weaponId, slot) == skillId
    end, Manager.VERIFY_TIMEOUT)

    table.insert(lines,
        slot .. "=" .. (verified and "EQUIPPED " or "FAILED ") .. skillId
            .. " Before=" .. tostring(before)
            .. " Fire=" .. tostring(okFire)
            .. " Err=" .. tostring(fireErr)
    )

    return verified ~= nil, verified and "EQUIPPED" or "FAILED"
end

function Manager.Run()
    local lines = {
        "Version=" .. Manager.VERSION,
        "PlaceId=" .. tostring(game.PlaceId),
        "StartedUnix=" .. tostring(os.time()),
    }

    if type(DataUtil) ~= "table"
        or type(WeaponUtil) ~= "table"
        or type(ResSkillTree) ~= "table"
        or type(ResSkill) ~= "table"
        or type(ResSkillStage) ~= "table"
    then
        table.insert(lines, "Result=MODULES_UNAVAILABLE")
        if type(writefile) == "function" then
            pcall(writefile, Manager.LOG_FILE, table.concat(lines, "\n"))
        end
        return false, "MODULES_UNAVAILABLE"
    end

    local data = pdata()
    if not data then
        table.insert(lines, "Result=PLAYERDATA_UNAVAILABLE")
        if type(writefile) == "function" then
            pcall(writefile, Manager.LOG_FILE, table.concat(lines, "\n"))
        end
        return false, "PLAYERDATA_UNAVAILABLE"
    end

    local classId, weaponId = equippedWeapon()
    table.insert(lines, "WeaponClass=" .. tostring(classId))
    table.insert(lines, "WeaponId=" .. tostring(weaponId))

    if not classId or not weaponId or type(ResSkillTree[classId]) ~= "table" then
        table.insert(lines, "Result=UNSUPPORTED_OR_NO_WEAPON")
        if type(writefile) == "function" then
            pcall(writefile, Manager.LOG_FILE, table.concat(lines, "\n"))
        end
        return false, "UNSUPPORTED_OR_NO_WEAPON"
    end

    table.insert(lines, "BeforeSkill1=" .. tostring(effectiveSlot(classId, weaponId, "Skill1")))
    table.insert(lines, "BeforeSkill2=" .. tostring(effectiveSlot(classId, weaponId, "Skill2")))
    table.insert(lines, "BeforeSkillU=" .. tostring(effectiveSlot(classId, weaponId, "SkillU")))

    local basics, ults = buildCandidates(classId, weaponId, data, lines)
    local pair = bestBasicPair(weaponId, basics)
    local bestUlt = ults[1]

    table.insert(lines, "SelectedSkill1=" .. tostring(pair and pair.Skill1 and pair.Skill1.ID or nil))
    table.insert(lines, "SelectedSkill2=" .. tostring(pair and pair.Skill2 and pair.Skill2.ID or nil))
    table.insert(lines, "SelectedSkillU=" .. tostring(bestUlt and bestUlt.ID or nil))

    local failures = 0
    local changes = 0

    if pair and pair.Skill1 then
        local ok, mode = equipSlot(classId, weaponId, "Skill1", pair.Skill1.ID, lines)
        if not ok then failures += 1 elseif mode == "EQUIPPED" then changes += 1 end
    end

    if pair and pair.Skill2 then
        local ok, mode = equipSlot(classId, weaponId, "Skill2", pair.Skill2.ID, lines)
        if not ok then failures += 1 elseif mode == "EQUIPPED" then changes += 1 end
    end

    if bestUlt then
        local ok, mode = equipSlot(classId, weaponId, "SkillU", bestUlt.ID, lines)
        if not ok then failures += 1 elseif mode == "EQUIPPED" then changes += 1 end
    end

    table.insert(lines, "AfterSkill1=" .. tostring(effectiveSlot(classId, weaponId, "Skill1")))
    table.insert(lines, "AfterSkill2=" .. tostring(effectiveSlot(classId, weaponId, "Skill2")))
    table.insert(lines, "AfterSkillU=" .. tostring(effectiveSlot(classId, weaponId, "SkillU")))
    table.insert(lines, "Changes=" .. tostring(changes))
    table.insert(lines, "Failed=" .. tostring(failures))
    table.insert(lines, "Result=" .. (failures == 0 and "OK" or "PARTIAL"))

    if type(writefile) == "function" then
        pcall(writefile, Manager.LOG_FILE, table.concat(lines, "\n"))
    end

    status(
        "Done | " .. tostring(classId)
            .. " | changes=" .. tostring(changes)
            .. " failed=" .. tostring(failures)
    )

    return failures == 0, {
        Class = classId,
        WeaponId = weaponId,
        Changes = changes,
        Failed = failures,
    }
end

getgenv().IronSoulSkillLoadoutManager = Manager
return Manager
