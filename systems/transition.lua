--========================================================--
-- IRON SOUL - FAST VERIFIED PORTAL TRANSITION V61.4
--
-- Factory module used by systems/combat.lua.
--
-- Keeps portal/gate discovery outside the main combat chunk so Luau does
-- not hit the "Out of local registers" compiler limit.
--========================================================--

return function(D)
    local Resolver = {}

    local Players =
        D.Players

    local RunService =
        game:GetService(
            "RunService"
        )

    local LocalPlayer =
        D.LocalPlayer

    local CFG =
        D.CFG

    local effectivelyVisible =
        D.effectivelyVisible

    local portalTeleportEvidence =
        D.portalTeleportEvidence

    local exactRoundDoorPortal =
        D.exactRoundDoorPortal

    local gameRound =
        D.gameRound

    local fullName =
        D.fullName

    local placeCharacter =
        D.placeCharacter

    local important =
        D.important

    local portalLog =
        D.portalLog

    local event =
        D.event

    local hasCombatObjective =
        D.hasCombatObjective

    local firetouchinterest =
        D.firetouchinterest

    local fireproximityprompt =
        D.fireproximityprompt

    local function Root()
        return D.getRoot()
    end

    local function CurrentRegion()
        return D.getCurrentRegion()
    end

    local function roomClearedVisible()
        local pg =
            LocalPlayer:
                FindFirstChildOfClass(
                    "PlayerGui"
                )

        if not pg then
            return false
        end

        for _, obj in ipairs(
            pg:GetDescendants()
        ) do
            if (
                obj:IsA("TextLabel")
                or obj:IsA("TextButton")
            )
                and effectivelyVisible(obj)
            then
                local text =
                    string.lower(
                        tostring(
                            obj.Text or ""
                        )
                    )

                if string.find(
                    text,
                    "room cleared",
                    1,
                    true
                )
                then
                    return true
                end
            end
        end

        return false
    end

    function Resolver:RoomClearedVisible()
        return roomClearedVisible()
    end

    -- Forward declaration:
    -- PulseNativeMovement() calls transitionEvidence(), so this symbol must
    -- exist in the lexical scope BEFORE PulseNativeMovement is created.
    local transitionEvidence

    local function emit(
        name,
        detail
    )
        if type(event)
            == "function"
        then
            pcall(
                event,
                name,
                detail
            )
        end

        portalLog(
            tostring(name)
                .. " "
                .. tostring(
                    detail
                    or ""
                )
        )
    end

    function Resolver:PulseNativeMovement(
        oldRegion,
        preferred,
        reason
    )
        local root =
            Root()

        if not root
            or not root.Parent
        then
            return false,
                "NO_ROOT"
        end

        local character =
            LocalPlayer.Character

        local humanoid =
            character
            and character:
                FindFirstChildOfClass(
                    "Humanoid"
                )

        if not humanoid
            or humanoid.Health <= 0
        then
            return false,
                "NO_HUMANOID"
        end

        local beforePos =
            root.Position

        local forward =
            preferred

        if not forward
            or forward.Magnitude < 0.1
        then
            forward =
                root.CFrame.LookVector
        end

        forward =
            Vector3.new(
                forward.X,
                0,
                forward.Z
            )

        if forward.Magnitude < 0.1 then
            forward =
                Vector3.new(
                    0,
                    0,
                    -1
                )
        else
            forward =
                forward.Unit
        end

        local right =
            Vector3.new(
                -forward.Z,
                0,
                forward.X
            )

        local directions = {
            forward,
            right,
            -right,
            -forward,
        }

        emit(
            "NATIVE_MOVE_START",
            "reason="
                .. tostring(reason)
                .. " pos="
                .. tostring(
                    beforePos
                )
                .. " region="
                .. tostring(
                    oldRegion
                    and fullName(
                        oldRegion
                    )
                )
        )

        local maxDirections =
            math.min(
                tonumber(
                    CFG.NATIVE_MOTION_MAX_DIRECTIONS
                )
                or 4,
                #directions
            )

        for i = 1,
            maxDirections
        do
            if not root.Parent
                or humanoid.Health <= 0
            then
                return false,
                    "CHARACTER_CHANGED"
            end

            local dir =
                directions[i]

            local pulseStart =
                os.clock()

            -- Real Humanoid movement rather than CFrame repositioning.
            -- Repeat per Heartbeat so MoveDirection/physics/touch state is
            -- genuinely updated for several simulation frames.
            while os.clock()
                - pulseStart
                < (
                    tonumber(
                        CFG.NATIVE_MOTION_STEP_TIME
                    )
                    or 0.11
                )
            do
                humanoid:
                    Move(
                        dir,
                        false
                    )

                RunService.Heartbeat:
                    Wait()

                local evidence =
                    transitionEvidence(
                        beforePos,
                        oldRegion,
                        false
                    )

                if evidence then
                    humanoid:
                        Move(
                            Vector3.zero,
                            false
                        )

                    emit(
                        "NATIVE_MOVE_SUCCESS",
                        "reason="
                            .. tostring(reason)
                            .. " dir="
                            .. tostring(i)
                            .. " result="
                            .. tostring(
                                evidence
                            )
                            .. " pos="
                            .. tostring(
                                root.Position
                            )
                    )

                    return true,
                        "NATIVE_MOVE_"
                            .. tostring(
                                evidence
                            )
                end
            end

            humanoid:
                Move(
                    Vector3.zero,
                    false
                )

            task.wait(
                tonumber(
                    CFG.NATIVE_MOTION_SETTLE
                )
                or 0.10
            )

            local evidence =
                transitionEvidence(
                    beforePos,
                    oldRegion,
                    false
                )

            if evidence then
                emit(
                    "NATIVE_MOVE_SUCCESS",
                    "reason="
                        .. tostring(reason)
                        .. " dir="
                        .. tostring(i)
                        .. " result="
                        .. tostring(
                            evidence
                        )
                        .. " pos="
                        .. tostring(
                            root.Position
                        )
                )

                return true,
                    "NATIVE_MOVE_"
                        .. tostring(
                            evidence
                        )
            end
        end

        -- Some controllers ignore Humanoid:Move when input ownership is in
        -- an unusual state. Use a tiny physical MoveTo as a safe fallback,
        -- still without keyboard simulation or CFrame teleporting.
        local fallbackDistance =
            tonumber(
                CFG.NATIVE_MOTION_MOVETO_FALLBACK
            )
            or 2.0

        if fallbackDistance > 0
            and root.Parent
            and humanoid.Health > 0
        then
            local target =
                root.Position
                + forward
                    * fallbackDistance

            pcall(
                humanoid.MoveTo,
                humanoid,
                target
            )

            local untilTime =
                os.clock() + 0.28

            while os.clock()
                < untilTime
            do
                RunService.Heartbeat:
                    Wait()

                local evidence =
                    transitionEvidence(
                        beforePos,
                        oldRegion,
                        false
                    )

                if evidence then
                    emit(
                        "NATIVE_MOVETO_SUCCESS",
                        "reason="
                            .. tostring(reason)
                            .. " result="
                            .. tostring(
                                evidence
                            )
                            .. " pos="
                            .. tostring(
                                root.Position
                            )
                    )

                    return true,
                        "NATIVE_MOVETO_"
                            .. tostring(
                                evidence
                            )
                end
            end
        end

        emit(
            "NATIVE_MOVE_NO_TRANSITION",
            "reason="
                .. tostring(reason)
                .. " moved="
                .. string.format(
                    "%.2f",
                    (
                        root.Position
                        - beforePos
                    ).Magnitude
                )
                .. " pos="
                .. tostring(
                    root.Position
                )
        )

        return false,
            "NATIVE_MOVE_NO_TRANSITION"
    end

    transitionEvidence = function(
        beforePos,
        oldRegion,
        wasRoomCleared
    )
        -- V60.5:
        -- Never use Room Cleared GUI disappearance as transition evidence.
        -- That banner naturally fades and caused false-positive navigation.
        --
        -- Only accept server/physical evidence supplied by combat:
        --   SETTLEMENT
        --   CHARACTER_CHANGED
        --   >100-stud movement
        --   actual RoundWakeTouch region change near the player.
        return portalTeleportEvidence(
            beforePos,
            oldRegion
        )
    end


    local function exactPortalMechanism()
        local portalRoot =
            exactRoundDoorPortal()

        if not portalRoot
            or not portalRoot.Parent
        then
            return nil
        end

        local rf =
            portalRoot:
                FindFirstChild(
                    "RF"
                )

        local localPortal =
            portalRoot:
                FindFirstChild(
                    "LocalRoundPortal"
                )

        local serverPortal =
            portalRoot:
                FindFirstChild(
                    "ServerRoundPortal"
                )

        if not rf
            or not rf:IsA(
                "RemoteFunction"
            )
            or not (
                localPortal
                or serverPortal
            )
        then
            return nil
        end

        local roundNum =
            tonumber(
                portalRoot:
                    GetAttribute(
                        "RoundNum"
                    )
            )

        local current =
            gameRound()

        local unlocked =
            not roundNum
            or not current
            or roundNum < current

        if not unlocked then
            return nil
        end

        return {
            Root = portalRoot,
            RF = rf,
            Score = 1000,
            Name =
                fullName(
                    portalRoot.Parent
                ),
        }
    end

    function Resolver:TryFastExactPortal()
        -- Disabled in V60.3.
        --
        -- V60.1 proved that the RF is real, but also proved that invoking a
        -- replicated section portal remotely can skip intermediate rooms.
        -- Exact RoundDoor.Portal progression is now handled only by
        -- combat.lua's physical near-portal handshake.
        return false,
            "DIRECT_ROUND_PORTAL_RF_DISABLED"
    end


    local function unlockedPortalTarget()
        local root =
            Root()

        if not root then
            return nil
        end

        local portal =
            exactRoundDoorPortal()

        if not portal
            or not portal.Parent
            or not portal:IsA(
                "BasePart"
            )
        then
            return nil
        end

        local current =
            gameRound()

        local roundNum =
            tonumber(
                portal:
                    GetAttribute(
                        "RoundNum"
                    )
            )

        -- High-confidence route rule:
        -- for fast movement the exact portal must belong to the round that
        -- just completed. This avoids snapping to stale older replicated
        -- portals.
        if roundNum
            and current
            and roundNum
                ~= current - 1
        then
            return nil
        end

        if roundNum
            and current
            and roundNum >= current
        then
            return nil
        end

        return portal
    end

    function Resolver:GuidedWalk(
        oldRegion,
        reason
    )
        local root =
            Root()

        if not root
            or not root.Parent
        then
            return false,
                "NO_ROOT"
        end

        local character =
            LocalPlayer.Character

        local humanoid =
            character
            and character:
                FindFirstChildOfClass(
                    "Humanoid"
                )

        if not humanoid
            or humanoid.Health <= 0
        then
            return false,
                "NO_HUMANOID"
        end

        local target =
            unlockedPortalTarget()

        if not target then
            emit(
                "GUIDED_WALK_NO_TARGET",
                "reason="
                    .. tostring(reason)
            )

            return false,
                "NO_UNLOCKED_PORTAL"
        end

        local beforePos =
            root.Position

        local beforeRound =
            gameRound()

        local startDistance =
            (
                target.Position
                - root.Position
            ).Magnitude

        --======================================================--
        -- V61.4 FAST VERIFIED PORTAL APPROACH
        --
        -- We already know:
        --   * no combat objective is active (caller gating)
        --   * target is exact RoundDoor.Portal
        --   * target.RoundNum == GameRound - 1
        --
        -- So long walking adds no safety. Move instantly to a safe point
        -- just before the portal, then use real Humanoid movement through
        -- the final ~20 studs so touch/movement callbacks still fire.
        --======================================================--
        if CFG.FAST_PORTAL_APPROACH
            and startDistance
                >= CFG.FAST_PORTAL_MIN_DISTANCE
            and startDistance
                <= CFG.FAST_PORTAL_MAX_DISTANCE
        then
            local objectiveActive =
                false

            if type(hasCombatObjective)
                == "function"
            then
                local ok, value =
                    pcall(
                        hasCombatObjective
                    )

                objectiveActive =
                    ok
                    and value == true
            end

            if not objectiveActive then
                local fromPortal =
                    root.Position
                    - target.Position

                fromPortal =
                    Vector3.new(
                        fromPortal.X,
                        0,
                        fromPortal.Z
                    )

                if fromPortal.Magnitude < 0.1 then
                    fromPortal =
                        -Vector3.new(
                            target.CFrame.LookVector.X,
                            0,
                            target.CFrame.LookVector.Z
                        )
                end

                if fromPortal.Magnitude < 0.1 then
                    fromPortal =
                        Vector3.new(
                            0,
                            0,
                            1
                        )
                else
                    fromPortal =
                        fromPortal.Unit
                end

                local prePos =
                    Vector3.new(
                        target.Position.X
                            + fromPortal.X
                                * CFG.FAST_PORTAL_PRE_DISTANCE,
                        target.Position.Y + 2.0,
                        target.Position.Z
                            + fromPortal.Z
                                * CFG.FAST_PORTAL_PRE_DISTANCE
                    )

                emit(
                    "FAST_PORTAL_START",
                    "reason="
                        .. tostring(reason)
                        .. " round="
                        .. tostring(
                            target:
                                GetAttribute(
                                    "RoundNum"
                                )
                        )
                        .. " distance="
                        .. string.format(
                            "%.1f",
                            startDistance
                        )
                        .. " pre="
                        .. tostring(
                            prePos
                        )
                        .. " portal="
                        .. tostring(
                            target.Position
                        )
                )

                -- Fast long-distance approach. We intentionally do NOT
                -- CFrame through the portal itself.
                root.CFrame =
                    CFrame.lookAt(
                        prePos,
                        target.Position
                    )

                pcall(function()
                    root.AssemblyLinearVelocity =
                        Vector3.zero

                    root.AssemblyAngularVelocity =
                        Vector3.zero
                end)

                task.wait(
                    CFG.FAST_PORTAL_SETTLE
                )

                -- Establish evidence baseline AFTER the snap, otherwise the
                -- snap itself could look like portal teleport evidence.
                local verifyFrom =
                    root.Position

                local crossDestination =
                    target.Position
                    - fromPortal
                        * CFG.FAST_PORTAL_CROSS_DISTANCE

                local verifyStarted =
                    os.clock()

                while os.clock()
                    - verifyStarted
                    < CFG.FAST_PORTAL_VERIFY
                do
                    if not root.Parent
                        or humanoid.Health <= 0
                    then
                        return true,
                            "CHARACTER_CHANGED"
                    end

                    if type(hasCombatObjective)
                        == "function"
                    then
                        local ok, objective =
                            pcall(
                                hasCombatObjective
                            )

                        if ok
                            and objective
                        then
                            humanoid:
                                Move(
                                    Vector3.zero,
                                    false
                                )

                            emit(
                                "FAST_PORTAL_OBJECTIVE",
                                "reason="
                                    .. tostring(reason)
                            )

                            return true,
                                "OBJECTIVE_APPEARED"
                        end
                    end

                    pcall(
                        humanoid.MoveTo,
                        humanoid,
                        crossDestination
                    )

                    if type(
                        firetouchinterest
                    ) == "function"
                    then
                        pcall(
                            firetouchinterest,
                            root,
                            target,
                            0
                        )

                        task.wait(0.025)

                        pcall(
                            firetouchinterest,
                            root,
                            target,
                            1
                        )
                    end

                    task.wait(0.07)

                    local evidence =
                        transitionEvidence(
                            verifyFrom,
                            nil,
                            false
                        )

                    if evidence then
                        humanoid:
                            Move(
                                Vector3.zero,
                                false
                            )

                        emit(
                            "FAST_PORTAL_SUCCESS",
                            "reason="
                                .. tostring(reason)
                                .. " result="
                                .. tostring(
                                    evidence
                                )
                                .. " pos="
                                .. tostring(
                                    root.Position
                                )
                        )

                        return true,
                            "FAST_"
                                .. tostring(
                                    evidence
                                )
                    end

                    if beforeRound
                        and gameRound()
                        and gameRound()
                            ~= beforeRound
                    then
                        emit(
                            "FAST_PORTAL_ROUND",
                            tostring(
                                beforeRound
                            )
                                .. "->"
                                .. tostring(
                                    gameRound()
                                )
                        )

                        return true,
                            "GAME_ROUND_CHANGED"
                    end
                end

                emit(
                    "FAST_PORTAL_NO_TRIGGER",
                    "reason="
                        .. tostring(reason)
                        .. " distanceNow="
                        .. string.format(
                            "%.1f",
                            (
                                target.Position
                                - root.Position
                            ).Magnitude
                        )
                )

                -- If final touch did not trigger, fall through to the existing
                -- real GuidedWalk logic from this much closer position.
                beforePos =
                    root.Position

                startDistance =
                    (
                        target.Position
                        - root.Position
                    ).Magnitude
            end
        end

        local bestDistance =
            startDistance

        local lastBestAt =
            os.clock()

        local lastProgressLog =
            0

        emit(
            "GUIDED_WALK_START",
            "reason="
                .. tostring(reason)
                .. " target="
                .. fullName(target)
                .. " targetRound="
                .. tostring(
                    target:
                        GetAttribute(
                            "RoundNum"
                        )
                )
                .. " distance="
                .. string.format(
                    "%.1f",
                    startDistance
                )
                .. " player="
                .. tostring(
                    root.Position
                )
                .. " targetPos="
                .. tostring(
                    target.Position
                )
        )

        local deadline =
            os.clock()
            + (
                tonumber(
                    CFG.GUIDED_WALK_MAX_TIME
                )
                or 8
            )

        while os.clock()
            < deadline
        do
            if not root.Parent
                or humanoid.Health <= 0
            then
                return true,
                    "CHARACTER_CHANGED"
            end

            if type(hasCombatObjective)
                    == "function"
            then
                local ok, objective =
                    pcall(
                        hasCombatObjective
                    )

                if ok
                    and objective
                then
                    humanoid:
                        Move(
                            Vector3.zero,
                            false
                        )

                    emit(
                        "GUIDED_WALK_OBJECTIVE",
                        "reason="
                            .. tostring(reason)
                            .. " distance="
                            .. string.format(
                                "%.1f",
                                (
                                    target.Position
                                    - root.Position
                                ).Magnitude
                            )
                    )

                    return true,
                        "OBJECTIVE_APPEARED"
                end
            end

            -- Re-issue MoveTo because Roblox's MoveTo can timeout on long
            -- targets. This is real Humanoid movement, not CFrame.
            pcall(
                humanoid.MoveTo,
                humanoid,
                target.Position
            )

            task.wait(
                tonumber(
                    CFG.GUIDED_WALK_REISSUE
                )
                or 0.22
            )

            local evidence =
                transitionEvidence(
                    beforePos,
                    oldRegion,
                    false
                )

            if evidence then
                humanoid:
                    Move(
                        Vector3.zero,
                        false
                    )

                emit(
                    "GUIDED_WALK_SUCCESS",
                    "reason="
                        .. tostring(reason)
                        .. " result="
                        .. tostring(
                            evidence
                        )
                        .. " pos="
                        .. tostring(
                            root.Position
                        )
                )

                return true,
                    "GUIDED_"
                        .. tostring(
                            evidence
                        )
            end

            if beforeRound
                and gameRound()
                and gameRound()
                    ~= beforeRound
            then
                humanoid:
                    Move(
                        Vector3.zero,
                        false
                    )

                emit(
                    "GUIDED_WALK_ROUND",
                    tostring(beforeRound)
                        .. "->"
                        .. tostring(
                            gameRound()
                        )
                )

                return true,
                    "GAME_ROUND_CHANGED"
            end

            local distance =
                (
                    target.Position
                    - root.Position
                ).Magnitude

            if distance
                <= (
                    tonumber(
                        CFG.GUIDED_WALK_TARGET_RADIUS
                    )
                    or 7
                )
            then
                -- Let a real walking/touch frame occur inside the portal.
                humanoid:
                    MoveTo(
                        target.Position
                    )

                task.wait(0.25)

                local finalEvidence =
                    transitionEvidence(
                        beforePos,
                        oldRegion,
                        false
                    )

                if finalEvidence then
                    emit(
                        "GUIDED_WALK_SUCCESS",
                        "reason="
                            .. tostring(reason)
                            .. " result="
                            .. tostring(
                                finalEvidence
                            )
                    )

                    return true,
                        "GUIDED_"
                            .. tostring(
                                finalEvidence
                            )
                end
            end

            if bestDistance
                - distance
                >= (
                    tonumber(
                        CFG.GUIDED_WALK_MIN_PROGRESS
                    )
                    or 1
                )
            then
                bestDistance =
                    distance

                lastBestAt =
                    os.clock()
            end

            if os.clock()
                    - lastProgressLog
                    >= (
                        tonumber(
                            CFG.GUIDED_WALK_PROGRESS_LOG
                        )
                        or 1
                    )
            then
                lastProgressLog =
                    os.clock()

                emit(
                    "GUIDED_WALK_PROGRESS",
                    "reason="
                        .. tostring(reason)
                        .. " distance="
                        .. string.format(
                            "%.1f",
                            distance
                        )
                        .. " improved="
                        .. string.format(
                            "%.1f",
                            startDistance
                                - distance
                        )
                        .. " pos="
                        .. tostring(
                            root.Position
                        )
                )
            end

            if os.clock()
                    - lastBestAt
                    >= (
                        tonumber(
                            CFG.GUIDED_WALK_STALL_TIME
                        )
                        or 1.6
                    )
            then
                humanoid:
                    Move(
                        Vector3.zero,
                        false
                    )

                emit(
                    "GUIDED_WALK_STALL",
                    "reason="
                        .. tostring(reason)
                        .. " start="
                        .. string.format(
                            "%.1f",
                            startDistance
                        )
                        .. " best="
                        .. string.format(
                            "%.1f",
                            bestDistance
                        )
                        .. " current="
                        .. string.format(
                            "%.1f",
                            distance
                        )
                        .. " pos="
                        .. tostring(
                            root.Position
                        )
                )

                return false,
                    "GUIDED_WALK_STALLED"
            end
        end

        humanoid:
            Move(
                Vector3.zero,
                false
            )

        local finalDistance =
            (
                target.Position
                - root.Position
            ).Magnitude

        emit(
            "GUIDED_WALK_TIMEOUT",
            "reason="
                .. tostring(reason)
                .. " start="
                .. string.format(
                    "%.1f",
                    startDistance
                )
                .. " final="
                .. string.format(
                    "%.1f",
                    finalDistance
                )
                .. " pos="
                .. tostring(
                    root.Position
                )
        )

        return false,
            "GUIDED_WALK_TIMEOUT"
    end

    local function objectPosition(obj)
        if not obj then
            return nil
        end

        if obj:IsA("BasePart") then
            return obj.Position
        end

        if obj:IsA("Attachment") then
            return obj.WorldPosition
        end

        if obj:IsA("Model") then
            local ok, pivot =
                pcall(
                    obj.GetPivot,
                    obj
                )

            if ok then
                return pivot.Position
            end
        end

        local part =
            obj:
                FindFirstChildWhichIsA(
                    "BasePart",
                    true
                )

        return part
            and part.Position
    end

    local function candidatePart(obj)
        if not obj then
            return nil
        end

        if obj:IsA("BasePart") then
            return obj
        end

        if obj:IsA("Model") then
            local root =
                obj:
                    FindFirstChild(
                        "Root",
                        true
                    )

            if root
                and root:IsA(
                    "BasePart"
                )
            then
                return root
            end

            return obj.PrimaryPart
                or obj:
                    FindFirstChildWhichIsA(
                        "BasePart",
                        true
                    )
        end

        return obj:
            FindFirstChildWhichIsA(
                "BasePart",
                true
            )
    end

    local function mechanism(obj)
        return {
            Prompt =
                obj:
                    FindFirstChildWhichIsA(
                        "ProximityPrompt",
                        true
                    ),

            Touch =
                obj:
                    FindFirstChildWhichIsA(
                        "TouchTransmitter",
                        true
                    ),

            RF =
                obj:
                    FindFirstChildWhichIsA(
                        "RemoteFunction",
                        true
                    ),

            RE =
                obj:
                    FindFirstChildWhichIsA(
                        "RemoteEvent",
                        true
                    ),

            LocalPortal =
                obj:
                    FindFirstChild(
                        "LocalRoundPortal",
                        true
                    ),

            ServerPortal =
                obj:
                    FindFirstChild(
                        "ServerRoundPortal",
                        true
                    ),
        }
    end

    local function candidateRows()
        local root =
            Root()

        if not root then
            return {}
        end

        local good = {
            portal = 180,
            teleport = 165,
            exit = 145,
            transition = 140,
            next = 120,
            gate = 105,
            door = 55,
        }

        local bad = {
            torch = 190,
            walltorch = 260,
            spawn = 200,
            reset = 230,
            kill = 260,
            damage = 180,
            lava = 220,
            hazard = 180,
            decoration = 120,
            decor = 120,
        }

        local rows = {}
        local seen = {}

        local function scoreName(text)
            local low =
                string.lower(
                    tostring(text or "")
                )

            local score = 0

            for word, value
                in pairs(good)
            do
                if string.find(
                    low,
                    word,
                    1,
                    true
                )
                then
                    score += value
                end
            end

            for word, value
                in pairs(bad)
            do
                if string.find(
                    low,
                    word,
                    1,
                    true
                )
                then
                    score -= value
                end
            end

            return score
        end

        local function consider(obj)
            if not obj
                or seen[obj]
            then
                return
            end

            seen[obj] = true

            local pos =
                objectPosition(obj)

            if not pos then
                return
            end

            local distance =
                (
                    pos
                    - root.Position
                ).Magnitude

            if distance
                > CFG.ADAPTIVE_MAX_DISTANCE
            then
                return
            end

            local path =
                fullName(obj)

            -- Never use generic Workspace.Portal: older validation proved
            -- that it can be a large safety/reset volume.
            --
            -- Also do NOT use RoundDoor.Portal here. That portal is handled
            -- only by combat.lua's physical near-portal handshake so a
            -- replicated future section portal cannot skip rooms.
            if path == "Workspace.Portal"
                or string.sub(
                    path,
                    1,
                    #"Workspace.Portal."
                ) == "Workspace.Portal."
                or path == "Workspace.RoundDoor.Portal"
                or string.sub(
                    path,
                    1,
                    #"Workspace.RoundDoor.Portal."
                ) == "Workspace.RoundDoor.Portal."
            then
                return
            end

            local mech =
                mechanism(obj)

            local score =
                scoreName(
                    obj.Name
                    .. " "
                    .. path
                )

            if mech.Prompt then
                score += 65
            end

            if mech.Touch then
                score += 55
            end

            if mech.RF then
                score += 60
            end

            if mech.LocalPortal
                or mech.ServerPortal
            then
                score += 150
            end

            score +=
                math.max(
                    0,
                    75
                        - distance * 0.20
                )

            local part =
                candidatePart(obj)

            if part
                and part:IsA(
                    "BasePart"
                )
            then
                local maxDim =
                    math.max(
                        part.Size.X,
                        part.Size.Y,
                        part.Size.Z
                    )

                if maxDim > 120 then
                    score -= 220
                end
            end

            if score >= 170
                and (
                    mech.RF
                    or mech.Prompt
                    or mech.Touch
                )
            then
                table.insert(
                    rows,
                    {
                        Object = obj,
                        Position = pos,
                        Distance = distance,
                        Score = score,
                        Mechanism = mech,
                        Part = part,
                    }
                )
            end
        end

        for _, obj in ipairs(
            workspace:GetDescendants()
        ) do
            if obj:IsA("Model")
                or obj:IsA("Folder")
                or obj:IsA("BasePart")
            then
                local low =
                    string.lower(
                        obj.Name
                    )

                local interesting =
                    false

                for word in pairs(good) do
                    if string.find(
                        low,
                        word,
                        1,
                        true
                    )
                    then
                        interesting =
                            true
                        break
                    end
                end

                if interesting then
                    consider(obj)
                end
            end
        end

        table.sort(
            rows,
            function(a,b)
                if a.Score
                    ~= b.Score
                then
                    return a.Score
                        > b.Score
                end

                return a.Distance
                    < b.Distance
            end
        )

        return rows
    end

    function Resolver:Snapshot(limit)
        local rows =
            candidateRows()

        limit =
            tonumber(limit)
            or 8

        local out = {}

        for i = 1,
            math.min(
                limit,
                #rows
            )
        do
            local row =
                rows[i]

            local mech =
                row.Mechanism

            table.insert(
                out,
                "#"
                    .. tostring(i)
                    .. " score="
                    .. string.format(
                        "%.1f",
                        row.Score
                    )
                    .. " dist="
                    .. string.format(
                        "%.1f",
                        row.Distance
                    )
                    .. " path="
                    .. fullName(
                        row.Object
                    )
                    .. " prompt="
                    .. tostring(
                        mech.Prompt ~= nil
                    )
                    .. " touch="
                    .. tostring(
                        mech.Touch ~= nil
                    )
                    .. " rf="
                    .. tostring(
                        mech.RF ~= nil
                    )
                    .. " re="
                    .. tostring(
                        mech.RE ~= nil
                    )
            )
        end

        if #out == 0 then
            return "none"
        end

        return table.concat(
            out,
            "\n"
        )
    end

    local function promptPosition(
        prompt
    )
        if not prompt
            or not prompt.Parent
        then
            return nil
        end

        local parent =
            prompt.Parent

        if parent:IsA(
            "Attachment"
        ) then
            return parent.WorldPosition
        end

        if parent:IsA(
            "BasePart"
        ) then
            return parent.Position
        end

        return objectPosition(
            parent
        )
    end

    function Resolver:TryAdaptive()
        local root =
            Root()

        if not root then
            return false,
                "NO_ROOT"
        end

        local rows =
            candidateRows()

        portalLog(
            "ADAPTIVE_LOCAL candidates="
                .. tostring(
                    #rows
                )
        )

        local oldRegion =
            CurrentRegion()

        local wasCleared =
            roomClearedVisible()

        for i = 1,
            math.min(
                6,
                #rows
            )
        do
            local row =
                rows[i]

            local mech =
                row.Mechanism

            local beforePos =
                root.Position

            portalLog(
                "ADAPTIVE_TRY #"
                    .. tostring(i)
                    .. " score="
                    .. string.format(
                        "%.1f",
                        row.Score
                    )
                    .. " dist="
                    .. string.format(
                        "%.1f",
                        row.Distance
                    )
                    .. " path="
                    .. fullName(
                        row.Object
                    )
            )

            if mech.RF
                and row.Distance <= 35
                and (
                    mech.LocalPortal
                    or mech.ServerPortal
                )
            then
                pcall(function()
                    mech.RF:
                        InvokeServer()
                end)

                local deadline =
                    os.clock() + 1.25

                while os.clock()
                    < deadline
                do
                    local evidence =
                        transitionEvidence(
                            beforePos,
                            oldRegion,
                            wasCleared
                        )

                    if evidence then
                        important(
                            "Phase | adaptive portal"
                        )

                        return true,
                            evidence
                    end

                    task.wait(0.08)
                end
            end

            if mech.Prompt
                and row.Distance <= 90
                and mech.Prompt.Enabled
                and type(
                    fireproximityprompt
                ) == "function"
            then
                local pos =
                    promptPosition(
                        mech.Prompt
                    )

                if pos then
                    local dir =
                        root.Position
                        - pos

                    if dir.Magnitude
                        < 0.1
                    then
                        dir =
                            root.CFrame.LookVector
                    else
                        dir =
                            dir.Unit
                    end

                    placeCharacter(
                        pos
                            + dir * 2.2,
                        -dir
                    )

                    task.wait(0.10)
                end

                pcall(
                    fireproximityprompt,
                    mech.Prompt,
                    0
                )

                local deadline =
                    os.clock() + 1.50

                while os.clock()
                    < deadline
                do
                    local evidence =
                        transitionEvidence(
                            beforePos,
                            oldRegion,
                            wasCleared
                        )

                    if evidence then
                        important(
                            "Phase | adaptive gate"
                        )

                        return true,
                            evidence
                    end

                    task.wait(0.08)
                end
            end

            local part =
                row.Part

            if part
                and row.Distance <= 110
                and part:IsA(
                    "BasePart"
                )
                and (
                    mech.Touch
                    or string.find(
                        string.lower(
                            fullName(
                                row.Object
                            )
                        ),
                        "portal",
                        1,
                        true
                    )
                    or string.find(
                        string.lower(
                            fullName(
                                row.Object
                            )
                        ),
                        "exit",
                        1,
                        true
                    )
                )
            then
                local maxDim =
                    math.max(
                        part.Size.X,
                        part.Size.Y,
                        part.Size.Z
                    )

                if maxDim <= 120 then
                    local center =
                        part.Position

                    local axis =
                        part.Size.X
                            < part.Size.Z
                        and part.CFrame.RightVector
                        or part.CFrame.LookVector

                    axis =
                        Vector3.new(
                            axis.X,
                            0,
                            axis.Z
                        )

                    if axis.Magnitude
                        < 0.1
                    then
                        axis =
                            root.CFrame.LookVector
                    else
                        axis =
                            axis.Unit
                    end

                    for _, offset
                        in ipairs({
                            -4,
                            -1,
                            0,
                            1,
                            4,
                        })
                    do
                        local p =
                            center
                            + axis * offset

                        placeCharacter(
                            Vector3.new(
                                p.X,
                                center.Y,
                                p.Z
                            ),
                            axis
                        )

                        if mech.Touch
                            and type(
                                firetouchinterest
                            ) == "function"
                        then
                            pcall(
                                firetouchinterest,
                                root,
                                part,
                                0
                            )

                            task.wait(0.035)

                            pcall(
                                firetouchinterest,
                                root,
                                part,
                                1
                            )
                        end

                        task.wait(0.12)

                        local evidence =
                            transitionEvidence(
                                beforePos,
                                oldRegion,
                                wasCleared
                            )

                        if evidence then
                            important(
                                "Phase | adaptive touch"
                            )

                            return true,
                                evidence
                        end
                    end
                end
            end
        end

        return false,
            "NO_ADAPTIVE_TRANSITION"
    end

    return Resolver
end
