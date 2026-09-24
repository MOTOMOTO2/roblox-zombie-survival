-- PowerupDefs: the floating pickups the horde sometimes drops. Team-wide effects.

local PowerupDefs = {}

PowerupDefs.List = {
	{
		id = "purge",
		name = "PURGE PULSE",
		blurb = "The horde is erased",
		weight = 14,
		color = Color3.fromRGB(255, 240, 120),
		duration = 0,
	},
	{
		id = "resupply",
		name = "RESUPPLY CACHE",
		blurb = "Ammo restored",
		weight = 26,
		color = Color3.fromRGB(120, 200, 255),
		duration = 0,
	},
	{
		id = "culling",
		name = "CULLING HOUR",
		blurb = "One touch kills",
		weight = 18,
		color = Color3.fromRGB(255, 90, 90),
		duration = 25,
	},
	{
		id = "surge",
		name = "SALVAGE SURGE",
		blurb = "Double salvage",
		weight = 26,
		color = Color3.fromRGB(150, 255, 150),
		duration = 30,
	},
	{
		id = "mend",
		name = "FIELD MEND",
		blurb = "Squad healed and lifted",
		weight = 16,
		color = Color3.fromRGB(255, 255, 255),
		duration = 0,
	},
}

local byId = {}
for _, def in ipairs(PowerupDefs.List) do
	byId[def.id] = def
end

function PowerupDefs.get(id)
	return byId[id]
end

function PowerupDefs.pool()
	local pool = {}
	for _, def in ipairs(PowerupDefs.List) do
		table.insert(pool, { value = def.id, weight = def.weight })
	end
	return pool
end

return PowerupDefs
