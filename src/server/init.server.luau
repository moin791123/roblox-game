-- 서버 시작점: 모든 서비스를 켜고 연결해요. (설계: docs/DESIGN.md)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local WorldBuilder = require(script.WorldBuilder)
local DataService = require(script.DataService)
local PlotService = require(script.PlotService)
local FollowService = require(script.FollowService)
local ConveyorService = require(script.ConveyorService)
local CarryService = require(script.CarryService)
local CoinFieldService = require(script.CoinFieldService)

WorldBuilder.Build()

PlotService.Callbacks.OnStealPrompt = CarryService.StartSteal

DataService.Start()
PlotService.Start()
FollowService.Start()
ConveyorService.Start()
CarryService.Start()
CoinFieldService.Start()

local function onCharacterAdded(player: Player, character: Model)
	character:WaitForChild("HumanoidRootPart", 10)
	if player.Parent == nil then
		return
	end
	PlotService.OnCharacterAdded(player, character)
	FollowService.UpdateSpeed(player)
	-- 기지로 텔레포트가 끝난 뒤에 펫을 불러야 맵을 가로질러 끌려오지 않음
	task.delay(0.4, function()
		if player.Parent and player.Character == character then
			FollowService.Refresh(player)
		end
	end)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		-- 데이터가 아직 없으면 로딩이 끝난 뒤 아래에서 처리
		if DataService.Get(player) then
			onCharacterAdded(player, character)
		end
	end)

	local data = DataService.Load(player)
	if not data or player.Parent == nil then
		return
	end

	PlotService.AssignPlot(player)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
	DataService.Sync(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	-- 앞 단계에서 오류가 나도 저장(Release)은 반드시 실행
	for _, fn in { CarryService.OnPlayerRemoving, FollowService.Clear, PlotService.ReleasePlot } do
		local ok, err = pcall(fn, player)
		if not ok then
			warn("[Server] PlayerRemoving 처리 오류:", err)
		end
	end
	DataService.Release(player)
end)

Remotes.RequestSync.OnServerEvent:Connect(function(player)
	if DataService.Get(player) then
		DataService.Sync(player)
	end
end)

game:BindToClose(function()
	local ok, err = pcall(CarryService.ReturnAll)
	if not ok then
		warn("[Server] ReturnAll 오류:", err)
	end
	DataService.SaveAll()
end)
