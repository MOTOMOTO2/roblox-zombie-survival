-- Hud: builds the entire interface in code and exposes small update functions.
-- Nothing here talks to the server directly; ClientMain feeds it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("NecrotideShared")
local TonicDefs = require(Shared.TonicDefs)
local Util = require(Shared.Util)

local player = Players.LocalPlayer

local Hud = {}

local FONT = Enum.Font.GothamBlack
local FONT_BODY = Enum.Font.GothamSemibold
local INK = Color3.fromRGB(240, 238, 245)
local PANEL = Color3.fromRGB(14, 13, 17)
local GOLD = Color3.fromRGB(255, 206, 122)

local ui = {}
local state = {
	crosshairSpread = 0,
	bleedRemaining = 0,
	downed = false,
	waveEndsAt = 0,
	wavePhase = "lobby",
	toasts = {},
}

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 6)
	c.Parent = parent
	return c
end

local function stroke(parent, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.fromRGB(70, 66, 78)
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0.2
	s.Parent = parent
	return s
end

local function frame(props)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = props.color or PANEL
	f.BackgroundTransparency = props.transparency or 0.25
	f.BorderSizePixel = 0
	f.Size = props.size
	f.Position = props.position
	f.AnchorPoint = props.anchor or Vector2.new(0, 0)
	f.Name = props.name or "Frame"
	f.Visible = props.visible ~= false
	f.ZIndex = props.z or 1
	f.Parent = props.parent
	if props.round ~= false then
		corner(f, props.radius or 8)
	end
	return f
end

local function label(props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = props.size or UDim2.fromScale(1, 1)
	l.Position = props.position or UDim2.fromScale(0, 0)
	l.AnchorPoint = props.anchor or Vector2.new(0, 0)
	l.Font = props.font or FONT_BODY
	l.Text = props.text or ""
	l.TextColor3 = props.color or INK
	l.TextTransparency = props.textTransparency or 0
	l.TextScaled = props.scaled ~= false
	l.TextXAlignment = props.align or Enum.TextXAlignment.Center
	l.TextYAlignment = props.valign or Enum.TextYAlignment.Center
	l.Name = props.name or "Label"
	l.ZIndex = props.z or 2
	l.TextStrokeTransparency = props.strokeTransparency or 0.6
	l.Parent = props.parent
	if props.textSize then
		l.TextScaled = false
		l.TextSize = props.textSize
	end
	return l
end

--------------------------------------------------------------------------------
-- construction
--------------------------------------------------------------------------------

function Hud.build()
	local playerGui = player:WaitForChild("PlayerGui")
	if playerGui:FindFirstChild("NecrotideHud") then
		-- a HUD already exists (can happen right after the drag-in installer runs)
		return nil
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "NecrotideHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	ui.gui = gui

	------------------------------------------------------------------ wave badge
	local waveBox = frame({
		parent = gui,
		name = "WaveBox",
		size = UDim2.fromOffset(290, 74),
		position = UDim2.new(0.5, 0, 0, 12),
		anchor = Vector2.new(0.5, 0),
		transparency = 0.25,
	})
	stroke(waveBox, GOLD, 1.5, 0.55)
	ui.waveLabel = label({
		parent = waveBox,
		name = "Wave",
		size = UDim2.new(1, -16, 0.56, 0),
		position = UDim2.new(0, 8, 0, 4),
		font = FONT,
		text = "THE ASHVAULT",
		color = GOLD,
	})
	ui.waveSub = label({
		parent = waveBox,
		name = "WaveSub",
		size = UDim2.new(1, -16, 0.38, 0),
		position = UDim2.new(0, 8, 0.58, 0),
		text = "standby",
		color = Color3.fromRGB(190, 188, 200),
	})

	------------------------------------------------------------------- boss bar
	local bossBox = frame({
		parent = gui,
		name = "BossBox",
		size = UDim2.fromOffset(620, 58),
		position = UDim2.new(0.5, 0, 0, 96),
		anchor = Vector2.new(0.5, 0),
		transparency = 0.2,
		visible = false,
	})
	stroke(bossBox, Color3.fromRGB(255, 80, 80), 1.5, 0.35)
	ui.bossBox = bossBox
	ui.bossName = label({
		parent = bossBox,
		name = "BossName",
		size = UDim2.new(1, -16, 0.44, 0),
		position = UDim2.new(0, 8, 0, 2),
		font = FONT,
		text = "BOSS",
		color = Color3.fromRGB(255, 120, 120),
	})
	local bossTrack = frame({
		parent = bossBox,
		name = "BossTrack",
		size = UDim2.new(1, -20, 0, 14),
		position = UDim2.new(0, 10, 0.56, 0),
		color = Color3.fromRGB(40, 20, 24),
		transparency = 0.1,
		radius = 4,
	})
	ui.bossFill = frame({
		parent = bossTrack,
		name = "BossFill",
		size = UDim2.fromScale(1, 1),
		color = Color3.fromRGB(255, 70, 70),
		transparency = 0,
		radius = 4,
		z = 2,
	})
	ui.bossHp = label({
		parent = bossTrack,
		name = "BossHp",
		size = UDim2.fromScale(1, 1),
		text = "",
		textSize = 12,
		z = 3,
		strokeTransparency = 0.2,
	})

	----------------------------------------------------------------- announcer
	ui.announce = label({
		parent = gui,
		name = "Announce",
		size = UDim2.new(0.8, 0, 0, 74),
		position = UDim2.new(0.5, 0, 0.2, 0),
		anchor = Vector2.new(0.5, 0.5),
		font = FONT,
		text = "",
		textTransparency = 1,
		strokeTransparency = 0.3,
	})
	ui.announceSub = label({
		parent = gui,
		name = "AnnounceSub",
		size = UDim2.new(0.7, 0, 0, 34),
		position = UDim2.new(0.5, 0, 0.2, 52),
		anchor = Vector2.new(0.5, 0.5),
		text = "",
		textTransparency = 1,
		color = Color3.fromRGB(215, 213, 225),
	})

	------------------------------------------------------------------- salvage
	local salvageBox = frame({
		parent = gui,
		name = "SalvageBox",
		size = UDim2.fromOffset(212, 62),
		position = UDim2.new(0, 16, 0, 16),
		transparency = 0.3,
	})
	stroke(salvageBox, GOLD, 1, 0.6)
	ui.salvage = label({
		parent = salvageBox,
		name = "Salvage",
		size = UDim2.new(1, -14, 0.6, 0),
		position = UDim2.new(0, 10, 0, 2),
		align = Enum.TextXAlignment.Left,
		font = FONT,
		text = "0",
		color = GOLD,
	})
	ui.kills = label({
		parent = salvageBox,
		name = "Kills",
		size = UDim2.new(1, -14, 0.34, 0),
		position = UDim2.new(0, 10, 0.62, 0),
		align = Enum.TextXAlignment.Left,
		text = "SALVAGE  -  0 KILLS",
		color = Color3.fromRGB(185, 183, 195),
	})

	--------------------------------------------------------------------- health
	local healthBox = frame({
		parent = gui,
		name = "HealthBox",
		size = UDim2.fromOffset(320, 66),
		position = UDim2.new(0, 16, 1, -16),
		anchor = Vector2.new(0, 1),
		transparency = 0.3,
	})
	ui.healthBox = healthBox
	local healthTrack = frame({
		parent = healthBox,
		name = "Track",
		size = UDim2.new(1, -20, 0, 16),
		position = UDim2.new(0, 10, 0, 12),
		color = Color3.fromRGB(46, 20, 22),
		transparency = 0.1,
		radius = 4,
	})
	ui.healthFill = frame({
		parent = healthTrack,
		name = "Fill",
		size = UDim2.fromScale(1, 1),
		color = Color3.fromRGB(235, 70, 70),
		transparency = 0,
		radius = 4,
		z = 2,
	})
	ui.healthText = label({
		parent = healthBox,
		name = "HealthText",
		size = UDim2.new(1, -20, 0, 20),
		position = UDim2.new(0, 10, 0, 34),
		align = Enum.TextXAlignment.Left,
		text = "100 / 100 VITALITY",
		color = Color3.fromRGB(230, 200, 200),
	})

	ui.tonicRow = Instance.new("Frame")
	ui.tonicRow.Name = "TonicRow"
	ui.tonicRow.BackgroundTransparency = 1
	ui.tonicRow.Size = UDim2.fromOffset(320, 34)
	ui.tonicRow.Position = UDim2.new(0, 16, 1, -90)
	ui.tonicRow.AnchorPoint = Vector2.new(0, 1)
	ui.tonicRow.Parent = gui
	local tonicLayout = Instance.new("UIListLayout")
	tonicLayout.FillDirection = Enum.FillDirection.Horizontal
	tonicLayout.Padding = UDim.new(0, 6)
	tonicLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	tonicLayout.Parent = ui.tonicRow

	--------------------------------------------------------------------- weapon
	local weaponBox = frame({
		parent = gui,
		name = "WeaponBox",
		size = UDim2.fromOffset(340, 96),
		position = UDim2.new(1, -16, 1, -16),
		anchor = Vector2.new(1, 1),
		transparency = 0.3,
	})
	ui.weaponBox = weaponBox
	ui.weaponName = label({
		parent = weaponBox,
		name = "WeaponName",
		size = UDim2.new(1, -16, 0.3, 0),
		position = UDim2.new(0, 8, 0, 4),
		align = Enum.TextXAlignment.Right,
		font = FONT,
		text = "-",
		color = INK,
	})
	ui.ammo = label({
		parent = weaponBox,
		name = "Ammo",
		size = UDim2.new(1, -16, 0.42, 0),
		position = UDim2.new(0, 8, 0.28, 0),
		align = Enum.TextXAlignment.Right,
		font = FONT,
		text = "0 / 0",
		color = GOLD,
	})
	ui.slots = label({
		parent = weaponBox,
		name = "Slots",
		size = UDim2.new(1, -16, 0.24, 0),
		position = UDim2.new(0, 8, 0.74, 0),
		align = Enum.TextXAlignment.Right,
		text = "[1] -   [2] -",
		color = Color3.fromRGB(180, 178, 190),
	})
	ui.reloadTrack = frame({
		parent = weaponBox,
		name = "ReloadTrack",
		size = UDim2.new(1, -20, 0, 5),
		position = UDim2.new(0, 10, 1, -6),
		anchor = Vector2.new(0, 1),
		color = Color3.fromRGB(50, 46, 40),
		transparency = 0.2,
		radius = 3,
		visible = false,
	})
	ui.reloadFill = frame({
		parent = ui.reloadTrack,
		name = "Fill",
		size = UDim2.fromScale(0, 1),
		color = GOLD,
		transparency = 0,
		radius = 3,
		z = 2,
	})

	------------------------------------------------------------------ crosshair
	local cross = Instance.new("Frame")
	cross.Name = "Crosshair"
	cross.BackgroundTransparency = 1
	cross.Size = UDim2.fromOffset(64, 64)
	cross.Position = UDim2.fromScale(0.5, 0.5)
	cross.AnchorPoint = Vector2.new(0.5, 0.5)
	cross.Parent = gui
	ui.cross = cross

	ui.crossArms = {}
	local arms = {
		{ name = "Up", size = UDim2.fromOffset(2, 10), anchor = Vector2.new(0.5, 1), pos = UDim2.new(0.5, 0, 0.5, -6), dir = Vector2.new(0, -1) },
		{ name = "Down", size = UDim2.fromOffset(2, 10), anchor = Vector2.new(0.5, 0), pos = UDim2.new(0.5, 0, 0.5, 6), dir = Vector2.new(0, 1) },
		{ name = "Left", size = UDim2.fromOffset(10, 2), anchor = Vector2.new(1, 0.5), pos = UDim2.new(0.5, -6, 0.5, 0), dir = Vector2.new(-1, 0) },
		{ name = "Right", size = UDim2.fromOffset(10, 2), anchor = Vector2.new(0, 0.5), pos = UDim2.new(0.5, 6, 0.5, 0), dir = Vector2.new(1, 0) },
	}
	for _, arm in ipairs(arms) do
		local part = Instance.new("Frame")
		part.Name = arm.name
		part.Size = arm.size
		part.Position = arm.pos
		part.AnchorPoint = arm.anchor
		part.BackgroundColor3 = Color3.fromRGB(245, 245, 250)
		part.BackgroundTransparency = 0.15
		part.BorderSizePixel = 0
		part.Parent = cross
		table.insert(ui.crossArms, { part = part, base = arm.pos, dir = arm.dir })
	end
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.Size = UDim2.fromOffset(2, 2)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	dot.BorderSizePixel = 0
	dot.Parent = cross

	ui.hitmarker = Instance.new("ImageLabel")
	ui.hitmarker.Name = "Hitmarker"
	ui.hitmarker.BackgroundTransparency = 1
	ui.hitmarker.Image = ""
	ui.hitmarker.Size = UDim2.fromOffset(28, 28)
	ui.hitmarker.Position = UDim2.fromScale(0.5, 0.5)
	ui.hitmarker.AnchorPoint = Vector2.new(0.5, 0.5)
	ui.hitmarker.Visible = false
	ui.hitmarker.Parent = gui
	for _, rotation in ipairs({ 45, -45 }) do
		local bar = Instance.new("Frame")
		bar.Size = UDim2.fromOffset(26, 3)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Rotation = rotation
		bar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		bar.BorderSizePixel = 0
		bar.Parent = ui.hitmarker
	end

	------------------------------------------------------------------- vignette
	ui.vignette = Instance.new("Frame")
	ui.vignette.Name = "Vignette"
	ui.vignette.Size = UDim2.fromScale(1, 1)
	ui.vignette.BackgroundColor3 = Color3.fromRGB(150, 20, 20)
	ui.vignette.BackgroundTransparency = 1
	ui.vignette.BorderSizePixel = 0
	ui.vignette.ZIndex = 0
	ui.vignette.Parent = gui

	-------------------------------------------------------------------- toasts
	ui.toastHolder = Instance.new("Frame")
	ui.toastHolder.Name = "Toasts"
	ui.toastHolder.BackgroundTransparency = 1
	ui.toastHolder.Size = UDim2.fromOffset(420, 200)
	ui.toastHolder.Position = UDim2.new(0.5, 0, 1, -130)
	ui.toastHolder.AnchorPoint = Vector2.new(0.5, 1)
	ui.toastHolder.Parent = gui
	local toastLayout = Instance.new("UIListLayout")
	toastLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	toastLayout.Padding = UDim.new(0, 4)
	toastLayout.Parent = ui.toastHolder

	---------------------------------------------------------------- crate panel
	ui.cratePanel = frame({
		parent = gui,
		name = "CratePanel",
		size = UDim2.fromOffset(460, 116),
		position = UDim2.new(0.5, 0, 0.66, 0),
		anchor = Vector2.new(0.5, 0.5),
		transparency = 0.15,
		visible = false,
	})
	stroke(ui.cratePanel, GOLD, 2, 0.3)
	label({
		parent = ui.cratePanel,
		name = "Title",
		size = UDim2.new(1, 0, 0.3, 0),
		position = UDim2.new(0, 0, 0, 6),
		font = FONT,
		text = "THE FATE CRATE",
		color = GOLD,
	})
	ui.crateReel = label({
		parent = ui.cratePanel,
		name = "Reel",
		size = UDim2.new(1, -20, 0.52, 0),
		position = UDim2.new(0, 10, 0.36, 0),
		font = FONT,
		text = "...",
		color = INK,
	})

	--------------------------------------------------------------- downed panel
	ui.downedPanel = frame({
		parent = gui,
		name = "DownedPanel",
		size = UDim2.fromOffset(520, 132),
		position = UDim2.new(0.5, 0, 0.74, 0),
		anchor = Vector2.new(0.5, 0.5),
		transparency = 0.15,
		visible = false,
	})
	stroke(ui.downedPanel, Color3.fromRGB(255, 80, 80), 2, 0.25)
	ui.downedTitle = label({
		parent = ui.downedPanel,
		name = "Title",
		size = UDim2.new(1, 0, 0.4, 0),
		position = UDim2.new(0, 0, 0, 6),
		font = FONT,
		text = "YOU ARE DOWN",
		color = Color3.fromRGB(255, 110, 110),
	})
	ui.downedSub = label({
		parent = ui.downedPanel,
		name = "Sub",
		size = UDim2.new(1, -20, 0.3, 0),
		position = UDim2.new(0, 10, 0.42, 0),
		text = "Hold on. A teammate can pick you up.",
	})
	local bleedTrack = frame({
		parent = ui.downedPanel,
		name = "BleedTrack",
		size = UDim2.new(1, -40, 0, 12),
		position = UDim2.new(0.5, 0, 0.84, 0),
		anchor = Vector2.new(0.5, 0.5),
		color = Color3.fromRGB(50, 20, 20),
		transparency = 0.1,
		radius = 4,
	})
	ui.bleedFill = frame({
		parent = bleedTrack,
		name = "Fill",
		size = UDim2.fromScale(1, 1),
		color = Color3.fromRGB(255, 90, 90),
		transparency = 0,
		radius = 4,
		z = 2,
	})

	------------------------------------------------------------------ run ended
	ui.endPanel = frame({
		parent = gui,
		name = "EndPanel",
		size = UDim2.fromScale(1, 1),
		position = UDim2.fromScale(0, 0),
		color = Color3.fromRGB(8, 6, 10),
		transparency = 0.35,
		visible = false,
		round = false,
		z = 40,
	})
	ui.endTitle = label({
		parent = ui.endPanel,
		name = "Title",
		size = UDim2.new(0.8, 0, 0, 96),
		position = UDim2.new(0.5, 0, 0.4, 0),
		anchor = Vector2.new(0.5, 0.5),
		font = FONT,
		text = "",
		z = 41,
	})
	ui.endSub = label({
		parent = ui.endPanel,
		name = "Sub",
		size = UDim2.new(0.7, 0, 0, 44),
		position = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		text = "",
		z = 41,
	})

	------------------------------------------------------------------ help card
	local help = frame({
		parent = gui,
		name = "Help",
		size = UDim2.fromOffset(250, 128),
		position = UDim2.new(1, -16, 0, 16),
		anchor = Vector2.new(1, 0),
		transparency = 0.45,
	})
	ui.help = help
	label({
		parent = help,
		size = UDim2.new(1, -16, 0, 22),
		position = UDim2.new(0, 8, 0, 6),
		align = Enum.TextXAlignment.Left,
		font = FONT,
		text = "CONTROLS",
		color = GOLD,
		textSize = 15,
	})
	label({
		parent = help,
		size = UDim2.new(1, -16, 1, -34),
		position = UDim2.new(0, 8, 0, 28),
		align = Enum.TextXAlignment.Left,
		valign = Enum.TextYAlignment.Top,
		text = "LMB  fire\nR  reload\n1 / 2  swap weapon\nE  buy / repair\nF  revive teammate\nShift  sprint\nH  hide this card",
		color = Color3.fromRGB(215, 213, 225),
		textSize = 14,
	})

	return gui
end

--------------------------------------------------------------------------------
-- updates
--------------------------------------------------------------------------------

function Hud.setEconomy(data)
	if not data then return end
	ui.salvage.Text = Util.comma(data.salvage or 0)
	ui.kills.Text = "SALVAGE  -  " .. Util.comma(data.kills or 0) .. " KILLS"
end

function Hud.setWave(data)
	if not data then return end
	state.wavePhase = data.phase
	state.waveEndsAt = data.endsAt or 0
	state.waveData = data

	if data.phase == "lobby" then
		ui.waveLabel.Text = "THE ASHVAULT"
	elseif data.phase == "ended" then
		ui.waveLabel.Text = "RUN OVER"
	else
		ui.waveLabel.Text = "WAVE " .. tostring(data.wave)
		if data.isBossWave then
			ui.waveLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
		else
			ui.waveLabel.TextColor3 = GOLD
		end
	end
end

function Hud.setBoss(data)
	if not data or not data.active then
		ui.bossBox.Visible = false
		return
	end
	ui.bossBox.Visible = true
	ui.bossName.Text = data.name .. (data.title and ("  -  " .. data.title) or "")
	local fraction = data.maxHealth > 0 and math.clamp(data.health / data.maxHealth, 0, 1) or 0
	TweenService:Create(ui.bossFill, TweenInfo.new(0.18), { Size = UDim2.fromScale(fraction, 1) }):Play()
	ui.bossHp.Text = Util.comma(math.max(0, data.health)) .. " / " .. Util.comma(data.maxHealth)
	ui.bossName.TextColor3 = data.final and Color3.fromRGB(255, 70, 70) or Color3.fromRGB(255, 150, 150)
end

function Hud.setLoadout(data)
	if not data then return end
	state.loadout = data
	local active = data.slots and data.slots[data.active]
	if active then
		ui.weaponName.Text = string.upper(active.name)
		ui.weaponName.TextColor3 = active.upgraded and Color3.fromRGB(150, 220, 255) or INK
		ui.ammo.Text = active.ammo .. " / " .. active.spare
	else
		ui.weaponName.Text = "UNARMED"
		ui.ammo.Text = "- / -"
	end

	local parts = {}
	for index = 1, 2 do
		local slot = data.slots and data.slots[index]
		local marker = (index == data.active) and ">" or " "
		table.insert(parts, marker .. "[" .. index .. "] " .. (slot and slot.name or "-"))
	end
	ui.slots.Text = table.concat(parts, "   ")

	if data.reloading then
		state.reloadStart = os.clock()
		state.reloadDuration = math.max(0.1, (active and active.reloadTime) or 1)
		ui.reloadTrack.Visible = true
	else
		ui.reloadTrack.Visible = false
	end
end

function Hud.setTonics(list)
	for _, child in ipairs(ui.tonicRow:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for _, id in ipairs(list or {}) do
		local def = TonicDefs.get(id)
		if def then
			local pip = Instance.new("Frame")
			pip.Size = UDim2.fromOffset(30, 30)
			pip.BackgroundColor3 = def.color
			pip.BackgroundTransparency = 0.1
			pip.BorderSizePixel = 0
			pip.Parent = ui.tonicRow
			corner(pip, 15)
			local initial = Instance.new("TextLabel")
			initial.Size = UDim2.fromScale(1, 1)
			initial.BackgroundTransparency = 1
			initial.Font = FONT
			initial.TextScaled = true
			initial.Text = string.sub(def.name, 1, 1)
			initial.TextColor3 = Color3.fromRGB(20, 18, 22)
			initial.Parent = pip
		end
	end
end

function Hud.announce(data)
	if not data then return end
	local color = data.color and Color3.fromRGB(data.color[1], data.color[2], data.color[3]) or INK
	ui.announce.Text = data.title or ""
	ui.announce.TextColor3 = color
	ui.announce.TextScaled = true
	ui.announceSub.Text = data.subtitle or ""
	ui.announce.TextTransparency = 0
	ui.announceSub.TextTransparency = 0
	ui.announce.Size = data.big and UDim2.new(0.9, 0, 0, 104) or UDim2.new(0.8, 0, 0, 74)

	local duration = data.duration or 2.5
	local token = (state.announceToken or 0) + 1
	state.announceToken = token
	task.delay(duration, function()
		if state.announceToken ~= token then return end
		TweenService:Create(ui.announce, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		TweenService:Create(ui.announceSub, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
	end)
end

function Hud.toast(data)
	if not data then return end
	local color = data.color and Color3.fromRGB(data.color[1], data.color[2], data.color[3]) or INK
	local holder = Instance.new("Frame")
	holder.Size = UDim2.fromOffset(420, 26)
	holder.BackgroundColor3 = PANEL
	holder.BackgroundTransparency = 0.35
	holder.BorderSizePixel = 0
	holder.Parent = ui.toastHolder
	corner(holder, 5)

	local text = label({
		parent = holder,
		size = UDim2.new(1, -12, 1, 0),
		position = UDim2.new(0, 6, 0, 0),
		text = data.text or "",
		color = color,
		textSize = 15,
	})

	task.delay(data.duration or 3, function()
		TweenService:Create(holder, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(text, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		task.wait(0.45)
		holder:Destroy()
	end)
end

function Hud.flashHitmarker(data)
	if data and data.taken then
		-- we got hit: pulse the damage vignette instead
		ui.vignette.BackgroundTransparency = 0.72
		TweenService:Create(ui.vignette, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
		return
	end
	local marker = ui.hitmarker
	marker.Visible = true
	local scale = 1
	if data and data.killed then scale = 1.5 end
	if data and data.headshot then scale = scale * 1.2 end
	marker.Size = UDim2.fromOffset(28 * scale, 28 * scale)
	for _, child in ipairs(marker:GetChildren()) do
		if child:IsA("Frame") then
			child.BackgroundColor3 = (data and data.killed) and Color3.fromRGB(255, 90, 90) or Color3.fromRGB(255, 255, 255)
		end
	end
	local token = (state.hitToken or 0) + 1
	state.hitToken = token
	task.delay(0.12, function()
		if state.hitToken == token then
			marker.Visible = false
		end
	end)
end

function Hud.crateSpin(data)
	if not data then return end
	local panel = ui.cratePanel
	panel.Visible = true
	local reel = data.reel or {}
	local duration = data.duration or 3.5
	local token = (state.crateToken or 0) + 1
	state.crateToken = token

	task.spawn(function()
		local elapsed = 0
		local index = 1
		while elapsed < duration and state.crateToken == token do
			ui.crateReel.Text = reel[index] or "???"
			ui.crateReel.TextColor3 = INK
			index = index % math.max(1, #reel) + 1
			-- ease the reel out towards the end
			local step = 0.06 + 0.22 * (elapsed / duration) ^ 2
			task.wait(step)
			elapsed = elapsed + step
		end
		if state.crateToken ~= token then return end
		ui.crateReel.Text = data.result or "???"
		ui.crateReel.TextColor3 = data.doll and Color3.fromRGB(200, 150, 255) or Color3.fromRGB(150, 255, 170)
		task.wait(2.2)
		if state.crateToken == token then
			panel.Visible = false
		end
	end)
end

function Hud.setDowned(data)
	if not data then return end
	state.downed = data.downed == true
	state.out = data.out == true
	state.bleedRemaining = data.bleedRemaining or 0
	state.bleedTotal = data.bleedTotal or 30

	ui.downedPanel.Visible = state.downed or state.out
	if state.out then
		ui.downedTitle.Text = "YOU BLED OUT"
		ui.downedTitle.TextColor3 = Color3.fromRGB(200, 200, 210)
		ui.downedSub.Text = "You are back on the next wave."
		ui.bleedFill.Size = UDim2.fromScale(0, 1)
	elseif state.downed then
		ui.downedTitle.Text = "YOU ARE DOWN"
		ui.downedTitle.TextColor3 = Color3.fromRGB(255, 110, 110)
		ui.downedSub.Text = data.canSelfRevive
			and "Hold F to use your Second Wind Phial."
			or "A teammate can hold F to pick you up."
	end
end

function Hud.runEnded(data)
	if not data then return end
	ui.endPanel.Visible = true
	ui.endTitle.Text = data.title or ""
	ui.endTitle.TextColor3 = data.victory and Color3.fromRGB(160, 255, 190) or Color3.fromRGB(255, 90, 90)
	ui.endSub.Text = data.subtitle or ""
	task.delay(9, function()
		ui.endPanel.Visible = false
	end)
end

function Hud.hideEndPanel()
	ui.endPanel.Visible = false
end

function Hud.toggleHelp()
	ui.help.Visible = not ui.help.Visible
end

function Hud.powerup(data)
	if not data then return end
	Hud.announce({
		title = data.name,
		subtitle = data.blurb .. (data.by and ("  -  picked up by " .. data.by) or ""),
		color = data.color,
		duration = 3,
	})
end

-- Called every frame by ClientMain with the local humanoid and spread factor.
function Hud.step(dt, humanoid, spreadFactor)
	if humanoid then
		local fraction = humanoid.MaxHealth > 0 and math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) or 0
		ui.healthFill.Size = UDim2.fromScale(fraction, 1)
		ui.healthText.Text = math.floor(humanoid.Health + 0.5) .. " / " .. math.floor(humanoid.MaxHealth) .. " VITALITY"
		ui.healthFill.BackgroundColor3 = fraction < 0.35 and Color3.fromRGB(255, 60, 60) or Color3.fromRGB(235, 90, 90)
		if fraction < 0.35 and not state.downed then
			ui.vignette.BackgroundTransparency = 0.88 + math.sin(os.clock() * 4) * 0.06
		end
	end

	-- crosshair bloom
	local target = 6 + (spreadFactor or 0) * 26
	state.crosshairSpread = Util.lerp(state.crosshairSpread, target, math.min(1, dt * 12))
	for _, arm in ipairs(ui.crossArms) do
		local offset = state.crosshairSpread
		arm.part.Position = UDim2.new(0.5, arm.dir.X * offset, 0.5, arm.dir.Y * offset)
	end

	-- wave subtitle: timer during intermission, kill counter during a wave
	local data = state.waveData
	if data then
		if (data.phase == "intermission" or data.phase == "lobby") and state.waveEndsAt > 0 then
			local remaining = state.waveEndsAt - workspace:GetServerTimeNow()
			ui.waveSub.Text = "NEXT WAVE IN " .. Util.formatTime(math.max(0, remaining))
		elseif data.phase == "active" then
			ui.waveSub.Text = (data.remaining or 0) .. " ENEMIES LEFT"
		elseif data.phase == "ended" then
			ui.waveSub.Text = "resetting"
		end
	end

	-- reload bar
	if ui.reloadTrack.Visible and state.reloadStart then
		local progress = math.clamp((os.clock() - state.reloadStart) / (state.reloadDuration or 1), 0, 1)
		ui.reloadFill.Size = UDim2.fromScale(progress, 1)
	end

	-- bleed-out countdown
	if state.downed then
		state.bleedRemaining = math.max(0, state.bleedRemaining - dt)
		local fraction = state.bleedTotal > 0 and (state.bleedRemaining / state.bleedTotal) or 0
		ui.bleedFill.Size = UDim2.fromScale(fraction, 1)
		ui.downedSub.Text = string.format("%.0f seconds left", state.bleedRemaining)
		ui.vignette.BackgroundTransparency = 0.6 + math.sin(os.clock() * 3) * 0.1
	end
end

return Hud
