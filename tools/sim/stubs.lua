-- Minimal Roblox API stand-in so the game's Lua can be executed off-platform.
-- Only the surface the modules actually touch is implemented; anything else is a
-- permissive no-op so that requiring a module never explodes for the wrong reason.

-- Luau extensions that Lua 5.3 does not have ---------------------------------
if not math.clamp then
	function math.clamp(n, lo, hi)
		if n < lo then return lo end
		if n > hi then return hi end
		return n
	end
end
if not math.pow then
	function math.pow(a, b)
		return a ^ b
	end
end
if not table.find then
	function table.find(haystack, needle)
		for index, value in ipairs(haystack) do
			if value == needle then return index end
		end
		return nil
	end
end

-- Vector3 / Vector2 ----------------------------------------------------------
local Vector3mt = {}
Vector3mt.__index = Vector3mt

local function v3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3mt)
end

Vector3mt.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
Vector3mt.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
Vector3mt.__unm = function(a) return v3(-a.X, -a.Y, -a.Z) end
Vector3mt.__mul = function(a, b)
	if type(a) == "number" then return v3(b.X * a, b.Y * a, b.Z * a) end
	if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3mt.__div = function(a, b)
	if type(b) == "number" then return v3(a.X / b, a.Y / b, a.Z / b) end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
Vector3mt.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
Vector3mt.__tostring = function(a) return string.format("(%.2f, %.2f, %.2f)", a.X, a.Y, a.Z) end
function Vector3mt.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function Vector3mt.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
Vector3mt.__newindex = function(t, k, value) rawset(t, k, value) end

local rawIndex = Vector3mt.__index
Vector3mt.__index = function(t, k)
	if k == "Magnitude" then
		return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
	elseif k == "Unit" then
		local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
		if m == 0 then return v3(0, 0, 0) end
		return v3(t.X / m, t.Y / m, t.Z / m)
	end
	return rawIndex[k]
end

Vector3 = { new = v3, zero = v3(0, 0, 0), one = v3(1, 1, 1) }
local Vector2mt = {}
local function v2(x, y)
	return setmetatable({ X = x or 0, Y = y or 0 }, Vector2mt)
end
Vector2mt.__add = function(a, b) return v2(a.X + b.X, a.Y + b.Y) end
Vector2mt.__sub = function(a, b) return v2(a.X - b.X, a.Y - b.Y) end
Vector2mt.__mul = function(a, b)
	if type(a) == "number" then return v2(b.X * a, b.Y * a) end
	if type(b) == "number" then return v2(a.X * b, a.Y * b) end
	return v2(a.X * b.X, a.Y * b.Y)
end
Vector2mt.__index = function(t, k)
	if k == "Magnitude" then
		return math.sqrt(t.X * t.X + t.Y * t.Y)
	elseif k == "Unit" then
		local m = math.sqrt(t.X * t.X + t.Y * t.Y)
		if m == 0 then return v2(0, 0) end
		return v2(t.X / m, t.Y / m)
	end
	return nil
end
Vector2 = { new = v2, zero = v2(0, 0) }

-- Colors, UDim, CFrame -------------------------------------------------------
local function color(r, g, b)
	return { R = r, G = g, B = b }
end
Color3 = {
	new = function(r, g, b) return color(r or 0, g or 0, b or 0) end,
	fromRGB = function(r, g, b) return color((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end,
	fromHSV = function() return color(1, 1, 1) end,
}
UDim = { new = function(s, o) return { Scale = s, Offset = o } end }
UDim2 = {
	new = function(sx, ox, sy, oy) return { X = { Scale = sx, Offset = ox }, Y = { Scale = sy, Offset = oy } } end,
	fromScale = function(sx, sy) return UDim2.new(sx, 0, sy, 0) end,
	fromOffset = function(ox, oy) return UDim2.new(0, ox, 0, oy) end,
}
NumberRange = { new = function(a, b) return { Min = a, Max = b or a } end }
NumberSequenceKeypoint = { new = function(t, v) return { Time = t, Value = v } end }
NumberSequence = { new = function(v) return { Value = v } end }
ColorSequence = { new = function(a, b) return { From = a, To = b } end }
Rect = { new = function() return {} end }
Font = { new = function() return {} end }

local CFramemt = {}
CFramemt.__index = CFramemt
local function cframe(position, look)
	return setmetatable({ Position = position or v3(), LookVector = look or v3(0, 0, -1) }, CFramemt)
end
CFramemt.__mul = function(a, b)
	if getmetatable(b) == Vector3mt then
		return b
	end
	return a
end
CFrame = {
	new = function(x, y, z)
		if type(x) == "number" then return cframe(v3(x, y, z)) end
		return cframe(x or v3())
	end,
	lookAt = function(from, to)
		local delta = to - from
		return cframe(from, delta.Magnitude > 0 and delta.Unit or v3(0, 0, -1))
	end,
	Angles = function() return cframe() end,
	fromEulerAnglesXYZ = function() return cframe() end,
	identity = cframe(),
}

-- Enum: every Enum.Foo.Bar resolves to a stable sentinel --------------------
local enumItemCache = {}
Enum = setmetatable({}, {
	__index = function(_, enumName)
		local group = enumItemCache[enumName]
		if not group then
			group = setmetatable({}, {
				__index = function(selfGroup, itemName)
					local item = { EnumType = enumName, Name = itemName, Value = 0 }
					rawset(selfGroup, itemName, item)
					return item
				end,
			})
			enumItemCache[enumName] = group
		end
		return group
	end,
})

-- Random ---------------------------------------------------------------------
Random = {
	new = function(seed)
		local state = { seed = seed or 0 }
		function state:NextNumber(a, b)
			local value = math.random()
			if a and b then return a + (b - a) * value end
			return value
		end
		function state:NextInteger(a, b)
			return math.random(a, b)
		end
		function state:Clone()
			return Random.new(self.seed)
		end
		return state
	end,
}

-- task / Debris style scheduling (immediate, no real clock) -----------------
local scheduled = {}
task = {
	spawn = function(fn, ...) return fn(...) end,
	defer = function(fn, ...)
		table.insert(scheduled, { fn = fn, args = { ... } })
	end,
	delay = function(_, fn, ...)
		table.insert(scheduled, { fn = fn, args = { ... } })
		return { cancelled = false }
	end,
	wait = function() return 0 end,
	cancel = function() end,
}
function SIM_FLUSH()
	local count = 0
	while #scheduled > 0 and count < 500 do
		local job = table.remove(scheduled, 1)
		job.fn(table.unpack(job.args))
		count = count + 1
	end
	return count
end
function wait() return 0 end
function typeof(value)
	local mt = getmetatable(value)
	if mt == Vector3mt then return "Vector3" end
	if mt == CFramemt then return "CFrame" end
	return type(value)
end
function tick() return os.clock() end
function warn(...)
	local parts = {}
	for _, value in ipairs({ ... }) do
		table.insert(parts, tostring(value))
	end
	print("[warn] " .. table.concat(parts, " "))
end

-- Instances ------------------------------------------------------------------
local Instancemt = {}
Instancemt.__index = function(t, key)
	if key == "Parent" then
		return rawget(t, "__parent")
	end
	local children = rawget(t, "__children")
	if children and children[key] then return children[key] end
	local class = rawget(t, "__api")
	if class and class[key] then return class[key] end
	return nil
end
Instancemt.__newindex = function(t, key, value)
	if key == "Parent" then
		rawset(t, "__parent", value)
		if value and rawget(value, "__children") then
			rawget(value, "__children")[rawget(t, "Name") or "?"] = t
			table.insert(rawget(value, "__order"), t)
		end
		return
	end
	rawset(t, key, value)
end

local InstanceApi = {}

function InstanceApi:FindFirstChild(name)
	return rawget(self, "__children")[name]
end
function InstanceApi:WaitForChild(name)
	return rawget(self, "__children")[name]
end
function InstanceApi:GetChildren()
	local out = {}
	for _, child in ipairs(rawget(self, "__order")) do
		table.insert(out, child)
	end
	return out
end
function InstanceApi:GetDescendants()
	local out = {}
	for _, child in ipairs(rawget(self, "__order")) do
		table.insert(out, child)
		for _, sub in ipairs(child:GetDescendants()) do
			table.insert(out, sub)
		end
	end
	return out
end
function InstanceApi:FindFirstChildOfClass(className)
	for _, child in ipairs(rawget(self, "__order")) do
		if rawget(child, "ClassName") == className then return child end
	end
	return nil
end
function InstanceApi:IsA(className)
	return rawget(self, "ClassName") == className
end
function InstanceApi:Destroy()
	local parent = rawget(self, "__parent")
	if parent then
		rawget(parent, "__children")[rawget(self, "Name")] = nil
	end
end
function InstanceApi:Clone()
	return self
end
function InstanceApi:SetAttribute(name, value)
	rawget(self, "__attributes")[name] = value
end
function InstanceApi:GetAttribute(name)
	return rawget(self, "__attributes")[name]
end
function InstanceApi:GetPropertyChangedSignal(property)
	return newSignal(self, "Changed:" .. tostring(property))
end
function InstanceApi:LoadCharacter() end
function InstanceApi:SetStateEnabled() end
function InstanceApi:ChangeState() end
function InstanceApi:MoveTo() end
function InstanceApi:PivotTo() end
function InstanceApi:GetPivot() return CFrame.identity end
function InstanceApi:Play() end
function InstanceApi:Emit() end
function InstanceApi:Connect(fn)
	if type(fn) ~= "function" then
		error("Connect expects a function, got " .. type(fn), 0)
	end
	return { Disconnect = function() end, Connected = true }
end

local signalNames = {
	"Triggered", "PlayerAdded", "PlayerRemoving", "CharacterAdded", "Died", "Heartbeat",
	"RenderStepped", "Stepped", "OnServerEvent", "OnClientEvent", "Changed", "Touched",
	"InputBegan", "InputEnded", "InputChanged", "PromptShown", "Completed",
}

local function newSignal(owner, name)
	local connections = {}
	local signal = { __connections = connections, __name = name }
	signal.Connect = function(_, fn)
		if type(fn) ~= "function" then
			error("Connect expects a function for " .. tostring(name) .. ", got " .. type(fn), 0)
		end
		table.insert(connections, fn)
		return { Disconnect = function() end, Connected = true }
	end
	signal.Once = signal.Connect
	signal.Wait = function() return nil end
	return signal
end

-- Invokes everything connected to one signal, so per-frame and input code can be
-- exercised instead of merely registered.
function SIM_FIRE(instance, signalName, ...)
	local signal = rawget(instance, signalName)
	if not signal or not signal.__connections then
		error("no signal " .. tostring(signalName) .. " to fire")
	end
	local fired = 0
	for _, fn in ipairs(signal.__connections) do
		fn(...)
		fired = fired + 1
	end
	return fired
end

local function newInstance(className, name)
	local inst = setmetatable({}, Instancemt)
	rawset(inst, "ClassName", className)
	rawset(inst, "Name", name or className)
	rawset(inst, "__children", {})
	rawset(inst, "__order", {})
	rawset(inst, "__attributes", {})
	rawset(inst, "__api", InstanceApi)
	for _, signal in ipairs(signalNames) do
		rawset(inst, signal, newSignal(inst, signal))
	end
	rawset(inst, "FireClient", function() end)
	rawset(inst, "FireAllClients", function() end)
	rawset(inst, "FireServer", function() end)
	return inst
end

Instance = {
	new = function(className, parent)
		local inst = newInstance(className)
		if parent then inst.Parent = parent end
		return inst
	end,
}

-- game / services ------------------------------------------------------------
local services = {}
local function service(name)
	if not services[name] then
		services[name] = newInstance(name, name)
	end
	return services[name]
end

local Players = service("Players")
rawset(Players, "GetPlayers", function() return {} end)
rawset(Players, "RespawnTime", 4)
rawset(Players, "CharacterAutoLoads", true)

local RunService = service("RunService")
rawset(RunService, "IsServer", function() return true end)
rawset(RunService, "IsClient", function() return false end)
rawset(RunService, "BindToRenderStep", function() end)

local PathfindingService = service("PathfindingService")
rawset(PathfindingService, "CreatePath", function()
	local path = newInstance("Path")
	rawset(path, "ComputeAsync", function() end)
	rawset(path, "Status", Enum.PathStatus.NoPath)
	rawset(path, "GetWaypoints", function() return {} end)
	return path
end)

local TweenService = service("TweenService")
rawset(TweenService, "Create", function()
	return { Play = function() end, Cancel = function() end, Completed = { Connect = function() end } }
end)
TweenInfo = { new = function() return {} end }

local Debris = service("Debris")
rawset(Debris, "AddItem", function() end)

service("ReplicatedStorage")
service("ServerScriptService")
service("Lighting")
service("SoundService")
service("UserInputService")
service("StarterGui")
service("StarterPlayer")

game = {
	GetService = function(_, name) return service(name) end,
	Players = Players,
}
workspace = newInstance("Workspace", "Workspace")
rawset(workspace, "Raycast", function() return nil end)
rawset(workspace, "GetServerTimeNow", function() return os.clock() end)
local camera = newInstance("Camera", "Camera")
rawset(camera, "ViewportSize", Vector2.new(1920, 1080))
rawset(camera, "CFrame", CFrame.new(Vector3.new(0, 6, 24)))
rawset(camera, "ViewportPointToRay", function(_, x, y)
	return { Origin = Vector3.new(0, 6, 24), Direction = Vector3.new(0, 0, -1) }
end)
rawset(workspace, "CurrentCamera", camera)
RaycastParams = { new = function() return {} end }
OverlapParams = { new = function() return {} end }

-- Module loader: mirrors the real instance tree ------------------------------
local loaded = {}
local sourceByInstance = setmetatable({}, { __mode = "k" })

local function ensurePath(root, segments, isModule, source)
	local current = root
	for index, segment in ipairs(segments) do
		local isLast = index == #segments
		local child = rawget(current, "__children")[segment]
		if not child then
			child = newInstance(isLast and isModule and "ModuleScript" or "Folder", segment)
			child.Parent = current
		end
		if isLast and isModule then
			rawset(child, "ClassName", "ModuleScript")
			sourceByInstance[child] = source
		end
		current = child
	end
	return current
end

function SIM_MOUNT(sources)
	for pathKey, source in pairs(sources) do
		local segments = {}
		for part in string.gmatch(pathKey, "[^/]+") do
			table.insert(segments, part)
		end
		local serviceName = table.remove(segments, 1)
		ensurePath(service(serviceName), segments, true, source)
	end
end

function require(target)
	if type(target) == "string" then
		error("string requires are not supported in the simulator: " .. target)
	end
	if loaded[target] then return loaded[target] end
	local source = sourceByInstance[target]
	if not source then
		error("no source mounted for instance " .. tostring(target and rawget(target, "Name")))
	end
	local chunk, err = load(source, "@" .. rawget(target, "Name"))
	if not chunk then
		error("compile failed for " .. rawget(target, "Name") .. ": " .. tostring(err))
	end
	local env = _ENV
	local result = chunk()
	loaded[target] = result == nil and true or result
	return loaded[target]
end

function SIM_SERVICE(name)
	return service(name)
end

-- Scripts and LocalScripts are not requireable, so they are run directly with a
-- `script` global pointing at where they would live in the tree.
function SIM_RUN_SCRIPT(source, name, scriptInstance)
	local chunk, err = load(source, "@" .. name)
	if not chunk then
		error("compile failed for " .. name .. ": " .. tostring(err), 0)
	end
	local previous = script
	script = scriptInstance
	local ok, runErr = pcall(chunk)
	script = previous
	if not ok then
		error(runErr, 0)
	end
	return true
end
