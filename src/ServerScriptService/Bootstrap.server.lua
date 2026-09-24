-- Bootstrap: the only Script in the place. It builds the arena, wires every
-- service together through one shared registry table and starts the round loop.
--
-- Services get `init(registry)` called in dependency order and talk to each other
-- through `S.OtherService`, which keeps requires acyclic.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("NecrotideShared")
local GameConfig = require(Shared.GameConfig)
local Net = require(Shared.Net)

local ServicesFolder = script.Parent:WaitForChild("Services")

Net.init()

Players.RespawnTime = 4
Players.CharacterAutoLoads = true

local S = {}

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

-- map first: every service reads S.Map
local MapBuilder = require(ServicesFolder:WaitForChild("MapBuilder"))
S.MapBuilder = MapBuilder
S.Map = MapBuilder.build()

for _, name in ipairs(ORDER) do
	S[name] = require(ServicesFolder:WaitForChild(name))
end

for _, name in ipairs(ORDER) do
	local service = S[name]
	if type(service.init) == "function" then
		local ok, err = pcall(service.init, S)
		if not ok then
			warn("[Necrotide] " .. name .. " failed to init: " .. tostring(err))
		end
	end
end

-- One round trip that gives a joining or respawning client its whole world state.
Net.get("RequestSnapshot").OnServerInvoke = function(player)
	local boss = S.EnemyService.boss()
	return {
		config = {
			gameName = GameConfig.GameName,
			tagline = GameConfig.Tagline,
			finalWave = GameConfig.FinalBossWave,
			crateCost = GameConfig.CrateBaseCost,
			forgeCost = GameConfig.ForgeCost,
			reviveTime = GameConfig.ReviveTime,
		},
		wave = S.WaveService.snapshot(),
		economy = S.Economy.snapshot(player),
		loadout = S.Loadout.snapshot(player),
		player = S.PlayerService.snapshot(player),
		boss = boss and {
			active = true,
			name = boss.def.name,
			title = boss.def.title,
			health = boss.health,
			maxHealth = boss.maxHealth,
			final = boss.def.isFinal == true,
		} or { active = false },
	}
end

S.WaveService.start()

print(string.format("[%s] Ashvault online. Final boss at wave %d.", GameConfig.GameName, GameConfig.FinalBossWave))
