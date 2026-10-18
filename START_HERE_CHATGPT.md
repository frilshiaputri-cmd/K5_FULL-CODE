# Iron Soul Kaitun — START HERE

Read this, then `IRONSOUL_PROJECT_MEMORY.md`, then inspect current repo. Long changelog is optional.

## Non-negotiable
- 24/7 **fresh account -> end progression**.
- **Headless/API-first:** remotes/modules/server state; no normal mouse/GUI clicking.
- **World1 movement = fast smooth CFrame tween/floating, NOT Roblox walking.** Do not use `Humanoid:MoveTo`/`Humanoid:Move` for gate/portal traversal.
- Tween toward exact/current progression, dwell about **0.60s before final portal touch/cross**, and require authoritative evidence.
- Movement/crossed-plane/raw displacement alone is never progression proof.
- Preserve proven paths unless evidence requires change.
- Historical `combat.lua` is near Luau's local-register ceiling: substantial new logic belongs in external modules/wrappers or existing patches updated in place.
- Diagnostics are downloadable `.lua`; result/log files may be `.txt`.

## Fresh Lobby truth
- Lobby `117533937949084` is the progression brain.
- Fresh PlayerData may be ready while `LG_Level=nil`; real level is `PlayerData.LevelData.Level`.

## World1 — STABLE
Fresh accounts progressed repeatedly through World1 Normal D1-D5. V61.15 routing remains baseline; do not casually retune World1 traversal/combat.

## World2 — NORMAL D1 + HELL TRIAL VALIDATED
- PlaceId `136216144170036`.
- Normal D1 unattended clear: settlement166.89s, GameRound6, 66 targets, 0 deaths, GateSuccess1/GateFail0, watchdog0, PortalsInvoked4.
- **Hell Trial** unattended clear: internal `Diff=6`, settlement179.14s, GameRound6, 51 targets, 0 deaths, GateSuccess1/GateFail0, watchdog0; BaseAttack + SkillU worked.
- Existing combat/transition stack handled both modes; route mapper remains discovery-only in W2.

### CRITICAL Hell stage mapping
The UI has only five visible stage buttons in both modes:
`Trial / Challenge / Penitent / Torment / Inferno`.

Internal IDs are:
- Normal Trial..Inferno = `Diff 1..5`.
- Hell Trial..Inferno = `Diff 6..10`.

Therefore **internal Diff6 means Hell Trial**, not a player-visible sixth difficulty.
For World2:
- Hell Trial internal6 unlock key `World2|1` — currently unlocked and live-cleared.
- Hell Challenge internal7 unlock key `World2|2` — currently locked until the corresponding Normal Challenge clear.
- Hell Penitent internal8 -> `World2|3`.
- Hell Torment internal9 -> `World2|4`.
- Hell Inferno internal10 -> `World2|5`.

## Hell-first progression V61.30
`systems/hell_planner.lua` now treats Hell as the default repeat/farm path because rewards are better.
- Do **not** permanently return to Normal just because a Normal stage becomes ready.
- Use Normal only as a **one-clear unlock bridge** when that corresponding Normal clear opens the next Hell stage.
- Immediately return to Hell on the next Lobby cycle.
- Level recommendation is a hard gate.
- Hell configs omit RecBattlePower, so use the matching Normal stage as a power proxy.
- Aggressive script-ready power floor = **78%** of that Normal recommendation.
- Never force a server-locked Hell stage.

Current intended W2 behavior:
`Hell Trial -> when Normal Challenge is unlocked + level-ready + >=78% power, clear Normal Challenge ONCE -> Hell Challenge -> repeat Hell Challenge -> later bridge Normal Penitent once -> Hell Penitent -> ...`.

Production commit: `a825ea380f61282e67b2195c35cd3b3a0a2f22f5`.

## Cave baseline
- Cave1 `91584731222940`; Cave2 `119524374829397`; Cave3 `132445869992129`.
- All are one-room Round1 resource activities. No Story doors/portals.
- `cave_chase.lua` V61.19 waits for combat-controller readiness before moving; preserve this safety.
- Cave2/Cave3 mobile validated; one Cave clear -> Lobby.

## SMART Cave V61.30 — AGGRESSIVE HIGHEST UNLOCKED TIER
`systems/cave_planner.lua` remains demand-driven, but stage selection is intentionally less conservative.
- server-unlocked stage is mandatory;
- **recommended level is a hard gate**;
- recommended power is not strict: allow stage when current power is at least **78%** of recommendation;
- among eligible stages, choose the **highest currently unlocked** tier;
- Ticket1 reserve5 and cooldown360s remain.
- Cave1 demand = exact Blessing/Fortify CrystalShards blocker.
- Cave2 demand = useful +4 keeper has empty enchant slot and zero usable Enchanted Stones.
- Cave3 first-pet demand = zero pets + zero eggs and egg-capable D2+ available.

This means a Cave recommending Power2880 is eligible around Power2247 if its level requirement and server unlock are satisfied. If the Cave requires Lv16 and account is Lv15, do **not** enter even if power is enough.

Production commit: `8e8d8faf5a1f7d6f728c89dd51b2deb96be1e572`.

### Cave3 egg truth
- D1 display rewards: pet-growth materials, **no egg**.
- D2/D3/D4 display `Random_Egg` plus increasingly advanced pet materials.
- Therefore highest eligible D2+ Abandoned Courtyard is a legitimate chance-based first-pet source.
- `ResMainTask.Main_Pet_001` separately defines a guaranteed `Pet_DragonIce_Egg|Egg|1`; claim only when legitimately active.

## Pet acquisition V61.25
`systems/pet_manager.lua` restores V20 claim/start/equip behavior:
- claim completed hatch and verify;
- read `PlayerData.PetHatch.Egg`;
- start highest-rarity owned egg in free slot via `StartHatch` and verify EggUUID;
- EquipBest after pet exists;
- no GUI/clicking/paid pet action; non-blocking.
Latest production state was correctly `WAIT_EGG`: 0 pets, 0 eggs, 3 empty hatch slots.

## Pet growth
- `PetsFortifyUtil` and `PetsUpgradeUtil` mapped.
- Pet Fortify costs use BrokenDragonScale -> WholeDragonScale -> DragonClaw -> DragonHorn/etc.
- Star1..9 Fortify caps 10/20/.../90.
- Exact live mutation remains disabled until an actual pet exists.

## Skill/combat baseline
- Level Skill branches = Level + weapon proficiency; activate only server-granted branches.
- V61.21 weapon-aware best loadout passed.
- V61.22 restored continuous headless BaseAttack and native charge-based SkillU; W1/W2/Cave/Hell Trial show verified basics and real Ultimates.

## Blessing / Fortify
- Blessing is player-facing name; internal system = `Fortify`/`FortifyUtil`.
- V61.23 production auto-upgrades useful gear only through guaranteed +4, reserves2 shards + Currency1 10000, verifies every mutation.

## Smart Enchant V61.24
- Exact write validated: `EquipmentRE:FireServer("Enchant", equipmentUUID, slotKey, stoneUUID)`.
- Keeper +4 minimum; existing empty slots only; one verified action/Lobby; no overwrite/UnEnchant.

## Grocery V61.30 — PURCHASE PROTOCOL PROVEN + PRODUCTION
V61.29 source recon proved exact client write:
`ConsumableShopUtil.RemoteEvent:FireServer("BuyShopItem", "Gold", itemConfigId)`.

Server source verifies rotation, stock, Currency1, daily limit, grants configured item, then updates BuyCount/DailyPurchaseCount.

Useful Gold stock can include:
- CrystalShards x3 / 1000.
- Burn_3/Methysis_3/Frost_3/Corrode_3 / 3000.
- BrokenDragonScale x5 /1000; WholeDragonScale x5 /2000; DragonClaw x5 /3500; DragonHorn x5 /5000; DragonTear x5 /7500.
- EXP/Drop/Attack/HP/etc potions and Hell ores.

`systems/shop_manager.lua` V61.30:
- buys **only an exact Fortify or Enchant blocker** from the current Gold rotation;
- no paid/manual refresh;
- Currency1 reserve20000;
- max3 purchases/Lobby;
- >=0.40s between purchases;
- verifies stock decrease + Currency decrease + actual resource/stone increase.
- pet-material buying waits until real pet-growth demand exists.
- potions are mapped but not auto-bought/used yet.

Production commit: `2650ec92f15a489ca36603e40ee80c19f100b2e3`.

## Current upgrade chain V61.30
`Forge/EquipBest -> Pet acquisition -> Blessing/Fortify -> Smart Enchant -> Grocery exact blocker -> re-run upgrades if shop bought -> SMART Cave exact blocker -> Hell-first planner -> Normal only when needed as Hell unlock bridge -> Story fallback only if Hell cannot handle`.

Preflight integration commit: `3c361ed55bb809f3038c604c8788c430bcb7f1ab`.

## Next validation
Run normal loader. Desired evidence:
1. Grocery buys CrystalShards only when current rotation has them and Fortify actually needs them; verifies purchase and re-runs Fortify before Cave.
2. Cave uses highest unlocked stage whose level is met and whose power floor >=78% rec.
3. W2 stays Hell Trial by default until Normal Challenge bridge becomes eligible; then Normal Challenge is cleared once and Hell Challenge should become the next default.
4. Keep World2 active routing unchanged unless specific D2+/Hell-stage evidence fails.
5. First pet -> controlled growth mutation -> exact Cave3 material demand.

## Settlement / replay
- Inventory maintenance threshold85; full/high inventory -> Lobby.
- Replay waits bounded; stuck/full replay -> Lobby.

Repo is source of truth when chat memory conflicts.