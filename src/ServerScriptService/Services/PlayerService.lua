-- PlayerService: player vitality, tonics, the downed/revive loop and squad-wipe
-- detection. All damage dealt to players funnels through PlayerService.damage so
-- nobody ever dies outright while a teammate could still pick them up.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("NecrotideShared")
local GameConfig = require(Shared.GameConfig)
local TonicDefs = require(Shared.TonicDefs)
local Net = require(Shared.Net)

local PlayerService = {}
local S

local state = {}
local heartbeatConn

local function ensure(player)
	local entry = state[player]
	if not entry then
		entry = {
			tonics = {},
			downed = false,
			out = false,
			bleedEnd = 0,
			lastDamage = 0,
			selfReviveUsed = false,
			revives = 0,
			downs = 0,
			prompt = nil,
		}
		state[player] = entry
	end
	return entry
end

function PlayerService.tonicAgg(player)
	local entry = ensure(player)
	if not entry.agg then
		entry.agg = TonicDefs.aggregate(entry.tonics)
	end
	return entry.agg
end

local function applyBody(player)
	local entry = ensure(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local agg = PlayerService.tonicAgg(player)
	local maxHealth = GameConfig.BaseMaxHealth + agg.bonusHealth
	local ratio = humanoid.MaxHealth > 0 and (humanoid.Health / humanoid.MaxHealth) or 1
	humanoid.MaxHealth = maxHealth
	if entry.downed then
		humanoid.Health = math.max(1, math.floor(maxHealth * 0.08))
	else
		humanoid.Health = math.clamp(maxHealth * ratio, 1, maxHealth)
	end
	if not entry.downed then
		humanoid.WalkSpeed = 16 * agg.speedMult
		humanoid.UseJumpPower = true
		humanoid.JumpPower = 50
	end
end

function PlayerService.pushTonics(player)
	local entry = ensure(player)
	local list = {}
	for id, has in pairs(entry.tonics) do
		if has then
			table.insert(list, id)
		end
	end
	Net.get("TonicsChanged"):FireClient(player, list)
end

function PlayerService.hasTonic(player, id)
	return ensure(player).tonics[id] == true
end

function PlayerService.grantTonic(player, id)
	local def = TonicDefs.get(id)
	if not def then return false end
	local entry = ensure(player)
	if entry.tonics[id] then return false end
	entry.tonics[id] = true
	entry.agg = nil
	applyBody(player)
	PlayerService.pushTonics(player)
	return true
end

function PlayerService.clearTonics(player)
	local entry = ensure(player)
	entry.tonics = {}
	entry.agg = nil
	PlayerService.pushTonics(player)
end

function PlayerService.isDowned(player)
	return ensure(player).downed
end

function PlayerService.isOut(player)
	return ensure(player).out
end

local function pushDowned(player)
	local entry = ensure(player)
	Net.get("DownedState"):FireClient(player, {
		downed = entry.downed,
		out = entry.out,
		-- seconds left, so the client never has to reason about server clocks
		bleedRemaining = math.max(0, entry.bleedEnd - os.clock()),
		bleedTotal = GameConfig.BleedOutTime,
		canSelfRevive = PlayerService.tonicAgg(player).selfRevive and not entry.selfReviveUsed,
	})
end

local function removePrompt(player)
	local entry = ensure(player)
	if entry.prompt then
		entry.prompt:Destroy()
		entry.prompt = nil
	end
end

-- True when nobody is left standing.
local function squadWiped()
	local anyUp = false
	for _, player in ipairs(Players:GetPlayers()) do
		local entry = ensure(player)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not entry.out and not entry.downed and humanoid and humanoid.Health > 0 then
			anyUp = true
		end
	end
	return not anyUp
end

local function checkWipe()
	if #Players:GetPlayers() == 0 then return end
	if squadWiped() and S.WaveService then
		S.WaveService.endRun(false)
	end
end

function PlayerService.reviveTo(player, healthFraction)
	local entry = ensure(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	entry.downed = false
	entry.bleedEnd = 0
	player:SetAttribute("Downed", false)
	removePrompt(player)
	if humanoid then
		applyBody(player)
		humanoid.Health = humanoid.MaxHealth * (healthFraction or 1)
		local agg = PlayerService.tonicAgg(player)
		humanoid.WalkSpeed = 16 * agg.speedMult
		humanoid.UseJumpPower = true
		humanoid.JumpPower = 50
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end
	if S.Loadout then
		S.Loadout.setSuppressed(player, false)
	end
	pushDowned(player)
end

local function setOut(player)
	local entry = ensure(player)
	entry.downed = false
	entry.out = true
	entry.bleedEnd = 0
	player:SetAttribute("Downed", true)
	removePrompt(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = 0
	end
	pushDowned(player)
	Net.get("Announce"):FireAllClients({
		title = player.DisplayName .. " BLED OUT",
		subtitle = "Back on the next wave",
		color = { 255, 90, 90 },
		duration = 3,
	})
	checkWipe()
end

local function buildRevivePrompt(player)
	local entry = ensure(player)
	local character = player.Character
	local root = character and (character.PrimaryPart or character:FindFirstChild("HumanoidRootPart"))
	if not root then return end
	removePrompt(player)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RevivePrompt"
	prompt.ActionText = "Revive " .. player.DisplayName
	prompt.ObjectText = "DOWNED"
	prompt.HoldDuration = GameConfig.ReviveTime
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.Parent = root
	entry.prompt = prompt

	prompt.Triggered:Connect(function(triggerer)
		if not entry.downed then return end
		if triggerer == player then
			-- only legal with the Second Wind Phial, once per wave
			local agg = PlayerService.tonicAgg(player)
			if not agg.selfRevive or entry.selfReviveUsed then
				return
			end
			entry.selfReviveUsed = true
			PlayerService.reviveTo(player, 0.6)
			Net.get("Notify"):FireClient(player, { text = "Second Wind spent", color = { 255, 255, 255 } })
			return
		end
		local helperEntry = ensure(triggerer)
		if helperEntry.downed or helperEntry.out then return end
		PlayerService.reviveTo(player, 1)
		helperEntry.revives = helperEntry.revives + 1
		S.Economy.add(triggerer, GameConfig.SalvagePerRevive, true)
		Net.get("Notify"):FireClient(triggerer, {
			text = "Revived " .. player.DisplayName .. "  +" .. GameConfig.SalvagePerRevive,
			color = { 150, 255, 150 },
		})
		Net.get("Notify"):FireClient(player, {
			text = "Picked up by " .. triggerer.DisplayName,
			color = { 150, 255, 150 },
		})
	end)
end

local function enterDowned(player)
	local entry = ensure(player)
	if entry.downed or entry.out then return end
	entry.downed = true
	entry.downs = entry.downs + 1
	entry.bleedEnd = os.clock() + GameConfig.BleedOutTime
	player:SetAttribute("Downed", true)

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = math.max(1, math.floor(humanoid.MaxHealth * 0.08))
		humanoid.WalkSpeed = 0
		humanoid.UseJumpPower = true
		humanoid.JumpPower = 0
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		humanoid.Sit = false
	end

	if S.Loadout then
		S.Loadout.setSuppressed(player, true)
	end

	buildRevivePrompt(player)
	pushDowned(player)
	Net.get("Announce"):FireAllClients({
		title = player.DisplayName .. " IS DOWN",
		subtitle = "Hold F nearby to pick them up",
		color = { 255, 160, 60 },
		duration = 2.5,
	})
	checkWipe()
end

-- Central damage entry point for anything that hurts a player.
function PlayerService.damage(player, amount, sourceName)
	local entry = ensure(player)
	if entry.out then return end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	entry.lastDamage = os.clock()

	if entry.downed then
		-- already down: chip the bleed-out timer instead of killing outright
		entry.bleedEnd = entry.bleedEnd - amount * 0.05
		pushDowned(player)
		return
	end

	local newHealth = humanoid.Health - amount
	if newHealth <= 0 then
		enterDowned(player)
	else
		humanoid.Health = newHealth
	end
	Net.get("Hitmarker"):FireClient(player, { taken = true, amount = amount, source = sourceName })
end

function PlayerService.healAll()
	for _, player in ipairs(Players:GetPlayers()) do
		local entry = ensure(player)
		if entry.downed then
			PlayerService.reviveTo(player, 1)
		elseif not entry.out then
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				humanoid.Health = humanoid.MaxHealth
			end
		end
	end
end

-- Called by WaveService when a new wave begins: everyone who bled out comes back.
function PlayerService.onWaveStart()
	for _, player in ipairs(Players:GetPlayers()) do
		local entry = ensure(player)
		entry.selfReviveUsed = false
		if entry.out then
			entry.out = false
			entry.downed = false
			player:SetAttribute("Downed", false)
			player:LoadCharacter()
			pushDowned(player)
		end
	end
end

function PlayerService.resetForNewRun()
	for _, player in ipairs(Players:GetPlayers()) do
		local entry = ensure(player)
		entry.tonics = {}
		entry.agg = nil
		entry.downed = false
		entry.out = false
		entry.selfReviveUsed = false
		entry.bleedEnd = 0
		player:SetAttribute("Downed", false)
		removePrompt(player)
		PlayerService.pushTonics(player)
		pushDowned(player)
		player:LoadCharacter()
	end
end

function PlayerService.snapshot(player)
	local entry = ensure(player)
	local list = {}
	for id, has in pairs(entry.tonics) do
		if has then table.insert(list, id) end
	end
	return {
		tonics = list,
		downed = entry.downed,
		out = entry.out,
		bleedRemaining = math.max(0, entry.bleedEnd - os.clock()),
		bleedTotal = GameConfig.BleedOutTime,
	}
end

function PlayerService.init(services)
	S = services

	local function onCharacter(player, character)
		local entry = ensure(player)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid then return end
		humanoid.BreakJointsOnDeath = false
		entry.downed = false
		entry.bleedEnd = 0
		player:SetAttribute("Downed", entry.out)
		removePrompt(player)
		applyBody(player)

		local map = S.Map
		if map and map.playerSpawn then
			local root = character:WaitForChild("HumanoidRootPart", 5)
			if root then
				local angle = math.random() * math.pi * 2
				root.CFrame = CFrame.new(map.playerSpawn + Vector3.new(math.cos(angle) * 8, 0, math.sin(angle) * 8))
			end
		end

		if S.Loadout then
			S.Loadout.onCharacter(player, character)
		end

		humanoid.Died:Connect(function()
			local e = ensure(player)
			if not e.out then
				e.out = true
				e.downed = false
				player:SetAttribute("Downed", true)
				removePrompt(player)
				pushDowned(player)
				checkWipe()
			end
		end)
	end

	local function onPlayer(player)
		ensure(player)
		PlayerService.pushTonics(player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			onCharacter(player, player.Character)
		else
			-- CharacterAutoLoads is off, so we spawn people in ourselves
			player:LoadCharacter()
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player)
		state[player] = nil
		task.defer(checkWipe)
	end)

	-- regen + bleed-out ticker
	local accumulator = 0
	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		accumulator = accumulator + dt
		if accumulator < 0.25 then return end
		local step = accumulator
		accumulator = 0
		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			local entry = state[player]
			if entry then
				if entry.downed then
					if now >= entry.bleedEnd then
						setOut(player)
					end
				elseif not entry.out then
					local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
					if humanoid and humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth then
						if now - entry.lastDamage >= GameConfig.RegenDelay then
							humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + GameConfig.RegenRate * step)
						end
					end
				end
			end
		end
	end)
end

function PlayerService.shutdown()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
end

return PlayerService
