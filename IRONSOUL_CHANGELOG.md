# Iron Soul Kaitun — Critical Change / Failure Notes

Use only when an old regression must be traced. `START_HERE_CHATGPT.md` + compact memory are the normal entry.

## Current World2 correction
**Evidence:** World2 reached Round4, then old objective resolver attacked `Tree -> IceCrystal -> Tree2`; their `HitCount`/removal was mistaken for progression. Local `PortalD` was also the real route in several stages.

**Fix:**
- `objective_probe.lua`: no broad destructible scan. Enemy/egg first, exact portal first, otherwise attack only the first collidable tagged destructible ray-hit on the route toward authoritative wake/portal. Obvious loot/scenery excluded. Object removal alone is not success.
- `transition_watchdog.lua`: exact current-1 local `Portal*` <=320, safe pre-position + native/touch crossing, no RoundPortal RF, authoritative verification. World2 cannot fall back to legacy far/learned recovery.

## Regressions that must not return
- **Boss skip after one stage:** far replicated Round1 portal was used; >100-stud movement counted as `PORTAL_MOVED`. Never use displacement as progression and never chase far portals.
- **Random scenery farming:** `HitCount`/`DestructibleObject` also exist on trees, chests/coins, IceCrystal and ordinary props. Tag/HitCount alone never means gate.
- **Portal RF skip:** direct RoundPortal remote can skip intermediate rooms/state. API-first does NOT mean force every remote; exact native/touch handshake is required when server state depends on it.
- **V61.9 nil crash:** objective resolver referenced `currentDragonEgg` before safe scope. Optional recovery helpers must fail closed.
- **Lobby line-342 patch failure:** mobile compatibility was added as a fragile late lobby patch. Queue aliases now normalize in bootstrap instead.
- **Watchdog line-408 patch failure:** another late watchdog diff failed to load. Prefer direct wrapper/module behavior over stacking fragile patches.
- **Combat line-9244 drift:** patch order shifted context. Patch loader V2 can re-anchor exact old text, but it cannot rescue a patch written against the wrong effective source.

## Stable milestones worth preserving
- V55.2 World1 full clear: 128 targets, 5 transitions, 0 deaths, headless remote attack, no mouse basic.
- V58 W1 D2: Lv10/P341 -> Lobby Lv11/P355.
- Normal combat and balanced forge are proven useful; do not retune without evidence.

## Permanent engineering rule
Headless/API-first, fast only when server-valid. Priority: enemy/egg -> exact local gate/portal -> verified physical blocker -> bounded recovery. Never click normal UI, never random CFrame through progression, never declare success from movement/object disappearance alone.
