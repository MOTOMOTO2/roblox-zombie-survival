-- EnemyDefs: the horde roster and the four bosses.
-- Every creature, name and ability here is original to this project.
--
-- Fields:
--   health/speed/damage  base values before wave scaling
--   minWave/weight       when it can appear and how common it is
--   height/width         model proportions (studs)
--   colors               torso / head / limb / glow
--   abilities            list of { kind, cooldown, ... } handled by EnemyService
--   phases               boss only: { at = healthFraction, speedMult, damageMult, abilities }

local EnemyDefs = {}

EnemyDefs.Normal = {
	{
		id = "husk",
		name = "Husk",
		health = 130,
		speed = 8.2,
		damage = 22,
		minWave = 1,
		weight = 100,
		height = 5.0,
		width = 1.9,
		colors = {
			torso = Color3.fromRGB(78, 92, 72),
			head = Color3.fromRGB(122, 132, 104),
			limb = Color3.fromRGB(66, 78, 62),
			glow = Color3.fromRGB(180, 255, 120),
		},
	},
	{
		id = "sprinter",
		name = "Sprinter",
		health = 95,
		speed = 14.5,
		damage = 16,
		minWave = 4,
		weight = 45,
		height = 4.8,
		width = 1.6,
		colors = {
			torso = Color3.fromRGB(96, 62, 62),
			head = Color3.fromRGB(150, 96, 90),
			limb = Color3.fromRGB(78, 52, 52),
			glow = Color3.fromRGB(255, 140, 120),
		},
	},
	{
		id = "crawler",
		name = "Crawler",
		health = 75,
		speed = 11.0,
		damage = 14,
		minWave = 6,
		weight = 32,
		height = 2.4,
		width = 2.2,
		colors = {
			torso = Color3.fromRGB(64, 70, 84),
			head = Color3.fromRGB(104, 112, 130),
			limb = Color3.fromRGB(52, 58, 70),
			glow = Color3.fromRGB(150, 190, 255),
		},
	},
	{
		id = "brute",
		name = "Ashbrute",
		health = 620,
		speed = 7.0,
		damage = 46,
		minWave = 7,
		weight = 18,
		height = 6.6,
		width = 2.9,
		colors = {
			torso = Color3.fromRGB(58, 54, 50),
			head = Color3.fromRGB(92, 84, 76),
			limb = Color3.fromRGB(46, 44, 40),
			glow = Color3.fromRGB(255, 170, 60),
		},
		abilities = {
			{ kind = "slam", cooldown = 7, range = 11, radius = 14, damage = 38 },
		},
	},
	{
		id = "spitter",
		name = "Bile Spitter",
		health = 180,
		speed = 8.8,
		damage = 18,
		minWave = 9,
		weight = 22,
		height = 5.1,
		width = 2.2,
		colors = {
			torso = Color3.fromRGB(88, 104, 56),
			head = Color3.fromRGB(140, 160, 80),
			limb = Color3.fromRGB(70, 84, 46),
			glow = Color3.fromRGB(190, 255, 80),
		},
		abilities = {
			{ kind = "spit", cooldown = 5.5, range = 70, damage = 26, radius = 9, speed = 90 },
		},
	},
}

EnemyDefs.Bosses = {
	{
		id = "warden",
		name = "The Rust Warden",
		title = "WARDEN OF THE FIRST GATE",
		health = 6200,
		speed = 9.2,
		damage = 55,
		height = 9.5,
		width = 4.2,
		isBoss = true,
		salvage = 2000,
		colors = {
			torso = Color3.fromRGB(104, 62, 34),
			head = Color3.fromRGB(150, 96, 44),
			limb = Color3.fromRGB(80, 48, 28),
			glow = Color3.fromRGB(255, 140, 40),
		},
		abilities = {
			{ kind = "slam", cooldown = 5.5, range = 16, radius = 22, damage = 45 },
			{ kind = "charge", cooldown = 11, range = 60, speedMult = 2.6, duration = 2.2, damage = 50 },
		},
		phases = {
			{ at = 0.5, speedMult = 1.2, damageMult = 1.15, announce = "THE RUST WARDEN SHEDS ITS PLATING" },
		},
	},
	{
		id = "howler",
		name = "Choir Howler",
		title = "SECOND VOICE OF THE HOLLOW CHOIR",
		health = 15000,
		speed = 10.6,
		damage = 60,
		height = 9.0,
		width = 3.6,
		isBoss = true,
		salvage = 3200,
		colors = {
			torso = Color3.fromRGB(58, 44, 92),
			head = Color3.fromRGB(96, 74, 150),
			limb = Color3.fromRGB(44, 34, 72),
			glow = Color3.fromRGB(190, 130, 255),
		},
		abilities = {
			{ kind = "shockwave", cooldown = 8, radius = 30, damage = 40 },
			{ kind = "summon", cooldown = 13, count = 4, enemy = "sprinter" },
		},
		phases = {
			{ at = 0.6, speedMult = 1.15, damageMult = 1.1, announce = "THE HOWLER CALLS THE CHOIR" },
			{ at = 0.3, speedMult = 1.35, damageMult = 1.25, announce = "THE HOWLER SCREAMS" },
		},
	},
	{
		id = "stitcher",
		name = "The Stitcher",
		title = "THIRD VOICE, MAKER OF CRAWLERS",
		health = 28000,
		speed = 9.6,
		damage = 68,
		height = 10.5,
		width = 4.0,
		isBoss = true,
		salvage = 4500,
		colors = {
			torso = Color3.fromRGB(96, 96, 104),
			head = Color3.fromRGB(150, 150, 160),
			limb = Color3.fromRGB(74, 74, 82),
			glow = Color3.fromRGB(120, 255, 235),
		},
		abilities = {
			{ kind = "summon", cooldown = 10, count = 5, enemy = "crawler" },
			{ kind = "blink", cooldown = 9, range = 90 },
			{ kind = "slam", cooldown = 7, range = 15, radius = 20, damage = 52 },
		},
		phases = {
			{ at = 0.55, speedMult = 1.2, damageMult = 1.15, announce = "THE STITCHER UNSPOOLS" },
			{ at = 0.25, speedMult = 1.4, damageMult = 1.3, announce = "THE STITCHER COMES APART" },
		},
	},
}

EnemyDefs.FinalBoss = {
	id = "sovereign",
	name = "HOLLOW SOVEREIGN",
	title = "THE LAST VOICE",
	health = 72000,
	speed = 10.0,
	damage = 80,
	height = 14.0,
	width = 5.4,
	isBoss = true,
	isFinal = true,
	salvage = 12000,
	colors = {
		torso = Color3.fromRGB(26, 26, 32),
		head = Color3.fromRGB(58, 58, 70),
		limb = Color3.fromRGB(18, 18, 24),
		glow = Color3.fromRGB(255, 70, 70),
	},
	abilities = {
		{ kind = "slam", cooldown = 6, range = 20, radius = 26, damage = 60 },
		{ kind = "shockwave", cooldown = 9, radius = 40, damage = 45 },
		{ kind = "summon", cooldown = 12, count = 4, enemy = "husk" },
	},
	phases = {
		{
			at = 0.7,
			speedMult = 1.12,
			damageMult = 1.1,
			announce = "THE SOVEREIGN OPENS ITS SECOND MOUTH",
			abilities = {
				{ kind = "slam", cooldown = 5, range = 20, radius = 28, damage = 66 },
				{ kind = "shockwave", cooldown = 7.5, radius = 44, damage = 52 },
				{ kind = "summon", cooldown = 10, count = 5, enemy = "sprinter" },
				{ kind = "charge", cooldown = 13, range = 80, speedMult = 2.4, duration = 2.4, damage = 70 },
			},
		},
		{
			at = 0.4,
			speedMult = 1.25,
			damageMult = 1.2,
			announce = "THE SOVEREIGN IS UNRAVELLING",
			abilities = {
				{ kind = "slam", cooldown = 4.5, range = 22, radius = 30, damage = 72 },
				{ kind = "shockwave", cooldown = 6.5, radius = 48, damage = 58 },
				{ kind = "summon", cooldown = 9, count = 6, enemy = "crawler" },
				{ kind = "blink", cooldown = 10, range = 110 },
			},
		},
		{
			at = 0.15,
			speedMult = 1.45,
			damageMult = 1.35,
			announce = "FINAL BREATH - KILL IT NOW",
			abilities = {
				{ kind = "slam", cooldown = 3.5, range = 24, radius = 34, damage = 80 },
				{ kind = "shockwave", cooldown = 5, radius = 55, damage = 64 },
				{ kind = "summon", cooldown = 8, count = 6, enemy = "brute" },
				{ kind = "charge", cooldown = 9, range = 100, speedMult = 2.8, duration = 2.6, damage = 85 },
			},
		},
	},
}

local normalById = {}
for _, def in ipairs(EnemyDefs.Normal) do
	normalById[def.id] = def
end
local bossById = {}
for _, def in ipairs(EnemyDefs.Bosses) do
	bossById[def.id] = def
end
bossById[EnemyDefs.FinalBoss.id] = EnemyDefs.FinalBoss

function EnemyDefs.get(id)
	return normalById[id] or bossById[id]
end

-- Weighted roster for a given wave.
function EnemyDefs.poolForWave(wave)
	local pool = {}
	for _, def in ipairs(EnemyDefs.Normal) do
		if wave >= def.minWave then
			local weight = def.weight
			if def.id == "husk" then
				-- plain husks thin out as the nastier variants unlock
				weight = math.max(30, def.weight - (wave - 1) * 3)
			end
			table.insert(pool, { value = def.id, weight = weight })
		end
	end
	return pool
end

-- Which boss belongs to a wave, if any. Waves past the final boss cycle the
-- mini-bosses again with scaled health (endless mode).
function EnemyDefs.bossForWave(wave, finalWave, interval)
	if wave == finalWave then
		return EnemyDefs.FinalBoss
	end
	if wave % interval ~= 0 then
		return nil
	end
	if wave < finalWave then
		local index = math.floor(wave / interval)
		return EnemyDefs.Bosses[math.min(index, #EnemyDefs.Bosses)]
	end
	-- endless: rotate through every boss including the Sovereign
	local all = {}
	for _, boss in ipairs(EnemyDefs.Bosses) do
		table.insert(all, boss)
	end
	table.insert(all, EnemyDefs.FinalBoss)
	local index = ((math.floor(wave / interval) - 1) % #all) + 1
	return all[index]
end

return EnemyDefs
