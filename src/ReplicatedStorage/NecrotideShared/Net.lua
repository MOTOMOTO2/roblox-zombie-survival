-- Net: creates (server) or waits for (client) the remotes used by the game.
-- Every remote name is declared here so the client -> server surface is auditable
-- in one place.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.Events = {
	-- client -> server
	"FireRequest",
	"ReloadRequest",
	"SwapRequest",
	-- server -> client
	"LoadoutChanged",
	"EconomyChanged",
	"WaveChanged",
	"Announce",
	"Notify",
	"Hitmarker",
	"ShotFx",
	"CrateSpin",
	"BossState",
	"DownedState",
	"RunEnded",
	"PowerupFx",
	"TonicsChanged",
}

Net.Functions = {
	"RequestSnapshot",
}

local FOLDER_NAME = "NecrotideRemotes"

local function folder()
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not existing then
			existing = Instance.new("Folder")
			existing.Name = FOLDER_NAME
			existing.Parent = ReplicatedStorage
		end
		return existing
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME, 60)
end

-- Server only: build every declared remote up front.
function Net.init()
	local root = folder()
	for _, name in ipairs(Net.Events) do
		if not root:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = root
		end
	end
	for _, name in ipairs(Net.Functions) do
		if not root:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = root
		end
	end
	return root
end

local cache = {}

function Net.get(name)
	local cached = cache[name]
	if cached and cached.Parent then
		return cached
	end
	local root = folder()
	if not root then
		error("Necrotide: remote folder never replicated")
	end
	local found
	if RunService:IsServer() then
		found = root:FindFirstChild(name)
		if not found then
			error("Necrotide: unknown remote " .. tostring(name))
		end
	else
		found = root:WaitForChild(name, 60)
	end
	cache[name] = found
	return found
end

return Net
