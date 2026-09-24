-- WeaponDefs: every gun in the game, plus its Overforge (upgraded) variant.
-- All names, models and stats are original to this project.
--
-- Fields:
--   damage      base body damage per bullet/pellet
--   headMult    multiplier when the shot lands on a head part
--   rpm         rounds per minute (server enforces this as the fire rate)
--   mag         rounds per magazine
--   reserve     spare rounds carried
--   reloadTime  seconds
--   spread      cone half-angle in degrees while hip firing
--   pellets     projectiles per trigger pull (shotguns)
--   range       max hitscan distance in studs
--   auto        true = holding the mouse keeps firing
--   wallCost    price on an Armory Rack, nil = crate only
--   crateWeight relative chance of rolling out of the Fate Crate, nil = never
--   explosive   { radius = studs, damage = n } area damage on impact
--   chain       { count = n, radius = studs, mult = n } arcs to nearby enemies
--   upgrade     the Overforge version (multipliers applied to the base stats)

local WeaponDefs = {}

WeaponDefs.StartingWeapon = "vesper45"

WeaponDefs.List = {
	{
		id = "vesper45",
		name = "Vesper .45",
		class = "Sidearm",
		damage = 45,
		headMult = 2.2,
		rpm = 380,
		mag = 12,
		reserve = 108,
		reloadTime = 1.35,
		spread = 0.9,
		pellets = 1,
		range = 320,
		auto = false,
		wallCost = 500,
		crateWeight = nil,
		body = { color = Color3.fromRGB(58, 58, 64), length = 1.5, bore = 0.22 },
		upgrade = {
			name = "Vesper Requiem",
			damageMult = 3.1,
			magMult = 1.6,
			reserveMult = 1.7,
			rpmMult = 1.15,
			spreadMult = 0.6,
			tint = Color3.fromRGB(120, 205, 255),
			explosive = { radius = 8, damage = 55 },
		},
	},
	{
		id = "scrapper",
		name = "Scrapper SMG",
		class = "SMG",
		damage = 30,
		headMult = 1.7,
		rpm = 820,
		mag = 32,
		reserve = 224,
		reloadTime = 1.9,
		spread = 2.6,
		pellets = 1,
		range = 260,
		auto = true,
		wallCost = 900,
		crateWeight = 10,
		body = { color = Color3.fromRGB(78, 74, 66), length = 1.9, bore = 0.24 },
		upgrade = {
			name = "Scrapper Shriek",
			damageMult = 2.9,
			magMult = 1.75,
			reserveMult = 1.8,
			rpmMult = 1.1,
			spreadMult = 0.7,
			tint = Color3.fromRGB(255, 150, 90),
		},
	},
	{
		id = "hornet",
		name = "Hornet PDW",
		class = "SMG",
		damage = 38,
		headMult = 1.8,
		rpm = 900,
		mag = 40,
		reserve = 280,
		reloadTime = 2.1,
		spread = 2.2,
		pellets = 1,
		range = 300,
		auto = true,
		wallCost = 1300,
		crateWeight = 10,
		body = { color = Color3.fromRGB(44, 48, 56), length = 2.1, bore = 0.24 },
		upgrade = {
			name = "Hornet Tempest",
			damageMult = 3.0,
			magMult = 1.8,
			reserveMult = 1.8,
			rpmMult = 1.12,
			spreadMult = 0.65,
			tint = Color3.fromRGB(255, 225, 90),
		},
	},
	{
		id = "ranger12",
		name = "Ranger 12",
		class = "Shotgun",
		damage = 34,
		headMult = 1.5,
		rpm = 78,
		mag = 6,
		reserve = 54,
		reloadTime = 2.9,
		spread = 6.5,
		pellets = 8,
		range = 90,
		auto = false,
		wallCost = 1500,
		crateWeight = 9,
		body = { color = Color3.fromRGB(96, 62, 42), length = 2.4, bore = 0.34 },
		upgrade = {
			name = "Ranger Cathedral",
			damageMult = 2.8,
			magMult = 1.65,
			reserveMult = 1.8,
			rpmMult = 1.25,
			spreadMult = 0.85,
			tint = Color3.fromRGB(255, 120, 120),
		},
	},
	{
		id = "cyclone",
		name = "Cyclone DMR",
		class = "Marksman",
		damage = 135,
		headMult = 2.4,
		rpm = 260,
		mag = 20,
		reserve = 140,
		reloadTime = 2.3,
		spread = 1.0,
		pellets = 1,
		range = 500,
		auto = false,
		wallCost = 1700,
		crateWeight = 9,
		body = { color = Color3.fromRGB(52, 60, 52), length = 2.8, bore = 0.26 },
		upgrade = {
			name = "Cyclone Verdict",
			damageMult = 3.0,
			magMult = 1.5,
			reserveMult = 1.7,
			rpmMult = 1.2,
			spreadMult = 0.5,
			tint = Color3.fromRGB(150, 255, 170),
		},
	},
	{
		id = "talon",
		name = "Talon AR",
		class = "Assault",
		damage = 62,
		headMult = 2.0,
		rpm = 640,
		mag = 30,
		reserve = 270,
		reloadTime = 2.2,
		spread = 1.8,
		pellets = 1,
		range = 420,
		auto = true,
		wallCost = 2000,
		crateWeight = 10,
		body = { color = Color3.fromRGB(38, 40, 44), length = 2.6, bore = 0.26 },
		upgrade = {
			name = "Talon Sovereign",
			damageMult = 3.0,
			magMult = 1.7,
			reserveMult = 1.8,
			rpmMult = 1.1,
			spreadMult = 0.6,
			tint = Color3.fromRGB(120, 180, 255),
		},
	},
	{
		id = "hailstorm",
		name = "Hailstorm Burst",
		class = "Assault",
		damage = 72,
		headMult = 2.1,
		rpm = 760,
		mag = 36,
		reserve = 288,
		reloadTime = 2.4,
		spread = 1.6,
		pellets = 1,
		range = 420,
		auto = true,
		wallCost = nil,
		crateWeight = 8,
		body = { color = Color3.fromRGB(70, 82, 96), length = 2.7, bore = 0.27 },
		upgrade = {
			name = "Hailstorm Sermon",
			damageMult = 3.1,
			magMult = 1.8,
			reserveMult = 1.8,
			rpmMult = 1.14,
			spreadMult = 0.6,
			tint = Color3.fromRGB(180, 230, 255),
		},
	},
	{
		id = "carnivore",
		name = "Carnivore Auto",
		class = "Shotgun",
		damage = 30,
		headMult = 1.5,
		rpm = 210,
		mag = 10,
		reserve = 80,
		reloadTime = 3.2,
		spread = 7.5,
		pellets = 7,
		range = 80,
		auto = true,
		wallCost = nil,
		crateWeight = 7,
		body = { color = Color3.fromRGB(84, 46, 46), length = 2.5, bore = 0.36 },
		upgrade = {
			name = "Carnivore Rapture",
			damageMult = 2.9,
			magMult = 1.8,
			reserveMult = 1.9,
			rpmMult = 1.2,
			spreadMult = 0.8,
			tint = Color3.fromRGB(255, 90, 140),
		},
	},
	{
		id = "reaper",
		name = "Reaper LMG",
		class = "LMG",
		damage = 88,
		headMult = 1.9,
		rpm = 700,
		mag = 100,
		reserve = 400,
		reloadTime = 4.4,
		spread = 2.6,
		pellets = 1,
		range = 420,
		auto = true,
		wallCost = nil,
		crateWeight = 6,
		body = { color = Color3.fromRGB(46, 44, 40), length = 3.1, bore = 0.3 },
		upgrade = {
			name = "Reaper Doctrine",
			damageMult = 3.2,
			magMult = 1.5,
			reserveMult = 1.8,
			rpmMult = 1.1,
			spreadMult = 0.6,
			tint = Color3.fromRGB(200, 120, 255),
		},
	},
	{
		id = "longbarrow",
		name = "Longbarrow LR",
		class = "Sniper",
		damage = 520,
		headMult = 3.0,
		rpm = 48,
		mag = 5,
		reserve = 45,
		reloadTime = 3.0,
		spread = 0.4,
		pellets = 1,
		range = 900,
		auto = false,
		wallCost = nil,
		crateWeight = 6,
		pierce = 3,
		body = { color = Color3.fromRGB(60, 56, 48), length = 3.6, bore = 0.28 },
		upgrade = {
			name = "Longbarrow Elegy",
			damageMult = 3.4,
			magMult = 2.0,
			reserveMult = 2.0,
			rpmMult = 1.3,
			spreadMult = 0.5,
			tint = Color3.fromRGB(255, 240, 160),
			pierce = 6,
		},
	},
	{
		id = "infernotube",
		name = "Inferno Tube",
		class = "Launcher",
		damage = 240,
		headMult = 1.0,
		rpm = 40,
		mag = 2,
		reserve = 16,
		reloadTime = 3.6,
		spread = 0.6,
		pellets = 1,
		range = 500,
		auto = false,
		wallCost = nil,
		crateWeight = 4,
		explosive = { radius = 18, damage = 600 },
		body = { color = Color3.fromRGB(88, 72, 40), length = 3.4, bore = 0.55 },
		upgrade = {
			name = "Inferno Requiem",
			damageMult = 2.4,
			magMult = 2.0,
			reserveMult = 2.0,
			rpmMult = 1.4,
			spreadMult = 1.0,
			tint = Color3.fromRGB(255, 130, 40),
			explosive = { radius = 28, damage = 1800 },
		},
	},
	{
		id = "arcbolt",
		name = "Arcbolt Lance",
		class = "Anomaly",
		damage = 420,
		headMult = 1.6,
		rpm = 150,
		mag = 18,
		reserve = 108,
		reloadTime = 2.8,
		spread = 0.8,
		pellets = 1,
		range = 400,
		auto = true,
		wallCost = nil,
		crateWeight = 3,
		tracerColor = Color3.fromRGB(140, 230, 255),
		chain = { count = 4, radius = 22, mult = 0.65 },
		body = { color = Color3.fromRGB(40, 70, 90), length = 3.0, bore = 0.4 },
		upgrade = {
			name = "Arcbolt Ascendant",
			damageMult = 2.6,
			magMult = 1.7,
			reserveMult = 1.8,
			rpmMult = 1.2,
			spreadMult = 0.5,
			tint = Color3.fromRGB(180, 250, 255),
			chain = { count = 8, radius = 30, mult = 0.8 },
		},
	},
}

local byId = {}
for _, def in ipairs(WeaponDefs.List) do
	byId[def.id] = def
end

function WeaponDefs.get(id)
	return byId[id]
end

function WeaponDefs.cratePool()
	local pool = {}
	for _, def in ipairs(WeaponDefs.List) do
		if def.crateWeight then
			table.insert(pool, { value = def.id, weight = def.crateWeight })
		end
	end
	return pool
end

-- Builds the runtime instance of a weapon that gets stored on a player's loadout.
function WeaponDefs.makeInstance(id, upgraded)
	local def = byId[id]
	if not def then return nil end

	local inst = {
		id = def.id,
		name = def.name,
		class = def.class,
		upgraded = false,
		damage = def.damage,
		headMult = def.headMult,
		rpm = def.rpm,
		mag = def.mag,
		reserve = def.reserve,
		ammo = def.mag,
		spare = def.reserve,
		reloadTime = def.reloadTime,
		spread = def.spread,
		pellets = def.pellets,
		range = def.range,
		auto = def.auto,
		pierce = def.pierce or 0,
		explosive = def.explosive,
		chain = def.chain,
		tracerColor = def.tracerColor,
	}

	if upgraded and def.upgrade then
		local up = def.upgrade
		inst.upgraded = true
		inst.name = up.name
		inst.damage = math.floor(def.damage * (up.damageMult or 2.5))
		inst.rpm = math.floor(def.rpm * (up.rpmMult or 1))
		inst.mag = math.floor(def.mag * (up.magMult or 1.5))
		inst.reserve = math.floor(def.reserve * (up.reserveMult or 1.5))
		inst.ammo = inst.mag
		inst.spare = inst.reserve
		inst.spread = def.spread * (up.spreadMult or 0.7)
		inst.pierce = up.pierce or def.pierce or 0
		inst.explosive = up.explosive or def.explosive
		inst.chain = up.chain or def.chain
		inst.tracerColor = up.tint or def.tracerColor
	end

	return inst
end

-- The stat block the HUD shows, trimmed of server-only bookkeeping.
function WeaponDefs.publicState(inst)
	if not inst then return nil end
	return {
		id = inst.id,
		name = inst.name,
		class = inst.class,
		upgraded = inst.upgraded,
		ammo = inst.ammo,
		mag = inst.mag,
		spare = inst.spare,
		rpm = inst.rpm,
		auto = inst.auto,
		reloadTime = inst.reloadTime,
		spread = inst.spread,
		pellets = inst.pellets,
		range = inst.range,
		tracerColor = inst.tracerColor,
	}
end

return WeaponDefs
