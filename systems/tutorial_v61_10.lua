-- IRON SOUL - STABLE VERSIONED TUTORIAL REDIRECT
local loadRaw = getgenv().IronSoulLoadRaw

if type(loadRaw) == "function" then
    local ok, result = loadRaw("systems/tutorial_v61_11.lua")
    if ok then
        return result
    end
end

local url =
    "https://raw.githubusercontent.com/"
    .. "MUshihara/ironsoulkaitun/main/systems/tutorial_v61_11.lua"
    .. "?t="
    .. tostring(os.time())

local source = game:HttpGet(url)
local fn, err = loadstring(source)
assert(fn, err)
return fn()
