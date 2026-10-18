getgenv().IronSoulConfig = {
    FPS_CAP = 8,
    FARM = "NEWBIE",
    TICKETS = "SMART",
    HEADLESS = true,
}

loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/MUshihara/ironsoulkaitun/main/bootstrap.lua"
))()
