# NECROTIDE: LAST STAND

A round-based undead survival shooter for Roblox. Hold **the Ashvault** against
escalating waves of the risen, buy guns off the walls, gamble at the **Fate
Crate**, upgrade at the **Overforge**, drink **Tonics**, and kill four bosses —
the last of them the **Hollow Sovereign** on wave 20.

Everything in this repo is original work: original names, original lore, original
stats, and geometry generated from code. There are no ripped assets, no external
asset IDs and no trademarked terminology. See [Originality](#originality).

---

## Import it into Roblox Studio

Two ways, pick one.

### 1. Open the finished place (easiest)

1. Download **`build/NecrotideLastStand.rbxlx`**.
2. In Studio: **File → Open from File…** and pick it.
3. Press **Play**. That's it — the arena, lighting, HUD and waves all build
   themselves at runtime.

> The editor viewport looks empty before you press Play. That is expected: the
> place file contains only scripts, and `MapBuilder.lua` generates the whole
> arena when the game starts.

### 2. Drag the model into a place you already have

1. Download **`build/NecrotideLastStand.rbxmx`**.
2. In Studio, with your own place open: **right-click Workspace → Insert from
   File…** and pick it (or drag the file onto the viewport). You get a folder
   named `NecrotideLastStand`.
3. Then either:
   - **Just press Play.** The `Boot` script installs everything and the game
     runs immediately. Like any runtime change, that install is discarded when
     you stop — fine for a look, but you have to press Play from the model each
     time.
   - **Install permanently:** open the **Command Bar** (View → Command Bar) and
     run this one line in edit mode, then save your place:
     ```lua
     require(workspace.NecrotideLastStand.Installer)
     ```
     The scripts move into `ReplicatedStorage`, `ServerScriptService` and
     `StarterPlayer.StarterPlayerScripts`, the model deletes itself, and the
     install is saved with the place.

> The game builds its own map into `Workspace.Ashvault` at runtime. If your place
> already has a baseplate or other geometry, the arena will be dropped on top of
> it at the origin — delete your own parts first for a clean result.

### 3. Rojo (if you already use it)

`default.project.json` is included and follows the standard Rojo layout, so
`rojo serve` works against `src/` directly.

---

## Controls

| Input | Action |
| --- | --- |
| **LMB** | Fire (hold for automatic weapons) |
| **R** | Reload |
| **1** / **2** / **Q** / mouse wheel | Swap weapon |
| **E** | Buy from a station / repair a barricade |
| **F** | Revive a downed teammate (hold) |
| **Shift** | Sprint |
| **Left Alt** | Toggle mouse lock |
| **H** | Hide the controls card |

---

## What's in it

### Waves
- Wave count and enemy health scale per wave and per player. Health grows
  linearly to wave 10, then compounds, so wave 25 husks have ~15x the health of
  wave 1 husks.
- A **boss every 5 waves**, the **final boss on wave 20**.
- Clear a wave for a `100 x wave` salvage bonus.
- After the Sovereign dies the game goes **endless**, cycling the bosses with
  scaled health (`GameConfig.EndlessAfterVictory`).

### Enemies
| Enemy | From wave | Notes |
| --- | --- | --- |
| Husk | 1 | the baseline shambler |
| Sprinter | 4 | fast, fragile |
| Crawler | 6 | low, quick, hard to see |
| Ashbrute | 7 | tanky, ground slam |
| Bile Spitter | 9 | ranged acid lob |

### Bosses
| Wave | Boss | Kit |
| --- | --- | --- |
| 5 | **The Rust Warden** | slam, charge, 1 phase shift |
| 10 | **Choir Howler** | shockwave, summons Sprinters, 2 phases |
| 15 | **The Stitcher** | summons Crawlers, blink, slam, 2 phases |
| 20 | **HOLLOW SOVEREIGN** | slam, shockwave, summons, blink, charge — **3 phases**, each one re-arming it with a harder ability set |

Bosses have a screen-wide health bar, a floating nameplate, phase announcements,
and they smash through barricades instead of clawing them.

### Weapons (12, each with an upgraded form)
Vesper .45 · Scrapper SMG · Hornet PDW · Ranger 12 · Cyclone DMR · Talon AR ·
Hailstorm Burst · Carnivore Auto · Reaper LMG · Longbarrow LR · Inferno Tube ·
**Arcbolt Lance** (chain lightning anomaly weapon)

Six are sold on **Armory Racks** bolted to the walls; the rest only come out of
the Fate Crate. Ammo restocks at any rack you own the gun for, at half price.

### The Fate Crate (weapon roulette)
950 salvage a pull, a spinning reel of weapon names, and an ~11% chance the
**Hollow Doll** turns up instead — you get nothing and the crate teleports to one
of five anchors around the map. Guaranteed relocate after 9 pulls.

### The Overforge (weapon upgrade)
5000 salvage. Feeds the gun in your hands into the machine for four seconds and
hands back its forged version: ~3x damage, bigger magazine, tighter spread, a new
name, a glowing receiver, and sometimes a new gimmick — a forged Vesper .45 fires
explosive rounds, a forged Arcbolt Lance chains to 8 targets.

### Tonics (permanent buffs)
Ironhide Draught (+120 vitality) · Quickhands Tincture (55% faster reloads) ·
Deadeye Elixir (+25% damage) · Fleetfoot Serum (+22% speed) · Scavenger Brew
(+35% salvage) · Second Wind Phial (self-revive once per wave)

### Powerups
Dropped by the horde: **Purge Pulse** (wipes the trash), **Resupply Cache** (max
ammo), **Culling Hour** (one-touch kills, 25s), **Salvage Surge** (double
salvage, 30s), **Field Mend** (heals and lifts the whole squad).

### Barricades, downs and revives
Six boarded gaps in the perimeter. Enemies tear boards off one at a time; you
hold **E** to nail them back on for salvage. Take enough damage and you go
**down** instead of dying: 32 seconds to bleed out, a teammate holds **F** to pick
you up, and anyone who bleeds out is back at the start of the next wave. If the
whole squad goes down the run ends and resets after 12 seconds.

---

## Running the tooling

Node 18+ is the only requirement (no Roblox install needed).

```bash
npm install
npm run all        # check + build + verify + test
```

| Script | What it does |
| --- | --- |
| `npm run check` | Syntax-checks every Lua file with `luaparse` |
| `npm run build` | Regenerates `build/*.rbxlx` and `build/*.rbxmx` from `src/` |
| `npm run verify` | Parses the generated XML, confirms the instance tree, and statically resolves every `Net.get`, `require`, `S.Service.method` and `GameConfig.Key` reference |
| `npm run test` | Runs the real game modules headlessly against a Roblox API stub |

### How it is verified without Roblox

Roblox can't be scripted from CI, so this project verifies itself three ways:

1. **Syntax gate.** The game is written in the Lua 5.1-compatible subset of Luau
   (no `+=`, no type annotations, no `continue`), so `luaparse` can parse every
   file offline. `tools/check-lua.js` also bans `]]>`, which would break the
   CDATA blocks in the generated place file.
2. **Static reference checks.** `tools/verify.js` re-parses the built `.rbxlx`,
   walks the `<Item>` tree, asserts every expected script exists with the right
   class, confirms each source file is embedded byte-for-byte, and then resolves
   cross-module references — remote names against `Net.lua`, service methods
   against the service that must define them, config keys against `GameConfig`,
   and weapon/enemy/tonic ids against their rosters.
3. **Headless execution.** `tools/sim/stubs.lua` implements just enough of the
   Roblox API (Instance, Vector3, CFrame, Color3, Enum, services, `task`) to run
   the real modules in a Lua VM (`fengari`). `tools/sim/tests.lua` then boots the
   game for real: it builds the map, initialises all nine services, buys and
   forges a gun, empties and reloads a magazine against a controllable clock,
   downs and revives a player, spawns the Rust Warden and phases it, purges a
   wave, tears and repairs a barricade, and prints the balance table.

Current state: **24 files parsed, 72 static checks, 194 runtime checks, 0
failures.**

```
wave | husk HP | sprinter HP | quota(1p) | quota(4p) | boss
   1 |     130 |          95 |        10 |        23 | -
   5 |     254 |         186 |        30 |        70 | The Rust Warden
  10 |     410 |         300 |        55 |        80 | Choir Howler
  15 |     692 |         505 |        80 |        80 | The Stitcher
  20 |    1166 |         852 |        80 |        80 | HOLLOW SOVEREIGN
  25 |    1965 |        1436 |        80 |        80 | The Rust Warden
```

What this does **not** cover: rendering, physics, animation, networking latency
and anything that needs a real Roblox client. Play-test in Studio before you
publish.

---

## Layout

```
src/
  ReplicatedStorage/NecrotideShared/   shared, replicated to clients
    GameConfig.lua      every balance number in the game
    WeaponDefs.lua      12 weapons + their forged variants
    EnemyDefs.lua       horde roster, 3 bosses, the final boss and its phases
    TonicDefs.lua       buyable permanent buffs
    PowerupDefs.lua     team-wide drops
    Net.lua             every remote, declared in one place
    Util.lua            small helpers
  ServerScriptService/
    Bootstrap.server.lua        builds the map, wires services, starts the rounds
    Services/
      MapBuilder.lua     generates the whole arena from data
      Economy.lua        salvage and leaderstats
      PlayerService.lua  vitality, tonics, downed/revive, squad wipe
      Loadout.lua        weapons, ammo, reloads, the welded gun model
      Combat.lua         server-authoritative hitscan, explosives, chain lightning
      EnemyService.lua   spawning, steering, abilities, bosses, death
      BarrierService.lua boards being torn off and nailed back on
      StationService.lua racks, Fate Crate, Overforge, Tonic Stills
      PowerupService.lua drops and their effects
      WaveService.lua    the round director
  StarterPlayer/StarterPlayerScripts/
    ClientMain.client.lua   input, aiming, remote plumbing
    Modules/Hud.lua         the entire interface, built in code
    Modules/Effects.lua     tracers, muzzle flash, camera kick, sounds
tools/                      build + verification (Node, no Roblox needed)
build/                      the importable .rbxlx and .rbxmx (committed)
```

### Design notes

- **The server is authoritative.** The client sends an aim direction and nothing
  else. The server owns the origin (it always fires from its own copy of your
  head), the spread roll, the raycast, the damage, the fire rate and the ammo.
  A client that lies about its origin by more than 14 studs is ignored.
- **Enemies are not Humanoids.** Each one is a small anchored `Model` moved with
  `Model:PivotTo` on a fixed 20 Hz tick, steering straight at its target when it
  has line of sight and falling back to `PathfindingService` around walls. That
  keeps dozens of them cheap and predictable, with no rig or physics fights.
- **Nothing is stored in the place file but scripts.** The arena, lighting,
  stations, HUD and gun models are all generated at runtime, so the place file is
  ~190 KiB of text you can diff.
- **All balance lives in `GameConfig.lua`** plus the three `*Defs` modules. You
  can retune the entire game without touching a system.

### Tuning examples

| Want | Edit |
| --- | --- |
| Final boss earlier | `GameConfig.FinalBossWave` |
| Bosses more often | `GameConfig.BossWaveInterval` |
| Harder/easier horde | `GameConfig.HealthLinearPerWave`, `HealthExponentialRate`, `EnemyCountPerWave` |
| More enemies on screen | `GameConfig.MaxAliveEnemies` (watch server CPU) |
| Cheaper crate / forge | `GameConfig.CrateBaseCost`, `GameConfig.ForgeCost` |
| A new gun | add an entry to `WeaponDefs.List` (give it an `upgrade` block), then put it on a wall in `MapBuilder.WALL_BUYS` or leave it crate-only |
| A new enemy | add an entry to `EnemyDefs.Normal` with a `minWave` and `weight` |

After editing anything under `src/`, run `npm run all` to rebuild the importable
files.

---

## Originality

The brief asked for a game in this genre that can't get you copyrighted, so
nothing here is borrowed. All code was written for this project; all geometry is
generated by `MapBuilder.lua`; the only external assets referenced are sounds
that ship with the Roblox client itself (`rbxasset://sounds/...`) and one
built-in particle texture. No audio, models, textures, fonts or asset IDs were
taken from anywhere.

Genre mechanics are not protectable, but names and presentation are, so every
term is this project's own:

| Genre convention | This game |
| --- | --- |
| upgrade machine | **The Overforge** |
| random weapon box | **The Fate Crate** |
| the box-moving toy | **The Hollow Doll** |
| perk machines / perks | **Tonic Stills / Tonics** |
| points | **Salvage** |
| wall weapons | **Armory Racks** |
| boarded windows | **Barricades** |
| instakill / max ammo / nuke / double points | **Culling Hour / Resupply Cache / Purge Pulse / Salvage Surge** |
| the map | **The Ashvault** |
| the horde | **Husks, Sprinters, Crawlers, Ashbrutes, Bile Spitters** |
| the bosses | **Rust Warden, Choir Howler, The Stitcher, Hollow Sovereign** |

Weapons are generic archetypes (SMG, DMR, LMG, launcher) under invented names —
no real-world manufacturer or model designations are used. Enemies are stylised
blocky figures that dissolve into ash with no blood or gore.

One practical note: if you publish this, pick your own game title and thumbnail
art too, and don't tag the page with another game's name.

---

## Assumptions made

Decisions taken without asking, all easy to reverse:

- **20 waves to the final boss**, bosses every 5, then endless mode.
- **Two weapon slots** (`GameConfig.MaxWeaponSlots`).
- **No DataStore persistence.** High rounds are not saved — DataStores need API
  access enabled and a published place, which would break the "open it and press
  Play" promise. Leaderstats show salvage and kills for the session.
- **Third-person with mouse lock**, since the gun is a visible welded model.
  Toggle with Left Alt.
- **Solo play is supported**: going down alone ends the run (buy the Second Wind
  Phial to get one self-revive per wave).
- **Friendly fire is off** and explosives don't hurt the thrower.
- No music track is included; add one to `SoundService` if you want a bed.
