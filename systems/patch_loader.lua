--========================================================--
-- IRON SOUL - IMMUTABLE BASE PATCH LOADER V2
--
-- Loads an immutable historical source revision, applies verified unified
-- diffs stored in this repo, then compiles/executes the patched source.
--
-- V2 keeps exact-context safety but no longer trusts stale hunk line numbers
-- blindly. If prior patches shift a later hunk, the loader re-anchors that
-- hunk only when its complete unchanged/removed source sequence matches.
--========================================================--

local function splitLines(text)
    text = tostring(text or "")
        :gsub("\r\n", "\n")
        :gsub("\r", "\n")

    local finalNewline =
        string.sub(text, -1) == "\n"

    if finalNewline then
        text = string.sub(text, 1, -2)
    end

    local out = {}

    if text ~= "" then
        for line in string.gmatch(
            text .. "\n",
            "(.-)\n"
        ) do
            table.insert(out, line)
        end
    end

    return out, finalNewline
end

local function applyUnifiedDiff(
    source,
    patch,
    targetPath
)
    local src,
        finalNewline =
            splitLines(source)

    local diff =
        select(1, splitLines(patch))

    if diff[1]
        ~= "--- a/" .. targetPath
        or diff[2]
            ~= "+++ b/" .. targetPath
    then
        error(
            "patch target mismatch for "
                .. tostring(targetPath)
        )
    end

    local out = {}
    local srcIndex = 1
    local i = 3

    local function copyUntil(lineNumber)
        while srcIndex < lineNumber do
            table.insert(
                out,
                src[srcIndex]
            )
            srcIndex += 1
        end
    end

    local function sourceRowsForHunk(
        firstRow,
        lastRow
    )
        local rows = {}

        for n = firstRow, lastRow do
            local row = diff[n]
            local prefix =
                string.sub(row, 1, 1)

            if prefix == " "
                or prefix == "-"
            then
                table.insert(
                    rows,
                    string.sub(row, 2)
                )
            end
        end

        return rows
    end

    local function hunkMatchesAt(
        position,
        sourceRows
    )
        if position < srcIndex then
            return false
        end

        if #sourceRows == 0 then
            return true
        end

        if position + #sourceRows - 1
            > #src
        then
            return false
        end

        for offset, expected in ipairs(
            sourceRows
        ) do
            if src[position + offset - 1]
                ~= expected
            then
                return false
            end
        end

        return true
    end

    local function resolveHunkStart(
        expectedStart,
        sourceRows
    )
        if #sourceRows == 0 then
            return math.max(
                srcIndex,
                expectedStart
            )
        end

        if hunkMatchesAt(
            expectedStart,
            sourceRows
        )
        then
            return expectedStart
        end

        -- Search the remaining immutable/patched source for the exact old
        -- hunk sequence. Choose the unique nearest match to the recorded
        -- location. This tolerates line drift but never fuzzy text changes.
        local best = nil
        local bestDistance = math.huge
        local tied = false

        local lastPossible =
            #src - #sourceRows + 1

        for position = srcIndex,
            lastPossible
        do
            if hunkMatchesAt(
                position,
                sourceRows
            )
            then
                local distance =
                    math.abs(
                        position
                        - expectedStart
                    )

                if distance < bestDistance then
                    best = position
                    bestDistance = distance
                    tied = false
                elseif distance == bestDistance then
                    tied = true
                end
            end
        end

        if best and not tied then
            return best
        end

        if tied then
            error(
                "patch hunk anchor ambiguous near source line "
                    .. tostring(expectedStart)
                    .. " for "
                    .. tostring(targetPath)
            )
        end

        error(
            "patch hunk source not found near source line "
                .. tostring(expectedStart)
                .. " for "
                .. tostring(targetPath)
        )
    end

    while i <= #diff do
        local line = diff[i]

        if string.sub(line, 1, 2)
            == "@@"
        then
            local oldStart,
                oldCount,
                newStart,
                newCount =
                    string.match(
                        line,
                        "^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@"
                    )

            oldStart = tonumber(oldStart)

            if oldStart == nil then
                error(
                    "bad hunk header: "
                        .. tostring(line)
                )
            end

            local firstRow = i + 1
            local lastRow = firstRow - 1
            local scan = firstRow

            while scan <= #diff
                and string.sub(
                    diff[scan],
                    1,
                    2
                ) ~= "@@"
            do
                lastRow = scan
                scan += 1
            end

            local sourceRows =
                sourceRowsForHunk(
                    firstRow,
                    lastRow
                )

            local anchor =
                resolveHunkStart(
                    oldStart,
                    sourceRows
                )

            copyUntil(anchor)
            i = firstRow

            while i <= lastRow do
                local row = diff[i]
                local prefix =
                    string.sub(row, 1, 1)

                local body =
                    string.sub(row, 2)

                if prefix == " " then
                    if src[srcIndex]
                        ~= body
                    then
                        error(
                            "patch context mismatch at source line "
                                .. tostring(srcIndex)
                                .. " for "
                                .. tostring(targetPath)
                        )
                    end

                    table.insert(out, body)
                    srcIndex += 1

                elseif prefix == "-" then
                    if src[srcIndex]
                        ~= body
                    then
                        error(
                            "patch removal mismatch at source line "
                                .. tostring(srcIndex)
                                .. " for "
                                .. tostring(targetPath)
                        )
                    end

                    srcIndex += 1

                elseif prefix == "+" then
                    table.insert(out, body)

                elseif prefix == "\\" then
                    -- "No newline at end of file" marker.

                elseif row ~= "" then
                    error(
                        "unexpected patch row: "
                            .. tostring(row)
                    )
                end

                i += 1
            end
        else
            i += 1
        end
    end

    while srcIndex <= #src do
        table.insert(
            out,
            src[srcIndex]
        )
        srcIndex += 1
    end

    local result =
        table.concat(out, "\n")

    if finalNewline then
        result ..= "\n"
    end

    return result
end

return function(opts)
    assert(
        type(opts) == "table",
        "patch loader options missing"
    )

    local repository =
        assert(opts.repository)

    local baseCommit =
        assert(opts.base_commit)

    local targetPath =
        assert(opts.path)

    local patchPaths =
        opts.patch_paths

    if type(patchPaths)
        ~= "table"
    then
        patchPaths = {
            assert(opts.patch_path),
        }
    end

    local baseUrl =
        "https://raw.githubusercontent.com/"
        .. repository
        .. "/"
        .. baseCommit
        .. "/"
        .. targetPath

    local patched =
        game:HttpGet(baseUrl)

    for index, patchPath in ipairs(
        patchPaths
    ) do
        local patchUrl =
            "https://raw.githubusercontent.com/"
            .. repository
            .. "/main/"
            .. patchPath
            .. "?is_patch="
            .. tostring(index)
            .. "&t="
            .. tostring(os.time())

        local patch =
            game:HttpGet(patchUrl)

        patched =
            applyUnifiedDiff(
                patched,
                patch,
                targetPath
            )
    end

    local fn, err =
        loadstring(patched)

    if not fn then
        error(
            "patched compile failed: "
                .. tostring(targetPath)
                .. " | "
                .. tostring(err)
        )
    end

    return fn()
end
