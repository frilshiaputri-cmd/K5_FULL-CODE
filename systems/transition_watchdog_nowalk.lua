--========================================================--
-- IRON SOUL - WORLD1 TWEEN WATCHDOG WRAPPER V61.14.5
--
-- Reuses the proven watchdog but intercepts World1 exact current-1 portals
-- before any native Humanoid walking path. World1 uses fast floating CFrame
-- tween movement + a short pre-cross settle + touch + authoritative verify.
-- Before portal recovery, it also asks world1_round_recovery.lua to route the
-- character to the wake matching authoritative GameRound. This repairs a
-- proven D3 failure where a reused portal sent GameRound5 into Round7 early.
-- World2 stays isolated.
--========================================================--

local baseLoadRaw =
    getgenv().IronSoulDependencyBaseLoadRaw
    or getgenv().IronSoulLoadRaw

assert(type(baseLoadRaw) == "function", "V61.14.5 watchdog base loader unavailable")

local ok, baseFactory = baseLoadRaw("systems/transition_watchdog.lua")
assert(ok and type(baseFactory) == "function", "V61.14.5 base watchdog unavailable")

local motionOk, Motion = baseLoadRaw("systems/world1_motion.lua")
assert(motionOk and type(Motion) == "table", "V61.14.5 World1 motion unavailable")

return function(D)
    local W = baseFactory(D)
    assert(type(W) == "table", "V61.14.5 base watchdog build failed")

    local baseRecover = W.Recover

    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local MAX_LOCAL_PORTAL_DISTANCE = 320

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

    local function emit(name, detail)
        if type(D.event) == "function" then
            pcall(D.event, name, detail)
        end
    end

    local function root()
        if type(D.getRoot) ~= "function" then return nil end
        local okRoot, value = pcall(D.getRoot)
        return okRoot and value or nil
    end

    local function round()
        if type(D.gameRound) ~= "function" then return nil end
        local okRound, value = pcall(D.gameRound)
        return okRound and tonumber(value) or nil
    end

    local function region()
        if type(D.getCurrentRegion) ~= "function" then return nil end
        local okRegion, value = pcall(D.getCurrentRegion)
        return okRegion and value or nil
    end

    local function hasObjective()
        if type(D.hasCombatObjective) ~= "function" then return false end
        local okObjective, value = pcall(D.hasCombatObjective)
        return okObjective and value == true
    end

    local function settled()
        if type(D.settlementDetected) ~= "function" then return false end
        local okSettlement, value = pcall(D.settlementDetected)
        return okSettlement and value == true
    end

    local function currentPortalRows()
        local r = root()
        local current = round()
        local folder = workspace:FindFirstChild("RoundDoor")
        local rows = {}

        if not r or not current or not folder then return rows end

        for _, part in ipairs(folder:GetDescendants()) do
            if part:IsA("BasePart")
                and part.Name == "Root"
                and part.Parent
                and string.sub(tostring(part.Parent.Name), 1, 6) == "Portal"
            then
                local roundNum = tonumber(part:GetAttribute("RoundNum"))
                if roundNum == current - 1 then
                    local distance = (part.Position - r.Position).Magnitude
                    if distance <= MAX_LOCAL_PORTAL_DISTANCE then
                        table.insert(rows, {
                            Root = part,
                            Name = tostring(part.Parent.Name),
                            RoundNum = roundNum,
                            Distance = distance,
                        })
                    end
                end
            end
        end

        table.sort(rows, function(a,b) return a.Distance < b.Distance end)
        return rows
    end

    local function horizontal(v, fallback)
        local h = Vector3.new(v.X, 0, v.Z)
        if h.Magnitude < 0.1 then h = fallback or Vector3.new(0,0,1) end
        if h.Magnitude < 0.1 then h = Vector3.new(0,0,1) end
        return h.Unit
    end

    local function exactTouch(r, portal)
        if type(D.firetouchinterest) ~= "function" then return false end
        local ok0 = pcall(D.firetouchinterest, r, portal, 0)
        task.wait(0.025)
        local ok1 = pcall(D.firetouchinterest, r, portal, 1)
        return ok0 or ok1
    end

    local function evidence(beforeRound, beforeRegion)
        if settled() then return "SETTLEMENT" end
        if hasObjective() then return "OBJECTIVE_APPEARED" end

        local nowRound = round()
        if beforeRound and nowRound and nowRound ~= beforeRound then
            return "GAME_ROUND_CHANGED"
        end

        local r = root()
        if r and type(D.nearestWakeRegion) == "function" then
            local okRegion, newRegion, distance = pcall(D.nearestWakeRegion, r.Position)
            if okRegion
                and newRegion
                and newRegion ~= beforeRegion
                and tonumber(distance)
                and tonumber(distance) <= 28
                and tostring(newRegion.Name)
                    == "Round" .. tostring(round())
            then
                return "NEW_REGION"
            end
        end

        return nil
    end

    local function portalSettleDelay()
        local requested =
            D.CFG
            and tonumber(D.CFG.FAST_PORTAL_SETTLE)
            or 0.60

        return math.min(1.0, math.max(0.60, requested or 0.60))
    end

    local function tweenPortal(row, oldRegion, reason)
        local r = root()
        if not r or not row or not row.Root or not row.Root.Parent then
            return false, "INVALID_PORTAL"
        end
        if hasObjective() then return false, "OBJECTIVE_ACTIVE" end

        local portal = row.Root
        local beforeRound = round()
        local beforeRegion = oldRegion or region()
        local fromPortal = horizontal(r.Position - portal.Position, -portal.CFrame.LookVector)
        local travelY = r.Position.Y

        local pre = Vector3.new(
            portal.Position.X + fromPortal.X * 9,
            travelY,
            portal.Position.Z + fromPortal.Z * 9
        )
        local beyond = Vector3.new(
            portal.Position.X - fromPortal.X * 13,
            travelY,
            portal.Position.Z - fromPortal.Z * 13
        )

        emit(
            "WATCHDOG_TWEEN_PORTAL_START",
            "reason=" .. tostring(reason)
                .. " name=" .. tostring(row.Name)
                .. " round=" .. tostring(row.RoundNum)
                .. " dist=" .. string.format("%.1f", row.Distance)
        )

        local moved, moveKind, moveDist, moveTime = Motion.MoveToPosition(
            r,
            pre,
            Vector3.new(portal.Position.X, travelY, portal.Position.Z),
            {
                Speed = row.Distance > 80 and Motion.FAR_SPEED or Motion.DEFAULT_SPEED,
                MaxTime = 0.90,
            }
        )

        if not moved then
            return false, "WATCHDOG_TWEEN_PRE_FAILED_" .. tostring(moveKind)
        end

        emit(
            "WATCHDOG_TWEEN_APPROACH",
            "kind=" .. tostring(moveKind)
                .. " studs=" .. string.format("%.1f", moveDist or 0)
                .. " time=" .. string.format("%.2f", moveTime or 0)
        )

        local early = evidence(beforeRound, beforeRegion)
        if early then return true, "WATCHDOG_TWEEN_" .. tostring(early) end

        local settle = portalSettleDelay()
        emit(
            "WATCHDOG_TWEEN_PORTAL_SETTLE",
            "seconds=" .. string.format("%.2f", settle)
                .. " name=" .. tostring(row.Name)
        )

        task.wait(settle)

        if not r.Parent or not portal.Parent then
            return false, "WATCHDOG_PORTAL_CHANGED_DURING_SETTLE"
        end

        local afterSettle = evidence(beforeRound, beforeRegion)
        if afterSettle then
            return true, "WATCHDOG_TWEEN_" .. tostring(afterSettle)
        end

        exactTouch(r, portal)

        Motion.MoveToPosition(
            r,
            beyond,
            Vector3.new(portal.Position.X, travelY, portal.Position.Z),
            {Speed = Motion.DEFAULT_SPEED, MaxTime = 0.30}
        )

        exactTouch(r, portal)

        local deadline = os.clock() + 1.20
        while os.clock() < deadline do
            task.wait(0.06)
            local hit = evidence(beforeRound, beforeRegion)
            if hit then
                emit(
                    "WATCHDOG_TWEEN_PORTAL_SUCCESS",
                    "name=" .. tostring(row.Name) .. " result=" .. tostring(hit)
                )
                return true, "WATCHDOG_TWEEN_" .. tostring(hit)
            end
        end

        for _, offset in ipairs({-2, 0, 2, -4, 4}) do
            if not r.Parent or not portal.Parent then break end

            local p = Vector3.new(
                portal.Position.X + fromPortal.X * offset,
                travelY,
                portal.Position.Z + fromPortal.Z * offset
            )

            Motion.MoveToPosition(
                r,
                p,
                Vector3.new(portal.Position.X, travelY, portal.Position.Z),
                {Speed = 240, MaxTime = 0.12}
            )
            exactTouch(r, portal)
            task.wait(0.045)

            local hit = evidence(beforeRound, beforeRegion)
            if hit then
                emit(
                    "WATCHDOG_TWEEN_PORTAL_SUCCESS",
                    "name=" .. tostring(row.Name)
                        .. " offset=" .. tostring(offset)
                        .. " result=" .. tostring(hit)
                )
                return true, "WATCHDOG_TWEEN_" .. tostring(hit)
            end
        end

        emit(
            "WATCHDOG_TWEEN_PORTAL_FAIL",
            "name=" .. tostring(row.Name) .. " round=" .. tostring(row.RoundNum)
        )

        return false, "WATCHDOG_TWEEN_NO_PROGRESSION"
    end

    function W:Recover(oldRegion, reason)
        if worldId() ~= "World1" then
            return baseRecover(self, oldRegion, reason)
        end

        -- First repair any cross-section mismatch by following the exact wake
        -- matching authoritative GameRound. This also handles a portal that
        -- physically misplaced us into a future boss section.
        if getgenv().IronSoulWorld1RoundRecovery
            and getgenv().IronSoulWorld1RoundRecovery:
                RecoverIfNeeded(
                    oldRegion,
                    "WATCHDOG:" .. tostring(reason)
                )
        then
            emit(
                "WATCHDOG_CURRENT_ROUND_ROUTE_SUCCESS",
                "round=" .. tostring(round())
                    .. " reason=" .. tostring(reason)
            )
            return true, "WATCHDOG_CURRENT_ROUND_TWEEN"
        end

        local rows = currentPortalRows()
        if #rows > 0 then
            for i = 1, math.min(3, #rows) do
                local okTween, result = tweenPortal(rows[i], oldRegion, reason)
                if okTween then return true, result end
            end

            return false, "WORLD1_LOCAL_PORTAL_TWEEN_UNRESOLVED"
        end

        return baseRecover(self, oldRegion, reason)
    end

    return W
end
