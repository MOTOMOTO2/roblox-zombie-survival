-- WaveService: the round director. Owns the intermission timer, the spawn budget,
-- the boss schedule, victory and the post-wipe reset.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("NecrotideShared")
local GameConfig = require(Shared.GameConfig)
local EnemyDefs = require(Shared.EnemyDefs)
local Util = require(Shared.Util)
local Net = require(Shared.Net)

local WaveService = {}
local S

local rng = Random.new(os.clock() * 977)

local wave = 0
local phase = "lobby" -- lobby | intermission | active | ended
local phaseEndsAt = 0
local pendingSpawns = 0
local waveKills = 0
local waveTotal = 0
local running = false
local runToken = 0
local victoryReached = false

local function serverNow()
	return workspace:GetServerTimeNow()
end

local function broadcast()
	Net.get("WaveChanged"):FireAllClients({
		wave = wave,
		phase = phase,
		endsAt = phaseEndsAt,
		remaining = math.max(0, pendingSpawns + S.EnemyService.aliveCount()),
		total = waveTotal,
		finalWave = GameConfig.FinalBossWave,
		isBossWave = wave > 0 and EnemyDefs.bossForWave(wave, GameConfig.FinalBossWave, GameConfig.BossWaveInterval) ~= nil,
	})
end

function WaveService.snapshot()
	return {
		wave = wave,
		phase = phase,
		endsAt = phaseEndsAt,
		remaining = math.max(0, pendingSpawns + S.EnemyService.aliveCount()),
		total = waveTotal,
		finalWave = GameConfig.FinalBossWave,
	}
end

local function quotaFor(waveNumber, playerCount)
	local base = GameConfig.EnemyBaseCount + GameConfig.EnemyCountPerWave * (waveNumber - 1)
	local scaled = base * (1 + GameConfig.EnemyCountPerExtraPlayer * math.max(0, playerCount - 1))
	return math.min(GameConfig.EnemyCountCap, math.floor(scaled))
end

-- Prefers spawn points near the squad so waves feel like pressure, not a hike.
local function pickSpawn()
	local points = S.Map.spawnPoints
	local targets = Util.activeTargets()
	if #targets == 0 then
		return points[rng:NextInteger(1, #points)]
	end

	local near = {}
	for _, point in ipairs(points) do
		for _, target in ipairs(targets) do
			if (Vector3.new(point.barrier.inside.X, 0, point.barrier.inside.Z) - Vector3.new(target.root.Position.X, 0, target.root.Position.Z)).Magnitude < 150 then
				table.insert(near, point)
				break
			end
		end
	end
	if #near > 0 then
		return near[rng:NextInteger(1, #near)]
	end
	return points[rng:NextInteger(1, #points)]
end

local function spawnOne(waveNumber)
	local pool = EnemyDefs.poolForWave(waveNumber)
	local id = Util.weightedPick(pool, rng)
	if not id then return false end
	local point = pickSpawn()
	if not point then return false end
	local jitter = Util.randomFlatOffset(6)
	local entity = S.EnemyService.spawn(id, waveNumber, point.position + jitter, { barrier = point.barrier })
	return entity ~= nil
end

local function spawnBoss(bossDef, waveNumber)
	local point = pickSpawn()
	local position = point and point.position or Vector3.new(0, 0, -100)
	local entity = S.EnemyService.spawn(bossDef.id, waveNumber, position, { barrier = point and point.barrier })
	if entity then
		Net.get("Announce"):FireAllClients({
			title = bossDef.name,
			subtitle = bossDef.title,
			color = { bossDef.colors.glow.R * 255, bossDef.colors.glow.G * 255, bossDef.colors.glow.B * 255 },
			duration = 4.5,
			big = true,
		})
	end
	return entity
end

function WaveService.onEnemyRemoved()
	waveKills = waveKills + 1
	broadcast()
end

local function waitPhase(duration, token)
	phaseEndsAt = serverNow() + duration
	broadcast()
	local deadline = os.clock() + duration
	while os.clock() < deadline do
		if token ~= runToken then return false end
		task.wait(0.25)
		broadcast()
	end
	return token == runToken
end

local function runWave(waveNumber, token)
	local playerCount = math.max(1, #Players:GetPlayers())
	local bossDef = EnemyDefs.bossForWave(waveNumber, GameConfig.FinalBossWave, GameConfig.BossWaveInterval)

	waveKills = 0
	pendingSpawns = quotaFor(waveNumber, playerCount)
	if bossDef then
		-- boss waves come with a smaller escort so the fight stays readable
		pendingSpawns = math.floor(pendingSpawns * 0.55)
	end
	waveTotal = pendingSpawns + (bossDef and 1 or 0)
	phase = "active"
	phaseEndsAt = 0

	S.PlayerService.onWaveStart()
	S.PowerupService.onWaveStart()
	broadcast()

	Net.get("Announce"):FireAllClients({
		title = "WAVE " .. waveNumber,
		subtitle = bossDef and ("BOSS: " .. bossDef.name) or (waveTotal .. " incoming"),
		color = bossDef and { 255, 90, 90 } or { 255, 220, 160 },
		duration = 2.6,
		big = bossDef ~= nil,
	})

	if bossDef then
		task.delay(2.2, function()
			if token == runToken then
				spawnBoss(bossDef, waveNumber)
			end
		end)
	end

	while running and token == runToken do
		if pendingSpawns > 0 and S.EnemyService.aliveCount() < GameConfig.MaxAliveEnemies then
			if spawnOne(waveNumber) then
				pendingSpawns = pendingSpawns - 1
				broadcast()
			end
			task.wait(math.max(0.15, GameConfig.SpawnInterval - waveNumber * 0.015))
		elseif pendingSpawns <= 0 and S.EnemyService.aliveCount() == 0 then
			break
		else
			task.wait(0.25)
		end
	end

	if token ~= runToken then return false end

	local bonus = GameConfig.WaveClearBonus * waveNumber
	for _, player in ipairs(Players:GetPlayers()) do
		S.Economy.add(player, bonus, true)
	end
	Net.get("Announce"):FireAllClients({
		title = "WAVE " .. waveNumber .. " CLEARED",
		subtitle = "+" .. bonus .. " salvage",
		color = { 160, 255, 180 },
		duration = 2.4,
	})
	return true
end

local function victory(token)
	victoryReached = true
	phase = "ended"
	broadcast()
	Net.get("RunEnded"):FireAllClients({
		victory = true,
		wave = wave,
		title = "THE HOLLOW SOVEREIGN FALLS",
		subtitle = GameConfig.EndlessAfterVictory
			and "The Ashvault holds. Endless waves begin shortly."
			or "The Ashvault holds.",
	})
	task.wait(8)
	if token ~= runToken then return end
	if not GameConfig.EndlessAfterVictory then
		WaveService.endRun(true, true)
	end
end

local function loop(token)
	while running and token == runToken do
		phase = wave == 0 and "lobby" or "intermission"
		local duration = wave == 0 and GameConfig.IntermissionFirst or GameConfig.IntermissionBetween
		Net.get("Announce"):FireAllClients({
			title = wave == 0 and "THE ASHVAULT" or ("WAVE " .. (wave + 1) .. " INBOUND"),
			subtitle = wave == 0 and "Board the gaps. Spend your salvage. Survive." or "Restock and repair",
			color = { 220, 220, 235 },
			duration = 3,
		})
		if not waitPhase(duration, token) then return end

		wave = wave + 1
		local completed = runWave(wave, token)
		if not completed then return end

		if wave == GameConfig.FinalBossWave and not victoryReached then
			victory(token)
			if not GameConfig.EndlessAfterVictory then
				return
			end
		end
	end
end

function WaveService.start()
	if running then return end
	running = true
	runToken = runToken + 1
	local token = runToken
	task.spawn(function()
		loop(token)
	end)
end

-- victory = finished the campaign, otherwise the squad wiped.
function WaveService.endRun(isVictory, skipRestart)
	if phase == "ended" and not isVictory then return end
	runToken = runToken + 1
	running = false
	phase = "ended"
	pendingSpawns = 0
	broadcast()

	S.EnemyService.clearAll()

	Net.get("RunEnded"):FireAllClients({
		victory = isVictory == true,
		wave = wave,
		title = isVictory and "THE ASHVAULT HOLDS" or "THE ASHVAULT HAS FALLEN",
		subtitle = isVictory and ("Cleared wave " .. wave) or ("You held until wave " .. wave .. ". Resetting..."),
	})

	if skipRestart then return end

	task.delay(GameConfig.RestartDelay, function()
		WaveService.reset()
	end)
end

function WaveService.reset()
	wave = 0
	phase = "lobby"
	pendingSpawns = 0
	waveTotal = 0
	waveKills = 0
	victoryReached = false

	S.EnemyService.clearAll()
	S.Economy.resetAll()
	S.PlayerService.resetForNewRun()
	S.Loadout.resetForNewRun()
	S.BarrierService.resetAll()
	S.StationService.resetForNewRun()
	S.PowerupService.resetForNewRun()

	broadcast()
	WaveService.start()
end

function WaveService.currentWave()
	return wave
end

function WaveService.init(services)
	S = services

	Players.PlayerAdded:Connect(function()
		task.defer(broadcast)
	end)
end

return WaveService
