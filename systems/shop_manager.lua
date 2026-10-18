--========================================================--
-- IRON SOUL - DEMAND-DRIVEN GOLD GROCERY MANAGER V61.30
--
-- Live V61.29 source proof:
--   client BuyItem -> RemoteEvent:FireServer("BuyShopItem", shopId, itemCfgId)
--   server validates rotation/stock/currency/daily cap, grants item, and updates
--   BuyCount + DailyPurchaseCount.
--
-- Policy:
--   * Gold shop only for now (Currency1).
--   * buy ONLY an exact current upgrade blocker;
--   * CrystalShards blocker first;
--   * EnchantedStone blocker second;
--   * no manual refresh purchases;
--   * preserve Currency1 reserve;
--   * max 3 purchases per Lobby pass;
--   * verify every purchase from replicated PlayerData before continuing.
--========================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local ShopManager = {}

ShopManager.VERSION = "V61.30"
ShopManager.LOG_FILE = "IronSoul_ShopManager_V61_30.txt"
ShopManager.DEMAND_FILE = "IronSoul_UpgradeDemand_V61_23.txt"
ShopManager.CURRENCY_RESERVE = 20000
ShopManager.MAX_PURCHASES_PER_PASS = 3
ShopManager.BUY_VERIFY_TIMEOUT = 2.5
ShopManager.MIN_BUY_INTERVAL = 0.40

local function status(text)
    local fn = getgenv().IronSoulStatus
    if type(fn) == "function" then
        pcall(fn, "Shop | " .. tostring(text))
    end
    print("[IronSoul Shop V61.30]", tostring(text))
end

local function write(lines)
    if type(writefile) == "function" then
        pcall(writefile, ShopManager.LOG_FILE, table.concat(lines, "\n"))
    end
end

local function parse(text)
    local out = {}
    for line in string.gmatch(tostring(text or ""), "[^\r\n]+") do
        local k, v = string.match(line, "^([^=]+)=(.*)$")
        if k then out[k] = v end
    end
    return out
end

local function readDemand()
    if type(readfile) ~= "function" then return {} end
    if type(isfile) == "function" and not isfile(ShopManager.DEMAND_FILE) then
        return {}
    end
    local ok, text = pcall(readfile, ShopManager.DEMAND_FILE)
    return ok and type(text) == "string" and parse(text) or {}
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
local ConsumableShopUtil = req("ConsumableShopUtil")
local ResShopGold = req("ResShop_Gold")

local function pdata()
    if type(DataUtil) ~= "table" or type(DataUtil.GetPlayerData) ~= "function" then
        return nil
    end
    local ok, value = pcall(function()
        return DataUtil:GetPlayerData(LocalPlayer)
    end)
    return ok and type(value) == "table" and value or nil
end

local function currency1(data)
    return data and data.Currency and tonumber(data.Currency.Currency1) or 0
end

local function goldData(data)
    return data and data.GoldShop or nil
end

local function stockLeft(data, configId)
    local shop = goldData(data)
    if type(shop) ~= "table" then return 0 end
    local limit = type(shop.StockLimit) == "table"
        and tonumber(shop.StockLimit[configId]) or 0
    local bought = type(shop.BuyCount) == "table"
        and tonumber(shop.BuyCount[configId]) or 0
    return math.max(0, limit - bought)
end

local function dailyLeft(data)
    local shop = goldData(data)
    if type(shop) ~= "table" then return 0 end
    return math.max(0, 15 - (tonumber(shop.DailyPurchaseCount) or 0))
end

local function crystalAmount(data, id)
    return data and data.Crystals and tonumber(data.Crystals[id]) or 0
end

local function enchantedStoneCount(data)
    local n = 0
    local owned = data and data.EnchantedStone and data.EnchantedStone.Owned
    if type(owned) == "table" then
        for _ in pairs(owned) do n += 1 end
    end
    return n
end

local function goldConfigs()
    local out = {}
    if type(ResShopGold) ~= "table" then return out end

    local keys = type(ResShopGold.__index) == "table"
        and ResShopGold.__index or nil

    if keys then
        for _, id in ipairs(keys) do
            local cfg = ResShopGold[id]
            if type(cfg) == "table" then table.insert(out, cfg) end
        end
    else
        for _, cfg in pairs(ResShopGold) do
            if type(cfg) == "table" and cfg.Id then table.insert(out, cfg) end
        end
    end

    return out
end

local GOLD_CONFIGS = goldConfigs()

local function findCurrentItem(data, predicate)
    local rows = {}
    for _, cfg in ipairs(GOLD_CONFIGS) do
        local id = tostring(cfg.Id or "")
        local left = stockLeft(data, id)
        if left > 0 and predicate(cfg) then
            table.insert(rows, {Cfg=cfg, Left=left})
        end
    end

    table.sort(rows, function(a,b)
        local ap = tonumber(a.Cfg.Price) or math.huge
        local bp = tonumber(b.Cfg.Price) or math.huge
        if ap ~= bp then return ap < bp end
        return tostring(a.Cfg.Id) < tostring(b.Cfg.Id)
    end)

    return rows[1]
end

local function boolValue(v)
    return tostring(v) == "true"
end

local function choosePurchase(data, demand)
    local missingShards = tonumber(demand.CrystalShardsMissing or 0) or 0
    if missingShards > 0 then
        local row = findCurrentItem(data, function(cfg)
            return tostring(cfg.ItemType) == "Crystals"
                and tostring(cfg.ItemId) == "CrystalShards"
        end)
        if row then
            return {
                Kind = "FORTIFY_CRYSTAL_BLOCKER",
                Row = row,
                Missing = missingShards,
                Before = crystalAmount(data, "CrystalShards"),
            }
        end
    end

    local cave2Needed = boolValue(demand.Cave2Needed)
    local enchantMissing = tonumber(demand.EnchantStoneMissing or 0) or 0
    local eligibleEmpty = tonumber(demand.EnchantEligibleEmptySlots or 0) or 0
    if cave2Needed and enchantMissing > 0 and eligibleEmpty > 0 then
        local row = findCurrentItem(data, function(cfg)
            return tostring(cfg.ItemType) == "EnchantedStone"
        end)
        if row then
            return {
                Kind = "ENCHANT_STONE_BLOCKER",
                Row = row,
                Missing = 1,
                Before = enchantedStoneCount(data),
            }
        end
    end
end

local function measure(data, chosen)
    if chosen.Kind == "FORTIFY_CRYSTAL_BLOCKER" then
        return crystalAmount(data, "CrystalShards")
    elseif chosen.Kind == "ENCHANT_STONE_BLOCKER" then
        return enchantedStoneCount(data)
    end
    return 0
end

local function buyOnce(chosen, lines)
    if not ConsumableShopUtil or not ConsumableShopUtil.RemoteEvent then
        return false, "SHOP_REMOTE_MISSING"
    end

    local cfg = chosen.Row.Cfg
    local configId = tostring(cfg.Id)
    local price = tonumber(cfg.Price) or 0
    local itemCount = tonumber(cfg.ItemCount) or 1

    local beforeData = pdata()
    if not beforeData then return false, "PLAYERDATA_MISSING" end
    local beforeCurrency = currency1(beforeData)
    local beforeValue = measure(beforeData, chosen)
    local beforeStock = stockLeft(beforeData, configId)
    local beforeDaily = dailyLeft(beforeData)

    if beforeStock <= 0 then return false, "OUT_OF_STOCK" end
    if beforeDaily <= 0 then return false, "DAILY_LIMIT" end
    if beforeCurrency - price < ShopManager.CURRENCY_RESERVE then
        return false, "CURRENCY_RESERVE"
    end

    table.insert(lines,
        "BUY_ATTEMPT=" .. tostring(configId)
            .. ",Item=" .. tostring(cfg.ItemId)
            .. ",Type=" .. tostring(cfg.ItemType)
            .. ",Count=" .. tostring(itemCount)
            .. ",Price=" .. tostring(price)
            .. ",StockBefore=" .. tostring(beforeStock)
            .. ",CurrencyBefore=" .. tostring(beforeCurrency)
            .. ",ValueBefore=" .. tostring(beforeValue)
    )

    local ok, err = pcall(function()
        ConsumableShopUtil.RemoteEvent:FireServer(
            "BuyShopItem",
            "Gold",
            configId
        )
    end)
    if not ok then return false, "REMOTE_ERROR:" .. tostring(err) end

    local deadline = os.clock() + ShopManager.BUY_VERIFY_TIMEOUT
    while os.clock() < deadline do
        task.wait(0.08)
        local afterData = pdata()
        if afterData then
            local afterCurrency = currency1(afterData)
            local afterValue = measure(afterData, chosen)
            local afterStock = stockLeft(afterData, configId)

            local stockMoved = afterStock < beforeStock
            local currencyMoved = afterCurrency <= beforeCurrency - price
            local valueMoved = afterValue > beforeValue

            if stockMoved and currencyMoved and valueMoved then
                table.insert(lines,
                    "BUY_VERIFIED=" .. tostring(configId)
                        .. ",Currency=" .. tostring(beforeCurrency) .. "->" .. tostring(afterCurrency)
                        .. ",Value=" .. tostring(beforeValue) .. "->" .. tostring(afterValue)
                        .. ",Stock=" .. tostring(beforeStock) .. "->" .. tostring(afterStock)
                )
                return true, {
                    ConfigId = configId,
                    ItemId = tostring(cfg.ItemId),
                    ItemType = tostring(cfg.ItemType),
                    ItemCount = itemCount,
                    Price = price,
                    ValueBefore = beforeValue,
                    ValueAfter = afterValue,
                }
            end
        end
    end

    return false, "VERIFY_TIMEOUT"
end

function ShopManager.Run()
    local config = getgenv().IronSoulConfig or {}
    if config.SHOP_AUTO == false then return true, {Purchased=0, Reason="DISABLED"} end

    local lines = {
        "Version=" .. ShopManager.VERSION,
        "StartedUnix=" .. tostring(os.time()),
        "PlaceId=" .. tostring(game.PlaceId),
        "CurrencyReserve=" .. tostring(ShopManager.CURRENCY_RESERVE),
        "MaxPurchasesPerPass=" .. tostring(ShopManager.MAX_PURCHASES_PER_PASS),
    }

    if not DataUtil or not ConsumableShopUtil or not ConsumableShopUtil.RemoteEvent or not ResShopGold then
        table.insert(lines, "Result=MISSING_MODULE")
        write(lines)
        return false, {Purchased=0, Reason="MISSING_MODULE"}
    end

    local purchased = 0
    local spent = 0
    local lastKind = "NONE"

    while purchased < ShopManager.MAX_PURCHASES_PER_PASS do
        local data = pdata()
        if not data then break end
        local demand = readDemand()
        local chosen = choosePurchase(data, demand)
        if not chosen then
            table.insert(lines, "Decision=NO_EXACT_BLOCKER_IN_CURRENT_GOLD_ROTATION")
            break
        end

        lastKind = chosen.Kind
        local cfg = chosen.Row.Cfg
        local itemCount = tonumber(cfg.ItemCount) or 1
        local remainingNeed = tonumber(chosen.Missing) or 1

        -- Do not buy more packs than the exact blocker can use in this pass.
        if chosen.Kind == "FORTIFY_CRYSTAL_BLOCKER" and remainingNeed <= 0 then break end

        local ok, detail = buyOnce(chosen, lines)
        if not ok then
            table.insert(lines, "BUY_STOP=" .. tostring(detail))
            break
        end

        purchased += 1
        spent += tonumber(detail.Price) or 0
        task.wait(ShopManager.MIN_BUY_INTERVAL)

        -- Demand file is rewritten by Fortify/Enchant after this manager returns.
        -- Locally reduce the blocker so we do not overbuy multiple packs now.
        if chosen.Kind == "FORTIFY_CRYSTAL_BLOCKER" then
            local demandNow = readDemand()
            local original = tonumber(demandNow.CrystalShardsMissing or 0) or 0
            if original <= itemCount * purchased then break end
        else
            -- One stone is enough for the next Enchant action.
            break
        end
    end

    table.insert(lines, "Purchased=" .. tostring(purchased))
    table.insert(lines, "SpentCurrency1=" .. tostring(spent))
    table.insert(lines, "LastKind=" .. tostring(lastKind))
    table.insert(lines, "Result=PASS")
    write(lines)

    if purchased > 0 then
        status("bought " .. tostring(purchased) .. " exact blocker pack(s) | spent=" .. tostring(spent))
    else
        status("no exact blocker in current Gold rotation")
    end

    return true, {
        Purchased = purchased,
        Spent = spent,
        Kind = lastKind,
    }
end

getgenv().IronSoulShopManager = ShopManager
return ShopManager
