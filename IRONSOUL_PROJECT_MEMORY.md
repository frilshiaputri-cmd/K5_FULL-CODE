# Iron Soul Kaitun — Compact Project Memory

## Goal
24/7 automatic **fresh account -> end progression**. Headless/API-first, fast, low CPU/RAM. No normal clicking.

## Stable foundation
- Tutorial `76701861705540`; Lobby `117533937949084`.
- World1 V61.15 routing stable/frozen through Normal D5.
- World1 traversal = smooth fast CFrame tween/floating, never Humanoid walking.
- Historical combat near Luau local-register ceiling; substantial new behavior stays external or inside existing patch functions.
- Fresh Lobby uses `PlayerData.LevelData.Level` if `LG_Level` is nil.

## World2 / Hell progression
- PlaceId `136216144170036`.
- Normal Trial/internal1 validated.
- Hell Trial/internal6 validated.
- Normal Challenge/internal2 validated, then Hell Challenge/internal7 validated.
- 2026-08-12 hour soak later cleared Normal Penitent/internal3 once, which legitimately unlocked Hell Penitent/internal8.
- Latest planner at Lv26/P7704 correctly selected World2 Hell Penitent.
- Route mapper remains discovery-only in World2; preserve successful transition stack except evidence-backed reliability guards.

### Hell UI vs internal IDs
UI always has five stages: `Trial / Challenge / Penitent / Torment / Inferno`.
- Normal internal1..5 = those five.
- Hell internal6..10 = same five.
- internal6=Hell Trial,7=Hell Challenge,8=Hell Penitent,9=Hell Torment,10=Hell Inferno.
Never describe internal6-10 as visible D6-D10.

## Hell-first V61.30
`systems/hell_planner.lua` commit `a825ea380f61282e67b2195c35cd3b3a0a2f22f5`.
- Hell is default repeat/farm.
- Normal only one-clear unlock bridge to next Hell stage; next Lobby returns to Hell.
- hard server unlock + level gate.
- Hell RecBattlePower blank -> matching Normal rec power proxy.
- script-ready power floor =78% of matching Normal recommendation.
- Latest Lv26/P7704: Hell Penitent ready; Normal Torment bridge needs10920 at78%, so still blocked.

## Cave
- Cave1 `91584731222940`; Cave2 `119524374829397`; Cave3 `132445869992129`.
- one-room Round1; V61.19 chase waits for combat readiness then handles far enemies.
- `systems/cave_planner.lua` V61.30 commit `8e8d8faf5a1f7d6f728c89dd51b2deb96be1e572`.
- demand-driven, highest server-unlocked Cave stage when level met and power >=78% rec; Ticket reserve5, cooldown360.
- Cave1=exact Fortify shards; Cave2=exact Enchant stone blocker; Cave3=no pet/no egg and egg-capable D2+.
- priority Fortify > first-pet egg > Enchant.
- Hour soak Cave1 D3: 3 clears, 35.02/36.39/35.64s, 32/33/35 targets, **0 hits /0 deaths**. Mark D3 Cave1 very stable.

## Pet / first egg
- Cave3 D1 no egg; D2/D3/D4 display Random_Egg.
- `Main_Pet_001` guaranteed DragonIce egg when legitimately active.
- `systems/pet_manager.lua` V61.25 claim/start/equip production; latest still correctly WAIT_EGG at 0 pets/0 eggs.
- Pet Fortify material chain mapped; mutation waits for first pet.

## Skills/combat
- V61.20 level-skill activation passed.
- V61.21 weapon-aware loadout passed.
- V61.22 BaseAttack + native charge-based SkillU passed in Cave/W1/W2/Hell.

## V61.31 threat-first boss combat — HOUR SOAK PASS
Pre-V61.31 Hell Challenge baseline: 276.39s, 19 hits, 3069 damage, 0 deaths, final~37.5%HP.

After V61.31 patch-chain repair, hour soak completed **7 consecutive Hell Challenge settlements, 0 deaths**:
- 253.77s /14 hits/2171 dmg
- 166.03s /10/1518
- 212.38s /12/1798
- 175.02s /7/1089
- 209.02s /8/1237
- 172.02s /8/1221
- 195.01s /6/957
Average: **197.61s, 9.29 hits, 1427 dmg**; median195.01s/8hits/1237dmg.
Versus old baseline this is about -28.5% time, -51% hits, -53.5% damage. Account gear/HP also improved during the hour, so treat this as combined systems improvement, not pure targeting A/B.

Threat-first behavior itself is proven active:
- threshold=`max(1500, PlayerMaxHP*3)` scaled 8421->9258->10734 as MaxHP increased;
- TARGET_PRIORITY selected true 15k-75k threats;
- medium1.6k-4k mobs no longer stole BossLike/Ultimate behavior;
- SkillU reserved for true threats.

Current heights remain: normal9, boss10.25, first evade11.25, wide12.25, lowHP10.5. Do not globally raise height; old 13+ permanent profiles hurt hit registration.

### Hell Penitent current evidence
Latest D8 archive was still RUNNING when ZIP captured: elapsed169.63s, Round6, targets33, hits11, damage3239, deaths0. Player was ~3021/4797 (~63%) when 118126HP boss began. Heavy hits included864/432/324. Not yet a settlement proof.
If completed Hell Penitent continues to show heavy large-boss damage, next combat change should be **pre-emptive HEAVY threat movement** only (candidate threshold ~PlayerMaxHP*6), starting wider/higher before first hit. Do not change global height first.

## V61.31 patch-chain repair
V61.31 initially broke strict patch anchoring because V61.7 added threat config lines and V61.8 expected old adjacency. Fixed existing `combat_v61_8_burst_safe.patch` context, final repair commit `216e7a72c2a1b01d7c3fff345b93b5be971e5cc0`. Hour soak proves current combat patch chain loads.

## V61.32 World2 far-wave stall guard
Hour soak exposed one serious reliability failure:
- Normal Penitent second run reached Round5 after Round4 clear;
- local enemies0, global19, nearest real enemy ~1049 studs;
- state remained GATE for ~895s with no watchdog start; eventually global timeout/lobby.
Do not guess/tween 1000 studs in World2.
Existing `combat_v61_9_unknown_objective.patch` updated commit `ab1e2d83d4ce5ec9e9aaed2ecb2ad5b468601172`:
- World2-only bad signature: GATE has no nearby gateEnemy, nearest real global enemy >=700 studs, same round persists45s;
- telemetry `WORLD2_FAR_WAVE_STALL_ARM/ABORT`;
- sets existing `GLOBAL_TIMEOUT` stopReason so proven failure->Lobby handling restarts run;
- no route/progression is faked, no change to World1/Cave.
Needs live validation when/if rare stall recurs.

## Battle chest truth / next recon
Historical current source `systems/objective_probe.lua` explicitly lists `chest/chest1/chest2/chest3` as ordinary World2 scenery/loot, separate from progression blockers. It also treats non-empty `DropLootId` as loot/scenery. Trees/chests/coins/IceCrystal can all share `DestructibleObject` + HitCount/PowerRate, so NEVER generically attack all destructibles or treat chest removal as progression.
The same source proves tagged physical destructibles can be damaged through the normal headless Skill1/2 + BaseAttack route while metric attributes change, but exact Chest reward identity/delta is not yet live-proven.
Next diagnostic: `IronSoul_BattleChest_Recon_V61_33.lua`, run during battle while a chest is visible; best test manually breaks exactly one chest during 75s capture. It records chest path/tags/attrs/DropLootId/interactions/source and PlayerData before/after resource delta.
Future production design: **enemy/boss/DragonEgg first -> current room locally clear -> optional current-room chest collector with tiny time budget -> gate/portal**. Chest never counts as progression success.

## Blessing/Fortify
Blessing=player-facing Fortify system. V61.23 automatic guaranteed +4 only, useful gear, reserve2 shards +10k Currency1, verify mutations.
Latest Lv26/P7704 state had Weapon Single_Hell_T2 +3, Breastplate +1, Helmet +4, CrystalShards2, exact remaining shards9.

## Smart Enchant
V61.24 exact write live-validated. +4 keeper, existing empty slots only, one action/Lobby, no overwrite/UnEnchant.
Latest demand had no eligible empty slots.

## Grocery V61.30
Exact Gold buy protocol: `ConsumableShopUtil.RemoteEvent:FireServer("BuyShopItem", "Gold", itemConfigId)`.
`systems/shop_manager.lua` commit `2650ec92f15a489ca36603e40ee80c19f100b2e3` buys only exact Fortify/Enchant blockers, no paid refresh, reserve20k, max3 buys/Lobby, verifies resource delta.
Hour soak included an earlier live cycle buying CrystalShards x3 three times for3000 total and then rerunning Fortify successfully. Latest rotation had no exact blocker, so correctly bought0.

## Current chain
`Forge/EquipBest -> Pet acquisition -> Fortify -> Enchant -> Grocery blocker -> re-run upgrade if bought -> SMART Cave -> Hell-first -> one-clear Normal bridge only to unlock next Hell -> Story fallback`.

## Immediate priorities
1. Continue normal loader; validate Hell Penitent settlement and observe V61.32 only if rare far-wave stall recurs.
2. Run Battle Chest Recon V61.33 when a battle chest is visible; manually open/break exactly one chest during capture.
3. If chest protocol/reward is proven, add isolated post-room loot collector; never merge it into progression objective resolver.
4. If Hell Penitent completed runs remain hit-heavy, implement pre-emptive heavy-threat movement (~6x MaxHP candidate) while preserving 9-stud normal profile.
5. First pet -> one controlled pet growth mutation -> exact Cave3 material demand.
6. Later: potion use policy, adaptive 78% difficulty threshold based on success/death history, higher-risk Blessing +5+ EV policy, Endless.