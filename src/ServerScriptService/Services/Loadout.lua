-- Loadout: which guns a player is carrying, their ammo, reloads, swapping and
-- the physical gun model welded to the character. Authoritative: the client only
-- ever asks, it never tells.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("NecrotideShared")
local GameConfig = require(Shared.GameConfig)
local WeaponDefs = require(Shared.WeaponDefs)
local Net = require(Shared.Net)

local Loadout = {}
local S

local state = {}

local function ensure(player)
	local entry = state[player]
	if not entry then
		entry = {
			slots = {},
			active = 1,
			reloading = false,
			reloadEnd = 0,
			lastShot = 0,
			suppressed = false,
			model = nil,
		}
		state[player] = entry
	end
	return entry
end

function Loadout.push(player)
	local entry = ensure(player)
	local slots = {}
	for i = 1, GameConfig.MaxWeaponSlots do
		slots[i] = WeaponDefs.publicState(entry.slots[i])
	end
	Net.get("LoadoutChanged"):FireClient(player, {
		slots = slots,
		active = entry.active,
		reloading = entry.reloading,
		reloadEnd = entry.reloadEnd,
	})
end

function Loadout.active(player)
	local entry = ensure(player)
	return entry.slots[entry.active]
end

local function attachPoint(character)
	return character:FindFirstChild("RightHand")
		or character:FindFirstChild("Right Arm")
		or character:FindFirstChild("HumanoidRootPart")
end

-- Builds a small blocky gun and welds it to the right hand.
local function buildGunModel(player, inst)
	local entry = ensure(player)
	if entry.model then
		entry.model:Destroy()
		entry.model = nil
	end
	local character = player.Character
	if not character or not inst then return end
	local hand = attachPoint(character)
	if not hand then return end

	local def = WeaponDefs.get(inst.id)
	local body = (def and def.body) or { color = Color3.fromRGB(60, 60, 60), length = 2, bore = 0.25 }

	local model = Instance.new("Model")
	model.Name = "NecrotideGun"

	local function piece(name, size, offset, color, material)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Color = color
		part.Material = material or Enum.Material.Metal
		part.CanCollide = false
		part.Massless = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.CFrame = hand.CFrame * CFrame.new(offset)
		part.Parent = model
		return part
	end

	local tint = inst.upgraded and (inst.tracerColor or Color3.fromRGB(150, 210, 255)) or body.color
	local receiver = piece("Receiver", Vector3.new(0.45, 0.6, body.length), Vector3.new(0, -0.6, -body.length * 0.4), tint)
	piece("Barrel", Vector3.new(body.bore, body.bore, body.length * 0.7), Vector3.new(0, -0.45, -body.length * 0.95), Color3.fromRGB(34, 34, 38))
	piece("Grip", Vector3.new(0.35, 0.7, 0.4), Vector3.new(0, -1.0, -body.length * 0.1), Color3.fromRGB(28, 26, 26), Enum.Material.Plastic)
	piece("Mag", Vector3.new(0.3, 0.6, 0.5), Vector3.new(0, -1.05, -body.length * 0.45), Color3.fromRGB(40, 40, 44))
	local sight = piece("Sight", Vector3.new(0.18, 0.22, 0.4), Vector3.new(0, -0.22, -body.length * 0.5), Color3.fromRGB(24, 24, 26))

	local muzzle = Instance.new("Part")
	muzzle.Name = "Muzzle"
	muzzle.Size = Vector3.new(0.2, 0.2, 0.2)
	muzzle.Transparency = 1
	muzzle.CanCollide = false
	muzzle.Massless = true
	muzzle.CFrame = hand.CFrame * CFrame.new(0, -0.45, -body.length * 1.3)
	muzzle.Parent = model

	if inst.upgraded then
		local glow = Instance.new("PointLight")
		glow.Color = inst.tracerColor or Color3.fromRGB(150, 210, 255)
		glow.Brightness = 1.6
		glow.Range = 12
		glow.Parent = receiver
		receiver.Material = Enum.Material.Neon
		sight.Color = inst.tracerColor or Color3.fromRGB(150, 210, 255)
	end

	model.PrimaryPart = receiver
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = hand
			weld.Part1 = part
			weld.Parent = part
			part.Anchored = false
		end
	end
	model.Parent = character
	entry.model = model
end

function Loadout.refreshModel(player)
	buildGunModel(player, Loadout.active(player))
end

function Loadout.setSuppressed(player, suppressed)
	ensure(player).suppressed = suppressed
end

function Loadout.onCharacter(player, character)
	local entry = ensure(player)
	entry.reloading = false
	entry.reloadEnd = 0
	entry.suppressed = false
	if #entry.slots == 0 then
		entry.slots[1] = WeaponDefs.makeInstance(WeaponDefs.StartingWeapon, false)
		entry.active = 1
	end
	task.defer(function()
		if player.Character == character then
			buildGunModel(player, Loadout.active(player))
			Loadout.push(player)
		end
	end)
end

-- Combat asks for permission to fire. Returns the weapon instance on success.
function Loadout.consumeShot(player)
	local entry = ensure(player)
	if entry.suppressed then return nil, "suppressed" end
	if S.PlayerService.isDowned(player) or S.PlayerService.isOut(player) then return nil, "down" end
	local inst = entry.slots[entry.active]
	if not inst then return nil, "empty" end

	local now = os.clock()
	if entry.reloading then
		if now < entry.reloadEnd then
			return nil, "reloading"
		end
		-- reload finished while nobody polled it
		Loadout.finishReload(player)
	end
	if inst.ammo <= 0 then
		Loadout.reload(player)
		return nil, "dry"
	end
	local interval = 60 / math.max(1, inst.rpm)
	if now - entry.lastShot < interval * 0.85 then
		return nil, "rate"
	end
	entry.lastShot = now
	inst.ammo = inst.ammo - 1
	Loadout.push(player)
	return inst
end

function Loadout.finishReload(player)
	local entry = ensure(player)
	local inst = entry.slots[entry.active]
	entry.reloading = false
	entry.reloadEnd = 0
	if not inst then return end
	local need = inst.mag - inst.ammo
	local take = math.min(need, inst.spare)
	inst.ammo = inst.ammo + take
	inst.spare = inst.spare - take
	Loadout.push(player)
end

function Loadout.reload(player)
	local entry = ensure(player)
	local inst = entry.slots[entry.active]
	if not inst or entry.reloading then return false end
	if inst.ammo >= inst.mag or inst.spare <= 0 then return false end
	if entry.suppressed or S.PlayerService.isDowned(player) then return false end

	local scale = S.PlayerService.tonicAgg(player).reloadScale
	local duration = inst.reloadTime * scale
	entry.reloading = true
	entry.reloadEnd = os.clock() + duration
	Loadout.push(player)

	task.delay(duration, function()
		local current = state[player]
		if not current or not current.reloading then return end
		if current.slots[current.active] ~= inst then
			current.reloading = false
			current.reloadEnd = 0
			Loadout.push(player)
			return
		end
		Loadout.finishReload(player)
	end)
	return true
end

function Loadout.swap(player, index)
	local entry = ensure(player)
	index = math.floor(tonumber(index) or 0)
	if index < 1 or index > GameConfig.MaxWeaponSlots then return false end
	if index == entry.active or not entry.slots[index] then return false end
	entry.active = index
	entry.reloading = false
	entry.reloadEnd = 0
	buildGunModel(player, entry.slots[index])
	Loadout.push(player)
	return true
end

-- Gives a weapon, filling an empty slot first, otherwise replacing the held one.
function Loadout.give(player, weaponId, upgraded)
	local inst = WeaponDefs.makeInstance(weaponId, upgraded)
	if not inst then return false end
	local entry = ensure(player)

	for i = 1, GameConfig.MaxWeaponSlots do
		if entry.slots[i] and entry.slots[i].id == weaponId then
			-- already owned: top the ammo off instead of duplicating
			local existing = entry.slots[i]
			if upgraded and not existing.upgraded then
				entry.slots[i] = inst
			else
				existing.ammo = existing.mag
				existing.spare = existing.reserve
			end
			entry.active = i
			entry.reloading = false
			buildGunModel(player, entry.slots[i])
			Loadout.push(player)
			return true
		end
	end

	local target
	for i = 1, GameConfig.MaxWeaponSlots do
		if not entry.slots[i] then
			target = i
			break
		end
	end
	target = target or entry.active
	entry.slots[target] = inst
	entry.active = target
	entry.reloading = false
	entry.reloadEnd = 0
	buildGunModel(player, inst)
	Loadout.push(player)
	return true
end

function Loadout.upgradeActive(player)
	local entry = ensure(player)
	local inst = entry.slots[entry.active]
	if not inst then return false, "nothing held" end
	if inst.upgraded then return false, "already forged" end
	local upgraded = WeaponDefs.makeInstance(inst.id, true)
	if not upgraded then return false, "cannot forge" end
	entry.slots[entry.active] = upgraded
	entry.reloading = false
	entry.reloadEnd = 0
	buildGunModel(player, upgraded)
	Loadout.push(player)
	return true, upgraded.name
end

-- Used by the Overforge: upgrades a specific slot, but only if the same weapon is
-- still sitting in it when the machine finishes.
function Loadout.upgradeSlot(player, slotIndex, weaponId)
	local entry = ensure(player)
	local inst = entry.slots[slotIndex]
	if not inst or inst.id ~= weaponId then return false, "weapon moved" end
	if inst.upgraded then return false, "already forged" end
	local upgraded = WeaponDefs.makeInstance(weaponId, true)
	if not upgraded then return false, "cannot forge" end
	entry.slots[slotIndex] = upgraded
	if entry.active == slotIndex then
		entry.reloading = false
		entry.reloadEnd = 0
		buildGunModel(player, upgraded)
	end
	Loadout.push(player)
	return true, upgraded.name
end

function Loadout.refillActive(player)
	local entry = ensure(player)
	local inst = entry.slots[entry.active]
	if not inst then return false end
	inst.ammo = inst.mag
	inst.spare = inst.reserve
	Loadout.push(player)
	return true
end

function Loadout.refillWeapon(player, weaponId)
	local entry = ensure(player)
	for i = 1, GameConfig.MaxWeaponSlots do
		local inst = entry.slots[i]
		if inst and inst.id == weaponId then
			inst.ammo = inst.mag
			inst.spare = inst.reserve
			Loadout.push(player)
			return true
		end
	end
	return false
end

function Loadout.maxAmmoEveryone()
	for _, player in ipairs(Players:GetPlayers()) do
		local entry = ensure(player)
		for i = 1, GameConfig.MaxWeaponSlots do
			local inst = entry.slots[i]
			if inst then
				inst.ammo = inst.mag
				inst.spare = inst.reserve
			end
		end
		Loadout.push(player)
	end
end

function Loadout.has(player, weaponId)
	local entry = ensure(player)
	for i = 1, GameConfig.MaxWeaponSlots do
		if entry.slots[i] and entry.slots[i].id == weaponId then
			return true, i
		end
	end
	return false
end

function Loadout.resetForNewRun()
	for _, player in ipairs(Players:GetPlayers()) do
		local entry = ensure(player)
		entry.slots = { WeaponDefs.makeInstance(WeaponDefs.StartingWeapon, false) }
		entry.active = 1
		entry.reloading = false
		entry.reloadEnd = 0
		buildGunModel(player, entry.slots[1])
		Loadout.push(player)
	end
end

function Loadout.snapshot(player)
	local entry = ensure(player)
	local slots = {}
	for i = 1, GameConfig.MaxWeaponSlots do
		slots[i] = WeaponDefs.publicState(entry.slots[i])
	end
	return { slots = slots, active = entry.active, reloading = entry.reloading, reloadEnd = entry.reloadEnd }
end

function Loadout.init(services)
	S = services

	Net.get("ReloadRequest").OnServerEvent:Connect(function(player)
		Loadout.reload(player)
	end)

	Net.get("SwapRequest").OnServerEvent:Connect(function(player, index)
		if typeof(index) ~= "number" then return end
		Loadout.swap(player, index)
	end)

	Players.PlayerRemoving:Connect(function(player)
		state[player] = nil
	end)
end

return Loadout
