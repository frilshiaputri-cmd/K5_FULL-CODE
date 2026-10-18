IRON SOUL V59.6 - BAG AWARE PATCH

Replace:
  systems/combat.lua
  systems/lobby.lua

Keep:
  bootstrap.lua
  systems/tutorial.lua

FULL BAG:
  Settlement -> NO Play Again -> return Lobby.
  Lobby -> normal equipment cleanup -> recheck bag.
  Still full -> STOP before matchmaking.

This prevents entering a dungeon that the game says will give no rewards.

Ore auto-selling is not guessed. Run the included/read-only
OreBagSellRecon in Lobby and send its generated folder so the exact native
sell route can be mapped safely.
