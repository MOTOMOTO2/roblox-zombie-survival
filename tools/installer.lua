-- Necrotide Installer (only used by the .rbxmx drag-in build).
--
-- The model you dragged into Studio contains every script in a disabled Payload
-- folder. This Script moves each part of the payload into the service it belongs
-- to, enables it, and then deletes itself.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local Players = game:GetService("Players")

local root = script.Parent
local payload = root and root:FindFirstChild("Payload")
if not payload then
	warn("[Necrotide] Installer could not find its Payload folder. Nothing was installed.")
	return
end

local function enableScripts(container)
	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("BaseScript") then
			descendant.Disabled = false
		end
	end
	if container:IsA("BaseScript") then
		container.Disabled = false
	end
end

local function moveChildren(from, to, replaceExisting)
	if not from then return end
	for _, child in ipairs(from:GetChildren()) do
		if replaceExisting then
			local existing = to:FindFirstChild(child.Name)
			if existing then
				existing:Destroy()
			end
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
	moveChildren(sharedPayload, ReplicatedStorage, true)
end

-- 2. client scripts, so players joining from here on get them automatically
local starterPlayerScripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
if clientPayload and starterPlayerScripts then
	enableScripts(clientPayload)
	-- anyone already in the server needs a live copy; StarterPlayerScripts only
	-- applies to future joins
	for _, player in ipairs(Players:GetPlayers()) do
		local playerGui = player:FindFirstChild("PlayerGui")
		if playerGui then
			local live = clientPayload:Clone()
			live.Name = "NecrotideClient"
			enableScripts(live)
			live.Parent = playerGui
		end
	end
	moveChildren(clientPayload, starterPlayerScripts, true)
end

-- 3. server last: the Bootstrap script starts the game the moment it is enabled
if serverPayload then
	moveChildren(serverPayload, ServerScriptService, true)
	for _, child in ipairs(ServerScriptService:GetChildren()) do
		if child.Name == "Bootstrap" or child.Name == "Services" then
			enableScripts(child)
		end
	end
end

print("[Necrotide] Installed. Press Play to hold the Ashvault.")
root:Destroy()
