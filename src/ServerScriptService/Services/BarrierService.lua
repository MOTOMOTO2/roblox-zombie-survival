-- BarrierService: the boarded gaps in the perimeter wall. Enemies claw the boards
-- off one at a time to get in; players hold E to nail them back on for salvage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("NecrotideShared")
local GameConfig = require(Shared.GameConfig)
local Net = require(Shared.Net)

local BarrierService = {}
local S

local function boardState(barrier)
	if not barrier.state then
		barrier.state = {
			intact = {},
			tearProgress = 0,
			repairing = false,
		}
		for index, board in ipairs(barrier.boards) do
			barrier.state.intact[index] = true
			board:SetAttribute("HomePos", board.Position)
			board:SetAttribute("HomeSize", board.Size)
		end
	end
	return barrier.state
end

local function intactCount(barrier)
	local state = boardState(barrier)
	local count = 0
	for _, isIntact in pairs(state.intact) do
		if isIntact then count = count + 1 end
	end
	return count
end

local function setBoardVisible(board, visible)
	if visible then
		board.Transparency = 0
		board.CanCollide = true
	else
		board.Transparency = 1
		board.CanCollide = false
	end
end

local function updatePrompt(barrier)
	local prompt = barrier.prompt
	if not prompt then return end
	local missing = #barrier.boards - intactCount(barrier)
	prompt.Enabled = missing > 0
	prompt.ObjectText = "BARRICADE  " .. intactCount(barrier) .. "/" .. #barrier.boards
end

function BarrierService.isOpen(barrier)
	return intactCount(barrier) == 0
end

-- Rips a board loose. Called every tick by an enemy pressed against the gap.
function BarrierService.tear(barrier, dt, entity)
	local state = boardState(barrier)
	state.tearProgress = state.tearProgress + dt
	local tearTime = GameConfig.BoardTearTime
	if state.tearProgress < tearTime then
		-- rattle the topmost intact board so the players can see it going
		for index = #barrier.boards, 1, -1 do
			if state.intact[index] then
				local board = barrier.boards[index]
				local home = board:GetAttribute("HomePos")
				if home then
					local jitter = Vector3.new((math.random() - 0.5) * 0.5, (math.random() - 0.5) * 0.3, (math.random() - 0.5) * 0.5)
					board.Position = home + jitter
				end
				break
			end
		end
		return false
	end

	state.tearProgress = 0
	for index = #barrier.boards, 1, -1 do
		if state.intact[index] then
			state.intact[index] = false
			local board = barrier.boards[index]
			setBoardVisible(board, false)

			-- a loose plank spins away from the gap
			local debris = board:Clone()
			debris.Name = "LoosePlank"
			debris.Transparency = 0
			debris.CanCollide = false
			debris.Anchored = false
			debris.Parent = S.Map.fxFolder
			debris.AssemblyLinearVelocity = barrier.inward * 22 + Vector3.new(0, 14, 0)
			debris.AssemblyAngularVelocity = Vector3.new(math.random() * 12, math.random() * 12, math.random() * 12)
			game:GetService("Debris"):AddItem(debris, 4)
			break
		end
	end
	updatePrompt(barrier)
	return intactCount(barrier) == 0
end

-- Bosses do not bother with carpentry.
function BarrierService.smash(barrier)
	local state = boardState(barrier)
	for index, board in ipairs(barrier.boards) do
		if state.intact[index] then
			state.intact[index] = false
			setBoardVisible(board, false)
		end
	end
	state.tearProgress = 0
	updatePrompt(barrier)
end

function BarrierService.repairOne(barrier, player)
	local state = boardState(barrier)
	for index, board in ipairs(barrier.boards) do
		if not state.intact[index] then
			state.intact[index] = true
			local home = board:GetAttribute("HomePos")
			if home then
				board.Position = home
			end
			setBoardVisible(board, true)
			local homeSize = board:GetAttribute("HomeSize") or board.Size
			board.Size = homeSize * 0.6
			TweenService:Create(board, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = homeSize,
			}):Play()
			updatePrompt(barrier)
			if player then
				local gained = S.Economy.add(player, GameConfig.SalvagePerBoardRepair)
				Net.get("Notify"):FireClient(player, {
					text = "Board replaced  +" .. gained,
					color = { 200, 170, 120 },
				})
			end
			return true
		end
	end
	return false
end

function BarrierService.resetAll()
	for _, barrier in ipairs(S.Map.barriers) do
		local state = boardState(barrier)
		state.tearProgress = 0
		for index, board in ipairs(barrier.boards) do
			state.intact[index] = true
			local home = board:GetAttribute("HomePos")
			if home then
				board.Position = home
			end
			setBoardVisible(board, true)
		end
		updatePrompt(barrier)
	end
end

function BarrierService.init(services)
	S = services
	for _, barrier in ipairs(S.Map.barriers) do
		boardState(barrier)

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RepairPrompt"
		prompt.ActionText = "Repair Barricade"
		prompt.ObjectText = "BARRICADE"
		prompt.HoldDuration = GameConfig.BoardRepairTime
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Enabled = false
		prompt.Parent = barrier.promptAnchor
		barrier.prompt = prompt

		prompt.Triggered:Connect(function(player)
			if S.PlayerService.isDowned(player) or S.PlayerService.isOut(player) then return end
			BarrierService.repairOne(barrier, player)
		end)

		updatePrompt(barrier)
	end
end

return BarrierService
