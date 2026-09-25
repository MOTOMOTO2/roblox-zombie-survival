-- MapBuilder: generates "The Ashvault" arena from data at runtime.
-- Nothing about the map is stored in the place file, so the whole layout can be
-- retuned by editing the tables at the top of this module.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("NecrotideShared")
local GameConfig = require(Shared.GameConfig)

local MapBuilder = {}

local WALL_HEIGHT = 22
local WALL_THICK = 4
local ARENA = 110 -- perimeter half-extent
local GAP = 14 -- barrier opening width

local PALETTE = {
	floor = Color3.fromRGB(64, 62, 58),
	floorAlt = Color3.fromRGB(52, 50, 48),
	wall = Color3.fromRGB(82, 78, 72),
	innerWall = Color3.fromRGB(96, 90, 82),
	trim = Color3.fromRGB(44, 42, 40),
	board = Color3.fromRGB(122, 84, 48),
	accent = Color3.fromRGB(255, 140, 50),
}

-- Barrier openings in the perimeter wall. `axis` is the wall the gap sits in.
local BARRIERS = {
	{ id = "north_west", axis = "north", along = -58 },
	{ id = "north_east", axis = "north", along = 42 },
	{ id = "south_west", axis = "south", along = -46 },
	{ id = "south_east", axis = "south", along = 54 },
	{ id = "west_mid", axis = "west", along = 18 },
	{ id = "east_mid", axis = "east", along = -22 },
}

-- Four buildings around a cross-shaped courtyard. Doors are gaps in a side.
local BUILDINGS = {
	{ id = "vault_nw", center = Vector2.new(-58, -58), size = Vector2.new(60, 54), doors = { "south", "east" } },
	{ id = "vault_ne", center = Vector2.new(58, -58), size = Vector2.new(60, 54), doors = { "south", "west" } },
	{ id = "vault_sw", center = Vector2.new(-58, 58), size = Vector2.new(60, 54), doors = { "north", "east" } },
	{ id = "vault_se", center = Vector2.new(58, 58), size = Vector2.new(60, 54), doors = { "north", "west" } },
}

-- Cover props in the courtyard so the middle is not a flat killing field.
local COVER = {
	{ pos = Vector3.new(0, 2, -34), size = Vector3.new(22, 4, 5) },
	{ pos = Vector3.new(0, 2, 34), size = Vector3.new(22, 4, 5) },
	{ pos = Vector3.new(-34, 2, 0), size = Vector3.new(5, 4, 22) },
	{ pos = Vector3.new(34, 2, 0), size = Vector3.new(5, 4, 22) },
	{ pos = Vector3.new(-16, 3, -16), size = Vector3.new(7, 6, 7) },
	{ pos = Vector3.new(16, 3, 16), size = Vector3.new(7, 6, 7) },
	{ pos = Vector3.new(16, 1.5, -16), size = Vector3.new(9, 3, 9) },
	{ pos = Vector3.new(-16, 1.5, 16), size = Vector3.new(9, 3, 9) },
}

-- Armory Racks: buyable wall weapons. `pos` sits just off a wall face and `face`
-- points away from that wall, into the room the player stands in. The wall planes
-- these hang on are:
--   courtyard-facing outer walls of the north buildings   z = -29.5
--   NW building, interior west wall                       x = -86.5
--   NE building, interior north wall                      z = -83.5
--   SE building, interior east wall                       x =  86.5
--   SW building, interior south wall                      z =  83.5
local WALL_BUYS = {
	{ weapon = "vesper45", pos = Vector3.new(-40, 4, -29.0), face = Vector3.new(0, 0, 1) },
	{ weapon = "scrapper", pos = Vector3.new(40, 4, -29.0), face = Vector3.new(0, 0, 1) },
	{ weapon = "ranger12", pos = Vector3.new(-86.0, 4, -60), face = Vector3.new(1, 0, 0) },
	{ weapon = "hornet", pos = Vector3.new(58, 4, -83.0), face = Vector3.new(0, 0, 1) },
	{ weapon = "cyclone", pos = Vector3.new(86.0, 4, 58), face = Vector3.new(-1, 0, 0) },
	{ weapon = "talon", pos = Vector3.new(-58, 4, 83.0), face = Vector3.new(0, 0, -1) },
}

-- Tonic Stills.
local TONIC_SPOTS = {
	{ tonic = "ironhide", pos = Vector3.new(-72, 0, -44) },
	{ tonic = "quickhands", pos = Vector3.new(72, 0, -44) },
	{ tonic = "fleetfoot", pos = Vector3.new(-72, 0, 44) },
	{ tonic = "scavenger", pos = Vector3.new(72, 0, 44) },
	{ tonic = "deadeye", pos = Vector3.new(0, 0, -46) },
	{ tonic = "secondwind", pos = Vector3.new(0, 0, 46) },
}

-- The Fate Crate hops between these anchors when the Hollow Doll shows up.
local CRATE_SPOTS = {
	Vector3.new(-40, 0, -40),
	Vector3.new(44, 0, -38),
	Vector3.new(-42, 0, 42),
	Vector3.new(40, 0, 40),
	Vector3.new(0, 0, 62),
}

local FORGE_SPOT = Vector3.new(-58, 0, 58)
-- south of the central brazier, so nobody spawns inside it
local PLAYER_SPAWN = Vector3.new(0, 4, 20)

local function newPart(name, size, position, color, parent, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Anchored = true
	part.Color = color
	part.Material = material or Enum.Material.Concrete
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Builds one side of a rectangle, skipping the given gaps.
-- `gaps` is a list of { center = n, width = n } along the side's long axis.
local function wallWithGaps(parent, name, isHorizontal, fixed, from, to, gaps, height, thickness, color)
	local cuts = {}
	for _, gap in ipairs(gaps or {}) do
		table.insert(cuts, { gap.center - gap.width * 0.5, gap.center + gap.width * 0.5 })
	end
	table.sort(cuts, function(a, b) return a[1] < b[1] end)

	local cursor = from
	local index = 0
	local function segment(a, b)
		if b - a <= 0.05 then return end
		index = index + 1
		local mid = (a + b) * 0.5
		local length = b - a
		local size, pos
		if isHorizontal then
			size = Vector3.new(length, height, thickness)
			pos = Vector3.new(mid, height * 0.5, fixed)
		else
			size = Vector3.new(thickness, height, length)
			pos = Vector3.new(fixed, height * 0.5, mid)
		end
		newPart(name .. "_" .. index, size, pos, color, parent)
	end

	for _, cut in ipairs(cuts) do
		segment(cursor, math.max(cursor, cut[1]))
		cursor = math.max(cursor, cut[2])
	end
	segment(cursor, to)
end

local function buildFloor(parent)
	local floor = newPart("Floor", Vector3.new(ARENA * 2 + WALL_THICK * 2, 2, ARENA * 2 + WALL_THICK * 2), Vector3.new(0, -1, 0), PALETTE.floor, parent, Enum.Material.Slate)
	floor.Name = "Floor"

	-- checkered inlay so the courtyard reads as a built space
	for x = -3, 3 do
		for z = -3, 3 do
			if (x + z) % 2 == 0 then
				newPart("Inlay", Vector3.new(22, 0.2, 22), Vector3.new(x * 22, 0.1, z * 22), PALETTE.floorAlt, parent, Enum.Material.Concrete)
			end
		end
	end

	-- kill plane far below in case anything falls out of the world
	local void = newPart("VoidCatcher", Vector3.new(600, 2, 600), Vector3.new(0, -120, 0), Color3.fromRGB(20, 12, 12), parent, Enum.Material.Neon)
	void.Transparency = 0.7
	void.CanCollide = false
	void:SetAttribute("NecrotideVoid", true)
	return floor
end

local function buildPerimeter(parent)
	local gapsBySide = { north = {}, south = {}, east = {}, west = {} }
	for _, barrier in ipairs(BARRIERS) do
		table.insert(gapsBySide[barrier.axis], { center = barrier.along, width = GAP })
	end

	wallWithGaps(parent, "WallNorth", true, -ARENA, -ARENA, ARENA, gapsBySide.north, WALL_HEIGHT, WALL_THICK, PALETTE.wall)
	wallWithGaps(parent, "WallSouth", true, ARENA, -ARENA, ARENA, gapsBySide.south, WALL_HEIGHT, WALL_THICK, PALETTE.wall)
	wallWithGaps(parent, "WallWest", false, -ARENA, -ARENA, ARENA, gapsBySide.west, WALL_HEIGHT, WALL_THICK, PALETTE.wall)
	wallWithGaps(parent, "WallEast", false, ARENA, -ARENA, ARENA, gapsBySide.east, WALL_HEIGHT, WALL_THICK, PALETTE.wall)

	-- outer apron so spawned enemies have ground to stand on
	newPart("Apron", Vector3.new(ARENA * 2 + 120, 2, ARENA * 2 + 120), Vector3.new(0, -1.2, 0), Color3.fromRGB(38, 36, 34), parent, Enum.Material.Ground)
end

local function barrierTransform(barrier)
	-- returns position of the gap centre, the inward direction, and a wall axis
	if barrier.axis == "north" then
		return Vector3.new(barrier.along, 0, -ARENA), Vector3.new(0, 0, 1), Vector3.new(1, 0, 0)
	elseif barrier.axis == "south" then
		return Vector3.new(barrier.along, 0, ARENA), Vector3.new(0, 0, -1), Vector3.new(1, 0, 0)
	elseif barrier.axis == "west" then
		return Vector3.new(-ARENA, 0, barrier.along), Vector3.new(1, 0, 0), Vector3.new(0, 0, 1)
	end
	return Vector3.new(ARENA, 0, barrier.along), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1)
end

local function buildBarriers(parent)
	local out = {}
	for _, barrier in ipairs(BARRIERS) do
		local origin, inward, along = barrierTransform(barrier)
		local model = Instance.new("Model")
		model.Name = "Barrier_" .. barrier.id
		model.Parent = parent

		-- frame posts on both sides of the gap
		for _, side in ipairs({ -1, 1 }) do
			local postPos = origin + along * (GAP * 0.5 + 1) * side + Vector3.new(0, WALL_HEIGHT * 0.5, 0)
			local post = newPart("Post", Vector3.new(2, WALL_HEIGHT, WALL_THICK + 0.4), postPos, PALETTE.trim, model)
			if barrier.axis == "west" or barrier.axis == "east" then
				post.Size = Vector3.new(WALL_THICK + 0.4, WALL_HEIGHT, 2)
			end
		end
		-- lintel above the gap
		local lintelSize = Vector3.new(GAP + 4, 6, WALL_THICK)
		if barrier.axis == "west" or barrier.axis == "east" then
			lintelSize = Vector3.new(WALL_THICK, 6, GAP + 4)
		end
		newPart("Lintel", lintelSize, origin + Vector3.new(0, WALL_HEIGHT - 3, 0), PALETTE.wall, model)

		local boards = {}
		for i = 1, GameConfig.BoardsPerBarrier do
			local height = 2.6 + (i - 1) * 2.7
			local boardSize = Vector3.new(GAP - 0.5, 1.5, 1.2)
			if barrier.axis == "west" or barrier.axis == "east" then
				boardSize = Vector3.new(1.2, 1.5, GAP - 0.5)
			end
			local board = newPart("Board" .. i, boardSize, origin + Vector3.new(0, height, 0), PALETTE.board, model, Enum.Material.WoodPlanks)
			board.Rotation = Vector3.new(0, 0, (i % 2 == 0) and 4 or -4)
			table.insert(boards, board)
		end

		local promptAnchor = newPart("PromptAnchor", Vector3.new(2, 2, 2), origin + inward * 3 + Vector3.new(0, 4, 0), PALETTE.trim, model)
		promptAnchor.Transparency = 1
		promptAnchor.CanCollide = false

		table.insert(out, {
			id = barrier.id,
			model = model,
			boards = boards,
			origin = origin,
			inward = inward,
			promptAnchor = promptAnchor,
			-- ground level: EnemyService lifts models by half their height
			outside = origin + inward * -16,
			inside = origin + inward * 14,
		})
	end
	return out
end

local function buildBuildings(parent)
	for _, b in ipairs(BUILDINGS) do
		local model = Instance.new("Model")
		model.Name = b.id
		model.Parent = parent

		local minX, maxX = b.center.X - b.size.X * 0.5, b.center.X + b.size.X * 0.5
		local minZ, maxZ = b.center.Y - b.size.Y * 0.5, b.center.Y + b.size.Y * 0.5
		local doorSet = {}
		for _, side in ipairs(b.doors) do
			doorSet[side] = true
		end

		local function gapsFor(side, axisCenter)
			if doorSet[side] then
				return { { center = axisCenter, width = 16 } }
			end
			return {}
		end

		wallWithGaps(model, b.id .. "_N", true, minZ, minX, maxX, gapsFor("north", b.center.X), 18, 3, PALETTE.innerWall)
		wallWithGaps(model, b.id .. "_S", true, maxZ, minX, maxX, gapsFor("south", b.center.X), 18, 3, PALETTE.innerWall)
		wallWithGaps(model, b.id .. "_W", false, minX, minZ, maxZ, gapsFor("west", b.center.Y), 18, 3, PALETTE.innerWall)
		wallWithGaps(model, b.id .. "_E", false, maxX, minZ, maxZ, gapsFor("east", b.center.Y), 18, 3, PALETTE.innerWall)

		-- interior detail: a few crates and a hanging lamp
		newPart(b.id .. "_Crate1", Vector3.new(6, 6, 6), Vector3.new(minX + 8, 3, minZ + 8), Color3.fromRGB(96, 74, 48), model, Enum.Material.WoodPlanks)
		newPart(b.id .. "_Crate2", Vector3.new(5, 5, 5), Vector3.new(maxX - 9, 2.5, maxZ - 9), Color3.fromRGB(88, 68, 44), model, Enum.Material.WoodPlanks)

		local lamp = newPart(b.id .. "_Lamp", Vector3.new(3, 0.6, 3), Vector3.new(b.center.X, 15, b.center.Y), PALETTE.accent, model, Enum.Material.Neon)
		lamp.CanCollide = false
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 176, 108)
		light.Brightness = 2.2
		light.Range = 46
		light.Shadows = true
		light.Parent = lamp
	end
end

local function buildCover(parent)
	for i, prop in ipairs(COVER) do
		newPart("Cover" .. i, prop.size, prop.pos, PALETTE.innerWall, parent, Enum.Material.Cobblestone)
	end

	-- central brazier: the visual anchor of the courtyard
	local base = newPart("BrazierBase", Vector3.new(10, 3, 10), Vector3.new(0, 1.5, 0), PALETTE.trim, parent, Enum.Material.Slate)
	local bowl = newPart("BrazierBowl", Vector3.new(6, 2, 6), Vector3.new(0, 4, 0), PALETTE.accent, parent, Enum.Material.Neon)
	bowl.CanCollide = false
	local fire = Instance.new("Fire")
	fire.Size = 18
	fire.Heat = 12
	fire.Color = Color3.fromRGB(255, 150, 60)
	fire.SecondaryColor = Color3.fromRGB(120, 40, 10)
	fire.Parent = bowl
	local light = Instance.new("PointLight")
	light.Brightness = 4
	light.Range = 70
	light.Color = Color3.fromRGB(255, 160, 80)
	light.Parent = bowl
	return base
end

local function buildSpawn(parent)
	local pad = newPart("SpawnPad", Vector3.new(26, 0.6, 26), Vector3.new(PLAYER_SPAWN.X, 0.3, PLAYER_SPAWN.Z), Color3.fromRGB(70, 90, 110), parent, Enum.Material.Metal)
	pad.CanCollide = false

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "AshvaultSpawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = PLAYER_SPAWN - Vector3.new(0, 3.6, 0)
	spawn.Anchored = true
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = parent
	return spawn
end

local function applyLighting()
	Lighting.Ambient = Color3.fromRGB(38, 36, 44)
	Lighting.OutdoorAmbient = Color3.fromRGB(46, 44, 56)
	Lighting.Brightness = 1.4
	Lighting.ClockTime = 0.6
	Lighting.GeographicLatitude = 12
	Lighting.FogColor = Color3.fromRGB(18, 16, 22)
	Lighting.FogStart = 60
	Lighting.FogEnd = 420
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.GlobalShadows = true

	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.42
		atmosphere.Offset = 0.1
		atmosphere.Color = Color3.fromRGB(150, 140, 160)
		atmosphere.Decay = Color3.fromRGB(80, 70, 90)
		atmosphere.Glare = 0.2
		atmosphere.Haze = 2.2
		atmosphere.Parent = Lighting
	end
	if not Lighting:FindFirstChild("NecrotideBloom") then
		local bloom = Instance.new("BloomEffect")
		bloom.Name = "NecrotideBloom"
		bloom.Intensity = 0.45
		bloom.Size = 26
		bloom.Threshold = 1.1
		bloom.Parent = Lighting
	end
	if not Lighting:FindFirstChild("NecrotideGrade") then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "NecrotideGrade"
		cc.Brightness = -0.03
		cc.Contrast = 0.16
		cc.Saturation = -0.12
		cc.TintColor = Color3.fromRGB(226, 220, 235)
		cc.Parent = Lighting
	end
end

function MapBuilder.build()
	local existing = workspace:FindFirstChild("Ashvault")
	if existing then
		existing:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = "Ashvault"
	root.Parent = workspace

	local structure = Instance.new("Folder")
	structure.Name = "Structure"
	structure.Parent = root

	buildFloor(structure)
	buildPerimeter(structure)
	buildBuildings(structure)
	buildCover(structure)
	local spawnLocation = buildSpawn(structure)

	local barrierFolder = Instance.new("Folder")
	barrierFolder.Name = "Barriers"
	barrierFolder.Parent = root
	local barriers = buildBarriers(barrierFolder)

	local stationFolder = Instance.new("Folder")
	stationFolder.Name = "Stations"
	stationFolder.Parent = root

	local enemyFolder = Instance.new("Folder")
	enemyFolder.Name = "Enemies"
	enemyFolder.Parent = root

	local fxFolder = Instance.new("Folder")
	fxFolder.Name = "Fx"
	fxFolder.Parent = root

	applyLighting()

	local spawnPoints = {}
	for _, barrier in ipairs(barriers) do
		table.insert(spawnPoints, { position = barrier.outside, barrier = barrier })
		-- a second, wider spawn ring position per barrier for big waves
		table.insert(spawnPoints, { position = barrier.origin + barrier.inward * -30, barrier = barrier })
	end

	return {
		root = root,
		structure = structure,
		stationFolder = stationFolder,
		enemyFolder = enemyFolder,
		fxFolder = fxFolder,
		barriers = barriers,
		spawnPoints = spawnPoints,
		wallBuys = WALL_BUYS,
		tonicSpots = TONIC_SPOTS,
		cratePositions = CRATE_SPOTS,
		forgePosition = FORGE_SPOT,
		playerSpawn = PLAYER_SPAWN,
		spawnLocation = spawnLocation,
		bounds = ARENA,
		newPart = newPart,
		palette = PALETTE,
	}
end

return MapBuilder
