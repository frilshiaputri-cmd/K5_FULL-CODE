-- IRON SOUL - STABLE TUTORIAL ENTRY
-- Keep bootstrap routing stable while tutorial logic is versioned separately.

local loadRaw = getgenv().IronSoulLoadRaw

if type(loadRaw) == "function" then
    local ok, result =
        loadRaw("systems/tutorial_v61_10.lua")

    if ok then
        return result
    end
end

local source = game:HttpGet(
    "https://raw.githubusercontent.com/"
        .. "MUshihara/ironsoulkaitun/main/systems/tutorial_v61_10.lua?t="
        .. tostring(os.time())
)

local fn, err = loadstring(source)
assert(fn, err)
return fn()
