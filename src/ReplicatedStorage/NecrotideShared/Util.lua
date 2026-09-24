-- Util: tiny shared helpers. No state, safe to require from client or server.

local Players = game:GetService("Players")

local Util = {}

function Util.clamp(n, lo, hi)
	if n < lo then return lo end
	if n > hi then return hi end
	return n
end

function Util.lerp(a, b, t)
	return a + (b - a) * t
end

-- Comma-separates a number for HUD display: 12400 -> "12,400"
function Util.comma(n)
	local s = tostring(math.floor(n))
	local out = ""
	local count = 0
	for i = #s, 1, -1 do
		out = s:sub(i, i) .. out
		count = count + 1
		if count % 3 == 0 and i > 1 then
			out = "," .. out
		end
	end
	return out
end

function Util.formatTime(seconds)
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

-- Weighted pick from { {value = x, weight = n}, ... }
function Util.weightedPick(entries, rng)
	local total = 0
	for _, entry in ipairs(entries) do
		total = total + (entry.weight or 1)
	end
	if total <= 0 then return nil end
	local roll = (rng and rng:NextNumber() or math.random()) * total
	local acc = 0
	for _, entry in ipairs(entries) do
		acc = acc + (entry.weight or 1)
		if roll <= acc then
			return entry.value
		end
	end
	return entries[#entries].value
end

function Util.shallowCopy(tbl)
	local out = {}
	for k, v in pairs(tbl) do
		out[k] = v
	end
	return out
end

function Util.deepCopy(tbl)
	local out = {}
	for k, v in pairs(tbl) do
		if type(v) == "table" then
			out[k] = Util.deepCopy(v)
		else
			out[k] = v
		end
	end
	return out
end

function Util.randomFlatOffset(radius)
	local angle = math.random() * math.pi * 2
	local dist = math.sqrt(math.random()) * radius
	return Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
end

-- Every player who is alive, standing and targetable by the horde.
function Util.activeTargets()
	local out = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			local root = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 and player:GetAttribute("Downed") ~= true then
				table.insert(out, {
					player = player,
					character = character,
					root = root,
					humanoid = humanoid,
				})
			end
		end
	end
	return out
end

-- Downed players still exist as targets of last resort so enemies do not idle.
function Util.anyLivingCharacters()
	local out = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and (character.PrimaryPart or character:FindFirstChild("HumanoidRootPart"))
		if humanoid and root and humanoid.Health > 0 then
			table.insert(out, { player = player, character = character, root = root, humanoid = humanoid })
		end
	end
	return out
end

return Util
