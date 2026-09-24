-- ClientMain: input, aiming, and the bridge between the server's remotes and the
-- HUD. The client is deliberately powerless: it asks to shoot, reload and swap,
-- and it renders whatever the server tells it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local Shared = ReplicatedStorage:WaitForChild("NecrotideShared")
local Net = require(Shared.Net)

local Modules = script.Parent:WaitForChild("Modules")
local Hud = require(Modules:WaitForChild("Hud"))
local Effects = require(Modules:WaitForChild("Effects"))

local SPRINT_MULT = 1.35
local AIM_RANGE = 900

local firing = false
local lastFire = 0
local sprinting = false
local baseWalkSpeed = 16
local mouseLocked = true
local loadout = nil
local downed = false
local movementSpread = 0

if not Hud.build() then
	-- another copy of the client is already running for this player
	return
end

pcall(function()
	StarterGui:SetCore("TopbarEnabled", true)
end)

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

local function character()
	return player.Character
end

local function humanoid()
	local c = character()
	return c and c:FindFirstChildOfClass("Humanoid")
end

local function head()
	local c = character()
	return c and (c:FindFirstChild("Head") or c.PrimaryPart)
end

local function activeWeapon()
	if not loadout or not loadout.slots then return nil end
	return loadout.slots[loadout.active]
end

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude
aimParams.IgnoreWater = true

local function refreshAimFilter()
	local filter = {}
	local c = character()
	if c then table.insert(filter, c) end
	local fx = camera:FindFirstChild("NecrotideClientFx")
	if fx then table.insert(filter, fx) end
	aimParams.FilterDescendantsInstances = filter
end

-- Where the centre of the screen is pointing, in world space.
local function aimPoint()
	local viewport = camera.ViewportSize
	local ray = camera:ViewportPointToRay(viewport.X * 0.5, viewport.Y * 0.5)
	local result = workspace:Raycast(ray.Origin, ray.Direction * AIM_RANGE, aimParams)
	if result then
		return result.Position
	end
	return ray.Origin + ray.Direction * AIM_RANGE
end

local function tryFire()
	local weapon = activeWeapon()
	if not weapon or downed then return end
	local h = head()
	if not h then return end
	local hum = humanoid()
	if not hum or hum.Health <= 0 then return end

	local interval = 60 / math.max(1, weapon.rpm)
	local now = os.clock()
	if now - lastFire < interval then return end
	lastFire = now

	local direction = (aimPoint() - h.Position)
	if direction.Magnitude < 0.01 then return end
	Net.get("FireRequest"):FireServer(direction.Unit, h.Position)

	Effects.addKick(weapon.class == "Shotgun" and 1.5 or 0.55)
	movementSpread = math.min(1, movementSpread + 0.22)
end

--------------------------------------------------------------------------------
-- remote wiring
--------------------------------------------------------------------------------

Net.get("EconomyChanged").OnClientEvent:Connect(Hud.setEconomy)
Net.get("WaveChanged").OnClientEvent:Connect(function(data)
	Hud.setWave(data)
	if data and data.phase ~= "ended" then
		Hud.hideEndPanel()
	end
end)
Net.get("Announce").OnClientEvent:Connect(Hud.announce)
Net.get("Notify").OnClientEvent:Connect(Hud.toast)
Net.get("BossState").OnClientEvent:Connect(Hud.setBoss)
Net.get("TonicsChanged").OnClientEvent:Connect(function(list)
	Hud.setTonics(list)
	Effects.play("pickup", 0.5, 1)
end)
Net.get("LoadoutChanged").OnClientEvent:Connect(function(data)
	loadout = data
	Hud.setLoadout(data)
end)
Net.get("Hitmarker").OnClientEvent:Connect(function(data)
	Hud.flashHitmarker(data)
	if data and data.hit then
		Effects.play("click", data.headshot and 0.5 or 0.3, data.headshot and 1.5 or 1.2)
	end
end)
Net.get("ShotFx").OnClientEvent:Connect(Effects.shot)
Net.get("CrateSpin").OnClientEvent:Connect(function(data)
	Hud.crateSpin(data)
	Effects.play("pickup", 0.4, 0.8)
end)
Net.get("PowerupFx").OnClientEvent:Connect(function(data)
	Hud.powerup(data)
	Effects.play("pickup", 0.7, 1.1)
end)
Net.get("DownedState").OnClientEvent:Connect(function(data)
	downed = data and (data.downed or data.out) or false
	Hud.setDowned(data)
	if downed then
		firing = false
		Effects.play("alarm", 0.45, 0.8)
	end
end)
Net.get("RunEnded").OnClientEvent:Connect(function(data)
	Hud.runEnded(data)
	Effects.play("alarm", 0.6, data and data.victory and 1.3 or 0.7)
end)

--------------------------------------------------------------------------------
-- input
--------------------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = true
		tryFire()
	elseif input.UserInputType == Enum.UserInputType.Touch then
		firing = true
		tryFire()
	elseif input.KeyCode == Enum.KeyCode.R then
		Net.get("ReloadRequest"):FireServer()
	elseif input.KeyCode == Enum.KeyCode.One then
		Net.get("SwapRequest"):FireServer(1)
	elseif input.KeyCode == Enum.KeyCode.Two then
		Net.get("SwapRequest"):FireServer(2)
	elseif input.KeyCode == Enum.KeyCode.Q then
		local other = (loadout and loadout.active == 1) and 2 or 1
		Net.get("SwapRequest"):FireServer(other)
	elseif input.KeyCode == Enum.KeyCode.H then
		Hud.toggleHelp()
	elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		sprinting = true
	elseif input.KeyCode == Enum.KeyCode.LeftAlt then
		mouseLocked = not mouseLocked
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		firing = false
	elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		sprinting = false
	end
end)

UserInputService.InputChanged:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType == Enum.UserInputType.MouseWheel and loadout then
		local other = (loadout.active == 1) and 2 or 1
		Net.get("SwapRequest"):FireServer(other)
	end
end)

--------------------------------------------------------------------------------
-- per-frame
--------------------------------------------------------------------------------

player.CharacterAdded:Connect(function(newCharacter)
	local hum = newCharacter:WaitForChild("Humanoid", 10)
	if hum then
		baseWalkSpeed = hum.WalkSpeed
		hum.AutoRotate = false
	end
	task.defer(refreshAimFilter)
end)

if character() then
	local hum = humanoid()
	if hum then
		baseWalkSpeed = hum.WalkSpeed
		hum.AutoRotate = false
	end
	refreshAimFilter()
end

local filterRefresh = 0

RunService.RenderStepped:Connect(function(dt)
	filterRefresh = filterRefresh + dt
	if filterRefresh > 1.5 then
		filterRefresh = 0
		refreshAimFilter()
	end

	local hum = humanoid()
	local weapon = activeWeapon()

	-- sprint (PvE only, so letting the client own its own legs is harmless)
	if hum and hum.Health > 0 and not downed then
		local wanted = sprinting and baseWalkSpeed * SPRINT_MULT or baseWalkSpeed
		if math.abs(hum.WalkSpeed - wanted) > 0.1 and hum.WalkSpeed > 0 then
			hum.WalkSpeed = wanted
		end
	end

	-- mouse lock and shooter-style body facing
	local shouldLock = mouseLocked and not downed and hum ~= nil and hum.Health > 0
	if shouldLock then
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
		UserInputService.MouseIconEnabled = false
	else
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		UserInputService.MouseIconEnabled = true
	end

	-- firing
	if firing and weapon then
		if weapon.auto then
			tryFire()
		end
	end

	-- crosshair bloom from weapon spread plus movement
	local moveFactor = 0
	if hum then
		moveFactor = math.min(1, hum.MoveDirection.Magnitude * (sprinting and 0.5 or 0.3))
	end
	movementSpread = math.max(0, movementSpread - dt * 1.6)
	local weaponSpread = weapon and math.min(1, weapon.spread / 8) or 0.2
	Hud.step(dt, hum, math.min(1.4, weaponSpread + moveFactor * 0.4 + movementSpread))
end)

RunService:BindToRenderStep("NecrotideCamera", Enum.RenderPriority.Camera.Value + 10, function(dt)
	Effects.stepCamera(dt)

	-- keep the body facing where the camera looks so the gun points forward
	local c = character()
	local hum = humanoid()
	local root = c and c:FindFirstChild("HumanoidRootPart")
	if not hum then return end

	local shouldSteer = root ~= nil and hum.Health > 0 and not downed and mouseLocked
	if hum.AutoRotate == shouldSteer then
		-- we steer the body by hand while locked, and hand it back when unlocked
		hum.AutoRotate = not shouldSteer
	end
	if shouldSteer then
		local look = camera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.01 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
		end
	end
end)

--------------------------------------------------------------------------------
-- initial state
--------------------------------------------------------------------------------

task.spawn(function()
	local ok, snapshot = pcall(function()
		return Net.get("RequestSnapshot"):InvokeServer()
	end)
	if not ok or not snapshot then return end
	Hud.setEconomy(snapshot.economy)
	Hud.setWave(snapshot.wave)
	Hud.setLoadout(snapshot.loadout)
	loadout = snapshot.loadout
	Hud.setBoss(snapshot.boss)
	if snapshot.player then
		Hud.setTonics(snapshot.player.tonics)
		Hud.setDowned(snapshot.player)
	end
	if snapshot.config then
		Hud.announce({
			title = snapshot.config.gameName,
			subtitle = snapshot.config.tagline,
			color = { 255, 206, 122 },
			duration = 4,
			big = true,
		})
	end
end)
