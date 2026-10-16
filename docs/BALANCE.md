# Balance

How the game's numbers were tuned (Phase 21), what they aim for, and how to
re-check them after a change.

## How it is measured
A scripted bot (`tests/support/run_bot.gd`) plays whole runs headless through
the same inputs and run calls a player uses: it kites away from zombies while
weapons auto-fire, fetches crates and loot when it's safe, heals when low,
uses boosts, throws grenades at clusters and prefers a weapon with ammo.
Two skill presets:

| Skill | Reaction | Notices zombies within | Heals below | Grenade at a cluster of |
|---|---|---|---|---|
| `casual` (the target player) | ~200 ms, sloppy steering | 90 px | 30% HP | 6 |
| `good` | every frame | 112 px (pistol), 105 (SMG), 82 (shotgun) | 45% HP | 4 |

The flee radius is capped at 75% of the current weapon's range so the bot
always shoots back; that cap is why `good` is 112 px rather than its preset
130, and why both presets flee at 82 px with the shotgun.

`tests/balance_sim.gd` plays several runs per **profile** (player progress)
and writes one JSON line per run:

| Profile | Weapons | Upgrades | Brought from the stash |
|---|---|---|---|
| `fresh` | pistol | none | nothing |
| `smg` | pistol, SMG | none | nothing |
| `mid` | pistol, SMG, shotgun | Toughness 2, Firepower 2, Sprint 1, Ammo Pouch 1 | 3 medkits, 2 grenades |
| `late` | all | everything maxed (Backpack 2) | 6 medkits, 6 grenades, 2 Rage, 2 Vitality, 120 SMG ammo |

```
godot --headless --path . --fixed-fps 60 -s res://tests/balance_sim.gd -- \
    --profile=fresh --skill=casual --runs=6 --max-wave=22 --out=/tmp/sim/fresh_casual.jsonl
python3 tests/support/summarize_sim.py /tmp/sim            # one row per profile/skill
python3 tests/support/summarize_sim.py /tmp/sim --waves    # per-wave medians
```
Each run takes 5–60 s of wall time. Several simulations can run at once (each
uses its own save file), but don't run the regular test suite at the same
time: every test-mode process clears `user://test_save.json` when it starts.

The bot is a proxy, not a person. It never panics, but it also never plans
routes; treat the numbers as relative and confirm with real playtests.

## Targets
"Wave" = median wave reached, i.e. the wave the bot died in (casual skill
unless stated).

| # | Target |
|---|---|
| T1 | `fresh`: wave 5–7 (`good`: 7–10) |
| T2 | `smg`: wave 7–10, at least one wave better than `fresh` |
| T3 | `mid`: wave 10–14 |
| T4 | `late`: wave 15+ |
| T5 | Waves 1–8 last ≤ 75 s of combat for `fresh` / `smg`; no wave before 15 above 150 s |
| T6 | `fresh` earns 60–130 coins a run (one run buys a 40–60 coin upgrade, the SMG takes ~3–5 runs); `mid` 200–450 |
| T7 | No medkit pile-up: `fresh` holds ≤ 6 medkits after wave 5 and uses medkits in most runs |
| T8 | Ammo pressure: with the SMG the bag runs low (< 60) in most runs, but the SMG still fires most shots |
| T9 | Loot: `fresh` sees 0.3–1.5 non-ammo items per wave in waves 1–5; ≤ 0.3 boost drops per wave before wave 10 |
| T10 | Pressure is readable: more / faster / tougher zombies and less free healing, no single cliff wave; the 80-speed player outruns every zombie |

## Results
Before: 3 runs per cell, capped at wave 20. After: 6 runs per cell, capped at
wave 25. "≥" marks cells where some runs survived to the cap (counted as the
cap). Longest wave = slowest single cleared wave before wave 15.

| Profile / skill | Wave before | Wave after | Coins / run before | after | Longest wave (after) |
|---|---|---|---|---|---|
| fresh / casual | 16 (16–18) | **7** (6–9) | 987 | **134** | 86 s |
| fresh / good | 17 (17–18) | **7** (5–8) | 1177 | 156 | 78 s |
| smg / casual | ≥20 (17–20) | **9** (7–9) | 1647 | 205 | 72 s |
| smg / good | 19 (18–19) | 8.5 (7–9) | 1406 | 183 | 61 s |
| mid / casual | 20 (19–20) | **11** (11–12) | 1551 | 309 | 43 s |
| mid / good | ≥20 (20) | 12 (11–13) | 1599 | 344 | 51 s |
| late / casual | ≥20 (all capped) | **19.5** (18–24) | 1760 | 854 | 46 s |
| late / good | ≥20 (all capped) | ≥23 (19–25, 2 capped) | 1712 | 1167 | 45 s |

Before, a kiting player took no damage until wave 7–8, health crates gave
3 medkits per break (24 in the bag by wave 7), and waves 10+ dragged on for
2–5 minutes. After, for fresh / casual (medians over runs that cleared the
wave): first real damage in wave 4, 2–7 medkits in the bag after wave 5
(median 3.5) and every run uses its medkits, waves 1–7 take 20–50 s. With the
SMG the bag ammo drops below 60 in every run and the pistol fills in for
0–10% of shots. Non-ammo loot for fresh players averages ~0.4 items per wave
in waves 1–5, with no boost drops before wave 10. Frame cost stays ~0.2 ms
per tick headless.

Targets: T1–T4 and T7–T10 are met. Two sit on the edge of their band:
- T6: fresh / casual earns 134 coins a run (99–211), just over the 130
  ceiling; the previous 6-run batch gave 125. The SMG still costs ~3 runs.
- T5: the one fresh run that cleared wave 8 took 86 s; waves 1–7 stay
  ≤ 50 s and nothing before wave 15 passes 86 s in any profile.
T1 for `good` sits on the floor: the good bot dies at about the same wave as
the casual one, because once walkers are fast the crowd decides the run more
than reaction time.

## What changed (and why)
Chosen from three independent proposals (zombie threat, resource attrition,
wave curve), each verified with the simulation, then judged against the
targets; the "threat" proposal won, with two grafts and one small code change.

| Data | Before → after | Why |
|---|---|---|
| Walker speed / damage / HP | 28 / 5 / 10 → **50 / 12 / 12** | The main lever. At 28 the crowd never reached a kiting player; now it closes in from wave 3–4 and a touch costs ~12% HP |
| Runner speed / damage / HP | 55 / 3 / 6 → **64 / 7 / 8** | Chip damage; still slower than the player (max 79.4 with the speed cap) |
| Brute speed / damage | 18 / 15 → **28 / 30** | A slow tank that actually pushes; one hit costs 30% HP |
| Runner weight / first wave | 4 / wave 3 → **8 / wave 2** | Pressure starts earlier |
| Brute first wave | 5 → **4** | A tank in wave 4; also the main early source of item loot |
| Brute Rage / Vitality drop chance | 0.05 → **0.03** | Brutes come earlier, keep boosts rare (T9) |
| Zombies per wave | +6 → **+3** | Flatter growth: upgrades buy many more waves, waves stay short |
| HP growth per wave | 12% → **10%** | Same: keeps late waves short |
| Speed growth per wave / cap | 3%, ×1.6 → **2.5%, ×1.24** | Faster base speeds, but runners never outrun an unupgraded player |
| Spawn interval / minimum | 0.8 s / 0.1 s → **0.5 s / 0.25 s** | Waves arrive as a crowd early, but big late waves build up instead of dropping at once |
| Crates per break | 3 → **2** | Less free healing. With 2 crates the mix is a fixed 1 health + 1 ammo; the HP-vs-ammo rule only picks the 3rd crate onward |
| Crates when no weapon uses ammo | (same as above) → **1** (`WaveTable.health_only_crates`) | They would all be health crates; this was the medkit pile-up |
| Medkit heal / price | 40 HP / 30 → **25 HP / 20** | Less healing per kit; cheaper so bought kits stay worth it |
| SMG unlock | 300 → **400** | ~3 fresh runs at ~125 coins each |

Kept as they were: coin values, item stack limits (ammo 120 / 24, everything
else 3), grenade stats, weapon damage, upgrade prices. The economy targets are
met by the shorter runs alone.

## Known limits
- Six runs per cell: single runs vary by ±1–2 waves. Run more before small tweaks.
- The bot can't feel frustration: if real players find walkers (50 speed,
  12 damage) too punishing on a phone, lower walker `contact_damage` to 9–10
  first and re-run the sim.
- `late` runs last 18–25 waves; the curve beyond wave 25 is untested.
- Not simulated: buying items from the shop between runs, the Coin Magnet's
  effect on coins (the bot vacuums coins at wave end anyway).
