--========================================================--
-- IRON SOUL - POST-FORGE UPGRADE PREFLIGHT V61.30
--
-- Exact order:
--   historical Forge/EquipBest
--     -> pet acquisition bridge
--     -> Blessing/Fortify manager (creates exact material demand)
--     -> Smart Enchant manager (creates exact stone demand)
--     -> demand-driven Gold Grocery
--     -> if Grocery bought a blocker: re-run Fortify + Enchant once
--     -> demand-driven SMART Cave
--     -> Hell-first progression planner
--     -> historical Story only if Hell cannot handle the account yet
--========================================================--

local Preflight = {}
Preflight.VERSION = "V61.30"
Preflight.LOG_FILE = "IronSoul_UpgradePreflight_V61_30.txt"

local function write(lines)
    if type(writefile) == "function" then
        pcall(writefile, Preflight.LOG_FILE, table.concat(lines, "\n"))
    end
end

local function status(text)
    local fn = getgenv().IronSoulStatus
    if type(fn) == "function" then
        pcall(fn, "Upgrade | " .. tostring(text))
    end
    print("[IronSoul Upgrade V61.30]", tostring(text))
end

local function loadRunner(path)
    local loadRaw = getgenv().IronSoulLoadRaw
    if type(loadRaw) ~= "function" then return nil, "LOADER_UNAVAILABLE" end
    local ok, value = loadRaw(path)
    if not ok or type(value) ~= "table" or type(value.Run) ~= "function" then
        return nil, value
    end
    return value
end

local function runChecked(lines, label, module)
    local ok, result, detail = pcall(module.Run)
    table.insert(lines, label .. "Pcall=" .. tostring(ok))
    table.insert(lines, label .. "Ok=" .. tostring(result))
    table.insert(lines, label .. "Detail=" .. tostring(detail))
    return ok, result, detail
end

function Preflight.Run()
    local lines = {
        "Version=" .. Preflight.VERSION,
        "StartedUnix=" .. tostring(os.time()),
        "PlaceId=" .. tostring(game.PlaceId),
    }

    if type(getgenv().IronSoulLoadRaw) ~= "function" then
        table.insert(lines, "Result=LOADER_UNAVAILABLE")
        write(lines)
        return false, "LOADER_UNAVAILABLE"
    end

    -- Pet acquisition remains intentionally non-blocking.
    local petManager = loadRunner("systems/pet_manager.lua")
    if petManager then
        local ok, petOk, petDetail = runChecked(lines, "PetManager", petManager)
        if not ok or petOk ~= true then
            status("Pet bridge unavailable; continuing core progression")
        end
    else
        table.insert(lines, "PetManager=LOAD_FAILED")
    end

    local fortify, fortifyErr = loadRunner("systems/fortify_manager.lua")
    if not fortify then
        table.insert(lines, "Fortify=LOAD_FAILED " .. tostring(fortifyErr))
        table.insert(lines, "Result=FAIL_CLOSED_TO_STORY")
        write(lines)
        return false, "FORTIFY_LOAD_FAILED"
    end

    local okFortify, fortifyOk = runChecked(lines, "Fortify", fortify)
    if not okFortify or fortifyOk ~= true then
        table.insert(lines, "Result=FAIL_CLOSED_TO_STORY")
        write(lines)
        status("Fortify unavailable -> Story")
        return false, "FORTIFY_NOT_READY"
    end

    local enchant, enchantErr = loadRunner("systems/enchant_manager.lua")
    if not enchant then
        table.insert(lines, "Enchant=LOAD_FAILED " .. tostring(enchantErr))
        table.insert(lines, "Result=FAIL_CLOSED_TO_STORY")
        write(lines)
        return false, "ENCHANT_LOAD_FAILED"
    end

    local okEnchant, enchantOk = runChecked(lines, "Enchant", enchant)
    if not okEnchant or enchantOk ~= true then
        table.insert(lines, "Result=FAIL_CLOSED_TO_STORY")
        write(lines)
        status("Enchant unavailable -> Story")
        return false, "ENCHANT_NOT_READY"
    end

    -- Grocery is non-blocking. It may solve an exact Fortify/Enchant blocker
    -- before we spend a Ticket1. No random stock is purchased.
    local shop = loadRunner("systems/shop_manager.lua")
    local shopPurchased = 0
    if shop then
        local okShop, shopOk, shopDetail = runChecked(lines, "Shop", shop)
        if okShop and shopOk == true and type(shopDetail) == "table" then
            shopPurchased = tonumber(shopDetail.Purchased) or 0
            table.insert(lines, "ShopPurchased=" .. tostring(shopPurchased))
            table.insert(lines, "ShopSpent=" .. tostring(shopDetail.Spent or 0))
        else
            table.insert(lines, "ShopNonBlocking=true")
            status("Shop unavailable; continuing without purchase")
        end
    else
        table.insert(lines, "Shop=LOAD_FAILED_NONBLOCKING")
    end

    -- If Grocery changed resources, immediately consume/re-evaluate them so
    -- Cave decisions use fresh demand instead of the pre-purchase blocker.
    if shopPurchased > 0 then
        local okFortify2, fortifyOk2 = runChecked(lines, "FortifyAfterShop", fortify)
        local okEnchant2, enchantOk2 = runChecked(lines, "EnchantAfterShop", enchant)

        if not okFortify2 or fortifyOk2 ~= true or not okEnchant2 or enchantOk2 ~= true then
            -- Purchased resources are safe, but demand is no longer trustworthy
            -- enough to spend a Cave ticket. Skip paid Cave and let Hell/Story run.
            table.insert(lines, "PaidCaveSkipped=POST_SHOP_DEMAND_UNTRUSTED")
        else
            table.insert(lines, "PostShopDemandFresh=true")
        end
    end

    local caveAllowed = true
    for _, row in ipairs(lines) do
        if row == "PaidCaveSkipped=POST_SHOP_DEMAND_UNTRUSTED" then
            caveAllowed = false
            break
        end
    end

    if caveAllowed then
        local planner = loadRunner("systems/cave_planner.lua")
        if planner then
            local okPlan, handled, detail = runChecked(lines, "CavePlanner", planner)
            if okPlan and handled == true then
                table.insert(lines, "Result=CAVE")
                write(lines)
                status("SMART Cave handled | " .. tostring(detail))
                return true, detail
            end
        else
            table.insert(lines, "CavePlanner=LOAD_FAILED")
        end
    end

    -- Hell is now the default free farming/progression mode. Its own V61.30
    -- policy may launch exactly one Normal unlock bridge when that clear opens
    -- the next visible Hell stage; otherwise it stays in Hell.
    local hell = loadRunner("systems/hell_planner.lua")
    if hell then
        local okHell, handledHell, detailHell = runChecked(lines, "HellPlanner", hell)
        if okHell and handledHell == true then
            table.insert(lines, "Result=HELL_OR_UNLOCK_BRIDGE")
            write(lines)
            status("Hell-first handled | " .. tostring(detailHell))
            return true, detailHell
        end
    else
        table.insert(lines, "HellPlanner=LOAD_FAILED")
    end

    table.insert(lines, "Result=STORY_FALLBACK")
    write(lines)
    status("Hell/Cave unavailable -> historical Story fallback")
    return false, "STORY_FALLBACK"
end

getgenv().IronSoulUpgradePreflight = Preflight
return Preflight
