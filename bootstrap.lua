-- IRON SOUL KAITUN - STABLE ENTRY
-- Existing loader URLs stay valid; active runtime is versioned here.

local url =
    "https://raw.githubusercontent.com/"
    .. "MUshihara/ironsoulkaitun/main/bootstrap_v61_11.lua"
    .. "?t="
    .. tostring(os.time())

local source = game:HttpGet(url)
local fn, err = loadstring(source)
assert(fn, err)
return fn()
