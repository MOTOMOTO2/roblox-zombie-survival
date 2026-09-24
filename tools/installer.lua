-- Necrotide Installer (only used by the .rbxmx drag-in build).
--
-- The model you dragged into Studio keeps every script in a disabled `Payload`
-- folder. Requiring this module moves each part of the payload into the service
-- it belongs to, enables it, and deletes the model.
--
-- It runs two ways:
--   * Studio Command Bar (edit mode, the install is saved with your place):
--         require(workspace.NecrotideLastStand.Installer)
--   * pressing Play: the sibling `Boot` script requires this automatically, so
--     the game is playable immediately - though, like any runtime change, that
--     install disappears again when you stop.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local Players = game:GetService("Players")

local root = script.Parent
local payload = root and root:FindFirstChild("Payload")
if not payload then
	warn("[Necrotide] Installer could not find its Payload folder. Nothing was installed.")
	return false
end

local function enableScripts(container)
	if container:IsA("BaseScript") then
		container.Disabled = false
	end
	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("BaseScript") then
			descendant.Disabled = false
		end
	end
end

local function moveChildren(from, to)
	if not from then return end
	for _, child in ipairs(from:GetChildren()) do
		local existing = to:FindFirstChild(child.Name)
		if existing then
			existing:Destroy()
		end
		child.Parent = to
	end
end

local sharedPayload = payload:FindFirstChild("ReplicatedStorage")
local clientPayload = payload:FindFirstChild("StarterPlayerScripts")
local serverPayload = payload:FindFirstChild("ServerScriptService")

-- 1. shared modules first: everything else requires them
if sharedPayload then
	enableScripts(sharedPayload)
	moveChildren(sharedPayload, ReplicatedStorage)
end

-- 2. client scripts, so anyone joining from here on gets them automatically
local starterPlayerScripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
if clientPayload and starterPlayerScripts then
	enableScripts(clientPayload)
	-- StarterPlayerScripts only applies to future joins, so anyone already in the
	-- server needs a live copy parented somewhere LocalScripts run
	for _, player in ipairs(Players:GetPlayers()) do
		local playerGui = player:FindFirstChild("PlayerGui")
		if playerGui and not playerGui:FindFirstChild("NecrotideClient") then
			local live = clientPayload:Clone()
			live.Name = "NecrotideClient"
			enableScripts(live)
			live.Parent = playerGui
		end
	end
	moveChildren(clientPayload, starterPlayerScripts)
end

-- 3. server last: Bootstrap starts the game the moment it is enabled
if serverPayload then
	moveChildren(serverPayload, ServerScriptService)
	for _, name in ipairs({ "Services", "Bootstrap" }) do
		local installed = ServerScriptService:FindFirstChild(name)
		if installed then
			enableScripts(installed)
		end
	end
end

print("[Necrotide] Installed into ReplicatedStorage, ServerScriptService and StarterPlayerScripts.")
if root then
	root:Destroy()
end

return true
