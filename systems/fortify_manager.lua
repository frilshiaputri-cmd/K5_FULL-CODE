--========================================================--
-- IRON SOUL - SAFE DEMAND-AWARE FORTIFY MANAGER V61.23
--
-- Runs AFTER Forge/EquipBest and before Cave/Story planning.
--
-- Policy:
--   * only server-defined 100% Fortify steps;
--   * current unattended ceiling = +4;
--   * primary Weapon first, then equipped Armor by official power;
--   * weak Weapon2 is skipped unless it is competitive with the primary;
--   * preserve small Currency1 / CrystalShards reserves;
--   * every mutation is verified from PlayerData;
--   * no retry loop on an unverified mutation;
--   * write exact remaining material demand for SMART Cave.
--========================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Manager = {}

Manager.VERSION = "V61.23"
Manager.SAFE_TARGET = 4
Manager.MAX_ACTIONS_PER_LOBBY = 6
Manager.CRYSTAL_SHARD_RESERVE = 2
Manager.CURRENCY1_RESERVE = 10000
Manager.SECONDARY_POWER_RATIO = 0.80
Manager.LOG_FILE = "IronSoul_FortifyManager_V61_23.txt"
Manager.DEMAND_FILE = "IronSoul_UpgradeDemand_V61_23.txt"

local lines = {}

local function add(text)
    table.insert(lines, tostring(text))
end

local function save()
    if type(writefile) == "function" then
        pcall(writefile, Manager.LOG_FILE, table.concat(lines, "\n"))
    end
end

local function status(text)
    text = tostring(text or "")
    local fn = getgenv().IronSoulStatus
    if type(fn) == "function" then
        pcall(fn, "Fortify | " .. text)
    end
    print("[IronSoul Fortify V61.23]", text)
end

local function findByName(root, wanted, className)
    for _, obj in ipairs(root:GetDescendants()) do
        if obj.Name == wanted and (not className or obj:IsA(className)) then
            return obj
        end
    end
end

local function req(name)
    local obj = findByName(ReplicatedStorage, name, "ModuleScript")
    if not obj then return nil end
    local ok, value = pcall(require, obj)
    return ok and value or nil
end

local DataUtil = req("DataUtil")
local EquipmentUtil = req("EquipmentUtil")
local FortifyUtil = req("FortifyUtil")
local EquipmentRE = findByName(ReplicatedStorage, "EquipmentRE", "RemoteEvent")

local function pdata()
    if type(DataUtil) ~= "table" or type(DataUtil.GetPlayerData) ~= "function" then
        return nil
    end
    local ok, value = pcall(function()
        return DataUtil:GetPlayerData(LocalPlayer)
    end)
    return ok and type(value) == "table" and value or nil
end

local function owned()
    local d = pdata()
    return d and d.Equipment and d.Equipment.Owned or {}
end

local function slots()
    local d = pdata()
    return d and d.Equipment and d.Equipment.EquipSlots or {}
end

local function resourceAmount(id)
    local d = pdata()
    if not d then return 0 end

    if id == "Currency1" then
        return d.Currency and tonumber(d.Currency.Currency1) or 0
    end

    if d.Crystals and tonumber(d.Crystals[id]) then
        return tonumber(d.Crystals[id])
    end

    if d.Currency and tonumber(d.Currency[id]) then
        return tonumber(d.Currency[id])
    end

    if type(DataUtil.GetValue) == "function" then
        local ok, value = pcall(function()
            return DataUtil:GetValue(LocalPlayer, {"Crystals", id})
        end)
        if ok and type(value) == "number" then return value end

        ok, value = pcall(function()
            return DataUtil:GetValue(LocalPlayer, {"Currency", id})
        end)
        if ok and type(value) == "number" then return value end
    end

    return 0
end

local function reserveFor(id)
    if id == "CrystalShards" then return Manager.CRYSTAL_SHARD_RESERVE end
    if id == "Currency1" then return Manager.CURRENCY1_RESERVE end
    return 0
end

local function officialPower(uuid)
    if type(EquipmentUtil) ~= "table"
        or type(EquipmentUtil.GetEquipmentPowerByUUID) ~= "function"
    then
        return 0
    end

    local ok, value = pcall(function()
        return EquipmentUtil:GetEquipmentPowerByUUID(LocalPlayer, uuid)
    end)
    return ok and tonumber(value) or 0
end

local function rarity(item)
    if type(item) ~= "table"
        or not item.MaxOre
        or type(EquipmentUtil) ~= "table"
        or type(EquipmentUtil.GetOreRarity) ~= "function"
    then
        return nil
    end

    local ok, value = pcall(function()
        return EquipmentUtil:GetOreRarity(item.MaxOre)
    end)
    return ok and tonumber(value) or nil
end

local function fortifyDef(item, target)
    local r = rarity(item)
    if not r or type(FortifyUtil) ~= "table"
        or type(FortifyUtil.GetFortifyDef) ~= "function"
    then
        return nil, nil, r
    end

    local ok, cost, cfg = pcall(function()
        return FortifyUtil:GetFortifyDef(r, target)
    end)
    if not ok then return nil, nil, r end
    return cost, cfg, r
end

local function targetRows()
    local currentOwned = owned()
    local currentSlots = slots()
    local primaryPower = 0

    if currentSlots.Weapon and currentOwned[currentSlots.Weapon] then
        primaryPower = officialPower(currentSlots.Weapon)
    end

    local rows = {}

    for slot, uuid in pairs(currentSlots) do
        local item = uuid and currentOwned[uuid]
        if type(item) == "table" then
            local p = officialPower(uuid)
            local include = false
            local priority = 0
            local reason = ""

            if slot == "Weapon" then
                include = true
                priority = 1000000
                reason = "PRIMARY_WEAPON"
            elseif item.Type == "Armor" then
                include = true
                priority = 500000 + p
                reason = "EQUIPPED_ARMOR"
            elseif slot == "Weapon2" then
                if primaryPower <= 0 or p >= primaryPower * Manager.SECONDARY_POWER_RATIO then
                    include = true
                    priority = 100000 + p
                    reason = "COMPETITIVE_SECONDARY"
                else
                    reason = "SKIP_WEAK_SECONDARY"
                end
            end

            table.insert(rows, {
                Slot = tostring(slot),
                UUID = tostring(uuid),
                Item = item,
                Power = p,
                Include = include,
                Priority = priority,
                Reason = reason,
            })
        end
    end

    table.sort(rows, function(a,b)
        if a.Include ~= b.Include then return a.Include end
        if a.Priority ~= b.Priority then return a.Priority > b.Priority end
        return a.Slot < b.Slot
    end)

    return rows
end

local function hasResources(cost)
    if type(cost) ~= "table" then return false, "COST_MISSING" end

    for id, amount in pairs(cost) do
        local need = tonumber(amount) or 0
        local have = resourceAmount(id)
        local reserve = reserveFor(id)
        if have - need < reserve then
            return false,
                tostring(id)
                    .. " have=" .. tostring(have)
                    .. " need=" .. tostring(need)
                    .. " reserve=" .. tostring(reserve)
        end
    end

    return true
end

local function waitFortify(uuid, expected, timeout)
    local deadline = os.clock() + (timeout or 4)
    while os.clock() < deadline do
        local item = owned()[uuid]
        if not item then return false, "ITEM_MISSING" end
        if tonumber(item.Fortify) == expected then return true, "VERIFIED" end
        task.wait(0.06)
    end
    return false, "TIMEOUT"
end

local function spendOne(row)
    local latest = owned()[row.UUID]
    if type(latest) ~= "table" then return false, "ITEM_MISSING" end

    local current = tonumber(latest.Fortify) or 1
    if current >= Manager.SAFE_TARGET then return false, "AT_TARGET" end

    local target = current + 1
    local cost, cfg, r = fortifyDef(latest, target)
    if type(cost) ~= "table" or type(cfg) ~= "table" then
        return false, "DEF_MISSING"
    end

    if tonumber(cfg.PR) ~= 100 then
        return false, "PR_NOT_100"
    end

    local enough, reason = hasResources(cost)
    if not enough then return false, "RESOURCE_BLOCKED " .. tostring(reason) end

    local beforePower = officialPower(row.UUID)
    local beforeResources = {}
    for id in pairs(cost) do beforeResources[id] = resourceAmount(id) end

    add(
        "FORTIFY_START Slot=" .. row.Slot
            .. " ID=" .. tostring(latest.ID)
            .. " UUID=" .. row.UUID
            .. " From=" .. tostring(current)
            .. " To=" .. tostring(target)
            .. " Rarity=" .. tostring(r)
            .. " PowerBefore=" .. tostring(beforePower)
    )

    local okFire, fireErr = pcall(function()
        EquipmentRE:FireServer("Fortify", row.UUID)
    end)

    if not okFire then
        add("FORTIFY_FIRE_FAILED Err=" .. tostring(fireErr))
        return false, "FIRE_FAILED"
    end

    local changed, verify = waitFortify(row.UUID, target, 4.5)
    task.wait(0.12)

    local afterPower = officialPower(row.UUID)
    add(
        "FORTIFY_RESULT Verified=" .. tostring(changed)
            .. " Verify=" .. tostring(verify)
            .. " PowerAfter=" .. tostring(afterPower)
            .. " PowerGain=" .. tostring(afterPower - beforePower)
    )

    for id, before in pairs(beforeResources) do
        local after = resourceAmount(id)
        add(
            "RESOURCE_DELTA " .. tostring(id)
                .. " " .. tostring(before)
                .. "->" .. tostring(after)
                .. " Delta=" .. tostring(after - before)
        )
    end

    return changed == true, changed and "OK" or "UNVERIFIED"
end

local function computeDemand(rows)
    local totals = {}
    local detail = {}

    for _, row in ipairs(rows) do
        if row.Include then
            local item = owned()[row.UUID]
            if type(item) == "table" then
                local current = tonumber(item.Fortify) or 1
                for target = current + 1, Manager.SAFE_TARGET do
                    local cost, cfg = fortifyDef(item, target)
                    if type(cost) ~= "table"
                        or type(cfg) ~= "table"
                        or tonumber(cfg.PR) ~= 100
                    then
                        break
                    end

                    for id, amount in pairs(cost) do
                        totals[id] = (totals[id] or 0) + (tonumber(amount) or 0)
                    end
                end

                table.insert(detail,
                    row.Slot .. "=" .. tostring(item.ID)
                        .. "|Fortify=" .. tostring(current)
                        .. "|Power=" .. tostring(officialPower(row.UUID))
                        .. "|Policy=" .. tostring(row.Reason)
                )
            end
        end
    end

    return totals, detail
end

local function writeDemand(rows)
    local totals, detail = computeDemand(rows)
    local out = {
        "Version=" .. Manager.VERSION,
        "GeneratedUnix=" .. tostring(os.time()),
        "SafeTarget=" .. tostring(Manager.SAFE_TARGET),
        "CrystalShardReserve=" .. tostring(Manager.CRYSTAL_SHARD_RESERVE),
        "Currency1Reserve=" .. tostring(Manager.CURRENCY1_RESERVE),
    }

    for _, text in ipairs(detail) do
        table.insert(out, "Target=" .. text)
    end

    local keys = {}
    for id in pairs(totals) do table.insert(keys, id) end
    table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)

    for _, id in ipairs(keys) do
        local need = tonumber(totals[id]) or 0
        local have = resourceAmount(id)
        local reserve = reserveFor(id)
        local missing = math.max(0, need + reserve - have)
        table.insert(out,
            "Demand=" .. tostring(id)
                .. "|Need=" .. tostring(need)
                .. "|Have=" .. tostring(have)
                .. "|Reserve=" .. tostring(reserve)
                .. "|Missing=" .. tostring(missing)
        )

        if id == "CrystalShards" then
            table.insert(out, "CrystalShardsNeed=" .. tostring(need))
            table.insert(out, "CrystalShardsHave=" .. tostring(have))
            table.insert(out, "CrystalShardsMissing=" .. tostring(missing))
            table.insert(out, "Cave1Needed=" .. tostring(missing > 0))
        end
    end

    if totals.CrystalShards == nil then
        local have = resourceAmount("CrystalShards")
        table.insert(out, "CrystalShardsNeed=0")
        table.insert(out, "CrystalShardsHave=" .. tostring(have))
        table.insert(out, "CrystalShardsMissing=0")
        table.insert(out, "Cave1Needed=false")
    end

    if type(writefile) == "function" then
        pcall(writefile, Manager.DEMAND_FILE, table.concat(out, "\n"))
    end

    return totals
end

function Manager.Run()
    lines = {
        "Version=" .. Manager.VERSION,
        "PlaceId=" .. tostring(game.PlaceId),
        "StartedUnix=" .. tostring(os.time()),
        "SafeTarget=" .. tostring(Manager.SAFE_TARGET),
        "MaxActions=" .. tostring(Manager.MAX_ACTIONS_PER_LOBBY),
    }

    if type(DataUtil) ~= "table"
        or type(EquipmentUtil) ~= "table"
        or type(FortifyUtil) ~= "table"
        or not EquipmentRE
    then
        add("Result=MODULES_UNAVAILABLE")
        save()
        return false, "MODULES_UNAVAILABLE"
    end

    local rows = targetRows()
    for _, row in ipairs(rows) do
        add(
            "POLICY Slot=" .. row.Slot
                .. " ID=" .. tostring(row.Item.ID)
                .. " Fortify=" .. tostring(row.Item.Fortify)
                .. " Power=" .. tostring(row.Power)
                .. " Include=" .. tostring(row.Include)
                .. " Reason=" .. tostring(row.Reason)
        )
    end

    local actions = 0
    local failures = 0

    for _, row in ipairs(rows) do
        if row.Include then
            while actions < Manager.MAX_ACTIONS_PER_LOBBY do
                local item = owned()[row.UUID]
                if not item or (tonumber(item.Fortify) or 1) >= Manager.SAFE_TARGET then
                    break
                end

                local ok, reason = spendOne(row)
                if ok then
                    actions += 1
                else
                    add("FORTIFY_STOP Slot=" .. row.Slot .. " Reason=" .. tostring(reason))
                    if not string.find(tostring(reason), "RESOURCE_BLOCKED", 1, true)
                        and reason ~= "AT_TARGET"
                    then
                        failures += 1
                    end
                    break
                end
            end
        end

        if actions >= Manager.MAX_ACTIONS_PER_LOBBY then break end
    end

    -- Re-read current equipment after spending; the resulting demand is the
    -- exact blocker consumed by the Cave planner in the same Lobby cycle.
    local finalRows = targetRows()
    local totals = writeDemand(finalRows)

    add("Actions=" .. tostring(actions))
    add("Failures=" .. tostring(failures))
    add("CrystalShardsNow=" .. tostring(resourceAmount("CrystalShards")))
    add("CrystalShardsRemainingNeed=" .. tostring(totals.CrystalShards or 0))
    add("Result=" .. (failures == 0 and "OK" or "PARTIAL"))
    save()

    status(
        "Done | actions=" .. tostring(actions)
            .. " shards=" .. tostring(resourceAmount("CrystalShards"))
            .. " remainingNeed=" .. tostring(totals.CrystalShards or 0)
    )

    return failures == 0, {
        Actions = actions,
        Failures = failures,
        CrystalShards = resourceAmount("CrystalShards"),
        RemainingNeed = totals.CrystalShards or 0,
    }
end

getgenv().IronSoulFortifyManager = Manager
return Manager
