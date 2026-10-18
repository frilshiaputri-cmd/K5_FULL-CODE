--========================================================--
-- IRON SOUL - PET ACQUISITION MANAGER V61.25
--
-- One bounded Lobby pass. Restores the validated V20 bridge that was lost
-- from the later lightweight Lobby pet pass:
--   claim completed hatch -> start best owned eggs -> EquipBest.
--
-- NO GUI / NO CLICKING / NO POLLING LOOP / NO PAID PET ACTION.
--========================================================--

local PetManager = {}
PetManager.VERSION = "V61.25"
PetManager.LOG_FILE = "IronSoul_PetManager_V61_25.txt"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local lines = {}

local function add(text)
    local row = tostring(text)
    table.insert(lines, row)
    print("[IronSoul Pets V61.25]", row)
end

local function save()
    if type(writefile) == "function" then
        pcall(writefile, PetManager.LOG_FILE, table.concat(lines, "\n"))
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
    local obj = findByName(ReplicatedStorage, name, "ModuleScript")
    if not obj then
        return nil
    end

    local ok, value = pcall(require, obj)
    return ok and value or nil
end

local DataUtil = req("DataUtil")
local PetsHatchUtil = req("PetsHatchUtil")
local PetsUtil = req("PetsUtil")

local function pdata()
    if not DataUtil or type(DataUtil.GetPlayerData) ~= "function" then
        return nil
    end

    local ok, value = pcall(function()
        return DataUtil:GetPlayerData(LocalPlayer)
    end)

    return ok and type(value) == "table" and value or nil
end

local function countTable(t)
    local n = 0
    if type(t) == "table" then
        for _ in pairs(t) do
            n += 1
        end
    end
    return n
end

local function waitUntil(fn, timeout, step)
    local deadline = os.clock() + (timeout or 4)
    step = step or 0.06

    while os.clock() < deadline do
        local ok, value = pcall(fn)
        if ok and value then
            return value
        end
        task.wait(step)
    end
end

local function getOwnedPets()
    if PetsUtil and type(PetsUtil.GetOwnedPets) == "function" then
        local ok, value = pcall(function()
            return PetsUtil:GetOwnedPets(LocalPlayer)
        end)

        if ok and type(value) == "table" then
            return value
        end
    end

    local d = pdata()
    local owned = d and d.Pets and d.Pets.Owned or {}
    local result = {}

    for uid, pet in pairs(owned) do
        if type(pet) == "table" then
            local copy = {}
            for k, v in pairs(pet) do
                copy[k] = v
            end
            if copy.UID == nil then
                copy.UID = uid
            end
            table.insert(result, copy)
        end
    end

    return result
end

local function getEquippedPets()
    if PetsUtil and type(PetsUtil.GetEquippedPets) == "function" then
        local ok, value = pcall(function()
            return PetsUtil:GetEquippedPets(LocalPlayer)
        end)

        if ok and type(value) == "table" then
            return value
        end
    end

    local d = pdata()
    return d and d.Pets and d.Pets.Equipped or {}
end

local function getOwnedEggs()
    local d = pdata()
    local hatch = d and d.PetHatch or {}
    return type(hatch.Egg) == "table" and hatch.Egg or {}
end

local function getSlotCount()
    if PetsHatchUtil and type(PetsHatchUtil.GetSlotCount) == "function" then
        local ok, value = pcall(function()
            return PetsHatchUtil:GetSlotCount(LocalPlayer)
        end)

        if ok and type(value) == "number" and value > 0 then
            return math.floor(value)
        end
    end

    return 3
end

local function getSlotData(index)
    if PetsHatchUtil and type(PetsHatchUtil.GetSlotData) == "function" then
        local ok, value = pcall(function()
            return PetsHatchUtil:GetSlotData(LocalPlayer, index)
        end)

        if ok then
            return value
        end
    end

    local d = pdata()
    local slots = d and d.PetHatch and d.PetHatch.Slots or {}
    return slots[index] or slots[tostring(index)]
end

-- V20-validated signature: IsCompleted(slotData), NOT (player, slotIndex).
local function isCompleted(slotData)
    if not PetsHatchUtil or type(PetsHatchUtil.IsCompleted) ~= "function" then
        return false
    end

    local ok, value = pcall(function()
        return PetsHatchUtil:IsCompleted(slotData)
    end)

    return ok and value == true
end

local function eggRarity(eggId)
    if PetsHatchUtil and type(PetsHatchUtil.GetEggCfg) == "function" then
        local ok, cfg = pcall(function()
            return PetsHatchUtil:GetEggCfg(eggId)
        end)

        if ok and type(cfg) == "table" then
            return tonumber(cfg.Rarity) or 0
        end
    end

    return 0
end

local function claimReadySlots()
    local remote = PetsHatchUtil and PetsHatchUtil.RemoteEvent
    if not remote then
        add("Claim=SKIP_NO_HATCH_REMOTE")
        return 0
    end

    local claimed = 0

    for index = 1, getSlotCount() do
        local slot = getSlotData(index)

        if slot and slot.EggId and isCompleted(slot) then
            local beforeCount = #getOwnedPets()
            add(
                "CLAIM_START slot=" .. tostring(index)
                .. " EggId=" .. tostring(slot.EggId)
                .. " EggUUID=" .. tostring(slot.EggUUID)
            )

            local okFire, err = pcall(function()
                remote:FireServer("Claim", index)
            end)

            if not okFire then
                add("CLAIM_REMOTE_ERROR slot=" .. tostring(index) .. " err=" .. tostring(err))
            else
                local verified = waitUntil(function()
                    local latest = getSlotData(index)
                    return latest == nil and #getOwnedPets() > beforeCount
                end, 6, 0.06)

                if verified then
                    claimed += 1
                    add("CLAIM_VERIFIED slot=" .. tostring(index))
                else
                    add("CLAIM_UNVERIFIED slot=" .. tostring(index))
                end
            end
        end
    end

    return claimed
end

local function freeSlots()
    local result = {}
    for index = 1, getSlotCount() do
        if getSlotData(index) == nil then
            table.insert(result, index)
        end
    end
    return result
end

local function startOwnedEggs()
    local remote = PetsHatchUtil and PetsHatchUtil.RemoteEvent
    if not remote then
        add("StartHatch=SKIP_NO_HATCH_REMOTE")
        return 0
    end

    local eggs = getOwnedEggs()
    local eggRows = {}

    for uuid, egg in pairs(eggs) do
        if type(uuid) == "string" and type(egg) == "table" and egg.EggId then
            table.insert(eggRows, {
                UUID = uuid,
                Egg = egg,
                Rarity = eggRarity(egg.EggId),
            })
        end
    end

    table.sort(eggRows, function(a, b)
        if a.Rarity ~= b.Rarity then
            return a.Rarity > b.Rarity
        end
        return tostring(a.UUID) < tostring(b.UUID)
    end)

    local slots = freeSlots()
    local actions = math.min(#slots, #eggRows)
    local started = 0

    if #eggRows == 0 then
        add("StartHatch=WAIT_EGG")
        return 0
    end

    if #slots == 0 then
        add("StartHatch=ALL_SLOTS_OCCUPIED")
        return 0
    end

    for i = 1, actions do
        local index = slots[i]
        local row = eggRows[i]

        add(
            "START_HATCH slot=" .. tostring(index)
            .. " EggId=" .. tostring(row.Egg.EggId)
            .. " UUID=" .. tostring(row.UUID)
            .. " Rarity=" .. tostring(row.Rarity)
        )

        local okFire, err = pcall(function()
            remote:FireServer("StartHatch", index, row.UUID)
        end)

        if not okFire then
            add("START_REMOTE_ERROR slot=" .. tostring(index) .. " err=" .. tostring(err))
        else
            local verified = waitUntil(function()
                local latest = getSlotData(index)
                return latest and latest.EggUUID == row.UUID
            end, 4, 0.05)

            if verified then
                started += 1
                local latest = getSlotData(index)
                add(
                    "START_VERIFIED slot=" .. tostring(index)
                    .. " StartTime=" .. tostring(latest and latest.StartTime)
                )
            else
                add("START_UNVERIFIED slot=" .. tostring(index))
            end
        end
    end

    return started
end

local function equipBest()
    local owned = getOwnedPets()
    if #owned == 0 then
        add("EquipBest=WAIT_PET")
        return false
    end

    local remote = PetsUtil and PetsUtil.RemoteEvent
    if not remote then
        add("EquipBest=SKIP_NO_REMOTE")
        return false
    end

    local before = countTable(getEquippedPets())
    local okFire, err = pcall(function()
        remote:FireServer("EquipBest")
    end)

    if not okFire then
        add("EquipBest=REMOTE_ERROR " .. tostring(err))
        return false
    end

    local verified = waitUntil(function()
        return countTable(getEquippedPets()) > 0
    end, 5, 0.08)

    add(
        "EquipBest=" .. tostring(verified ~= nil)
        .. " EquippedBefore=" .. tostring(before)
        .. " EquippedAfter=" .. tostring(countTable(getEquippedPets()))
    )

    return verified ~= nil
end

function PetManager.Run()
    lines = {
        "Version=" .. PetManager.VERSION,
        "PlaceId=" .. tostring(game.PlaceId),
        "StartedUnix=" .. tostring(os.time()),
    }

    if game.PlaceId ~= 117533937949084 then
        add("Result=NOT_LOBBY")
        save()
        return true, "NOT_LOBBY"
    end

    if not DataUtil or not PetsHatchUtil or not PetsUtil then
        add("DataUtil=" .. tostring(DataUtil ~= nil))
        add("PetsHatchUtil=" .. tostring(PetsHatchUtil ~= nil))
        add("PetsUtil=" .. tostring(PetsUtil ~= nil))
        add("Result=MODULE_MISSING")
        save()
        return false, "MODULE_MISSING"
    end

    local d = pdata()
    if not d then
        add("Result=PLAYERDATA_UNAVAILABLE")
        save()
        return false, "PLAYERDATA_UNAVAILABLE"
    end

    add("OwnedPetsBefore=" .. tostring(#getOwnedPets()))
    add("EquippedPetsBefore=" .. tostring(countTable(getEquippedPets())))
    add("OwnedEggsBefore=" .. tostring(countTable(getOwnedEggs())))
    add("HatchSlots=" .. tostring(getSlotCount()))

    for index = 1, getSlotCount() do
        local slot = getSlotData(index)
        if slot then
            add(
                "Slot" .. tostring(index)
                .. " EggId=" .. tostring(slot.EggId)
                .. " EggUUID=" .. tostring(slot.EggUUID)
                .. " StartTime=" .. tostring(slot.StartTime)
                .. " Completed=" .. tostring(isCompleted(slot))
            )
        else
            add("Slot" .. tostring(index) .. "=EMPTY")
        end
    end

    local claimed = claimReadySlots()
    local started = startOwnedEggs()
    local equipped = equipBest()

    add("Claimed=" .. tostring(claimed))
    add("HatchesStarted=" .. tostring(started))
    add("OwnedPetsAfter=" .. tostring(#getOwnedPets()))
    add("EquippedPetsAfter=" .. tostring(countTable(getEquippedPets())))
    add("OwnedEggsAfter=" .. tostring(countTable(getOwnedEggs())))

    if #getOwnedPets() > 0 then
        add("State=PET_READY")
    elseif countTable(getOwnedEggs()) > 0 or started > 0 then
        add("State=HATCHING")
    else
        add("State=WAIT_EGG")
    end

    add("Result=PASS")
    save()
    return true, "PASS"
end

getgenv().IronSoulPetManager = PetManager
return PetManager
