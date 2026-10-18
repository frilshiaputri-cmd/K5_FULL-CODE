--========================================================--
-- IRON SOUL - ROUTE-BLOCKER OBJECTIVE RESOLVER V61.12.1
--
-- Priority:
--   1) normal enemy / DragonEgg
--   2) exact current-1 local Portal*
--      BUT first destroy a real physical blocker on the route to it
--   3) if no local portal, inspect route toward authoritative current wake
--
-- NEVER select a target because HitCount/tag/name alone.
-- NEVER treat object removal alone as progression success.
--========================================================--

return function(D)
    local R = {}

    local CollectionService = game:GetService("CollectionService")

    local LastTry = -math.huge
    local LastArchiveAt = -math.huge
    local ProbeSerial = 0

    local TRY_COOLDOWN = 0.70
    local ARCHIVE_COOLDOWN = 10.0
    local LOCAL_PORTAL_MAX = 320
    local ROUTE_TARGET_MAX = 520
    local BLOCKER_ATTACK_MAX = 150

    -- These were proven by recon to be ordinary loot/scenery in World2.
    -- A real progression rock/crystal remains eligible when it is tagged and
    -- physically blocks the authoritative route.
    local SCENERY_NAMES = {
        tree = true,
        tree1 = true,
        tree2 = true,
        tree3 = true,
        chest = true,
        chest1 = true,
        chest2 = true,
        chest3 = true,
        goldcoin = true,
        icecrystal = true,
    }

    local function emit(name, detail)
        if type(D.event) == "function" then
            pcall(D.event, name, detail)
        end
    end

    local function root()
        if type(D.getRoot) ~= "function" then
            return nil
        end

        local ok, value = pcall(D.getRoot)
        return ok and value or nil
    end

    local function currentRegion()
        if type(D.getCurrentRegion) ~= "function" then
            return nil
        end

        local ok, value = pcall(D.getCurrentRegion)
        return ok and value or nil
    end

    local function gameRound()
        if type(D.gameRound) ~= "function" then
            return nil
        end

        local ok, value = pcall(D.gameRound)
        return ok and tonumber(value) or nil
    end

    local function fullName(obj)
        if type(D.fullName) == "function" then
            local ok, value = pcall(D.fullName, obj)
            if ok then
                return tostring(value)
            end
        end

        if typeof(obj) ~= "Instance" then
            return tostring(obj)
        end

        local ok, value = pcall(function()
            return obj:GetFullName()
        end)

        return ok and tostring(value) or tostring(obj.Name)
    end

    local function hasNormalObjective()
        if type(D.hasNormalObjective) ~= "function" then
            return false
        end

        local ok, value = pcall(D.hasNormalObjective)
        return ok and value == true
    end

    local function settled()
        if type(D.settlementDetected) ~= "function" then
            return false
        end

        local ok, value = pcall(D.settlementDetected)
        return ok and value == true
    end

    local function progressionEvidence(beforeRound, beforeRegion)
        if settled() then
            return "SETTLEMENT"
        end

        if hasNormalObjective() then
            return "OBJECTIVE_APPEARED"
        end

        local nowRound = gameRound()
        if beforeRound and nowRound and nowRound ~= beforeRound then
            return "GAME_ROUND_CHANGED"
        end

        local nowRegion = currentRegion()
        if beforeRegion and nowRegion and nowRegion ~= beforeRegion then
            return "REGION_CHANGED"
        end

        return nil
    end

    local function portalRows()
        local r = root()
        local round = gameRound()
        local folder = workspace:FindFirstChild("RoundDoor")
        local rows = {}

        if not r or not round or not folder then
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
                        Name = tostring(part.Parent.Name),
                        RoundNum = roundNum,
                        Distance = (part.Position - r.Position).Magnitude,
                    })
                end
            end
        end

        table.sort(rows, function(a, b)
            return a.Distance < b.Distance
        end)

        return rows
    end

    local function currentWake()
        local round = gameRound()
        local r = root()

        if not round or not r then
            return nil, nil
        end

        local worldEnemies = workspace:FindFirstChild("WorldEnemys")
        local folder = worldEnemies and worldEnemies:FindFirstChild("RoundWakeTouch")

        if not folder then
            return nil, nil
        end

        local exact = folder:FindFirstChild("Round" .. tostring(round), true)

        if not exact or not exact:IsA("BasePart") then
            return nil, nil
        end

        local localPos = exact.CFrame:PointToObjectSpace(r.Position)
        local half = exact.Size * 0.5

        local dx = math.max(math.abs(localPos.X) - half.X, 0)
        local dy = math.max(math.abs(localPos.Y) - half.Y, 0)
        local dz = math.max(math.abs(localPos.Z) - half.Z, 0)

        return exact, Vector3.new(dx, dy, dz).Magnitude
    end

    local function destructibleAncestor(instance)
        local current = instance

        while current and current ~= workspace do
            local ok, tagged = pcall(
                CollectionService.HasTag,
                CollectionService,
                current,
                "DestructibleObject"
            )

            if ok and tagged then
                return current
            end

            current = current.Parent
        end

        return nil
    end

    local function obviousScenery(obj)
        if not obj then
            return true
        end

        local low = string.lower(tostring(obj.Name or ""))

        if SCENERY_NAMES[low] then
            return true
        end

        local dropLoot = obj:GetAttribute("DropLootId")
        return dropLoot ~= nil and tostring(dropLoot) ~= ""
    end

    -- Return only the FIRST collidable tagged destructible physically hit on
    -- the route. Decorative tagged models are ignored and raycast continues.
    local function firstRouteBlocker(targetPart)
        local r = root()

        if not r or not targetPart or not targetPart.Parent then
            return nil, "NO_ROUTE_TARGET"
        end

        local delta = targetPart.Position - r.Position
        local targetDistance = delta.Magnitude

        if targetDistance < 4 then
            return nil, "TARGET_ALREADY_NEAR"
        end

        if targetDistance > ROUTE_TARGET_MAX then
            return nil, "TARGET_TOO_FAR"
        end

        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.IgnoreWater = true

        local excluded = {}

        if D.LocalPlayer and D.LocalPlayer.Character then
            table.insert(excluded, D.LocalPlayer.Character)
        end

        for _ = 1, 20 do
            params.FilterDescendantsInstances = excluded

            local result = workspace:Raycast(r.Position, delta, params)

            if not result or not result.Instance then
                return nil, "ROUTE_CLEAR"
            end

            local hit = result.Instance
            local blocker = destructibleAncestor(hit)

            if blocker then
                local d = (result.Position - r.Position).Magnitude

                if hit:IsA("BasePart")
                    and hit.CanCollide == true
                    and d <= BLOCKER_ATTACK_MAX
                    and not obviousScenery(blocker)
                then
                    return {
                        Object = blocker,
                        HitPart = hit,
                        HitPosition = result.Position,
                        Distance = d,
                        Target = targetPart,
                        TargetDistance = targetDistance,
                    }
                end

                table.insert(excluded, blocker)

            elseif hit:IsA("BasePart")
                and (
                    hit.CanCollide == false
                    or hit.Transparency >= 0.98
                )
            then
                table.insert(excluded, hit)

            else
                -- A normal solid map wall/terrain is not a destroyable
                -- objective. Do not randomly attack around it.
                return nil, "SOLID_MAP_GEOMETRY:" .. fullName(hit)
            end
        end

        return nil, "RAY_LIMIT"
    end

    local function metric(obj)
        if not obj or not obj.Parent then
            return nil
        end

        for _, key in ipairs({
            "HitCount",
            "HitDamage",
            "DamageTaken",
            "Progress",
            "Health",
            "HP",
            "Durability",
        }) do
            local value = obj:GetAttribute(key)
            if type(value) == "number" then
                return key, value
            end
        end

        return nil
    end

    local function archive(reason, detail)
        local now = os.clock()

        if now - LastArchiveAt < ARCHIVE_COOLDOWN then
            return
        end

        LastArchiveAt = now
        ProbeSerial += 1

        local r = root()
        local text = table.concat({
            "Version=V61.12.1",
            "Reason=" .. tostring(reason),
            "PlaceId=" .. tostring(game.PlaceId),
            "GameRound=" .. tostring(gameRound()),
            "PlayerPos=" .. tostring(r and r.Position),
            tostring(detail or ""),
        }, "\n")

        if type(writefile) == "function" then
            pcall(writefile, "IronSoul_LastObjectiveProbe_V61_12_1.txt", text)
        end

        local telemetry = getgenv().IronSoulTelemetry

        if telemetry and type(telemetry.ArchiveFile) == "function" then
            pcall(
                telemetry.ArchiveFile,
                telemetry,
                string.format(
                    "ObjectiveProbe_%03d_R%s.txt",
                    ProbeSerial,
                    tostring(gameRound())
                ),
                text
            )
        end
    end

    local function attackBlocker(row)
        if not row
            or not row.Object
            or not row.Object.Parent
            or not row.HitPart
            or not row.HitPart.Parent
        then
            return false, "BLOCKER_INVALID"
        end

        local obj = row.Object
        local beforeRound = gameRound()
        local beforeRegion = currentRegion()
        local key, value = metric(obj)

        local started = os.clock()
        local lastProgress = started
        local sawProgress = false

        emit(
            "OBJECTIVE_ROUTE_BLOCKER_START",
            "name=" .. tostring(obj.Name)
                .. " path=" .. fullName(obj)
                .. " dist=" .. string.format("%.1f", row.Distance)
                .. " target=" .. fullName(row.Target)
                .. " targetDist=" .. string.format("%.1f", row.TargetDistance)
        )

        while os.clock() - started < 4.2 do
            local evidence = progressionEvidence(beforeRound, beforeRegion)
            if evidence then
                return true, evidence
            end

            if not obj.Parent then
                local deadline = os.clock() + 0.70

                while os.clock() < deadline do
                    task.wait(0.08)
                    evidence = progressionEvidence(beforeRound, beforeRegion)
                    if evidence then
                        return true, evidence
                    end
                end

                emit(
                    "OBJECTIVE_ROUTE_BLOCKER_REMOVED_NO_PROGRESS",
                    "name=" .. tostring(obj.Name)
                )

                return false, "BLOCKER_REMOVED_NO_PROGRESSION"
            end

            if hasNormalObjective() then
                return true, "OBJECTIVE_APPEARED"
            end

            local r = root()
            if not r then
                return false, "NO_ROOT"
            end

            local hitPos =
                row.HitPart.Parent
                and row.HitPart.Position
                or row.HitPosition

            if hitPos then
                local horizontal = Vector3.new(
                    r.Position.X - hitPos.X,
                    0,
                    r.Position.Z - hitPos.Z
                )

                if horizontal.Magnitude < 0.1 then
                    horizontal = -Vector3.new(
                        row.HitPart.CFrame.LookVector.X,
                        0,
                        row.HitPart.CFrame.LookVector.Z
                    )
                end

                if horizontal.Magnitude < 0.1 then
                    horizontal = Vector3.new(0, 0, 1)
                else
                    horizontal = horizontal.Unit
                end

                local goal = hitPos + horizontal * 5 + Vector3.new(0, 1.5, 0)
                r.CFrame = CFrame.lookAt(goal, hitPos)
            end

            if type(D.skillReady) == "function"
                and type(D.castSkill) == "function"
            then
                if D.skillReady("Skill2") then
                    pcall(D.castSkill, "Skill2")
                elseif D.skillReady("Skill1") then
                    pcall(D.castSkill, "Skill1")
                end
            end

            if type(D.sendHeadlessAttack) == "function" then
                pcall(D.sendHeadlessAttack)
            end

            local newKey, newValue = metric(obj)

            if key
                and newKey == key
                and type(value) == "number"
                and type(newValue) == "number"
                and newValue ~= value
            then
                sawProgress = true
                lastProgress = os.clock()

                emit(
                    "OBJECTIVE_ROUTE_BLOCKER_DAMAGE",
                    tostring(key) .. " " .. tostring(value) .. "->" .. tostring(newValue)
                )

                value = newValue
            elseif newKey then
                key = newKey
                value = newValue
            end

            if not sawProgress and os.clock() - lastProgress >= 1.35 then
                return false, "NO_CONFIRMED_BLOCKER_DAMAGE"
            end

            task.wait(0.11)
        end

        return false, sawProgress and "DAMAGE_PROGRESS" or "NO_CONFIRMED_BLOCKER_DAMAGE"
    end

    local function resolveBlocker(reason, target, targetLabel)
        local blocker, why = firstRouteBlocker(target)

        if not blocker then
            archive(
                reason,
                "Target=" .. tostring(targetLabel)
                    .. "\nRoute=" .. tostring(why)
            )
            return false, "NO_ROUTE_BLOCKER:" .. tostring(why)
        end

        archive(
            reason,
            "BLOCKER=" .. fullName(blocker.Object)
                .. "\nHitPart=" .. fullName(blocker.HitPart)
                .. "\nDistance=" .. tostring(blocker.Distance)
                .. "\nTarget=" .. fullName(blocker.Target)
        )

        local ok, result = attackBlocker(blocker)
        emit("OBJECTIVE_ROUTE_BLOCKER_RESULT", tostring(result))

        if ok then
            return true, "OBJECTIVE_" .. tostring(result)
        end

        return false, tostring(result)
    end

    function R:TryResolve(reason, age)
        local now = os.clock()

        if now - LastTry < TRY_COOLDOWN then
            return false, "COOLDOWN"
        end

        LastTry = now

        if hasNormalObjective() then
            return false, "NORMAL_OBJECTIVE_ACTIVE"
        end

        local portals = portalRows()
        local nearestPortal = portals[1]

        if nearestPortal and nearestPortal.Distance <= LOCAL_PORTAL_MAX then
            -- IMPORTANT: a valid portal may exist BEHIND a real breakable rock/
            -- crystal. Do not fast-snap across it. Route blocker gets one chance
            -- first; if route is clear, portal watchdog owns the transition.
            local blocker = firstRouteBlocker(nearestPortal.Root)

            if blocker then
                return resolveBlocker(
                    "LOCAL_PORTAL_BLOCKED_" .. tostring(reason),
                    nearestPortal.Root,
                    nearestPortal.Name
                )
            end

            emit(
                "OBJECTIVE_DEFER_TO_PORTAL",
                "name=" .. tostring(nearestPortal.Name)
                    .. " round=" .. tostring(nearestPortal.RoundNum)
                    .. " dist=" .. string.format("%.1f", nearestPortal.Distance)
            )

            local watchdog = getgenv().IronSoulTransitionWatchdog

            if watchdog
                and type(watchdog.Recover) == "function"
                and tonumber(age)
                and tonumber(age) >= 0.75
            then
                local ok, result = watchdog:Recover(
                    currentRegion(),
                    "OBJECTIVE_DEFER_LOCAL_PORTAL"
                )

                if ok then
                    return true, tostring(result)
                end
            end

            return false, "KNOWN_LOCAL_PORTAL"
        end

        local wake, wakeDistance = currentWake()

        if not wake
            or not wakeDistance
            or wakeDistance <= 3
            or wakeDistance > ROUTE_TARGET_MAX
        then
            archive(
                reason,
                "NearestPortal="
                    .. tostring(nearestPortal and nearestPortal.Name)
                    .. "@"
                    .. tostring(nearestPortal and nearestPortal.Distance)
                    .. "\nWake="
                    .. tostring(wake and fullName(wake))
                    .. "@"
                    .. tostring(wakeDistance)
            )

            return false, "NO_SAFE_BLOCKER_TARGET"
        end

        return resolveBlocker(
            reason,
            wake,
            "RoundWakeTouch.Round" .. tostring(gameRound())
        )
    end

    return R
end
