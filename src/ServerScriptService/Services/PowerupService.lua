-- PowerupService: the glowing pickups the horde drops. Effects are team-wide,
-- which is what makes them worth shouting about.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("NecrotideShared")
local GameConfig = require(Shared.GameConfig)
local PowerupDefs = require(Shared.PowerupDefs)
local Util = require(Shared.Util)
local Net = require(Shared.Net)

local PowerupService = {}
local S

local active = {}
local droppedThisWave = 0
local rng = Random.new(os.clock() * 1531)
local heartbeatConn
local timers = {}

local function announce(def, collector)
	Net.get("PowerupFx"):FireAllClients({
		id = def.id,
		name = def.name,
		blurb = def.blurb,
		color = { def.color.R * 255, def.color.G * 255, def.color.B * 255 },
		by = collector and collector.DisplayName or nil,
	})
end

local function clearTimer(key)
	if timers[key] then
		task.cancel(timers[key])
		timers[key] = nil
	end
end

local effects = {}

effects.purge = function(collector)
	local killed = S.EnemyService.purge(collector)
	for _, player in ipairs(Players:GetPlayers()) do
		S.Economy.add(player, 400, true)
	end
	return killed .. " erased"
end

effects.resupply = function()
	S.Loadout.maxAmmoEveryone()
	return "ammo restored"
end

effects.culling = function(_, duration)
	S.EnemyService.setInstakill(true)
	clearTimer("culling")
	timers.culling = task.delay(duration, function()
		S.EnemyService.setInstakill(false)
		timers.culling = nil
		Net.get("Notify"):FireAllClients({ text = "Culling Hour is over", color = { 255, 160, 160 } })
	end)
	return "one touch kills"
end

effects.surge = function(_, duration)
	S.Economy.setGlobalMultiplier(2)
	clearTimer("surge")
	timers.surge = task.delay(duration, function()
		S.Economy.setGlobalMultiplier(1)
		timers.surge = nil
		Net.get("Notify"):FireAllClients({ text = "Salvage Surge is over", color = { 160, 255, 160 } })
	end)
	return "double salvage"
end

effects.mend = function()
	S.PlayerService.healAll()
	return "squad restored"
end

local function collect(entry, player)
	if entry.taken then return end
	entry.taken = true
	if entry.part then
		entry.part:Destroy()
	end
	local def = entry.def
	local handler = effects[def.id]
	if handler then
		handler(player, def.duration)
	end
	announce(def, player)
end

local function buildPickup(def, position)
	local part = Instance.new("Part")
	part.Name = "Powerup_" .. def.id
	part.Size = Vector3.new(2.6, 2.6, 2.6)
	part.Position = position + Vector3.new(0, 3.2, 0)
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Neon
	part.Color = def.color
	part.Parent = S.Map.fxFolder

	local light = Instance.new("PointLight")
	light.Color = def.color
	light.Brightness = 4
	light.Range = 26
	light.Parent = part

	local beam = Instance.new("Part")
	beam.Name = "Beam"
	beam.Size = Vector3.new(1.2, 40, 1.2)
	beam.Position = position + Vector3.new(0, 20, 0)
	beam.Anchored = true
	beam.CanCollide = false
	beam.Material = Enum.Material.Neon
	beam.Color = def.color
	beam.Transparency = 0.7
	beam.Parent = part

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(10, 0, 2, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 250
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = def.color
	label.TextStrokeTransparency = 0.2
	label.Text = def.name
	label.Parent = gui

	return part
end

function PowerupService.maybeDrop(position)
	if droppedThisWave >= GameConfig.PowerupMaxPerWave then return end
	if rng:NextNumber() > GameConfig.PowerupDropChance then return end
	PowerupService.forceDrop(position)
end

function PowerupService.forceDrop(position)
	local id = Util.weightedPick(PowerupDefs.pool(), rng)
	local def = PowerupDefs.get(id)
	if not def then return end
	droppedThisWave = droppedThisWave + 1

	local part = buildPickup(def, position)
	local entry = {
		def = def,
		part = part,
		expiresAt = os.clock() + GameConfig.PowerupLifetime,
		taken = false,
		basePosition = part.Position,
	}
	table.insert(active, entry)
end

function PowerupService.onWaveStart()
	droppedThisWave = 0
end

function PowerupService.resetForNewRun()
	for _, entry in ipairs(active) do
		if entry.part then entry.part:Destroy() end
		entry.taken = true
	end
	active = {}
	droppedThisWave = 0
	S.EnemyService.setInstakill(false)
	S.Economy.setGlobalMultiplier(1)
	clearTimer("culling")
	clearTimer("surge")
end

function PowerupService.init(services)
	S = services

	local spin = 0
	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		if #active == 0 then return end
		spin = spin + dt
		local now = os.clock()
		for index = #active, 1, -1 do
			local entry = active[index]
			if entry.taken then
				table.remove(active, index)
			elseif now >= entry.expiresAt then
				entry.taken = true
				if entry.part then entry.part:Destroy() end
				table.remove(active, index)
			else
				if entry.part then
					local bobY = math.sin(spin * 2.6) * 0.5
					entry.part.CFrame = CFrame.new(entry.basePosition + Vector3.new(0, bobY, 0))
						* CFrame.Angles(math.rad(spin * 60), math.rad(spin * 90), 0)
					-- fade out in the last three seconds
					if entry.expiresAt - now < 3 then
						entry.part.Transparency = 0.5 + math.sin(now * 20) * 0.35
					end
				end
				for _, target in ipairs(Util.activeTargets()) do
					if (target.root.Position - entry.basePosition).Magnitude < 7 then
						collect(entry, target.player)
						break
					end
				end
			end
		end
	end)
end

function PowerupService.shutdown()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
end

return PowerupService
