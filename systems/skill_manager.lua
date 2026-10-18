--========================================================--
-- IRON SOUL - WEAPON-AWARE SKILL TREE MANAGER V61.20.1
--
-- Live recon proved:
--   * PlayerData.SkillTree.Unlock is authoritative server-granted state;
--   * TryUnlockSkill/CanUnlockSkill are governed by Level + weapon proficiency;
--   * no ore/crystal/currency cost exists in the level-skill unlock path;
--   * historical Lobby already safely activates unlocked Sword branches using
--     RemoteEvent("ActiveSkill", class, UnlockSkillN).
--
-- Policy:
--   * NEVER invent/force a skill unlock that the server has not granted.
--   * For every weapon class present in SkillTree.Unlock, activate every
--     server-unlocked branch not yet active.
--   * Verify each activation from PlayerData.SkillTree.Active.
--   * Wait for authoritative skill data on fresh/mobile Lobby loads.
--   * Fail closed; skill maintenance must never block Lobby progression.
--========================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local SkillManager = {}

SkillManager.VERSION = "V61.20.1"
SkillManager.LOG_FILE = "IronSoul_SkillManager_V61_20.txt"
SkillManager.MAX_BRANCH = 7
SkillManager.VERIFY_TIMEOUT = 2.5
SkillManager.DATA_TIMEOUT = 12

local function status(text)
    text = tostring(text or "")

    local fn = getgenv().IronSoulStatus
    if type(fn) == "function" then
        pcall(fn, "Skills | " .. text)
    end

    print("[IronSoul Skills V61.20.1]", text)
end

local function writeLog(lines)
    if type(writefile) ~= "function" then
        return
    end

    pcall(
        writefile,
        SkillManager.LOG_FILE,
        table.concat(lines or {}, "\n")
    )
end

local function findModule(name)
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("ModuleScript") and obj.Name == name then
            return obj
        end
    end
end

local function requireModule(name)
    local module = findModule(name)
    if not module then
        return nil, "missing " .. tostring(name)
    end

    local ok, value = pcall(require, module)
    if not ok or type(value) ~= "table" then
        return nil, "require failed " .. tostring(name)
    end

    return value
end

local DataUtil
local SkillTreeUtil

local function ensureModules()
    if type(DataUtil) ~= "table" then
        local value, err = requireModule("DataUtil")
        if not value then return false, err end
        DataUtil = value
    end

    if type(SkillTreeUtil) ~= "table" then
        local value, err = requireModule("SkillTreeUtil")
        if not value then return false, err end
        SkillTreeUtil = value
    end

    if not SkillTreeUtil.RemoteEvent then
        return false, "SkillTree RemoteEvent missing"
    end

    return true
end

local function pdata()
    if type(DataUtil) ~= "table" or type(DataUtil.GetPlayerData) ~= "function" then
        return nil
    end

    local ok, value = pcall(function()
        return DataUtil:GetPlayerData(LocalPlayer)
    end)

    return ok and type(value) == "table" and value or nil
end

local function waitUntil(fn, timeout)
    local deadline = os.clock() + (tonumber(timeout) or 2)

    while os.clock() < deadline do
        local ok, value = pcall(fn)
        if ok and value then
            return value
        end
        task.wait(0.08)
    end

    return nil
end

local function sortedClasses(unlock)
    local classes = {}

    for classId, branches in pairs(unlock or {}) do
        if type(classId) == "string" and type(branches) == "table" then
            table.insert(classes, classId)
        end
    end

    table.sort(classes)
    return classes
end

local function profValue(data, classId)
    local profs = data
        and data.SkillTree
        and data.SkillTree.WpnProfs

    return type(profs) == "table" and tonumber(profs[classId]) or 0
end

local function isActive(data, classId, key)
    local active = data
        and data.SkillTree
        and data.SkillTree.Active
        and data.SkillTree.Active[classId]

    return type(active) == "table" and active[key] == true
end

function SkillManager.Run()
    local lines = {
        "Version=" .. SkillManager.VERSION,
        "PlaceId=" .. tostring(game.PlaceId),
        "StartedUnix=" .. tostring(os.time()),
    }

    local okModules, moduleErr = ensureModules()
    if not okModules then
        table.insert(lines, "Result=MODULES_UNAVAILABLE")
        table.insert(lines, "Detail=" .. tostring(moduleErr))
        writeLog(lines)
        return false, moduleErr
    end

    status("Waiting for SkillTree PlayerData")

    local data = waitUntil(function()
        local current = pdata()
        local tree = current and current.SkillTree
        local unlock = tree and tree.Unlock

        if type(unlock) == "table" then
            return current
        end
    end, SkillManager.DATA_TIMEOUT)

    local tree = data and data.SkillTree
    local unlock = tree and tree.Unlock

    if type(unlock) ~= "table" then
        table.insert(lines, "Result=NO_UNLOCK_DATA")
        writeLog(lines)
        return false, "NO_UNLOCK_DATA"
    end

    local level = tonumber(LocalPlayer:GetAttribute("LG_Level"))
        or (data.LevelData and tonumber(data.LevelData.Level))
        or 0

    table.insert(lines, "Level=" .. tostring(level))

    local activated = 0
    local failed = 0
    local already = 0
    local serverUnlocked = 0

    for _, classId in ipairs(sortedClasses(unlock)) do
        local branches = unlock[classId]
        local prof = profValue(data, classId)

        table.insert(lines, "Class=" .. tostring(classId) .. " Prof=" .. tostring(prof))

        for i = 1, SkillManager.MAX_BRANCH do
            local key = "UnlockSkill" .. tostring(i)

            if branches[key] == true then
                serverUnlocked += 1

                local current = pdata()
                if isActive(current, classId, key) then
                    already += 1
                    table.insert(lines, "  " .. key .. "=ALREADY_ACTIVE")
                else
                    status("Activate " .. tostring(classId) .. " " .. key)

                    local okFire, fireErr = pcall(function()
                        SkillTreeUtil.RemoteEvent:FireServer(
                            "ActiveSkill",
                            classId,
                            key
                        )
                    end)

                    local verified = okFire and waitUntil(function()
                        return isActive(pdata(), classId, key)
                    end, SkillManager.VERIFY_TIMEOUT)

                    if verified then
                        activated += 1
                        table.insert(lines, "  " .. key .. "=ACTIVATED")
                    else
                        failed += 1
                        table.insert(
                            lines,
                            "  " .. key .. "=FAILED fire=" .. tostring(okFire)
                                .. " err=" .. tostring(fireErr)
                        )
                    end
                end
            end
        end
    end

    table.insert(lines, "ServerUnlocked=" .. tostring(serverUnlocked))
    table.insert(lines, "AlreadyActive=" .. tostring(already))
    table.insert(lines, "Activated=" .. tostring(activated))
    table.insert(lines, "Failed=" .. tostring(failed))
    table.insert(lines, "Result=" .. (failed == 0 and "OK" or "PARTIAL"))

    writeLog(lines)

    status(
        "Done | unlocked=" .. tostring(serverUnlocked)
            .. " activated=" .. tostring(activated)
            .. " failed=" .. tostring(failed)
    )

    return true, {
        ServerUnlocked = serverUnlocked,
        AlreadyActive = already,
        Activated = activated,
        Failed = failed,
    }
end

getgenv().IronSoulSkillManager = SkillManager
return SkillManager
