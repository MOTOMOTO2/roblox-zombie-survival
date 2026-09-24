-- TonicDefs: the buyable permanent buffs ("Tonics"), dispensed by Tonic Stills
-- placed around the Ashvault. Original names and effects.

local TonicDefs = {}

TonicDefs.List = {
	{
		id = "ironhide",
		name = "Ironhide Draught",
		blurb = "+120 max vitality",
		cost = 2500,
		color = Color3.fromRGB(220, 80, 60),
		effects = { bonusHealth = 120 },
	},
	{
		id = "quickhands",
		name = "Quickhands Tincture",
		blurb = "Reload 55% faster",
		cost = 2000,
		color = Color3.fromRGB(240, 200, 70),
		effects = { reloadScale = 0.45 },
	},
	{
		id = "deadeye",
		name = "Deadeye Elixir",
		blurb = "+25% weapon damage",
		cost = 3000,
		color = Color3.fromRGB(120, 200, 255),
		effects = { damageMult = 1.25 },
	},
	{
		id = "fleetfoot",
		name = "Fleetfoot Serum",
		blurb = "+22% sprint speed",
		cost = 1800,
		color = Color3.fromRGB(120, 240, 160),
		effects = { speedMult = 1.22 },
	},
	{
		id = "scavenger",
		name = "Scavenger Brew",
		blurb = "+35% salvage earned",
		cost = 2200,
		color = Color3.fromRGB(190, 140, 255),
		effects = { salvageMult = 1.35 },
	},
	{
		id = "secondwind",
		name = "Second Wind Phial",
		blurb = "Revive yourself once per wave",
		cost = 3500,
		color = Color3.fromRGB(255, 255, 255),
		effects = { selfRevive = true },
	},
}

local byId = {}
for _, def in ipairs(TonicDefs.List) do
	byId[def.id] = def
end

function TonicDefs.get(id)
	return byId[id]
end

-- Collapses a player's owned tonic ids into one multiplier table.
function TonicDefs.aggregate(owned)
	local agg = {
		bonusHealth = 0,
		reloadScale = 1,
		damageMult = 1,
		speedMult = 1,
		salvageMult = 1,
		selfRevive = false,
	}
	for id, has in pairs(owned or {}) do
		local def = has and byId[id]
		if def then
			local e = def.effects
			agg.bonusHealth = agg.bonusHealth + (e.bonusHealth or 0)
			agg.reloadScale = agg.reloadScale * (e.reloadScale or 1)
			agg.damageMult = agg.damageMult * (e.damageMult or 1)
			agg.speedMult = agg.speedMult * (e.speedMult or 1)
			agg.salvageMult = agg.salvageMult * (e.salvageMult or 1)
			if e.selfRevive then
				agg.selfRevive = true
			end
		end
	end
	return agg
end

return TonicDefs
