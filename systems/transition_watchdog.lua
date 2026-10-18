-- IRON SOUL - V61.12 LOCAL-SAFE FAST TRANSITION WATCHDOG
--
-- Fast path policy:
--   * exact current-1 Portal* only;
--   * local only (<= 320 studs);
--   * safe pre-position BEFORE portal, never through it;
--   * native Humanoid movement + exact touch handshake;
--   * never force RoundPortal RF;
--   * success requires authoritative progression evidence;
--   * World2 never falls back to legacy far/learned recovery.

local function getPatcher()
    local loadRaw = getgenv().IronSoulLoadRaw

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
    assert(type(patcher) == "function", "V61.12 watchdog patch loader unavailable")
    return patcher
end

local baseFactory = getPatcher()({
    repository = "MUshihara/ironsoulkaitun",
    base_commit = "1d47f7f50ec8ecd92bca691b17d586d6bdecfa55",
    path = "systems/transition_watchdog.lua",
    patch_paths = {
        "systems/patches/watchdog_v61_6.patch",
        "systems/patches/watchdog_v61_6_1_hotfix.patch",
        "systems/patches/watchdog_v61_6_2_learning_guard.patch",
        "systems/patches/watchdog_v61_8_learned_fastpath.patch",
    },
})

assert(type(baseFactory) == "function", "V61.12 base watchdog factory unavailable")

return function(D)
    local old = baseFactory(D)
    assert(type(old) == "table", "V61.12 base watchdog build failed")

    local W = {}

    local ReplicatedStorage = game:GetService("ReplicatedStorage")

    local MAX_LOCAL_PORTAL_DISTANCE = 320
    local FAST_APPROACH_DISTANCE = 22
    local PRE_PORTAL_DISTANCE = 10
    local ENTER_TIMEOUT = 0.95
    local CROSS_TIMEOUT = 1.05
    local VERIFY_TIMEOUT = 0.85

    local function emit(name, detail)
        if type(D.event) == "function" then
            pcall(D.event, name, detail)
        end
    end

    local function getRoot()
        if type(D.getRoot) ~= "function" then
            return nil
        end

        local ok, value = pcall(D.getRoot)
        return ok and value or nil
    end

    local function getRegion()
        if type(D.getCurrentRegion) ~= "function" then
            return nil
        end

        local ok, value = pcall(D.getCurrentRegion)
        return ok and value or nil
    end

    local function hasObjective()
        if type(D.hasCombatObjective) ~= "function" then
            return false
        end

        local ok, value = pcall(D.hasCombatObjective)
        return ok and value == true
    end

    local function settled()
        if type(D.settlementDetected) ~= "function" then
            return false
        end

        local ok, value = pcall(D.settlementDetected)
        return ok and value == true
    end

    local function gameRound()
        if type(D.gameRound) ~= "function" then
            return nil
        end

        local ok, value = pcall(D.gameRound)
        return ok and tonumber(value) or nil
    end

    local function worldId()
        local cfg = ReplicatedStorage:FindFirstChild("GameRoundCfg")
        if cfg then
            local value = cfg:GetAttribute("WorldId")
            if value ~= nil then
                return tostring(value)
            end
        end

        local value = workspace:GetAttribute("WorldName")
        return value ~= nil and tostring(value) or "?"
    end

    local function currentPortalRows()
        local root = getRoot()
        local round = gameRound()
        local folder = workspace:FindFirstChild("RoundDoor")
        local rows = {}

        if not root or not round or not folder then
            return rows
        end

        for _, part in ipairs(folder:GetDescendants()) do
            if part:IsA("BasePart")
                and part.Name == "Root"
                and part.Parent
                and string.sub(tostring(part.Parent.Name), 1, 6) == "Portal"
            then
                local roundNum = tonumber(part:GetAttribute("RoundNum"))

                if roundNum == round - 1 then
                    table.insert(rows, {
                        Root = part,
                        ParentName = tostring(part.Parent.Name),
                        RoundNum = roundNum,
                        Distance = (part.Position - root.Position).Magnitude,
                    })
                end
            end
        end

        table.sort(rows, function(a, b)
            return a.Distance < b.Distance
        end)

        return rows
    end

    local function progressionEvidence(beforeRound, beforeRegion)
        if settled() then
            return "SETTLEMENT"
        end

        if hasObjective() then
            return "OBJECTIVE_APPEARED"
        end

        local nowRound = gameRound()
        if beforeRound and nowRound and nowRound ~= beforeRound then
            return "GAME_ROUND_CHANGED"
        end

        local root = getRoot()
        if root and type(D.nearestWakeRegion) == "function" then
            local ok, region, distance = pcall(D.nearestWakeRegion, root.Position)

            if ok
                and region
                and region ~= beforeRegion
                and tonumber(distance)
                and tonumber(distance) <= 28
            then
                return "NEW_REGION"
            end
        end

        return nil
    end

    local function horizontalUnit(v, fallback)
        local h = Vector3.new(v.X, 0, v.Z)

        if h.Magnitude < 0.1 then
            h = fallback or Vector3.new(0, 0, 1)
        end

        if h.Magnitude < 0.1 then
            h = Vector3.new(0, 0, 1)
        end

        return h.Unit
    end

    local function portalAxis(part)
        -- Cross through the thinnest horizontal portal dimension.
        if part.Size.X <= part.Size.Z then
            return horizontalUnit(part.CFrame.RightVector)
        end

        return horizontalUnit(part.CFrame.LookVector)
    end

    local function exactTouch(root, portal)
        if type(D.firetouchinterest) ~= "function"
            or not root
            or not portal
            or not portal.Parent
        then
            return false
        end

        local ok0 = pcall(D.firetouchinterest, root, portal, 0)
        task.wait(0.025)
        local ok1 = pcall(D.firetouchinterest, root, portal, 1)

        return ok0 or ok1
    end

    local function nativeWalk(humanoid, target, timeout, beforeRound, beforeRegion)
        local deadline = os.clock() + timeout

        while os.clock() < deadline do
            local evidence = progressionEvidence(beforeRound, beforeRegion)
            if evidence then
                return evidence
            end

            local root = getRoot()
            if not root or not root.Parent or humanoid.Health <= 0 then
                return nil
            end

            pcall(humanoid.MoveTo, humanoid, target)
            task.wait(0.07)
        end

        return progressionEvidence(beforeRound, beforeRegion)
    end

    local function tryLocalPortal(row, oldRegion)
        local root = getRoot()
        local character = D.LocalPlayer and D.LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")

        if not root
            or not humanoid
            or humanoid.Health <= 0
            or not row
            or not row.Root
            or not row.Root.Parent
        then
            return false, "LOCAL_PORTAL_INVALID"
        end

        if row.Distance > MAX_LOCAL_PORTAL_DISTANCE then
            return false, "LOCAL_PORTAL_TOO_FAR"
        end

        local portal = row.Root
        local beforeRound = gameRound()
        local beforeRegion = oldRegion or getRegion()
        local axis = portalAxis(portal)

        local toPlayer = horizontalUnit(
            root.Position - portal.Position,
            -axis
        )

        local side = toPlayer:Dot(axis) >= 0 and 1 or -1
        local approachAxis = axis * side

        emit(
            "WATCHDOG_LOCAL_PORTAL_START",
            "name=" .. tostring(row.ParentName)
                .. " round=" .. tostring(row.RoundNum)
                .. " dist=" .. string.format("%.1f", row.Distance)
                .. " pos=" .. tostring(portal.Position)
        )

        -- Fast farming optimization: if the exact portal is local but not
        -- immediately near, snap only to a safe point BEFORE the portal.
        -- Never CFrame through it and never use a far replicated portal.
        if row.Distance > FAST_APPROACH_DISTANCE then
            local pre = portal.Position + approachAxis * PRE_PORTAL_DISTANCE

            root.CFrame = CFrame.lookAt(
                Vector3.new(pre.X, root.Position.Y, pre.Z),
                Vector3.new(portal.Position.X, root.Position.Y, portal.Position.Z)
            )

            pcall(function()
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end)

            task.wait(0.06)
        end

        local evidence = progressionEvidence(beforeRound, beforeRegion)

        -- Native move INTO the exact portal volume.
        if not evidence then
            evidence = nativeWalk(
                humanoid,
                Vector3.new(portal.Position.X, root.Position.Y, portal.Position.Z),
                ENTER_TIMEOUT,
                beforeRound,
                beforeRegion
            )
        end

        -- Exact touch helper is allowed only on this verified local current-1
        -- portal. No RF InvokeServer is used because that was proven to skip
        -- valid intermediate rooms on some maps.
        if not evidence then
            exactTouch(getRoot(), portal)
            task.wait(0.07)
            evidence = progressionEvidence(beforeRound, beforeRegion)
        end

        -- Cross completely through the portal along its thin axis using
        -- Humanoid movement, keeping the game's native touch callbacks alive.
        if not evidence then
            local halfThin = math.min(portal.Size.X, portal.Size.Z) * 0.5
            local beyond = portal.Position - approachAxis * (halfThin + 7)

            evidence = nativeWalk(
                humanoid,
                Vector3.new(beyond.X, root.Position.Y, beyond.Z),
                CROSS_TIMEOUT,
                beforeRound,
                beforeRegion
            )
        end

        if not evidence then
            exactTouch(getRoot(), portal)

            local deadline = os.clock() + VERIFY_TIMEOUT
            while os.clock() < deadline do
                task.wait(0.07)
                evidence = progressionEvidence(beforeRound, beforeRegion)
                if evidence then
                    break
                end
            end
        end

        pcall(humanoid.Move, humanoid, Vector3.zero, false)

        if evidence then
            emit(
                "WATCHDOG_LOCAL_PORTAL_SUCCESS",
                "name=" .. tostring(row.ParentName)
                    .. " evidence=" .. tostring(evidence)
            )

            return true, "WATCHDOG_LOCAL_PORTAL_" .. tostring(evidence)
        end

        emit(
            "WATCHDOG_LOCAL_PORTAL_FAIL",
            "name=" .. tostring(row.ParentName)
                .. " round=" .. tostring(row.RoundNum)
                .. " finalDist="
                .. tostring(
                    getRoot()
                    and (getRoot().Position - portal.Position).Magnitude
                )
        )

        return false, "LOCAL_PORTAL_NO_PROGRESSION"
    end

    function W:Recover(oldRegion, reason)
        if hasObjective() then
            return false, "OBJECTIVE_ACTIVE"
        end

        local rows = currentPortalRows()
        local localRows = {}
        local farRows = {}

        for _, row in ipairs(rows) do
            if row.Distance <= MAX_LOCAL_PORTAL_DISTANCE then
                table.insert(localRows, row)
            else
                table.insert(farRows, row)
            end
        end

        if #localRows > 0 then
            for i = 1, math.min(3, #localRows) do
                local ok, result = tryLocalPortal(localRows[i], oldRegion)
                if ok then
                    return true, result
                end
            end

            -- A legitimate local current-1 portal exists. Do not abandon it
            -- for a far duplicate or historical learned route.
            return false, "LOCAL_CURRENT_PORTAL_UNRESOLVED"
        end

        if #farRows > 0 then
            emit(
                "WATCHDOG_FAR_PORTAL_REJECT",
                "reason=" .. tostring(reason)
                    .. " nearest=" .. string.format("%.1f", farRows[1].Distance)
                    .. " name=" .. tostring(farRows[1].ParentName)
                    .. " round=" .. tostring(farRows[1].RoundNum)
            )

            return false, "ONLY_FAR_CURRENT_PORTALS"
        end

        -- World2 has different progression objects. Never delegate it to the
        -- old World1 learned/far-route recovery when no exact current portal
        -- exists; objective_probe owns evidence-backed physical blockers.
        if worldId() == "World2" then
            return false, "WORLD2_NO_SAFE_LOCAL_PORTAL"
        end

        -- Preserve previously validated World1 recovery behavior.
        if type(old.Recover) == "function" then
            return old:Recover(oldRegion, reason)
        end

        return false, "BASE_RECOVER_UNAVAILABLE"
    end

    function W:HasLearnedRoute()
        local rows = currentPortalRows()
        local nearestLocal = nil
        local nearestFar = nil

        for _, row in ipairs(rows) do
            if row.Distance <= MAX_LOCAL_PORTAL_DISTANCE then
                nearestLocal = nearestLocal or row
            else
                nearestFar = nearestFar or row
            end
        end

        if nearestLocal then
            return true,
                "LOCAL_CURRENT_PORTAL",
                nearestLocal.ParentName,
                nearestLocal.Distance
        end

        if nearestFar then
            return false,
                "ONLY_FAR_CURRENT_PORTALS",
                nearestFar.ParentName,
                nearestFar.Distance
        end

        if worldId() == "World2" then
            return false, "WORLD2_NO_SAFE_LOCAL_PORTAL"
        end

        if type(old.HasLearnedRoute) == "function" then
            return old:HasLearnedRoute()
        end

        return false, "NO_SAFE_ROUTE"
    end

    return W
end
