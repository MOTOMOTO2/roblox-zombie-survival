-- Headless integration tests. Runs the real game modules against the Roblox stub
-- in tools/sim/stubs.lua: builds the map, boots every service, buys guns, forges
-- them, downs a player, spawns a boss and phases it.

local failures = 0
local checks = 0

local function check(ok, label, detail)
	checks = checks + 1
	if ok then
		print("ok   " .. label)
	else
		failures = failures + 1
		print("FAIL " .. label .. (detail and (" - " .. tostring(detail)) or ""))
	end
end

local function near(a, b, tolerance)
	return math.abs(a - b) <= (tolerance or 0.001)
end

local ReplicatedStorage = SIM_SERVICE("ReplicatedStorage")
local ServerScriptService = SIM_SERVICE("ServerScriptService")
local Players = SIM_SERVICE("Players")

local Shared = ReplicatedStorage:WaitForChild("NecrotideShared")
local Services = ServerScriptService:WaitForChild("Services")

--------------------------------------------------------------------------------
-- 1. shared definition modules load and are self-consistent
--------------------------------------------------------------------------------

local GameConfig = require(Shared.GameConfig)
local Util = require(Shared.Util)
local WeaponDefs = require(Shared.WeaponDefs)
local EnemyDefs = require(Shared.EnemyDefs)
local TonicDefs = require(Shared.TonicDefs)
local PowerupDefs = require(Shared.PowerupDefs)
local Net = require(Shared.Net)

check(GameConfig.FinalBossWave == 20, "final boss is wave 20")
check(Util.comma(1234567) == "1,234,567", "Util.comma formats thousands", Util.comma(1234567))
check(Util.formatTime(75) == "1:15", "Util.formatTime", Util.formatTime(75))
check(Util.clamp(12, 0, 5) == 5, "Util.clamp")

local weaponCount = 0
local crateOnly = 0
for _, def in ipairs(WeaponDefs.List) do
	weaponCount = weaponCount + 1
	if not def.wallCost then crateOnly = crateOnly + 1 end

	local base = WeaponDefs.makeInstance(def.id, false)
	local forged = WeaponDefs.makeInstance(def.id, true)
	check(base ~= nil and forged ~= nil, def.id .. " builds both variants")
	check(forged.damage > base.damage, def.id .. " forged damage is higher", base.damage .. " -> " .. forged.damage)
	check(forged.mag >= base.mag, def.id .. " forged magazine is not smaller")
	check(forged.name ~= base.name, def.id .. " forged name differs", forged.name)
	check(base.ammo == base.mag and base.spare == base.reserve, def.id .. " spawns loaded")

	local public = WeaponDefs.publicState(base)
	check(public.name == base.name and public.ammo == base.ammo, def.id .. " public state is complete")
end
check(weaponCount == 12, "weapon roster has 12 guns", weaponCount)
check(crateOnly >= 5, "at least 5 guns are crate-only", crateOnly)

local pool = WeaponDefs.cratePool()
local poolWeight = 0
for _, entry in ipairs(pool) do
	poolWeight = poolWeight + entry.weight
end
check(#pool >= 9 and poolWeight > 0, "crate pool is populated", #pool .. " entries / weight " .. poolWeight)

check(#EnemyDefs.poolForWave(1) == 1, "wave 1 only spawns husks", #EnemyDefs.poolForWave(1))
check(#EnemyDefs.poolForWave(12) == 5, "wave 12 spawns the full roster", #EnemyDefs.poolForWave(12))

local interval = GameConfig.BossWaveInterval
local finalWave = GameConfig.FinalBossWave
check(EnemyDefs.bossForWave(1, finalWave, interval) == nil, "wave 1 has no boss")
check(EnemyDefs.bossForWave(5, finalWave, interval).id == "warden", "wave 5 boss is the Rust Warden")
check(EnemyDefs.bossForWave(10, finalWave, interval).id == "howler", "wave 10 boss is the Choir Howler")
check(EnemyDefs.bossForWave(15, finalWave, interval).id == "stitcher", "wave 15 boss is the Stitcher")
check(EnemyDefs.bossForWave(20, finalWave, interval).id == "sovereign", "wave 20 boss is the Hollow Sovereign")
check(EnemyDefs.bossForWave(20, finalWave, interval).isFinal == true, "the Sovereign is flagged final")
check(EnemyDefs.bossForWave(25, finalWave, interval) ~= nil, "endless mode keeps producing bosses")
check(#EnemyDefs.FinalBoss.phases == 3, "the final boss has three phases")

local agg = TonicDefs.aggregate({ ironhide = true, deadeye = true, scavenger = true })
check(agg.bonusHealth == 120, "ironhide grants +120 vitality", agg.bonusHealth)
check(near(agg.damageMult, 1.25), "deadeye grants +25% damage", agg.damageMult)
check(near(agg.salvageMult, 1.35), "scavenger grants +35% salvage", agg.salvageMult)
check(TonicDefs.aggregate({}).reloadScale == 1, "no tonics means no modifiers")
check(#PowerupDefs.pool() == #PowerupDefs.List, "powerup pool covers every powerup")
check(#Net.Events >= 15, "remote list is populated", #Net.Events)

--------------------------------------------------------------------------------
-- 2. the map generates
--------------------------------------------------------------------------------

Net.init()

local MapBuilder = require(Services.MapBuilder)
local map = MapBuilder.build()

check(map ~= nil, "MapBuilder.build returns a descriptor")
check(#map.barriers == 6, "six barricaded entry points", #map.barriers)
check(#map.barriers[1].boards == GameConfig.BoardsPerBarrier, "each barricade has its boards", #map.barriers[1].boards)
check(#map.spawnPoints == 12, "twelve horde spawn points", #map.spawnPoints)
check(#map.wallBuys == 6, "six armory racks", #map.wallBuys)
check(#map.tonicSpots == 6, "six tonic stills", #map.tonicSpots)
check(#map.cratePositions == 5, "five fate crate anchors", #map.cratePositions)
check(map.bounds == 110, "arena half-extent", map.bounds)
local structureParts = #map.structure:GetChildren()
check(structureParts > 40, "arena geometry was generated", structureParts .. " top-level parts")

-- Geometry checks. Every wall weapon has to hang on something solid, and every
-- station has to stand somewhere a player can actually walk to. These are easy to
-- get wrong by hand, because the coordinates are typed out in MapBuilder.
local solids = {}
for _, descendant in ipairs(map.structure:GetDescendants()) do
	if descendant.ClassName == "Part" and descendant.CanCollide ~= false then
		table.insert(solids, descendant)
	end
end
check(#solids > 60, "collected the collidable geometry", #solids .. " parts")

local function solidAt(point, pad)
	pad = pad or 0
	for _, part in ipairs(solids) do
		local half = part.Size * 0.5
		local delta = point - part.Position
		if math.abs(delta.X) <= half.X + pad
			and math.abs(delta.Y) <= half.Y + pad
			and math.abs(delta.Z) <= half.Z + pad then
			return part
		end
	end
	return nil
end

for _, spec in ipairs(map.wallBuys) do
	local behind = spec.pos - spec.face * 2.2
	local inFront = spec.pos + spec.face * 2.5
	check(solidAt(behind, 0.6) ~= nil, "armory rack for " .. spec.weapon .. " is mounted on a wall")
	check(solidAt(inFront, 0) == nil, "armory rack for " .. spec.weapon .. " is reachable from the room")
end

local standing = { { "player spawn", map.playerSpawn }, { "overforge", map.forgePosition } }
for _, spec in ipairs(map.tonicSpots) do
	table.insert(standing, { "tonic still " .. spec.tonic, spec.pos })
end
for index, pos in ipairs(map.cratePositions) do
	table.insert(standing, { "fate crate anchor " .. index, pos })
end
for _, entry in ipairs(standing) do
	local point = Vector3.new(entry[2].X, 5, entry[2].Z)
	check(solidAt(point, 0) == nil, entry[1] .. " stands in clear space")
	check(math.abs(entry[2].X) < map.bounds - 6 and math.abs(entry[2].Z) < map.bounds - 6, entry[1] .. " is inside the arena")
end

for _, barrier in ipairs(map.barriers) do
	check(solidAt(Vector3.new(barrier.inside.X, 6, barrier.inside.Z), 0) == nil, barrier.id .. " opens into walkable floor")
	check(solidAt(Vector3.new(barrier.outside.X, 6, barrier.outside.Z), 0) == nil, barrier.id .. " has clear ground outside")
end

--------------------------------------------------------------------------------
-- 3. boot every service the way Bootstrap does
--------------------------------------------------------------------------------

local S = { Map = map, MapBuilder = MapBuilder }
local ORDER = {
	"Economy",
	"PlayerService",
	"Loadout",
	"Combat",
	"EnemyService",
	"BarrierService",
	"StationService",
	"PowerupService",
	"WaveService",
}
for _, name in ipairs(ORDER) do
	S[name] = require(Services[name])
end
for _, name in ipairs(ORDER) do
	local ok, err = pcall(S[name].init, S)
	check(ok, name .. ".init() runs", err)
end
SIM_FLUSH()

-- The round loop needs a real clock to tick, which the simulator does not have.
-- Swap it for a spy so we can still assert that a wipe schedules a fresh run.
local runsStarted = 0
S.WaveService.start = function()
	runsStarted = runsStarted + 1
end

--------------------------------------------------------------------------------
-- 4. a fake player: economy, loadout, forging
--------------------------------------------------------------------------------

local player = Instance.new("Player")
player.Name = "TestOperative"
player.DisplayName = "TestOperative"
player.Parent = Players
rawset(Players, "GetPlayers", function() return { player } end)

-- the stub registers children by name at parent time, so name before parenting
local function mk(className, name, parent)
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = parent
	return inst
end

local character = Instance.new("Model")
character.Name = "TestOperative"
local root = mk("Part", "HumanoidRootPart", character)
local head = mk("Part", "Head", character)
local humanoid = mk("Humanoid", "Humanoid", character)
humanoid.Health = 100
humanoid.MaxHealth = 100
humanoid.WalkSpeed = 16
character.PrimaryPart = root
player.Character = character

check(S.Economy.get(player) == GameConfig.StartingSalvage, "starting salvage", S.Economy.get(player))
check(S.Economy.spend(player, 200) == true, "spending salvage works")
check(S.Economy.get(player) == 300, "salvage decreases", S.Economy.get(player))
check(S.Economy.spend(player, 99999) == false, "cannot overspend")
S.Economy.add(player, 100)
check(S.Economy.get(player) == 400, "salvage increases", S.Economy.get(player))

S.PlayerService.grantTonic(player, "scavenger")
S.Economy.add(player, 100)
check(S.Economy.get(player) == 535, "scavenger multiplies salvage income", S.Economy.get(player))
S.PlayerService.grantTonic(player, "ironhide")
check(humanoid.MaxHealth == GameConfig.BaseMaxHealth + 120, "ironhide raises max health", humanoid.MaxHealth)

S.Loadout.onCharacter(player, character)
SIM_FLUSH()
local active = S.Loadout.active(player)
check(active ~= nil and active.id == WeaponDefs.StartingWeapon, "players start with the sidearm", active and active.id)

check(S.Loadout.give(player, "hornet", false), "wall buy grants a weapon")
active = S.Loadout.active(player)
check(active.id == "hornet" and active.name == "Hornet PDW", "the new weapon is equipped", active.name)
check(select(1, S.Loadout.has(player, "vesper45")), "the sidearm stays in the other slot")

-- empty the magazine one shot at a time, respecting the server's fire rate
local fireInterval = 60 / active.rpm
local fired = 0
for _ = 1, active.mag do
	SIM_ADVANCE(fireInterval)
	if S.Loadout.consumeShot(player) then fired = fired + 1 end
end
check(fired == active.mag, "fired a full magazine", fired .. "/" .. active.mag)
check(active.ammo == 0, "magazine is empty", active.ammo)

SIM_ADVANCE(fireInterval)
check(S.Loadout.consumeShot(player) == nil, "cannot fire on an empty magazine")
SIM_FLUSH()
check(active.ammo == active.mag, "auto reload refilled the magazine", active.ammo)
check(active.spare == active.reserve - active.mag, "spare ammo was consumed", active.spare)

SIM_ADVANCE(fireInterval)
check(S.Loadout.consumeShot(player) ~= nil, "firing resumes after the reload")

-- rate limiting: two shots in the same instant must not both land
local before = active.ammo
S.Loadout.consumeShot(player)
check(active.ammo == before, "fire rate is enforced server-side", active.ammo)

local slotIndex = select(2, S.Loadout.has(player, "hornet"))
local forgedOk, forgedName = S.Loadout.upgradeSlot(player, slotIndex, "hornet")
check(forgedOk and forgedName == "Hornet Tempest", "the Overforge upgrades the right slot", forgedName)
local forged = S.Loadout.active(player)
check(forged.upgraded and forged.damage > 38, "forged weapon hits harder", forged.damage)
check(select(1, S.Loadout.upgradeSlot(player, slotIndex, "hornet")) == false, "a weapon cannot be forged twice")

S.Loadout.maxAmmoEveryone()
check(S.Loadout.active(player).spare == forged.reserve, "resupply refills reserves")

--------------------------------------------------------------------------------
-- 5. downed, revive and bleed-out
--------------------------------------------------------------------------------

S.PlayerService.damage(player, 50)
check(near(humanoid.Health, 170, 0.01), "damage reduces health", humanoid.Health)
check(S.PlayerService.isDowned(player) == false, "one hit does not down you")

S.PlayerService.damage(player, 500)
check(S.PlayerService.isDowned(player) == true, "lethal damage puts you down instead of killing you")
check(humanoid.Health > 0, "a downed player is still alive", humanoid.Health)
check(player:GetAttribute("Downed") == true, "the Downed attribute is set for the horde to read")
check(humanoid.WalkSpeed == 0, "downed players cannot walk")
check(character:FindFirstChild("HumanoidRootPart"):FindFirstChild("RevivePrompt") ~= nil, "a revive prompt appears")

S.PlayerService.damage(player, 40)
check(S.PlayerService.isDowned(player) == true, "damage while downed does not kill outright")

S.PlayerService.reviveTo(player, 1)
check(S.PlayerService.isDowned(player) == false, "revive lifts the player")
check(near(humanoid.Health, humanoid.MaxHealth, 0.01), "revive restores health", humanoid.Health)
check(humanoid.WalkSpeed > 0, "revived players can walk again")
SIM_ADVANCE(1)
check(S.Loadout.consumeShot(player) ~= nil, "a revived player can shoot again")

-- downing the only player is a squad wipe: the run should end and reschedule
SIM_FLUSH()
check(runsStarted >= 1, "a squad wipe resets the run", runsStarted)
check(S.Economy.get(player) == GameConfig.StartingSalvage, "the reset restores starting salvage", S.Economy.get(player))
check(S.Loadout.active(player).id == WeaponDefs.StartingWeapon, "the reset returns players to the sidearm")
check(S.PlayerService.hasTonic(player, "ironhide") == false, "the reset clears tonics")

--------------------------------------------------------------------------------
-- 6. enemies, scaling, and boss phases
--------------------------------------------------------------------------------

local EnemyService = S.EnemyService
check(EnemyService.scaledHealth(100, 1, 1) == 100, "wave 1 uses base health", EnemyService.scaledHealth(100, 1, 1))
local previous = 0
local monotonic = true
for wave = 1, 30 do
	local value = EnemyService.scaledHealth(100, wave, 1)
	if value < previous then monotonic = false end
	previous = value
end
check(monotonic, "health scaling never goes backwards")
check(
	EnemyService.scaledHealth(100, 20, 1) > EnemyService.scaledHealth(100, 10, 1) * 1.5,
	"late waves compound health",
	EnemyService.scaledHealth(100, 20, 1)
)
check(
	EnemyService.scaledHealth(100, 5, 4) > EnemyService.scaledHealth(100, 5, 1),
	"more players means tougher enemies"
)

local husk = EnemyService.spawn("husk", 1, Vector3.new(20, 0, 20), { insideAlready = true })
check(husk ~= nil, "a husk spawns")
check(EnemyService.aliveCount() == 1, "alive counter tracks it", EnemyService.aliveCount())
check(husk.health == EnemyService.scaledHealth(130, 1, 1), "husk health matches the scaling table", husk.health)
check(husk.model.Name == "Necro_husk", "the model was built", husk.model.Name)
check(husk.y == EnemyDefs.get("husk").height * 0.5, "husks stand on the floor, not above it", husk.y)
local groundedSpawn = map.spawnPoints[1].position
check(groundedSpawn.Y == 0, "horde spawn points are at ground level", groundedSpawn.Y)
check(husk.head ~= nil and husk.head.Name == "Head", "husks have a head for headshots")
check(husk.root:GetAttribute("NecroEnemy") == husk.uid, "the root part is tagged for hit detection")

local dealt = EnemyService.damage(husk, 40, player, false)
check(dealt == 40, "damage is applied", dealt)
check(husk.health == EnemyService.scaledHealth(130, 1, 1) - 40, "health went down", husk.health)

local salvageBefore = S.Economy.get(player)
EnemyService.damage(husk, 99999, player, true)
SIM_FLUSH()
check(husk.alive == false, "the husk died")
check(EnemyService.aliveCount() == 0, "alive counter went back to zero", EnemyService.aliveCount())
check(S.Economy.get(player) > salvageBefore, "killing pays salvage", S.Economy.get(player) - salvageBefore)

-- instakill powerup
local tough = EnemyService.spawn("brute", 15, Vector3.new(0, 0, 40), { insideAlready = true })
EnemyService.setInstakill(true)
EnemyService.damage(tough, 1, player, false)
check(tough.alive == false, "Culling Hour kills trash instantly")
EnemyService.setInstakill(false)

-- purge powerup clears trash but leaves bosses
local warden = EnemyService.spawn("warden", 5, Vector3.new(0, 0, -60), { insideAlready = true })
check(warden ~= nil and warden.isBoss, "the Rust Warden spawns as a boss")
check(EnemyService.boss() == warden, "the boss is tracked")
for index = 1, 5 do
	EnemyService.spawn("husk", 5, Vector3.new(index * 4, 0, 0), { insideAlready = true })
end
check(EnemyService.aliveCount() == 6, "boss plus escort", EnemyService.aliveCount())
local purged = EnemyService.purge(player)
check(purged == 5, "purge erased only the escort", purged)
check(EnemyService.aliveCount() == 1 and warden.alive, "the boss survived the purge")

-- phase transition at 50% health
local speedBefore = warden.speed
EnemyService.damage(warden, warden.maxHealth * 0.55, player, false)
SIM_FLUSH()
check(warden.phaseIndex == 1, "the Warden entered phase two", warden.phaseIndex)
check(warden.speed > speedBefore, "phase two is faster", speedBefore .. " -> " .. warden.speed)

EnemyService.damage(warden, warden.maxHealth, player, false)
SIM_FLUSH()
check(warden.alive == false, "the boss can be killed")
check(EnemyService.boss() == nil, "the boss slot clears")

-- the final boss scales hardest
local sovereign = EnemyService.spawn("sovereign", 20, Vector3.new(0, 0, -80), { insideAlready = true })
check(sovereign.maxHealth >= EnemyDefs.FinalBoss.health, "the Sovereign keeps its huge health pool", sovereign.maxHealth)
check(#sovereign.abilities == 3, "the Sovereign starts with three abilities", #sovereign.abilities)
EnemyService.damage(sovereign, sovereign.maxHealth * 0.35, player, false)
SIM_FLUSH()
check(sovereign.phaseIndex == 1, "the Sovereign advanced a phase", sovereign.phaseIndex)
check(#sovereign.abilities == 4, "phase two unlocks another ability", #sovereign.abilities)
EnemyService.clearAll()
check(EnemyService.aliveCount() == 0, "clearAll empties the arena")

--------------------------------------------------------------------------------
-- 7. barricades
--------------------------------------------------------------------------------

local barrier = map.barriers[1]
check(S.BarrierService.isOpen(barrier) == false, "barricades start boarded up")

-- a crowd hammering the same window in one tick must not strip it instantly
for _ = 1, 12 do
	S.BarrierService.tear(barrier, GameConfig.BoardTearTime, husk)
end
check(S.BarrierService.isOpen(barrier) == false, "a crowd cannot strip a barricade in one tick")

for _ = 1, GameConfig.BoardsPerBarrier do
	SIM_ADVANCE(0.05)
	S.BarrierService.tear(barrier, GameConfig.BoardTearTime + 0.01, husk)
end
check(S.BarrierService.isOpen(barrier) == true, "sustained clawing opens the gap")
check(S.BarrierService.repairOne(barrier, player) == true, "players can nail a board back on")
check(S.BarrierService.isOpen(barrier) == false, "one board is enough to close it")
S.BarrierService.smash(barrier)
check(S.BarrierService.isOpen(barrier) == true, "bosses smash straight through")
S.BarrierService.resetAll()
check(S.BarrierService.isOpen(barrier) == false, "resetAll re-boards every gap")

--------------------------------------------------------------------------------
-- 8. wave director state
--------------------------------------------------------------------------------

local snapshot = S.WaveService.snapshot()
check(snapshot.phase == "lobby", "the run starts in the lobby", snapshot.phase)
check(snapshot.finalWave == GameConfig.FinalBossWave, "the snapshot reports the final wave")
check(S.WaveService.currentWave() == 0, "no wave has started yet")

--------------------------------------------------------------------------------
-- balance table (informational)
--------------------------------------------------------------------------------

print("")
print("wave | husk HP | sprinter HP | quota(1p) | quota(4p) | boss")
local function quota(wave, players)
	local base = GameConfig.EnemyBaseCount + GameConfig.EnemyCountPerWave * (wave - 1)
	local scaled = base * (1 + GameConfig.EnemyCountPerExtraPlayer * math.max(0, players - 1))
	return math.min(GameConfig.EnemyCountCap, math.floor(scaled))
end
local bossWavesSeen = 0
for _, wave in ipairs({ 1, 3, 5, 8, 10, 12, 15, 18, 20, 25 }) do
	local boss = EnemyDefs.bossForWave(wave, finalWave, interval)
	if boss then bossWavesSeen = bossWavesSeen + 1 end
	print(string.format(
		"%4d | %7d | %11d | %9d | %9d | %s",
		wave,
		EnemyService.scaledHealth(130, wave, 1),
		EnemyService.scaledHealth(95, wave, 1),
		quota(wave, 1),
		quota(wave, 4),
		boss and boss.name or "-"
	))
end

check(bossWavesSeen == 5, "the printed table found every boss wave", bossWavesSeen)

print("")
print(checks .. " checks, " .. failures .. " failure(s).")
if failures > 0 then
	error("simulation failed with " .. failures .. " failing check(s)", 0)
end
