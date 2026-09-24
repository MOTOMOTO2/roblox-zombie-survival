-- EnemyService: spawns, animates, steers and kills every creature in the game.
--
-- Enemies are lightweight: each one is a small anchored Model that is moved with
-- Model:PivotTo on a fixed 20 Hz tick. That keeps dozens of them cheap and, more
-- importantly, keeps them perfectly predictable - no rigs, no physics fights, no
-- Humanoid pathing quirks. Steering walks straight at the target when there is a
-- clear line, and falls back to PathfindingService around walls.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("NecrotideShared")
local GameConfig = require(Shared.GameConfig)
local EnemyDefs = require(Shared.EnemyDefs)
local Util = require(Shared.Util)
local Net = require(Shared.Net)

local EnemyService = {}
local S

local TICK_RATE = 1 / 20

local entities = {}
local aliveCount = 0
local boss = nil
local instakill = false
local nextId = 0
local accumulator = 0
local heartbeatConn
local rng = Random.new(os.clock() * 1000)

--------------------------------------------------------------------------------
-- construction
--------------------------------------------------------------------------------

local function makePart(name, size, color, material, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function buildModel(def, position)
	local h = def.height
	local w = def.width
	local colors = def.colors

	local model = Instance.new("Model")
	model.Name = "Necro_" .. def.id

	local torsoHeight = h * 0.42
	local torso = makePart("Torso", Vector3.new(w, torsoHeight, w * 0.62), colors.torso, Enum.Material.Fabric, model)
	torso.CanCollide = true
	torso.Position = position + Vector3.new(0, h * 0.5, 0)

	local headSize = w * 0.62
	local head = makePart("Head", Vector3.new(headSize, headSize, headSize), colors.head, Enum.Material.SmoothPlastic, model)
	head.Position = torso.Position + Vector3.new(0, torsoHeight * 0.5 + headSize * 0.5, 0)

	local eyeSize = math.max(0.16, headSize * 0.16)
	for _, side in ipairs({ -1, 1 }) do
		local eye = makePart("Eye", Vector3.new(eyeSize, eyeSize, eyeSize), colors.glow, Enum.Material.Neon, model)
		eye.Position = head.Position + Vector3.new(side * headSize * 0.24, headSize * 0.1, -headSize * 0.52)
		local light = Instance.new("PointLight")
		light.Color = colors.glow
		light.Brightness = def.isBoss and 3 or 0.8
		light.Range = def.isBoss and 30 or 10
		light.Parent = eye
	end

	local armLength = h * 0.34
	for _, side in ipairs({ -1, 1 }) do
		local arm = makePart("Arm", Vector3.new(w * 0.24, armLength, w * 0.24), colors.limb, Enum.Material.Fabric, model)
		-- arms held forward, classic shambling reach
		arm.CFrame = CFrame.new(torso.Position + Vector3.new(side * (w * 0.55), torsoHeight * 0.1, -armLength * 0.42))
			* CFrame.Angles(math.rad(-72), 0, 0)
	end

	local legLength = h * 0.34
	for _, side in ipairs({ -1, 1 }) do
		local leg = makePart("Leg", Vector3.new(w * 0.3, legLength, w * 0.3), colors.limb, Enum.Material.Fabric, model)
		leg.Position = torso.Position + Vector3.new(side * (w * 0.22), -(torsoHeight * 0.5 + legLength * 0.5), 0)
	end

	if def.isBoss then
		-- a crown of spikes so bosses read instantly at distance
		for i = 1, 6 do
			local angle = (i / 6) * math.pi * 2
			local spike = makePart("Spike", Vector3.new(w * 0.14, h * 0.22, w * 0.14), colors.glow, Enum.Material.Neon, model)
			spike.CFrame = CFrame.new(head.Position + Vector3.new(math.cos(angle) * headSize * 0.5, headSize * 0.6, math.sin(angle) * headSize * 0.5))
				* CFrame.Angles(math.rad(math.cos(angle) * 22), 0, math.rad(math.sin(angle) * 22))
		end
		local aura = Instance.new("PointLight")
		aura.Color = colors.glow
		aura.Brightness = 5
		aura.Range = 60
		aura.Parent = torso
	end

	model.PrimaryPart = torso
	return model, torso, head
end

local function buildBossBar(entity)
	local gui = Instance.new("BillboardGui")
	gui.Name = "BossBar"
	gui.Size = UDim2.new(16, 0, 1.6, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, entity.def.height * 0.65, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 600
	gui.Parent = entity.root

	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(16, 12, 14)
	back.BorderSizePixel = 0
	back.Parent = gui

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = entity.def.colors.glow
	fill.BorderSizePixel = 0
	fill.Parent = back

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = entity.def.name
	label.Parent = back

	entity.bossFill = fill
end

--------------------------------------------------------------------------------
-- scaling
--------------------------------------------------------------------------------

function EnemyService.scaledHealth(base, wave, playerCount)
	local health
	local pivot = GameConfig.HealthExponentialWave
	if wave <= pivot then
		health = base * (1 + GameConfig.HealthLinearPerWave * (wave - 1))
	else
		health = base
			* (1 + GameConfig.HealthLinearPerWave * (pivot - 1))
			* math.pow(GameConfig.HealthExponentialRate, wave - pivot)
	end
	return math.floor(health * (1 + 0.15 * math.max(0, playerCount - 1)))
end

local function scaledSpeed(base, wave)
	return math.min(GameConfig.MaxEnemySpeed, base + GameConfig.SpeedPerWave * (wave - 1))
end

--------------------------------------------------------------------------------
-- spawning
--------------------------------------------------------------------------------

local function abilityState(abilities)
	local out = {}
	for _, ability in ipairs(abilities or {}) do
		table.insert(out, {
			def = ability,
			nextUse = os.clock() + rng:NextNumber(1.5, ability.cooldown),
		})
	end
	return out
end

-- options: { barrier = barrierTable, insideAlready = bool, healthMult = n, isSummon = bool }
function EnemyService.spawn(defId, wave, position, options)
	options = options or {}
	local def = EnemyDefs.get(defId)
	if not def then return nil end
	local map = S.Map
	if not map then return nil end

	local playerCount = math.max(1, #Players:GetPlayers())
	local model, root, head = buildModel(def, position)
	model.Parent = map.enemyFolder

	nextId = nextId + 1
	local maxHealth = EnemyService.scaledHealth(def.health, wave, playerCount)
	if def.isBoss then
		-- bosses lean much harder on squad size and keep climbing in endless mode
		maxHealth = math.floor(def.health * (1 + 0.6 * (playerCount - 1)) * (1 + 0.08 * math.max(0, wave - GameConfig.BossWaveInterval)))
	end
	maxHealth = math.floor(maxHealth * (options.healthMult or 1))

	local entity = {
		uid = nextId,
		def = def,
		model = model,
		root = root,
		head = head,
		health = maxHealth,
		maxHealth = maxHealth,
		speed = def.isBoss and def.speed or scaledSpeed(def.speed, wave),
		damage = def.isBoss and def.damage or math.floor(def.damage * (1 + 0.04 * (wave - 1))),
		wave = wave,
		isBoss = def.isBoss == true,
		y = position.Y + def.height * 0.5,
		lastAttack = 0,
		abilities = abilityState(def.abilities),
		phaseIndex = 0,
		barrier = options.barrier,
		entered = options.insideAlready == true or options.barrier == nil,
		bob = rng:NextNumber(0, math.pi * 2),
		pathAt = 0,
		path = nil,
		pathIndex = 1,
		pathPending = false,
		target = nil,
		retargetAt = 0,
		chargeUntil = 0,
		stunUntil = 0,
		alive = true,
	}

	root:SetAttribute("NecroEnemy", entity.uid)
	root:SetAttribute("MaxHealth", maxHealth)
	root:SetAttribute("Health", maxHealth)
	if head then
		head:SetAttribute("NecroEnemy", entity.uid)
	end

	entities[entity.uid] = entity
	aliveCount = aliveCount + 1

	if entity.isBoss then
		boss = entity
		buildBossBar(entity)
		Net.get("BossState"):FireAllClients({
			active = true,
			name = def.name,
			title = def.title,
			health = entity.health,
			maxHealth = entity.maxHealth,
			final = def.isFinal == true,
		})
	end

	return entity
end

function EnemyService.aliveCount()
	return aliveCount
end

function EnemyService.boss()
	return boss
end

function EnemyService.setInstakill(value)
	instakill = value
end

function EnemyService.entityFromPart(part)
	if not part then return nil end
	local uid = part:GetAttribute("NecroEnemy")
	if not uid then
		local parent = part.Parent
		uid = parent and parent:IsA("Model") and parent.PrimaryPart and parent.PrimaryPart:GetAttribute("NecroEnemy")
	end
	if not uid then return nil end
	return entities[uid]
end

function EnemyService.forEach(fn)
	for _, entity in pairs(entities) do
		if entity.alive then
			fn(entity)
		end
	end
end

--------------------------------------------------------------------------------
-- death
--------------------------------------------------------------------------------

local function ashBurst(entity)
	local root = entity.root
	if not root then return end
	local burst = Instance.new("Part")
	burst.Size = Vector3.new(1, 1, 1)
	burst.Position = root.Position
	burst.Anchored = true
	burst.CanCollide = false
	burst.Transparency = 1
	burst.Parent = S.Map.fxFolder

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(entity.def.colors.torso, entity.def.colors.glow)
	emitter.Lifetime = NumberRange.new(0.4, 0.9)
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(6, 16)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(entity.def.width * 0.8)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = burst
	emitter:Emit(entity.isBoss and 160 or 26)
	Debris:AddItem(burst, 2)
end

local function despawn(entity)
	if not entity.alive then return end
	entity.alive = false
	entities[entity.uid] = nil
	aliveCount = math.max(0, aliveCount - 1)
	if entity.model then
		entity.model:Destroy()
	end
	if entity == boss then
		boss = nil
		Net.get("BossState"):FireAllClients({ active = false })
	end
	if S.WaveService then
		S.WaveService.onEnemyRemoved(entity)
	end
end

local function killEntity(entity, killer, headshot)
	if not entity.alive then return end
	ashBurst(entity)

	if killer and killer.Parent then
		local reward = entity.def.salvage
		if not reward then
			reward = headshot and GameConfig.SalvagePerHeadshotKill or GameConfig.SalvagePerKill
		end
		S.Economy.add(killer, reward)
		S.Economy.addKill(killer)
		Net.get("Hitmarker"):FireClient(killer, { kill = true, boss = entity.isBoss, headshot = headshot })
	end

	if not entity.isBoss and S.PowerupService then
		S.PowerupService.maybeDrop(entity.root.Position)
	end

	despawn(entity)
end

function EnemyService.damage(entity, amount, attacker, headshot)
	if not entity or not entity.alive then return 0 end
	if instakill and not entity.isBoss then
		amount = entity.health
	end
	local dealt = math.min(entity.health, amount)
	entity.health = entity.health - dealt
	if entity.root then
		entity.root:SetAttribute("Health", math.max(0, entity.health))
	end

	if entity.isBoss then
		local fraction = math.max(0, entity.health / entity.maxHealth)
		if entity.bossFill then
			entity.bossFill.Size = UDim2.fromScale(fraction, 1)
		end
		-- the in-world nameplate above updates every hit; the screen-wide bar is
		-- a broadcast, so throttle it to ~10 Hz (and always send the killing blow)
		local now = os.clock()
		if entity.health <= 0 or not entity.bossPushAt or now - entity.bossPushAt >= 0.1 then
			entity.bossPushAt = now
			Net.get("BossState"):FireAllClients({
				active = true,
				name = entity.def.name,
				title = entity.def.title,
				health = math.max(0, entity.health),
				maxHealth = entity.maxHealth,
				final = entity.def.isFinal == true,
			})
		end
		-- phase transitions
		local phases = entity.def.phases
		if phases then
			for index, phase in ipairs(phases) do
				if index > entity.phaseIndex and fraction <= phase.at then
					entity.phaseIndex = index
					entity.speed = entity.def.speed * (phase.speedMult or 1)
					entity.damage = math.floor(entity.def.damage * (phase.damageMult or 1))
					if phase.abilities then
						entity.abilities = abilityState(phase.abilities)
					end
					if phase.announce then
						Net.get("Announce"):FireAllClients({
							title = phase.announce,
							subtitle = entity.def.name,
							color = { entity.def.colors.glow.R * 255, entity.def.colors.glow.G * 255, entity.def.colors.glow.B * 255 },
							duration = 3,
						})
					end
				end
			end
		end
	end

	if entity.health <= 0 then
		killEntity(entity, attacker, headshot)
	end
	return dealt
end

-- Powerup: wipe the trash mobs, leave bosses standing.
function EnemyService.purge(awardTo)
	local victims = {}
	for _, entity in pairs(entities) do
		if entity.alive and not entity.isBoss then
			table.insert(victims, entity)
		end
	end
	for _, entity in ipairs(victims) do
		ashBurst(entity)
		if awardTo then
			S.Economy.addKill(awardTo)
		end
		despawn(entity)
	end
	return #victims
end

function EnemyService.clearAll()
	for _, entity in pairs(entities) do
		despawn(entity)
	end
	entities = {}
	aliveCount = 0
	boss = nil
	Net.get("BossState"):FireAllClients({ active = false })
end

--------------------------------------------------------------------------------
-- abilities
--------------------------------------------------------------------------------

local function ringFx(position, radius, color, lifetime)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.6, 2, 2)
	ring.CFrame = CFrame.new(position.X, 0.7, position.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.25
	ring.Parent = S.Map.fxFolder

	local tween = TweenService:Create(ring, TweenInfo.new(lifetime or 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.6, radius * 2, radius * 2),
		Transparency = 1,
	})
	tween:Play()
	Debris:AddItem(ring, (lifetime or 0.55) + 0.2)
end

local function damagePlayersInRadius(center, radius, damage, sourceName)
	for _, target in ipairs(Util.activeTargets()) do
		local delta = target.root.Position - center
		local flat = Vector3.new(delta.X, 0, delta.Z)
		if flat.Magnitude <= radius and math.abs(delta.Y) < 20 then
			S.PlayerService.damage(target.player, damage, sourceName)
		end
	end
end

local abilityHandlers = {}

abilityHandlers.slam = function(entity, ability, target, dist)
	if dist > (ability.range or 14) then return false end
	entity.stunUntil = os.clock() + 0.75
	local center = entity.root.Position
	ringFx(center, ability.radius or 16, entity.def.colors.glow, 0.5)
	task.delay(0.45, function()
		if not entity.alive then return end
		damagePlayersInRadius(entity.root.Position, ability.radius or 16, ability.damage or 35, entity.def.name .. " slam")
		ringFx(entity.root.Position, (ability.radius or 16) * 0.6, entity.def.colors.glow, 0.35)
	end)
	return true
end

abilityHandlers.shockwave = function(entity, ability)
	entity.stunUntil = os.clock() + 1.0
	local radius = ability.radius or 30
	ringFx(entity.root.Position, radius, entity.def.colors.glow, 1.0)
	local center = entity.root.Position
	for step = 1, 3 do
		task.delay(step * 0.25, function()
			if not entity.alive then return end
			damagePlayersInRadius(center, radius * (step / 3), math.floor((ability.damage or 40) / 2), entity.def.name .. " shockwave")
		end)
	end
	return true
end

abilityHandlers.summon = function(entity, ability)
	local count = ability.count or 4
	for i = 1, count do
		local offset = Util.randomFlatOffset(entity.def.width * 2 + 8)
		local pos = entity.root.Position + offset
		pos = Vector3.new(
			math.clamp(pos.X, -S.Map.bounds + 8, S.Map.bounds - 8),
			0,
			math.clamp(pos.Z, -S.Map.bounds + 8, S.Map.bounds - 8)
		)
		local spawned = EnemyService.spawn(ability.enemy or "husk", entity.wave, pos, { insideAlready = true, healthMult = 0.8 })
		if spawned then
			ringFx(pos, 6, entity.def.colors.glow, 0.4)
		end
	end
	Net.get("Notify"):FireAllClients({
		text = entity.def.name .. " summons reinforcements",
		color = { 255, 170, 80 },
	})
	return true
end

abilityHandlers.blink = function(entity, ability, target)
	if not target then return false end
	local behind = target.root.Position - target.root.CFrame.LookVector * 10
	local pos = Vector3.new(behind.X, entity.y, behind.Z)
	ringFx(entity.root.Position, 10, entity.def.colors.glow, 0.3)
	entity.model:PivotTo(CFrame.new(pos))
	entity.path = nil
	ringFx(pos, 10, entity.def.colors.glow, 0.3)
	return true
end

abilityHandlers.charge = function(entity, ability, target, dist)
	if not target or dist > (ability.range or 60) or dist < 12 then return false end
	entity.chargeUntil = os.clock() + (ability.duration or 2)
	entity.chargeMult = ability.speedMult or 2.5
	entity.chargeDamage = ability.damage or entity.damage
	Net.get("Notify"):FireAllClients({
		text = entity.def.name .. " charges",
		color = { 255, 110, 110 },
	})
	return true
end

abilityHandlers.spit = function(entity, ability, target, dist)
	if not target or dist > (ability.range or 70) then return false end
	local origin = entity.root.Position + Vector3.new(0, entity.def.height * 0.3, 0)
	local goal = target.root.Position

	local blob = Instance.new("Part")
	blob.Shape = Enum.PartType.Ball
	blob.Size = Vector3.new(2.2, 2.2, 2.2)
	blob.Position = origin
	blob.Anchored = true
	blob.CanCollide = false
	blob.Material = Enum.Material.Neon
	blob.Color = entity.def.colors.glow
	blob.Parent = S.Map.fxFolder

	local travel = math.clamp((goal - origin).Magnitude / (ability.speed or 90), 0.2, 2.5)
	TweenService:Create(blob, TweenInfo.new(travel, Enum.EasingStyle.Linear), { Position = goal }):Play()
	task.delay(travel, function()
		if blob.Parent then
			ringFx(goal, ability.radius or 9, entity.def.colors.glow, 0.4)
			damagePlayersInRadius(goal, ability.radius or 9, ability.damage or 24, entity.def.name .. " bile")
			blob:Destroy()
		end
	end)
	return true
end

--------------------------------------------------------------------------------
-- steering
--------------------------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function refreshRayFilter()
	local filter = {}
	if S.Map then
		table.insert(filter, S.Map.enemyFolder)
		table.insert(filter, S.Map.fxFolder)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(filter, player.Character)
		end
	end
	rayParams.FilterDescendantsInstances = filter
end

local function hasLineOfSight(fromPos, toPos)
	local delta = toPos - fromPos
	local distance = delta.Magnitude
	if distance < 0.1 then return true end
	local result = workspace:Raycast(fromPos, delta.Unit * math.min(distance, 140), rayParams)
	return result == nil
end

local function requestPath(entity, goal)
	if entity.pathPending then return end
	entity.pathPending = true
	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = math.max(2, entity.def.width * 0.6),
			AgentHeight = entity.def.height,
			AgentCanJump = false,
			WaypointSpacing = 8,
		})
		local ok = pcall(function()
			path:ComputeAsync(entity.root.Position, goal)
		end)
		if entity.alive and ok and path.Status == Enum.PathStatus.Success then
			local waypoints = path:GetWaypoints()
			entity.path = waypoints
			entity.pathIndex = math.min(2, #waypoints)
		else
			entity.path = nil
		end
		entity.pathPending = false
	end)
end

local function pickTarget(entity)
	local now = os.clock()
	if entity.target and now < entity.retargetAt then
		local character = entity.target.player and entity.target.player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and entity.target.root and entity.target.root.Parent then
			return entity.target
		end
	end

	local candidates = Util.activeTargets()
	if #candidates == 0 then
		candidates = Util.anyLivingCharacters()
	end
	local best, bestDist
	local myPos = entity.root.Position
	for _, candidate in ipairs(candidates) do
		local dist = (candidate.root.Position - myPos).Magnitude
		if not bestDist or dist < bestDist then
			best, bestDist = candidate, dist
		end
	end
	entity.target = best
	entity.retargetAt = now + rng:NextNumber(1.2, 2.4)
	entity.path = nil
	return best
end

-- Separation so a pack does not collapse into one stack of cubes.
local function separation(entity)
	local push = Vector3.new()
	local myPos = entity.root.Position
	local personal = entity.def.width * 1.5
	local checked = 0
	for _, other in pairs(entities) do
		if other ~= entity and other.alive then
			local delta = myPos - other.root.Position
			local flat = Vector3.new(delta.X, 0, delta.Z)
			local dist = flat.Magnitude
			if dist > 0.01 and dist < personal then
				push = push + flat.Unit * ((personal - dist) / personal)
			end
			checked = checked + 1
			if checked > 24 then break end
		end
	end
	return push
end

local function moveEntity(entity, dt)
	local now = os.clock()
	if now < entity.stunUntil then return end

	local root = entity.root
	local myPos = root.Position
	local target = pickTarget(entity)

	local goalPos
	local gating = false

	if not entity.entered and entity.barrier then
		local barrier = entity.barrier
		local gate = barrier.origin
		local flatToGate = Vector3.new(gate.X - myPos.X, 0, gate.Z - myPos.Z)
		if flatToGate.Magnitude <= 8 then
			if entity.isBoss then
				S.BarrierService.smash(barrier)
				entity.entered = true
			elseif S.BarrierService.isOpen(barrier) then
				entity.entered = true
			else
				S.BarrierService.tear(barrier, dt, entity)
				gating = true
			end
		end
		goalPos = barrier.inside
		if entity.entered then
			goalPos = nil
		end
	end

	if gating then
		-- pressed against the boards: face the gap and keep clawing
		local look = Vector3.new(entity.barrier.inward.X, 0, entity.barrier.inward.Z)
		entity.model:PivotTo(CFrame.lookAt(Vector3.new(myPos.X, entity.y, myPos.Z), Vector3.new(myPos.X, entity.y, myPos.Z) + look))
		return
	end

	if not goalPos then
		if not target then
			return
		end
		goalPos = target.root.Position
	end

	local flat = Vector3.new(goalPos.X - myPos.X, 0, goalPos.Z - myPos.Z)
	local dist = flat.Magnitude
	local attackRange = GameConfig.EnemyAttackRange + entity.def.width * 0.5

	-- attack / abilities
	if target then
		local toTarget = target.root.Position - myPos
		local targetDist = Vector3.new(toTarget.X, 0, toTarget.Z).Magnitude
		if targetDist <= attackRange then
			if now - entity.lastAttack >= GameConfig.EnemyAttackCooldown then
				entity.lastAttack = now
				S.PlayerService.damage(target.player, entity.damage, entity.def.name)
			end
		end
		for _, slot in ipairs(entity.abilities) do
			if now >= slot.nextUse then
				local handler = abilityHandlers[slot.def.kind]
				if handler then
					local used = handler(entity, slot.def, target, targetDist)
					if used then
						slot.nextUse = now + slot.def.cooldown
					else
						slot.nextUse = now + 0.6
					end
				else
					slot.nextUse = now + slot.def.cooldown
				end
			end
		end
	end

	if dist <= attackRange * 0.9 then
		-- hold position but keep facing the player
		if dist > 0.05 then
			local look = flat.Unit
			entity.model:PivotTo(CFrame.lookAt(Vector3.new(myPos.X, entity.y, myPos.Z), Vector3.new(myPos.X, entity.y, myPos.Z) + look))
		end
		return
	end

	-- direction: straight line when possible, otherwise follow a computed path
	local eyePos = Vector3.new(myPos.X, entity.y, myPos.Z)
	local goalEye = Vector3.new(goalPos.X, entity.y, goalPos.Z)
	local direction

	if hasLineOfSight(eyePos, goalEye) then
		entity.path = nil
		direction = flat.Unit
	else
		if not entity.path or now - entity.pathAt > 1.4 then
			entity.pathAt = now
			requestPath(entity, goalPos)
		end
		if entity.path and entity.pathIndex <= #entity.path then
			local waypoint = entity.path[entity.pathIndex]
			local wpFlat = Vector3.new(waypoint.Position.X - myPos.X, 0, waypoint.Position.Z - myPos.Z)
			if wpFlat.Magnitude < 5 then
				entity.pathIndex = entity.pathIndex + 1
				if entity.pathIndex <= #entity.path then
					waypoint = entity.path[entity.pathIndex]
					wpFlat = Vector3.new(waypoint.Position.X - myPos.X, 0, waypoint.Position.Z - myPos.Z)
				end
			end
			if wpFlat.Magnitude > 0.05 then
				direction = wpFlat.Unit
			end
		end
		if not direction then
			-- last resort: sidestep the obstacle
			for _, degrees in ipairs({ 45, -45, 90, -90, 135, -135 }) do
				local rotated = CFrame.Angles(0, math.rad(degrees), 0) * flat.Unit
				if hasLineOfSight(eyePos, eyePos + rotated * 14) then
					direction = rotated
					break
				end
			end
		end
		direction = direction or flat.Unit
	end

	local speed = entity.speed
	if now < entity.chargeUntil then
		speed = speed * (entity.chargeMult or 2.4)
	end

	local push = separation(entity)
	local steer = direction + push * 0.55
	if steer.Magnitude < 0.05 then
		steer = direction
	end
	steer = steer.Unit

	local step = math.min(speed * dt, dist)
	local newPos = Vector3.new(myPos.X, entity.y, myPos.Z) + steer * step

	-- stay inside the world
	local limit = S.Map.bounds + 44
	newPos = Vector3.new(
		math.clamp(newPos.X, -limit, limit),
		entity.y + math.sin((now + entity.bob) * 6) * 0.18,
		math.clamp(newPos.Z, -limit, limit)
	)

	local lookAt = newPos + Vector3.new(steer.X, 0, steer.Z)
	local lurch = math.sin((now + entity.bob) * 5) * 0.09
	entity.model:PivotTo(CFrame.lookAt(newPos, lookAt) * CFrame.Angles(0, 0, lurch))
end

--------------------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------------------

function EnemyService.init(services)
	S = services
	refreshRayFilter()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.defer(refreshRayFilter)
		end)
		task.defer(refreshRayFilter)
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(refreshRayFilter)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function()
			task.defer(refreshRayFilter)
		end)
	end

	local filterRefreshAt = 0
	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		accumulator = accumulator + dt
		if accumulator < TICK_RATE then return end
		local step = accumulator
		accumulator = 0

		local now = os.clock()
		if now - filterRefreshAt > 2 then
			filterRefreshAt = now
			refreshRayFilter()
		end

		for _, entity in pairs(entities) do
			if entity.alive and entity.root and entity.root.Parent then
				local ok, err = pcall(moveEntity, entity, step)
				if not ok and GameConfig.DebugLogging then
					warn("[Necrotide] enemy step failed: " .. tostring(err))
				end
			end
		end
	end)
end

function EnemyService.shutdown()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
end

return EnemyService
