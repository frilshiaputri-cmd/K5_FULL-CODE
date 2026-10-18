-- IRON SOUL - V61.9 TELEMETRY ENTRY
-- Applies V61.6 multi-match telemetry, scope hardening, journal metadata,
-- settlement finalization, and terminal-summary protection.

local function getPatcher()
    local loadRaw =
        getgenv().IronSoulLoadRaw

    if type(loadRaw) == "function" then
        local ok, patcher =
            loadRaw(
                "systems/patch_loader.lua"
            )

        if ok
            and type(patcher) == "function"
        then
            return patcher
        end
    end

    local source =
        game:HttpGet(
            "https://raw.githubusercontent.com/MUshihara/ironsoulkaitun/main/systems/patch_loader.lua?t="
                .. tostring(os.time())
        )

    local fn, err =
        loadstring(source)

    assert(fn, err)

    local patcher = fn()
    assert(
        type(patcher) == "function",
        "V61.9 telemetry patch loader unavailable"
    )

    return patcher
end

return getPatcher()({
    repository = "MUshihara/ironsoulkaitun",
    base_commit = "1d47f7f50ec8ecd92bca691b17d586d6bdecfa55",
    path = "systems/telemetry.lua",
    patch_paths = {
        "systems/patches/telemetry_v61_6.patch",
        "systems/patches/telemetry_v61_6_hotfix.patch",
        "systems/patches/telemetry_v61_9_journal_metadata.patch",
        "systems/patches/telemetry_v61_7_settlement_finalize.patch",
        "systems/patches/telemetry_v61_9_terminal_summary.patch",
    },
})
