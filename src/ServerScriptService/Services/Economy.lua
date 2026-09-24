-- Economy: salvage (the currency), kill counters and leaderstats.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("NecrotideShared")
local GameConfig = require(Shared.GameConfig)
local Net = require(Shared.Net)

local Economy = {}
local S

local state = {}
local globalSalvageMult = 1

local function ensure(player)
	local entry = state[player]
	if not entry then
		entry = { salvage = GameConfig.StartingSalvage, kills = 0, spent = 0 }
		state[player] = entry
	end
	return entry
end

local function push(player)
	local entry = ensure(player)
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		local salvage = stats:FindFirstChild("Salvage")
		local kills = stats:FindFirstChild("Kills")
		if salvage then salvage.Value = entry.salvage end
		if kills then kills.Value = entry.kills end
	end
	Net.get("EconomyChanged"):FireClient(player, {
		salvage = entry.salvage,
		kills = entry.kills,
	})
end

function Economy.init(services)
	S = services

	local function setup(player)
		ensure(player)
		local stats = player:FindFirstChild("leaderstats")
		if not stats then
			stats = Instance.new("Folder")
			stats.Name = "leaderstats"
			stats.Parent = player
		end
		if not stats:FindFirstChild("Salvage") then
			local v = Instance.new("IntValue")
			v.Name = "Salvage"
			v.Value = state[player].salvage
			v.Parent = stats
		end
		if not stats:FindFirstChild("Kills") then
			local v = Instance.new("IntValue")
			v.Name = "Kills"
			v.Value = 0
			v.Parent = stats
		end
		push(player)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		setup(player)
	end
	Players.PlayerAdded:Connect(setup)
	Players.PlayerRemoving:Connect(function(player)
		state[player] = nil
	end)
end

function Economy.get(player)
	return ensure(player).salvage
end

function Economy.setGlobalMultiplier(mult)
	globalSalvageMult = mult
end

-- `raw = true` skips tonic/powerup multipliers (used for refunds and bonuses).
function Economy.add(player, amount, raw)
	if not player or not player.Parent then return 0 end
	local entry = ensure(player)
	local final = amount
	if not raw then
		local mult = globalSalvageMult
		if S and S.PlayerService then
			mult = mult * S.PlayerService.tonicAgg(player).salvageMult
		end
		final = math.floor(amount * mult)
	end
	entry.salvage = math.max(0, entry.salvage + final)
	push(player)
	return final
end

function Economy.canAfford(player, cost)
	return ensure(player).salvage >= cost
end

function Economy.spend(player, cost)
	local entry = ensure(player)
	if entry.salvage < cost then
		return false
	end
	entry.salvage = entry.salvage - cost
	entry.spent = entry.spent + cost
	push(player)
	return true
end

function Economy.addKill(player)
	local entry = ensure(player)
	entry.kills = entry.kills + 1
	push(player)
end

function Economy.resetAll()
	for player, entry in pairs(state) do
		entry.salvage = GameConfig.StartingSalvage
		entry.kills = 0
		entry.spent = 0
		push(player)
	end
	globalSalvageMult = 1
end

function Economy.snapshot(player)
	local entry = ensure(player)
	return { salvage = entry.salvage, kills = entry.kills }
end

return Economy
