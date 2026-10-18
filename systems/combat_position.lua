-- IRON SOUL - V61.8 COMBAT POSITION ENTRY
-- Applies V61.7 burst-lock positioning plus V61.8 recovery hardening
-- to immutable V61.4 combat_position.

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
        "V61.8 combat position patch loader unavailable"
    )

    return patcher
end

return getPatcher()({
    repository = "MUshihara/ironsoulkaitun",
    base_commit = "602aed720534a355a2633433a951659c396c3227",
    path = "systems/combat_position.lua",
    patch_paths = {
        "systems/patches/combat_position_v61_7_burst_lock.patch",
        "systems/patches/combat_position_v61_8_burst_safe.patch",
    },
})