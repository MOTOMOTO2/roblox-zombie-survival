-- StationService: everything you can walk up to and spend salvage on.
--   * Armory Racks   - wall weapons and ammo restocks
--   * The Fate Crate - random weapon roulette that sometimes packs up and moves
--   * The Overforge  - upgrades the weapon in your hands into its forged form
--   * Tonic Stills   - permanent buffs

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("NecrotideShared")
local GameConfig = require(Shared.GameConfig)
local WeaponDefs = require(Shared.WeaponDefs)
local TonicDefs = require(Shared.TonicDefs)
local Util = require(Shared.Util)
local Net = require(Shared.Net)

local StationService = {}
local S

local rng = Random.new(os.clock() * 4241)
local crate = {
	model = nil,
	spotIndex = 1,
	busy = false,
	uses = 0,
}
local forge = { model = nil, busy = false }

--------------------------------------------------------------------------------
-- shared building blocks
--------------------------------------------------------------------------------

local function newPart(parent, name, size, position, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material or Enum.Material.Metal
	part.Anchored = true
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function labelOn(part, title, subtitle, color, offsetY)
	local gui = Instance.new("BillboardGui")
	gui.Name = "StationLabel"
	gui.Size = UDim2.new(11, 0, 3.2, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY or 4, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 140
	gui.Parent = part

	local holder = Instance.new("Frame")
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.Parent = gui

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, 0, 0.58, 0)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBlack
	name.TextScaled = true
	name.TextColor3 = color or Color3.fromRGB(255, 220, 160)
	name.TextStrokeTransparency = 0.3
	name.Text = title
	name.Name = "Title"
	name.Parent = holder

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, 0, 0.42, 0)
	sub.Position = UDim2.new(0, 0, 0.58, 0)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamSemibold
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(235, 235, 235)
	sub.TextStrokeTransparency = 0.5
	sub.Text = subtitle or ""
	sub.Name = "Subtitle"
	sub.Parent = holder

	return gui
end

local function addPrompt(part, actionText, objectText, holdDuration, distance)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = holdDuration or 0
	prompt.MaxActivationDistance = distance or 11
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = part
	return prompt
end

local function canInteract(player)
	if S.PlayerService.isDowned(player) or S.PlayerService.isOut(player) then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function denied(player, text)
	Net.get("Notify"):FireClient(player, { text = text, color = { 255, 110, 110 } })
end

local function granted(player, text)
	Net.get("Notify"):FireClient(player, { text = text, color = { 150, 255, 170 } })
end

--------------------------------------------------------------------------------
-- armory racks (wall buys)
--------------------------------------------------------------------------------

local function buildWallBuy(spec)
	local def = WeaponDefs.get(spec.weapon)
	if not def then return end
	if not def.wallCost then
		warn("[Necrotide] " .. def.name .. " has no wallCost, so it cannot go on an Armory Rack")
		return
	end
	local folder = Instance.new("Model")
	folder.Name = "ArmoryRack_" .. def.id
	folder.Parent = S.Map.stationFolder

	local facing = spec.face
	local isXAxis = math.abs(facing.X) > 0.5
	local plateSize = isXAxis and Vector3.new(0.6, 5, 7) or Vector3.new(7, 5, 0.6)
	local plate = newPart(folder, "Plate", plateSize, spec.pos, Color3.fromRGB(46, 44, 42), Enum.Material.DiamondPlate)

	-- a chalk outline of the weapon on the wall
	local outlineSize = isXAxis and Vector3.new(0.3, 0.7, def.body.length) or Vector3.new(def.body.length, 0.7, 0.3)
	local outline = newPart(folder, "Outline", outlineSize, spec.pos + facing * 0.5, def.body.color, Enum.Material.SmoothPlastic)
	outline.CanCollide = false

	local ammoCost = math.floor((def.wallCost or 3000) * GameConfig.AmmoRefillCostRatio)
	labelOn(plate, def.name, "BUY " .. def.wallCost .. "   AMMO " .. ammoCost, Color3.fromRGB(255, 225, 170), 4)

	local prompt = addPrompt(plate, "Buy " .. def.name .. " [" .. def.wallCost .. "]", "ARMORY RACK", 0.25, 12)
	prompt.Triggered:Connect(function(player)
		if not canInteract(player) then return end
		local owned = S.Loadout.has(player, def.id)
		if owned then
			if not S.Economy.spend(player, ammoCost) then
				denied(player, "Need " .. ammoCost .. " salvage for ammo")
				return
			end
			S.Loadout.refillWeapon(player, def.id)
			granted(player, def.name .. " restocked")
		else
			if not S.Economy.spend(player, def.wallCost) then
				denied(player, "Need " .. def.wallCost .. " salvage")
				return
			end
			S.Loadout.give(player, def.id, false)
			granted(player, "Picked up " .. def.name)
		end
	end)
end

--------------------------------------------------------------------------------
-- the fate crate
--------------------------------------------------------------------------------

local function destroyCrate()
	if crate.model then
		crate.model:Destroy()
		crate.model = nil
	end
end

local function buildCrate(spotIndex)
	destroyCrate()
	crate.spotIndex = spotIndex
	local pos = S.Map.cratePositions[spotIndex]

	local model = Instance.new("Model")
	model.Name = "FateCrate"
	model.Parent = S.Map.stationFolder

	local base = newPart(model, "Base", Vector3.new(8, 4, 6), pos + Vector3.new(0, 2, 0), Color3.fromRGB(92, 66, 40), Enum.Material.WoodPlanks)
	local lid = newPart(model, "Lid", Vector3.new(8.4, 0.8, 6.4), pos + Vector3.new(0, 4.4, 0), Color3.fromRGB(66, 48, 30), Enum.Material.WoodPlanks)
	local glow = newPart(model, "Glow", Vector3.new(7.2, 0.4, 5.2), pos + Vector3.new(0, 4.1, 0), Color3.fromRGB(255, 190, 90), Enum.Material.Neon)
	glow.CanCollide = false

	for _, side in ipairs({ -1, 1 }) do
		local band = newPart(model, "Band", Vector3.new(8.3, 0.5, 6.3), pos + Vector3.new(0, 2 + side * 1.2, 0), Color3.fromRGB(40, 38, 36), Enum.Material.Metal)
		band.CanCollide = false
	end

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 110)
	light.Brightness = 3
	light.Range = 34
	light.Parent = glow

	local beacon = newPart(model, "Beacon", Vector3.new(1.2, 26, 1.2), pos + Vector3.new(0, 15, 0), Color3.fromRGB(255, 200, 120), Enum.Material.Neon)
	beacon.CanCollide = false
	beacon.Transparency = 0.55

	labelOn(lid, "THE FATE CRATE", GameConfig.CrateBaseCost .. " SALVAGE", Color3.fromRGB(255, 205, 120), 4)

	local display = Instance.new("Part")
	display.Name = "Display"
	display.Size = Vector3.new(2, 0.6, 0.6)
	display.Position = pos + Vector3.new(0, 7.5, 0)
	display.Anchored = true
	display.CanCollide = false
	display.Transparency = 1
	display.Parent = model

	local prompt = addPrompt(lid, "Open the Fate Crate [" .. GameConfig.CrateBaseCost .. "]", "FATE CRATE", 0.3, 12)
	prompt.Triggered:Connect(function(player)
		StationService.useCrate(player)
	end)

	crate.model = model
	crate.prompt = prompt
	crate.lid = lid
	crate.display = display
	crate.position = pos
end

local function relocateCrate()
	local from = crate.spotIndex
	local choices = {}
	for index = 1, #S.Map.cratePositions do
		if index ~= from then
			table.insert(choices, index)
		end
	end
	local target = choices[rng:NextInteger(1, #choices)]

	-- a puff where it was, a beam where it went
	local oldPos = crate.position
	destroyCrate()
	local puff = Instance.new("Part")
	puff.Size = Vector3.new(6, 6, 6)
	puff.Position = oldPos + Vector3.new(0, 3, 0)
	puff.Anchored = true
	puff.CanCollide = false
	puff.Transparency = 0.4
	puff.Material = Enum.Material.Neon
	puff.Color = Color3.fromRGB(180, 140, 255)
	puff.Parent = S.Map.fxFolder
	TweenService:Create(puff, TweenInfo.new(0.6), { Size = Vector3.new(18, 18, 18), Transparency = 1 }):Play()
	Debris:AddItem(puff, 1)

	crate.uses = 0
	buildCrate(target)
	Net.get("Announce"):FireAllClients({
		title = "THE FATE CRATE HAS MOVED",
		subtitle = "The Hollow Doll took it elsewhere",
		color = { 200, 150, 255 },
		duration = 3.5,
	})
end

function StationService.useCrate(player)
	if not canInteract(player) then return end
	if crate.busy then
		denied(player, "The crate is already spinning")
		return
	end
	if not S.Economy.spend(player, GameConfig.CrateBaseCost) then
		denied(player, "Need " .. GameConfig.CrateBaseCost .. " salvage")
		return
	end

	crate.busy = true
	crate.uses = crate.uses + 1

	local doll = rng:NextNumber() < GameConfig.CrateRelocateChance or crate.uses >= GameConfig.CrateForcedMoveUses
	local pool = WeaponDefs.cratePool()
	local resultId = Util.weightedPick(pool, rng)
	local resultDef = WeaponDefs.get(resultId)

	-- reel of names for the client-side roulette
	local reel = {}
	for _ = 1, 14 do
		local id = Util.weightedPick(pool, rng)
		local def = WeaponDefs.get(id)
		table.insert(reel, def and def.name or "???")
	end
	table.insert(reel, resultDef and resultDef.name or "???")

	if crate.lid then
		TweenService:Create(crate.lid, TweenInfo.new(0.4, Enum.EasingStyle.Back), {
			CFrame = crate.lid.CFrame * CFrame.new(0, 1.6, -2) * CFrame.Angles(math.rad(-70), 0, 0),
		}):Play()
	end

	Net.get("CrateSpin"):FireAllClients({
		position = crate.position,
		duration = GameConfig.CrateSpinTime,
		reel = reel,
		result = doll and "THE HOLLOW DOLL" or (resultDef and resultDef.name or "???"),
		doll = doll,
		buyer = player,
	})

	task.delay(GameConfig.CrateSpinTime, function()
		if doll then
			crate.busy = false
			relocateCrate()
			denied(player, "The Hollow Doll grins. The crate is gone.")
			return
		end
		if player.Parent and resultId then
			S.Loadout.give(player, resultId, false)
			granted(player, "The crate gave you " .. resultDef.name)
		end
		if crate.lid then
			TweenService:Create(crate.lid, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
				CFrame = CFrame.new(crate.position + Vector3.new(0, 4.4, 0)),
			}):Play()
		end
		crate.busy = false
	end)
end

--------------------------------------------------------------------------------
-- the overforge
--------------------------------------------------------------------------------

local function buildForge()
	local pos = S.Map.forgePosition
	local model = Instance.new("Model")
	model.Name = "Overforge"
	model.Parent = S.Map.stationFolder

	newPart(model, "Base", Vector3.new(12, 2, 10), pos + Vector3.new(0, 1, 0), Color3.fromRGB(48, 44, 42), Enum.Material.DiamondPlate)
	local column = newPart(model, "Column", Vector3.new(9, 12, 7), pos + Vector3.new(0, 8, 0), Color3.fromRGB(62, 54, 50), Enum.Material.CorrodedMetal)
	local maw = newPart(model, "Maw", Vector3.new(6, 5, 1), pos + Vector3.new(0, 7, -3.6), Color3.fromRGB(255, 120, 40), Enum.Material.Neon)
	maw.CanCollide = false

	for _, side in ipairs({ -1, 1 }) do
		local pipe = newPart(model, "Pipe", Vector3.new(1.4, 14, 1.4), pos + Vector3.new(side * 5.4, 9, 2.6), Color3.fromRGB(40, 38, 36), Enum.Material.CorrodedMetal)
		pipe.CanCollide = false
	end

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 130, 50)
	light.Brightness = 4
	light.Range = 42
	light.Parent = maw

	local fire = Instance.new("Fire")
	fire.Size = 10
	fire.Heat = 8
	fire.Color = Color3.fromRGB(255, 140, 50)
	fire.Parent = maw

	labelOn(column, "THE OVERFORGE", GameConfig.ForgeCost .. " SALVAGE  -  UPGRADE HELD WEAPON", Color3.fromRGB(255, 150, 70), 8)

	local prompt = addPrompt(column, "Overforge weapon [" .. GameConfig.ForgeCost .. "]", "OVERFORGE", 0.35, 13)
	prompt.Triggered:Connect(function(player)
		StationService.useForge(player)
	end)

	forge.model = model
	forge.maw = maw
end

function StationService.useForge(player)
	if not canInteract(player) then return end
	if forge.busy then
		denied(player, "The Overforge is already working")
		return
	end
	local held = S.Loadout.active(player)
	if not held then
		denied(player, "Nothing in your hands")
		return
	end
	if held.upgraded then
		denied(player, held.name .. " is already forged")
		return
	end
	if not S.Economy.spend(player, GameConfig.ForgeCost) then
		denied(player, "Need " .. GameConfig.ForgeCost .. " salvage")
		return
	end

	forge.busy = true
	local slotIndex = select(2, S.Loadout.has(player, held.id))
	local weaponId = held.id

	if forge.maw then
		TweenService:Create(forge.maw, TweenInfo.new(GameConfig.ForgeTime * 0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 1, true), {
			Size = Vector3.new(7.5, 6.5, 1),
			Color = Color3.fromRGB(255, 235, 180),
		}):Play()
	end

	Net.get("Notify"):FireClient(player, { text = "Forging " .. held.name .. "...", color = { 255, 170, 90 } })

	task.delay(GameConfig.ForgeTime, function()
		forge.busy = false
		if not player.Parent then return end
		local ok, newName = S.Loadout.upgradeSlot(player, slotIndex, weaponId)
		if ok then
			granted(player, "FORGED: " .. newName)
			Net.get("Announce"):FireAllClients({
				title = "OVERFORGED",
				subtitle = player.DisplayName .. " now carries the " .. newName,
				color = { 255, 160, 70 },
				duration = 3,
			})
		else
			-- the weapon left the slot mid-forge: refund rather than eat the salvage
			S.Economy.add(player, GameConfig.ForgeCost, true)
			denied(player, "Forge failed, salvage refunded")
		end
	end)
end

--------------------------------------------------------------------------------
-- tonic stills
--------------------------------------------------------------------------------

local function buildTonic(spec)
	local def = TonicDefs.get(spec.tonic)
	if not def then return end
	local pos = spec.pos

	local model = Instance.new("Model")
	model.Name = "TonicStill_" .. def.id
	model.Parent = S.Map.stationFolder

	newPart(model, "Base", Vector3.new(6, 1.5, 5), pos + Vector3.new(0, 0.75, 0), Color3.fromRGB(44, 42, 40), Enum.Material.DiamondPlate)
	local cabinet = newPart(model, "Cabinet", Vector3.new(5, 8, 4), pos + Vector3.new(0, 5.5, 0), Color3.fromRGB(58, 56, 54), Enum.Material.Metal)
	local tank = newPart(model, "Tank", Vector3.new(2.4, 5, 2.4), pos + Vector3.new(0, 6, -2.2), def.color, Enum.Material.Neon)
	tank.CanCollide = false
	tank.Transparency = 0.25

	local light = Instance.new("PointLight")
	light.Color = def.color
	light.Brightness = 2.4
	light.Range = 26
	light.Parent = tank

	labelOn(cabinet, def.name, def.blurb .. "  -  " .. def.cost, def.color, 6)

	local prompt = addPrompt(cabinet, "Drink " .. def.name .. " [" .. def.cost .. "]", "TONIC STILL", 0.3, 11)
	prompt.Triggered:Connect(function(player)
		if not canInteract(player) then return end
		if S.PlayerService.hasTonic(player, def.id) then
			denied(player, "Already coursing through you")
			return
		end
		if not S.Economy.spend(player, def.cost) then
			denied(player, "Need " .. def.cost .. " salvage")
			return
		end
		S.PlayerService.grantTonic(player, def.id)
		granted(player, def.name .. " - " .. def.blurb)
	end)
end

--------------------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------------------

function StationService.resetForNewRun()
	crate.uses = 0
	crate.busy = false
	forge.busy = false
	buildCrate(rng:NextInteger(1, #S.Map.cratePositions))
end

function StationService.init(services)
	S = services

	for _, spec in ipairs(S.Map.wallBuys) do
		buildWallBuy(spec)
	end
	for _, spec in ipairs(S.Map.tonicSpots) do
		buildTonic(spec)
	end
	buildForge()
	buildCrate(rng:NextInteger(1, #S.Map.cratePositions))
end

return StationService
