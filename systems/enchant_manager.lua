--========================================================--
-- IRON SOUL - SMART VERIFIED ENCHANT MANAGER V61.24
--
-- Runs after Blessing/Fortify and before SMART Cave planning.
--
-- Live-validated protocol 2026-08-12:
--   EquipmentRE:FireServer("Enchant", equipmentUUID, slotKey, stoneUUID)
--
-- Live proof:
--   Single_Gray +4, slot1 + Burn_1
--   Currency1 69286 -> 66886 (-2400)
--   equipment power 616 -> 696 (+80)
--   stone UUID consumed and slot server-verified.
--
-- Production policy:
--   * equipped keeper gear only;
--   * minimum Blessing/Fortify +4;
--   * active/primary weapon first, then strongest armor;
--   * secondary weapon only when competitive with primary;
--   * existing EMPTY enchant slots only;
--   * never overwrite, reroll, UnEnchant or use DetachTool;
--   * one enchant maximum per Lobby cycle;
--   * preserve Currency1 reserve;
--   * rank available stones from live effect data;
--   * verify both installed slot and exact stone consumption;
--   * publish real Cave2 demand only when a useful empty slot exists and
--     no valid Enchanted Stone is currently available.
--========================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Manager = {}

Manager.VERSION = "V61.24"
Manager.MIN_KEEPER_FORTIFY = 4
Manager.MAX_ACTIONS_PER_LOBBY = 1
Manager.CURRENCY1_RESERVE = 10000
Manager.SECONDARY_POWER_RATIO = 0.80
Manager.LOG_FILE = "IronSoul_EnchantManager_V61_24.txt"
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
    local fn = getgenv().IronSoulStatus
    if type(fn) == "function" then
        pcall(fn, "Enchant | " .. tostring(text))
    end
    print("[IronSoul Enchant V61.24]", tostring(text))
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
local EnchantmentUtil = req("EnchantmentUtil")
local ResEnchantedStoneConfig = req("ResEnchantedStoneConfig")
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

local function ownedEquipment()
    local d = pdata()
    return d and d.Equipment and d.Equipment.Owned or {}
end

local function equipSlots()
    local d = pdata()
    return d and d.Equipment and d.Equipment.EquipSlots or {}
end

local function currentWeaponSlot()
    local d = pdata()
    local slot = d and d.Equipment and d.Equipment.CurWeaponSlot or "Weapon"
    if slot ~= "Weapon" and slot ~= "Weapon2" then slot = "Weapon" end
    return slot
end

local function stones()
    local d = pdata()
    return d and d.EnchantedStone and d.EnchantedStone.Owned or {}
end

local function currency1()
    local d = pdata()
    return d and d.Currency and tonumber(d.Currency.Currency1) or 0
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

local function gearRarity(item)
    if type(item) ~= "table" or not item.MaxOre
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

local function emptyEnchantSlot(item)
    if type(item) ~= "table" or type(item.Enchantments) ~= "table" then
        return nil
    end

    local keys = {}
    for key in pairs(item.Enchantments) do table.insert(keys, key) end
    table.sort(keys, function(a,b)
        local na, nb = tonumber(a), tonumber(b)
        if na and nb then return na < nb end
        return tostring(a) < tostring(b)
    end)

    for _, key in ipairs(keys) do
        local slot = item.Enchantments[key]
        if type(slot) == "table" and slot.Type == nil then
            return key
        end
    end
end

local function enchantSlotStats(item)
    local total, empty, filled = 0, 0, 0
    if type(item) == "table" and type(item.Enchantments) == "table" then
        for _, slot in pairs(item.Enchantments) do
            total += 1
            if type(slot) == "table" and slot.Type == nil then
                empty += 1
            elseif type(slot) == "table" and slot.Type ~= nil then
                filled += 1
            end
        end
    end
    return total, empty, filled
end

local function targetRows()
    local owned = ownedEquipment()
    local slots = equipSlots()
    local active = currentWeaponSlot()
    local backup = active == "Weapon" and "Weapon2" or "Weapon"
    local activePower = slots[active] and officialPower(slots[active]) or 0
    local rows = {}

    for slotName, uuid in pairs(slots) do
        local item = uuid and owned[uuid]
        if type(item) == "table" then
            local p = officialPower(uuid)
            local include = false
            local priority = 0
            local reason = ""

            if slotName == active then
                include = true
                priority = 1000000 + p
                reason = "ACTIVE_PRIMARY_WEAPON"
            elseif item.Type == "Armor" then
                include = true
                priority = 500000 + p
                reason = "EQUIPPED_ARMOR"
            elseif slotName == backup then
                if activePower <= 0 or p >= activePower * Manager.SECONDARY_POWER_RATIO then
                    include = true
                    priority = 100000 + p
                    reason = "COMPETITIVE_SECONDARY"
                else
                    reason = "SKIP_WEAK_SECONDARY"
                end
            end

            local total, empty, filled = enchantSlotStats(item)
            local fortify = tonumber(item.Fortify) or 1
            local emptyKey = emptyEnchantSlot(item)
            local rarity = gearRarity(item)

            table.insert(rows, {
                Slot = tostring(slotName),
                UUID = tostring(uuid),
                RawUUID = uuid,
                Item = item,
                Power = p,
                Include = include,
                Priority = priority,
                Reason = reason,
                Fortify = fortify,
                EmptySlot = emptyKey,
                TotalSlots = total,
                EmptySlots = empty,
                FilledSlots = filled,
                Rarity = rarity,
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

local function stoneInfo(uuid, stone)
    if type(stone) ~= "table" then return nil end
    local id = stone.Id or stone.ID
    if type(id) ~= "string" then return nil end

    local def = type(ResEnchantedStoneConfig) == "table"
        and ResEnchantedStoneConfig[id]
        or nil
    local rarity = def and tonumber(def.Rarity) or tonumber(stone.Rarity)
    if not rarity then return nil end

    local dmg = tonumber(stone.DMG) or 0
    local chance = tonumber(stone.Chance) or 0
    local duration = tonumber(stone.Duration) or 0

    -- Effect-weighted progression score. Rarity is a small tie-break/quality
    -- bonus; actual effect fields dominate when present.
    local effect = dmg * math.max(chance, 0.01) * math.max(duration, 1)
    local score = effect + rarity * 0.25

    return {
        UUID = tostring(uuid),
        RawUUID = uuid,
        Stone = stone,
        Id = id,
        Type = stone.Type,
        Rarity = rarity,
        DMG = dmg,
        Chance = chance,
        Duration = duration,
        Score = score,
    }
end

local function stoneRows()
    local rows = {}
    for uuid, stone in pairs(stones()) do
        local info = stoneInfo(uuid, stone)
        if info then table.insert(rows, info) end
    end

    table.sort(rows, function(a,b)
        if a.Score ~= b.Score then return a.Score > b.Score end
        if a.Rarity ~= b.Rarity then return a.Rarity > b.Rarity end
        return a.UUID < b.UUID
    end)
    return rows
end

local function enchantCost(gearRarityValue, stoneRarityValue)
    if type(EnchantmentUtil) == "table"
        and type(EnchantmentUtil.GetEnchantCost) == "function"
    then
        local ok, value = pcall(function()
            return EnchantmentUtil:GetEnchantCost(gearRarityValue, stoneRarityValue)
        end)
        if ok and type(value) == "number" then return value, "API" end
    end
    return gearRarityValue * stoneRarityValue * 200, "RECOVERED_FORMULA"
end

local function waitEnchant(equipmentUUID, slotKey, stoneUUID, timeout)
    local deadline = os.clock() + (timeout or 6)
    while os.clock() < deadline do
        local item = ownedEquipment()[equipmentUUID]
        local slot = item and item.Enchantments and item.Enchantments[slotKey]
        local consumed = stones()[stoneUUID] == nil

        if type(slot) == "table" and slot.Type ~= nil and consumed then
            return true, slot
        end
        task.wait(0.05)
    end
    return false, nil
end

local function parseLines(text)
    local out = {}
    for line in string.gmatch(tostring(text or ""), "[^\r\n]+") do
        -- Fortify manager owns all non-Enchant/Cave2 fields. Strip any stale
        -- V61.24 fields before writing fresh values.
        if not string.match(line, "^Enchant")
            and not string.match(line, "^Cave2Needed=")
        then
            table.insert(out, line)
        end
    end
    return out
end

local function writeDemand(rows, stoneList, currencyBlocked)
    local existing = ""
    if type(readfile) == "function" then
        local ok, text = pcall(readfile, Manager.DEMAND_FILE)
        if ok and type(text) == "string" then existing = text end
    end

    local out = parseLines(existing)
    local eligibleEmpty = 0
    local targetSummary = {}

    for _, row in ipairs(rows) do
        if row.Include
            and row.Fortify >= Manager.MIN_KEEPER_FORTIFY
            and row.EmptySlot ~= nil
            and row.Rarity ~= nil
        then
            eligibleEmpty += row.EmptySlots
            table.insert(targetSummary,
                row.Slot .. ":" .. tostring(row.Item.ID)
                    .. ":empty=" .. tostring(row.EmptySlots)
                    .. ":power=" .. tostring(row.Power)
            )
        end
    end

    local usable = #stoneList
    local missing = eligibleEmpty > 0 and usable == 0 and 1 or 0
    local cave2 = missing > 0 and not currencyBlocked

    table.insert(out, "EnchantEligibleEmptySlots=" .. tostring(eligibleEmpty))
    table.insert(out, "EnchantUsableStones=" .. tostring(usable))
    table.insert(out, "EnchantStoneMissing=" .. tostring(missing))
    table.insert(out, "EnchantCurrencyBlocked=" .. tostring(currencyBlocked == true))
    table.insert(out, "Cave2Needed=" .. tostring(cave2))
    table.insert(out, "EnchantTargets=" .. table.concat(targetSummary, ";"))

    if type(writefile) == "function" then
        pcall(writefile, Manager.DEMAND_FILE, table.concat(out, "\n"))
    end

    return {
        EligibleEmpty = eligibleEmpty,
        UsableStones = usable,
        Missing = missing,
        Cave2Needed = cave2,
    }
end

local function chooseTarget(rows)
    for _, row in ipairs(rows) do
        if row.Include
            and row.Fortify >= Manager.MIN_KEEPER_FORTIFY
            and row.EmptySlot ~= nil
            and row.Rarity ~= nil
        then
            return row
        end
    end
end

function Manager.Run()
    lines = {
        "Version=" .. Manager.VERSION,
        "PlaceId=" .. tostring(game.PlaceId),
        "StartedUnix=" .. tostring(os.time()),
        "MinKeeperFortify=" .. tostring(Manager.MIN_KEEPER_FORTIFY),
        "MaxActions=" .. tostring(Manager.MAX_ACTIONS_PER_LOBBY),
        "CurrencyReserve=" .. tostring(Manager.CURRENCY1_RESERVE),
    }

    if type(DataUtil) ~= "table"
        or type(EquipmentUtil) ~= "table"
        or type(EnchantmentUtil) ~= "table"
        or not EquipmentRE
    then
        add("Result=MODULES_UNAVAILABLE")
        save()
        return false, "MODULES_UNAVAILABLE"
    end

    local rows = targetRows()
    local availableStones = stoneRows()

    for _, row in ipairs(rows) do
        add(
            "POLICY Slot=" .. row.Slot
                .. " ID=" .. tostring(row.Item.ID)
                .. " Power=" .. tostring(row.Power)
                .. " Fortify=" .. tostring(row.Fortify)
                .. " EnchantSlots=" .. tostring(row.TotalSlots)
                .. " Empty=" .. tostring(row.EmptySlots)
                .. " Filled=" .. tostring(row.FilledSlots)
                .. " Include=" .. tostring(row.Include)
                .. " Reason=" .. tostring(row.Reason)
        )
    end

    for _, stone in ipairs(availableStones) do
        add(
            "STONE ID=" .. tostring(stone.Id)
                .. " UUID=" .. tostring(stone.UUID)
                .. " Type=" .. tostring(stone.Type)
                .. " Rarity=" .. tostring(stone.Rarity)
                .. " DMG=" .. tostring(stone.DMG)
                .. " Chance=" .. tostring(stone.Chance)
                .. " Duration=" .. tostring(stone.Duration)
                .. " Score=" .. string.format("%.4f", stone.Score)
        )
    end

    local target = chooseTarget(rows)
    local stone = availableStones[1]
    local actions = 0
    local failures = 0
    local currencyBlocked = false

    if target and stone then
        local cost, source = enchantCost(target.Rarity, stone.Rarity)
        add(
            "SELECT Target=" .. tostring(target.Item.ID)
                .. " Slot=" .. tostring(target.Slot)
                .. " EnchantSlot=" .. tostring(target.EmptySlot)
                .. " Power=" .. tostring(target.Power)
                .. " Stone=" .. tostring(stone.Id)
                .. " StoneUUID=" .. tostring(stone.UUID)
                .. " Cost=" .. tostring(cost)
                .. " CostSource=" .. tostring(source)
        )

        if currency1() - cost < Manager.CURRENCY1_RESERVE then
            currencyBlocked = true
            add(
                "ENCHANT_STOP Reason=CURRENCY_RESERVE Have=" .. tostring(currency1())
                    .. " Cost=" .. tostring(cost)
                    .. " Reserve=" .. tostring(Manager.CURRENCY1_RESERVE)
            )
        else
            -- Last-second server-state validation. Never overwrite a slot that
            -- became populated and never use a stone that disappeared.
            local latest = ownedEquipment()[target.RawUUID]
            local latestSlot = latest and latest.Enchantments and latest.Enchantments[target.EmptySlot]
            local latestStone = stones()[stone.RawUUID]

            if type(latest) ~= "table"
                or type(latestSlot) ~= "table"
                or latestSlot.Type ~= nil
                or latestStone == nil
            then
                add("ENCHANT_STOP Reason=STALE_TARGET_OR_STONE")
                failures += 1
            else
                local beforeCurrency = currency1()
                local beforePower = officialPower(target.RawUUID)

                add(
                    "ENCHANT_START Equipment=" .. target.UUID
                        .. " Slot=" .. tostring(target.EmptySlot)
                        .. " Stone=" .. stone.UUID
                )

                local okFire, fireErr = pcall(function()
                    EquipmentRE:FireServer(
                        "Enchant",
                        target.RawUUID,
                        target.EmptySlot,
                        stone.RawUUID
                    )
                end)

                if not okFire then
                    add("ENCHANT_FIRE_FAILED Err=" .. tostring(fireErr))
                    failures += 1
                else
                    local verified, installed = waitEnchant(
                        target.RawUUID,
                        target.EmptySlot,
                        stone.RawUUID,
                        6
                    )
                    task.wait(0.10)

                    local afterCurrency = currency1()
                    local afterPower = officialPower(target.RawUUID)
                    add(
                        "ENCHANT_RESULT Verified=" .. tostring(verified)
                            .. " Type=" .. tostring(installed and installed.Type)
                            .. " ID=" .. tostring(installed and installed.Id)
                            .. " Currency=" .. tostring(beforeCurrency)
                            .. "->" .. tostring(afterCurrency)
                            .. " CurrencyDelta=" .. tostring(afterCurrency - beforeCurrency)
                            .. " Power=" .. tostring(beforePower)
                            .. "->" .. tostring(afterPower)
                            .. " PowerGain=" .. tostring(afterPower - beforePower)
                            .. " StoneConsumed=" .. tostring(stones()[stone.RawUUID] == nil)
                    )

                    if verified then
                        actions = 1
                    else
                        failures += 1
                    end
                end
            end
        end
    elseif not target then
        add("ENCHANT_STOP Reason=NO_ELIGIBLE_EMPTY_KEEPER_SLOT")
    else
        add("ENCHANT_STOP Reason=NO_USABLE_STONE")
    end

    -- Recalculate AFTER any mutation. This is the authoritative Cave2 demand:
    -- an actual +4 keeper still has an empty slot AND no usable stone remains.
    local finalRows = targetRows()
    local finalStones = stoneRows()
    local demand = writeDemand(finalRows, finalStones, currencyBlocked)

    add("Actions=" .. tostring(actions))
    add("Failures=" .. tostring(failures))
    add("EligibleEmptySlots=" .. tostring(demand.EligibleEmpty))
    add("UsableStones=" .. tostring(demand.UsableStones))
    add("EnchantStoneMissing=" .. tostring(demand.Missing))
    add("Cave2Needed=" .. tostring(demand.Cave2Needed))
    add("Result=" .. (failures == 0 and "OK" or "PARTIAL"))
    save()

    status(
        "Done | actions=" .. tostring(actions)
            .. " empty=" .. tostring(demand.EligibleEmpty)
            .. " stones=" .. tostring(demand.UsableStones)
            .. " cave2=" .. tostring(demand.Cave2Needed)
    )

    return failures == 0, {
        Actions = actions,
        Failures = failures,
        EligibleEmpty = demand.EligibleEmpty,
        UsableStones = demand.UsableStones,
        Cave2Needed = demand.Cave2Needed,
    }
end

getgenv().IronSoulEnchantManager = Manager
return Manager
