-- Effects: purely cosmetic client-side feedback - tracers, muzzle flash, chain
-- arcs, camera kick and the small sound kit. Uses only sounds that ship with the
-- Roblox client, so the place file has no external asset dependencies.

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local Effects = {}

local FX_FOLDER_NAME = "NecrotideClientFx"

local SOUNDS = {
	shot = "rbxasset://sounds/collide.mp3",
	click = "rbxasset://sounds/switch3.wav",
	impact = "rbxasset://sounds/bass.mp3",
	pickup = "rbxasset://sounds/electronicpingshort.wav",
	alarm = "rbxasset://sounds/action_falling.mp3",
}

local function fxFolder()
	local existing = camera:FindFirstChild(FX_FOLDER_NAME)
	if not existing then
		existing = Instance.new("Folder")
		existing.Name = FX_FOLDER_NAME
		existing.Parent = camera
	end
	return existing
end

function Effects.play(kind, volume, pitch)
	local asset = SOUNDS[kind]
	if not asset then return end
	local sound = Instance.new("Sound")
	sound.SoundId = asset
	sound.Volume = volume or 0.4
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 3)
end

local function muzzleOf(character)
	local gun = character and character:FindFirstChild("NecrotideGun")
	if not gun then return nil end
	local muzzle = gun:FindFirstChild("Muzzle")
	return muzzle and muzzle.Position or (gun.PrimaryPart and gun.PrimaryPart.Position)
end

local function drawBeam(from, to, color, thickness, life)
	local delta = to - from
	local distance = delta.Magnitude
	if distance < 0.5 then return end

	local beam = Instance.new("Part")
	beam.Name = "Tracer"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.Material = Enum.Material.Neon
	beam.Color = color
	beam.Size = Vector3.new(thickness, thickness, distance)
	beam.CFrame = CFrame.lookAt(from + delta * 0.5, to)
	beam.Transparency = 0.15
	beam.Parent = fxFolder()

	TweenService:Create(beam, TweenInfo.new(life or 0.09), {
		Transparency = 1,
		Size = Vector3.new(thickness * 0.2, thickness * 0.2, distance),
	}):Play()
	Debris:AddItem(beam, (life or 0.09) + 0.15)
end

local function impactPuff(position, color)
	local puff = Instance.new("Part")
	puff.Shape = Enum.PartType.Ball
	puff.Size = Vector3.new(0.6, 0.6, 0.6)
	puff.Position = position
	puff.Anchored = true
	puff.CanCollide = false
	puff.CanQuery = false
	puff.Material = Enum.Material.Neon
	puff.Color = color
	puff.Transparency = 0.2
	puff.Parent = fxFolder()
	TweenService:Create(puff, TweenInfo.new(0.22), { Size = Vector3.new(2.4, 2.4, 2.4), Transparency = 1 }):Play()
	Debris:AddItem(puff, 0.5)
end

function Effects.shot(data)
	if not data then return end
	local shooter = data.shooter
	local character = shooter and shooter.Character
	local origin = muzzleOf(character)
	if not origin then
		local root = character and character:FindFirstChild("HumanoidRootPart")
		origin = root and root.Position
	end
	if not origin then return end

	local color = data.color and Color3.fromRGB(data.color[1], data.color[2], data.color[3])
		or Color3.fromRGB(255, 222, 160)

	for _, point in ipairs(data.points or {}) do
		drawBeam(origin, point, color, data.upgraded and 0.28 or 0.18, 0.09)
		impactPuff(point, color)
	end

	if data.chain then
		local previous = (data.points and data.points[1]) or origin
		for _, linkPos in ipairs(data.chain) do
			drawBeam(previous, linkPos, color, 0.22, 0.18)
			previous = linkPos
		end
	end

	-- muzzle flash
	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(1.1, 1.1, 1.1)
	flash.Position = origin
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.Material = Enum.Material.Neon
	flash.Color = color
	flash.Parent = fxFolder()
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 6
	light.Range = 16
	light.Parent = flash
	TweenService:Create(flash, TweenInfo.new(0.08), { Size = Vector3.new(0.1, 0.1, 0.1), Transparency = 1 }):Play()
	Debris:AddItem(flash, 0.2)

	if shooter == player then
		Effects.play("shot", 0.35, 0.9 + math.random() * 0.25)
	elseif character then
		local root = character:FindFirstChild("HumanoidRootPart")
		local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and myRoot and (root.Position - myRoot.Position).Magnitude < 160 then
			Effects.play("shot", 0.14, 0.9 + math.random() * 0.25)
		end
	end
end

local kick = Vector2.new()

function Effects.addKick(amount)
	kick = kick + Vector2.new((math.random() - 0.5) * amount * 0.6, amount)
end

-- Applied by ClientMain every frame; decays back to zero.
function Effects.stepCamera(dt)
	if kick.Magnitude < 0.0001 then return end
	local applied = kick * math.min(1, dt * 12)
	camera.CFrame = camera.CFrame * CFrame.Angles(math.rad(applied.Y), math.rad(applied.X), 0)
	kick = kick * math.max(0, 1 - dt * 9)
end

return Effects
