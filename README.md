# NECROTIDE: LAST STAND

A round-based undead survival shooter for Roblox. Hold **the Ashvault** against
escalating waves of the risen, buy guns off the walls, gamble at the **Fate
Crate**, upgrade at the **Overforge**, drink **Tonics**, and kill four bosses —
the last of them the **Hollow Sovereign** on wave 20.

Everything in this repo is original work: original names, original lore, original
stats, and geometry generated from code. There are no ripped assets, no external
asset IDs and no trademarked terminology. See [Originality](#originality).

---

## Can Claude edit straight into my Studio?

Not literally, and nothing can — but `npm run live` gets you the practical
version of it: **Claude pushes a commit, and a few seconds later the script has
changed inside your open place. You do nothing.**

```bash
npm run live      # leave this one window open; that is the whole workflow
```

That command serves the code to Studio *and* watches GitHub. Every 15 seconds it
fetches; when a commit lands it pulls and hands the files to the running Rojo
server, which streams them into your open place. On a Mac you can double-click
**`live-sync.command`** instead.

What it prints when a change arrives:

```
23:41:07 live  pulled 1 commit(s) from origin/main
         live  2 file(s) changed, 1 of them scripts:
         live    src/ServerScriptService/Services/WaveService.lua
         live  Rojo is pushing them into Studio now
```

Why the "not literally":

- **A Studio session only accepts connections from its own machine.** The Rojo
  server listens on `localhost` — your MacBook — and there is no remote port to
  reach even if you wanted one. Claude runs on a different machine with no route
  to yours, so the repo is the channel between us: Claude commits, the watcher on
  your side pulls.
- **So one process has to be running on your machine.** That is `npm run live`.
  Close the window and the link is gone until you start it again; nothing is
  lost, it just stops updating.
- **It only touches the three code containers** `default.project.json` maps.
  Anything you build by hand in the viewport is never overwritten — see
  [Editing it together](#editing-it-together).
- **Roblox's Open Cloud API can publish a whole place to a live game**, and an
  agent with an API key could do that. It replaces the published version and
  cannot touch an *open editor* — so it is publishing, not editing, and this repo
  deliberately does not ask you for that key.

If you would rather approve every change by hand, use `npm run sync` (serve only)
and run `npm run pull` when you want the new code. Same result, one more step.

---

## Get it into Roblox Studio

Three ways. **Live sync** is the one you want if you are going to keep editing
the code; the other two are one-shot imports.

### 1. Live sync with Rojo (edit here, see it in Studio)

[Rojo](https://rojo.space) streams `src/` into an open Studio place: save a
file, the matching script updates a second later. This is the setup to use if
you are going to keep working on the game — yours is the only copy of the place,
and the code lives in git.

#### macOS (MacBook)

You need [Node](https://nodejs.org) 18 or newer — `node -v` to check, `brew
install node` or the installer from nodejs.org if you don't have it. Then, in
Terminal:

```bash
git clone https://github.com/MOTOMOTO2/roblox-zombie-survival.git
cd roblox-zombie-survival
npm run setup     # fetches the pinned Rojo into .tools/ and installs the Studio plugin
npm run live      # serves the code AND auto-pulls new commits - leave this open
```

`npm run setup` is a first-run-only step. After that, one command is the whole
ritual — or double-click a `.command` file in Finder, which does both and needs
no Terminal knowledge:

| | serves `src/` to Studio | pulls new commits by itself |
|---|---|---|
| `npm run live` / `live-sync.command` | yes | yes, every 15s |
| `npm run sync` / `start-sync.command` | yes | no — you run `npm run pull` |

Use `live` unless you specifically want to approve each change.

**Quit Studio completely and reopen it** after the first `npm run setup`, or the
new plugin won't be loaded.

#### Windows

Identical, with the same commands, in PowerShell or Git Bash. The `.command`
files are macOS-only; use `npm run live` (or `npm run sync`).

#### Connecting the place you already have open

1. Open your place in Studio (the one you imported — or **File → New** if you'd
   rather start clean, since all the content is generated from code).
2. **Plugins → Rojo → Connect**. The defaults, `localhost` port `34872`, are
   exactly what `npm run sync` serves.
3. Rojo shows what it is about to change and you accept it. If the place already
   contains a copy of the game (you imported the `.rbxlx` or ran the installer),
   the existing scripts are *updated in place* rather than duplicated — matching
   name and class is how Rojo pairs them up. The files on disk win.
4. The tree fills in: `ReplicatedStorage.NecrotideShared`,
   `ServerScriptService.Bootstrap` and `Services`, and
   `StarterPlayer.StarterPlayerScripts.ClientMain` and `Modules`.
5. Press **Play**. Save the place (⌘S) to keep the scripts in it.

Save the place somewhere of your own — `place.rbxl` in this folder is
gitignored, so it will not fight with the generated files in `build/`.

Worth knowing:

- **You do not have to install anything else first.** If no `rojo` is on your
  PATH, the setup downloads the pinned Rojo **7.7.0** into `.tools/`
  (gitignored, nothing system-wide) and uses that. If you prefer a managed
  toolchain, `rokit.toml` pins the same version — `rokit install`. Aftman users
  can copy it to `aftman.toml`.
- **Sync is one-way while it runs: files → Studio.** Editing a synced script
  inside Studio works until the next save on disk overwrites it. To go the other
  way on purpose, see [`npm run sync:back`](#pulling-studio-edits-back-into-the-repo).
- **Your place is not taken over.** Rojo only manages what
  `default.project.json` maps — the three containers listed above; anything
  else in your Workspace or Lighting is left alone. The arena
  is generated at run time by `MapBuilder.lua`, so an empty viewport before you
  press Play is correct.
- `npm run doctor` checks the whole path — project paths, Node, Studio, Rojo
  version, whether the plugin is installed, whether you are behind on git,
  whether the port is free — and prints what is missing. Run it first whenever
  something is off.
- Port already taken? `npm run sync -- --port 34873`, then type that port into
  the plugin.

<details>
<summary>If it will not connect</summary>

| Symptom | Fix |
| --- | --- |
| No **Rojo** button in the Plugins tab | `npm run sync:plugin`, then quit and reopen Studio (on a Mac, ⌘Q — closing the window is not enough) |
| Plugin says it cannot reach the server | `npm run live` (or `npm run sync`) has to be running in this folder at the same time; check the port matches |
| Plugin warns about a version mismatch | The plugin and CLI must be the same major version — `npm run sync:plugin` reinstalls the plugin that matches the pinned CLI |
| Scripts arrive but nothing happens on Play | Check the Output window; `Bootstrap` needs `ReplicatedStorage.NecrotideShared` to be present, which means letting the first sync finish before pressing Play |
| `"rojo" cannot be opened because Apple cannot check it` | Something re-quarantined the binary. `npm run doctor` says so and prints the one-line `xattr -d` fix; deleting `.tools/` and re-running `npm run setup` also works |
| `zsh: permission denied: ./start-sync.command` | `chmod +x start-sync.command` (git should preserve the bit, but a zip download will not) — same for `live-sync.command` |
| `npm run live` says *serving files only* | It found no git clone, no `origin`, or no upstream branch; it prints which. `git branch --set-upstream-to origin/main` fixes the usual one. Rojo still serves what is on disk |
| A commit was pushed but Studio never changed | Look at the `live` lines in that window: no `pulled` line within ~15s means the fetch is failing (it says so), and a `needs a hand` line means a conflict stopped the watcher. `npm run pull` in another terminal shows the same error in full |
| `live` printed *git pull needs a hand* | Your local commits or edits clash with what was pushed. Resolve it in another terminal (`git status`), then restart `npm run live`; Rojo kept serving the whole time |

</details>

### 2. Open the finished place (no tooling at all)

1. Download **`build/NecrotideLastStand.rbxlx`**.
2. In Studio: **File → Open from File…** and pick it.
3. Press **Play**. That's it — the arena, lighting, HUD and waves all build
   themselves at runtime.

> The editor viewport looks empty before you press Play. That is expected: the
> place file contains only scripts, and `MapBuilder.lua` generates the whole
> arena when the game starts.

### 3. Drag the model into a place you already have

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

---

## Editing it together

The code lives in the GitHub repo; your Studio place is just a view of it. That
is what makes two people (or you and Claude) able to work on the same game
without stepping on each other.

```
Claude edits src/ ──> git push ──> npm run live fetches ──> Rojo ──> your Studio
                                  (every 15s, by itself)
```

**To take in changes made for you:** nothing, if `npm run live` is running — it
fetches, pulls and reports what changed on its own. If you are running plain
`npm run sync`, do it by hand:

```bash
npm run pull       # or double-click pull-latest.command in Finder
```

Either way the sync server pushes the new files into the open place — no
reconnect, no restart. Press Play again to see them. Uncommitted edits of yours
are stashed and put back, so it is safe at any time; the test suite covers
exactly that case (`npm run test:sync`).

`npm run live -- --interval 60` slows the polling down; five seconds is the
floor. If a pull ever conflicts with your own commits, the watcher stops and
prints git's message rather than retrying forever — fix it in another terminal,
then restart `npm run live`. Rojo keeps serving throughout.

**To send your own changes back:**

```bash
git add -A
git commit -m "raise the Ashvault barricade cost"
git push
```

Then whoever is working with you pulls, exactly the same way.

Two honest limits:

- **Nobody can reach into your Studio session but you.** The Rojo server listens
  on `localhost`, i.e. only your MacBook, and that is the right setting. Claude
  edits files and commits them; the watcher in `npm run live` (or a manual
  `npm run pull`) is the step that carries them across — which is as direct as it
  gets, see [Can Claude edit straight into my Studio?](#can-claude-edit-straight-into-my-studio).
  Roblox's own Team Create is the tool for two people editing one live place, and
  it is separate from this.
- **Git is the source of truth, not the place file.** Anything you build by hand
  in the Studio viewport lives only in your local `.rbxl` unless you either put
  it in code (`MapBuilder.lua` generates the whole arena) or sync it back —
  next section.

### Pulling Studio edits back into the repo

If you changed a script inside Studio and want to keep it:

```bash
# in Studio: File > Save As... -> place.rbxl in this folder
npm run sync:back -- place.rbxl            # dry run: lists what would change
npm run sync:back -- place.rbxl --write    # actually writes it over src/
```

This only touches the containers `default.project.json` maps — your Workspace
geometry and Lighting are marked `$ignoreUnknownInstances` and are not
serialised. Commit before `--write` so you can undo it with `git checkout .`.

> `syncback` needs a place saved out of Studio, which has every service the
> project references. Run against the trimmed `build/NecrotideLastStand.rbxlx`
> instead and Rojo stops with *"The child 'Lighting' … is present only in a
> project file"* — that is expected; use your own saved place.

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
npm run all        # check + build + verify + test + test:sync + doctor
```

| Script | What it does |
| --- | --- |
| `npm run check` | Syntax-checks every Lua file with `luaparse` |
| `npm run build` | Regenerates `build/*.rbxlx` and `build/*.rbxmx` from `src/` |
| `npm run verify` | Parses the generated XML, confirms the instance tree, and statically resolves every `Net.get`, `require`, `S.Service.method` and `GameConfig.Key` reference |
| `npm run test` | Runs the real game modules headlessly against a Roblox API stub |
| `npm run test:sync` | Drives the live watcher against throwaway git repos: pulls, dirty trees, conflicts, offline |
| `npm run doctor` | Checks the whole sync path: project paths, Node, Studio, Rojo, plugin, git state, port |
| `npm run setup` | First-run convenience: `sync:install` + `sync:plugin` + `doctor` |
| `npm run live` | Sync server **plus** a git watcher: pushed commits go into Studio by themselves (`-- --interval 60` to slow it, `-- --port N` to move it) |
| `npm run sync` | Starts the Rojo sync server alone (see [live sync](#1-live-sync-with-rojo-edit-here-see-it-in-studio)) |
| `npm run pull` | Pulls new commits (stashing your edits) and reports which scripts changed |
| `npm run sync:plugin` | Installs the Rojo Studio plugin for the current user |
| `npm run sync:install` | Downloads the pinned Rojo CLI into `.tools/` without starting it |
| `npm run sync:build` | Builds a place with Rojo into `build/rojo/` instead of `tools/build.js` |
| `npm run sync:back -- <place.rbxl>` | Reverse direction: writes a saved place's scripts back over `src/` (dry run unless `--write`) |
| `npm run sourcemap` | Writes `sourcemap.json` so Luau LSP can resolve `require`s |

Only `npm run sync*`, `npm run setup`, `npm run pull` and `npm run live` touch
the network — to fetch that one pinned Rojo release, and to talk to git.
Everything else, `npm run test:sync` included, runs offline.

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
   wave, tears and repairs a barricade, and prints the balance table. It also
   checks the generated geometry: every Armory Rack must be backed by a solid
   wall and reachable from the room in front of it, and every station, crate
   anchor and barricade exit must stand in walkable space.

   The client is covered too: the stub runs `ClientMain` top to bottom, builds
   the real HUD, feeds it every payload shape the server sends, and then fires
   the connected render-step and input handlers so the per-frame code and every
   keybind execute. Event connections reject a nil callback the way Roblox does,
   so a misspelled handler fails the run rather than the game.

Current state: **24 files parsed, 72 static checks, 283 runtime checks, 0
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
  build.js            src/ -> .rbxlx and .rbxmx, no external tooling
  check-lua.js        syntax gate
  verify.js           static checks against the built place
  sim.js, sim/        headless run of the real modules
  sync.js             Rojo sync: doctor, install, plugin, serve, live, pull
  test-sync.js        tests the live watcher on throwaway git repos
  installer.lua       the drag-in model's permanent installer
build/                      the importable .rbxlx and .rbxmx (committed)
default.project.json        Rojo mapping of src/ onto Roblox services
rokit.toml                  pins Rojo 7.7.0 for Rokit/Aftman users
live-sync.command           macOS: double-click for serve + auto-pull
start-sync.command          macOS: double-click for serve only
pull-latest.command         macOS: double-click to pull once
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
- **"Sync into Studio" is taken to mean Rojo live sync**, since that is the
  standard way to keep a repo like this and an open place in step. Rojo **7.7.0**
  is pinned, the CLI is vendored into `.tools/` on first use instead of being
  installed system-wide, and the live sync is one-way (files → Studio); the
  reverse is the deliberate, explicit `npm run sync:back`. If you only wanted the
  game in Studio once, use option 2 or 3 above and ignore all of it.
- **Collaboration goes through git, not through a shared Studio session.** The
  Rojo server binds to `localhost` and is not exposed to the network; changes
  travel as commits and land in Studio via `npm run live` or `npm run pull`.
  Roblox Team Create is the alternative if you want two people in one live place,
  and it does not conflict with any of this.
- **"Can Claude edit directly in my Studio" is taken to mean hands-free, not
  literally remote.** No remote process can attach to a Studio session, so
  `npm run live` polls the git remote on your machine instead — the closest
  faithful answer. Polling every 15 seconds is a guess at the right trade between
  feeling instant and being quiet; `-- --interval N` changes it. Publishing to a
  live game through Roblox's Open Cloud API would be a different feature and
  needs an API key of yours, so it is deliberately not built here.
- **The `.command` launchers are macOS-only** double-click convenience wrappers
  around `npm run live`, `npm run sync` and `npm run pull`; nothing depends on
  them.
