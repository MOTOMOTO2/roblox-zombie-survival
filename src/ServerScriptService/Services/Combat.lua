-- Combat: server-authoritative hitscan. The client sends only an aim direction;
-- the server owns the origin, the spread roll, the raycast, the damage and the
-- ammo. Explosives, chain lightning and piercing all resolve here too.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("NecrotideShared")
local GameConfig = require(Shared.GameConfig)
local Net = require(Shared.Net)

local Combat = {}
local S

local MAX_ORIGIN_DRIFT = 14 -- studs the claimed origin may differ from the head
local rng = Random.new(os.clock() * 7919)

local function shootParams(character)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local filter = { character }
	if S.Map then
		table.insert(filter, S.Map.fxFolder)
	end
	params.FilterDescendantsInstances = filter
	return params
end

local function applySpread(direction, spreadDegrees)
	if spreadDegrees <= 0 then return direction end
	local spread = math.rad(spreadDegrees)
	local up = math.abs(direction.Y) > 0.99 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
	local right = direction:Cross(up).Unit
	local trueUp = right:Cross(direction).Unit
	local angle = rng:NextNumber(0, math.pi * 2)
	local magnitude = math.sqrt(rng:NextNumber()) * spread
	local offset = (right * math.cos(angle) + trueUp * math.sin(angle)) * math.tan(magnitude)
	return (direction + offset).Unit
end

local function explode(center, radius, damage, attacker, color)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Ball
	ring.Size = Vector3.new(4, 4, 4)
	ring.Position = center
	ring.Anchored = true
	ring.CanCollide = false
	ring.Material = Enum.Material.Neon
	ring.Color = color or Color3.fromRGB(255, 150, 60)
	ring.Transparency = 0.15
	ring.Parent = S.Map.fxFolder
	TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(radius * 2, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.8)

	local hits = 0
	S.EnemyService.forEach(function(entity)
		local delta = entity.root.Position - center
		if delta.Magnitude <= radius then
			local falloff = 1 - (delta.Magnitude / radius) * 0.5
			S.EnemyService.damage(entity, damage * falloff, attacker, false)
			hits = hits + 1
		end
	end)
	return hits
end

local function chainFrom(entity, inst, attacker, chainDef, alreadyHit)
	local origin = entity.root.Position
	local remaining = chainDef.count or 3
	local damage = inst.damage * (chainDef.mult or 0.6)
	local links = {}
	local current = origin

	while remaining > 0 do
		local best, bestDist
		S.EnemyService.forEach(function(candidate)
			if alreadyHit[candidate.uid] then return end
			local dist = (candidate.root.Position - current).Magnitude
			if dist <= (chainDef.radius or 20) and (not bestDist or dist < bestDist) then
				best, bestDist = candidate, dist
			end
		end)
		if not best then break end
		alreadyHit[best.uid] = true
		table.insert(links, best.root.Position)
		S.EnemyService.damage(best, damage, attacker, false)
		current = best.root.Position
		damage = damage * (chainDef.mult or 0.6)
		remaining = remaining - 1
	end
	return links
end

local function resolveShot(player, direction)
	local character = player.Character
	if not character then return end
	local head = character:FindFirstChild("Head") or character.PrimaryPart
	if not head then return end

	local inst = S.Loadout.consumeShot(player)
	if not inst then return end

	local origin = head.Position
	local damageMult = S.PlayerService.tonicAgg(player).damageMult
	local params = shootParams(character)
	local pellets = math.max(1, inst.pellets or 1)
	local endPoints = {}
	local chainLinks = nil
	-- a shotgun blast is one hitmarker, not eight, so feedback is aggregated
	local feedback = { hit = false, headshot = false, killed = false, boss = false }

	for _ = 1, pellets do
		local dir = applySpread(direction, inst.spread)
		local remainingPierce = inst.pierce or 0
		local rayOrigin = origin
		local rayParams = params
		-- piercing rounds accumulate exclusions so they never re-hit a target
		local pierceFilter = { character, S.Map.fxFolder }
		local hitThisPellet = {}
		local travelled = 0
		local landed = origin + dir * inst.range

		while true do
			local remainingRange = inst.range - travelled
			if remainingRange <= 0 then break end
			local result = workspace:Raycast(rayOrigin, dir * remainingRange, rayParams)
			if not result then
				landed = rayOrigin + dir * remainingRange
				break
			end
			landed = result.Position
			local entity = S.EnemyService.entityFromPart(result.Instance)
			if entity then
				local isHead = result.Instance.Name == "Head"
				local damage = inst.damage * damageMult * (isHead and inst.headMult or 1)
				local before = entity.health
				S.EnemyService.damage(entity, damage, player, isHead)
				hitThisPellet[entity.uid] = true

				if before > 0 and entity.health > 0 then
					S.Economy.add(player, GameConfig.SalvagePerHit)
				end
				feedback.hit = true
				feedback.headshot = feedback.headshot or isHead
				feedback.killed = feedback.killed or entity.health <= 0
				feedback.boss = feedback.boss or entity.isBoss

				if inst.chain then
					chainLinks = chainFrom(entity, inst, player, inst.chain, hitThisPellet)
				end

				if remainingPierce > 0 then
					remainingPierce = remainingPierce - 1
					travelled = travelled + (result.Position - rayOrigin).Magnitude + 0.5
					rayOrigin = result.Position + dir * 0.5
					if entity.model then
						table.insert(pierceFilter, entity.model)
					end
					local nextParams = RaycastParams.new()
					nextParams.FilterType = Enum.RaycastFilterType.Exclude
					nextParams.IgnoreWater = true
					nextParams.FilterDescendantsInstances = pierceFilter
					rayParams = nextParams
				else
					break
				end
			else
				break
			end
		end

		if inst.explosive then
			explode(landed, inst.explosive.radius, inst.explosive.damage * damageMult, player, inst.tracerColor)
		end
		table.insert(endPoints, landed)
	end

	if feedback.hit then
		Net.get("Hitmarker"):FireClient(player, feedback)
	end

	Net.get("ShotFx"):FireAllClients({
		shooter = player,
		points = endPoints,
		color = inst.tracerColor and { inst.tracerColor.R * 255, inst.tracerColor.G * 255, inst.tracerColor.B * 255 } or nil,
		chain = chainLinks,
		upgraded = inst.upgraded,
		class = inst.class,
	})
end

function Combat.init(services)
	S = services

	Net.get("FireRequest").OnServerEvent:Connect(function(player, direction, claimedOrigin)
		if typeof(direction) ~= "Vector3" then return end
		if direction.Magnitude < 0.01 or direction.Magnitude > 1000 then return end
		local character = player.Character
		local head = character and (character:FindFirstChild("Head") or character.PrimaryPart)
		if not head then return end
		if typeof(claimedOrigin) == "Vector3" then
			-- the claimed origin is only ever used as a sanity check; the shot
			-- always starts from the server's copy of the player's head
			if (claimedOrigin - head.Position).Magnitude > MAX_ORIGIN_DRIFT then
				return
			end
		end
		local ok, err = pcall(resolveShot, player, direction.Unit)
		if not ok and GameConfig.DebugLogging then
			warn("[Necrotide] shot failed: " .. tostring(err))
		end
	end)
end

return Combat
