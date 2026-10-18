--========================================================--
-- IRON SOUL - WORLD1 TRANSITION MOTION V61.14
--
-- Smooth floating/tween-style movement for World1 transitions.
-- NO Humanoid:Move / MoveTo. NO keyboard/mouse input.
-- CFrame is interpolated at high speed so farming stays fast while the
-- character visibly glides instead of walking or hard-snapping everywhere.
--========================================================--

local RunService = game:GetService("RunService")

local Motion = {}

Motion.DEFAULT_SPEED = 210       -- studs/sec, normal gate/portal travel
Motion.FAR_SPEED = 260           -- studs/sec, long empty-corridor traversal
Motion.MIN_TIME = 0.07
Motion.MAX_TIME = 1.60           -- lets 300-400+ stud travel visibly glide

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function stopPhysics(root)
    if not root or not root.Parent then
        return
    end

    pcall(function()
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
end

function Motion.Duration(distance, speed, minTime, maxTime)
    distance = math.max(0, tonumber(distance) or 0)
    speed = math.max(1, tonumber(speed) or Motion.DEFAULT_SPEED)
    minTime = tonumber(minTime) or Motion.MIN_TIME
    maxTime = tonumber(maxTime) or Motion.MAX_TIME

    return clamp(distance / speed, minTime, maxTime)
end

function Motion.Move(root, targetCFrame, opts)
    opts = opts or {}

    if not root or not root.Parent or typeof(targetCFrame) ~= "CFrame" then
        return false, "INVALID_MOVE"
    end

    local start = root.CFrame
    local distance = (start.Position - targetCFrame.Position).Magnitude

    local duration = Motion.Duration(
        distance,
        opts.Speed,
        opts.MinTime,
        opts.MaxTime
    )

    if distance <= (tonumber(opts.SnapDistance) or 0.35) then
        root.CFrame = targetCFrame
        stopPhysics(root)
        return true, "SNAP", distance, 0
    end

    stopPhysics(root)

    local started = os.clock()

    while root.Parent do
        local elapsed = os.clock() - started
        local alpha = duration > 0 and math.min(1, elapsed / duration) or 1

        -- SmoothStep gives the familiar floating/tween farm look without
        -- engaging Roblox's walking controller or animations.
        local eased = alpha * alpha * (3 - 2 * alpha)

        root.CFrame = start:Lerp(targetCFrame, eased)
        stopPhysics(root)

        if alpha >= 1 then
            break
        end

        RunService.Heartbeat:Wait()
    end

    if root.Parent then
        root.CFrame = targetCFrame
        stopPhysics(root)
        return true, "TWEEN", distance, os.clock() - started
    end

    return false, "ROOT_REMOVED", distance, os.clock() - started
end

function Motion.MoveToPosition(root, position, lookAt, opts)
    if not root or not position then
        return false, "INVALID_POSITION"
    end

    local target

    if lookAt and (lookAt - position).Magnitude > 0.01 then
        target = CFrame.lookAt(position, lookAt)
    else
        target = CFrame.new(position) * (root.CFrame - root.CFrame.Position)
    end

    return Motion.Move(root, target, opts)
end

-- Combat patches/wrappers can reuse the already-loaded helper without
-- repeatedly fetching/compiling it during a 24/7 session.
getgenv().IronSoulWorld1Motion = Motion

return Motion
