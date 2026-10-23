-- 서버 시작점: 모든 서비스를 켜고 연결해요. (설계: docs/DESIGN.md "init.server.luau")
-- 한 모듈이 고장 나도 게임 전체가 멈추지 않도록 불러오기(require)와 Start 를 하나씩 pcall 로 감싸요.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

-- 핵심 모듈 (없으면 게임이 안 돼요)
local DataService = require(script.DataService)
local PassService = require(script.PassService) -- ★v7.2 게임 패스 (🧲 / ⚡ / 🏦)
local PlotService = require(script.PlotService)
local FollowService = require(script.FollowService)

-- 고장 나도 괜찮게 불러와요 (실패하면 nil + 경고)
local function tryRequire(name: string): any
	local mod = script:FindFirstChild(name)
	if not (mod and mod:IsA("ModuleScript")) then
		warn("[Server] 모듈이 없어요:", name)
		return nil
	end
	local ok, result = pcall(require, mod)
	if not ok then
		warn("[Server] 모듈 불러오기 오류:", name, result)
		return nil
	end
	return result
end

local WorldBuilder: typeof(require(script.WorldBuilder))? = tryRequire("WorldBuilder")
local ConveyorService: typeof(require(script.ConveyorService))? = tryRequire("ConveyorService")
local CoinFieldService: typeof(require(script.CoinFieldService))? = tryRequire("CoinFieldService")
local ZoneService: typeof(require(script.ZoneService))? = tryRequire("ZoneService")
local ShopService: typeof(require(script.ShopService))? = tryRequire("ShopService")
local LeaderboardService: typeof(require(script.LeaderboardService))? = tryRequire("LeaderboardService")
local AdminService: typeof(require(script.AdminService))? = tryRequire("AdminService") -- ★v7.4 🛠 관리자 페이지

-- 하나씩 켜요. 오류가 나면 경고만 하고 다음 모듈로
local function start(name: string, fn: (() -> ())?)
	if not fn then
		warn("[Server] " .. name .. " 을(를) 켤 수 없어요 (모듈 없음)")
		return
	end
	local ok, err = pcall(fn)
	if not ok then
		warn("[Server] " .. name .. " 시작 오류:", err)
	end
end

-- 순서: 월드 → 데이터 → 게임 패스 → 집 → 따라오는 펫 → 컨베이어 → 들판 코인 → 지역 → 상점 → 순위표 → 관리자
start("WorldBuilder.Build", WorldBuilder and WorldBuilder.Build)
start("DataService", DataService.Start)
start("PassService", PassService.Start)
start("PlotService", PlotService.Start)
start("FollowService", FollowService.Start)
start("ConveyorService", ConveyorService and ConveyorService.Start)
start("CoinFieldService", CoinFieldService and CoinFieldService.Start)
start("ZoneService", ZoneService and ZoneService.Start)
start("ShopService", ShopService and ShopService.Start)
start("LeaderboardService", LeaderboardService and LeaderboardService.Start)
start("AdminService", AdminService and AdminService.Start)

-- 오류가 나도 멈추지 않게 부르기
local function safe(label: string, fn: (...any) -> ...any, ...: any)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn("[Server] " .. label .. " 오류:", err)
	end
end

local function onCharacterAdded(player: Player, character: Model)
	character:WaitForChild("HumanoidRootPart", 10)
	if player.Parent == nil then
		return
	end
	safe("OnCharacterAdded", PlotService.OnCharacterAdded, player, character)
	safe("UpdateSpeed", FollowService.UpdateSpeed, player)
	-- 기지로 텔레포트가 끝난 뒤에 펫을 불러야 맵을 가로질러 끌려오지 않음
	task.delay(0.4, function()
		if player.Parent and player.Character == character then
			safe("FollowService.Refresh", FollowService.Refresh, player)
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

	local ok, data = pcall(DataService.Load, player)
	if not ok then
		warn("[Server] 데이터 불러오기 오류:", player.Name, data)
		return
	end
	if not data or player.Parent == nil then
		return
	end
	-- ★v7.4 저장된 관리자 선물 (AdminGrants) 을 게임 패스 속성에 바로 반영
	safe("PassService.Refresh", PassService.Refresh, player)

	-- 집 배정 (OnPlotChanged "Assign" → ShopService 가 가구를 검사하고 그려요)
	safe("AssignPlot", PlotService.AssignPlot, player)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
	DataService.Sync(player)
	if LeaderboardService then
		safe("LeaderboardService.SendTo", LeaderboardService.SendTo, player)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	-- 앞 단계에서 오류가 나도 저장(Release)은 반드시 실행 (ReleasePlot 이 OnPlotChanged "Release" 를 보내요)
	for _, fn in { FollowService.Clear, PlotService.ReleasePlot } do
		local ok, err = pcall(fn, player)
		if not ok then
			warn("[Server] PlayerRemoving 처리 오류:", err)
		end
	end
	local ok, err = pcall(DataService.Release, player)
	if not ok then
		warn("[Server] 저장(Release) 오류:", err)
	end
end)

Remotes.RequestSync.OnServerEvent:Connect(function(player)
	if DataService.Get(player) then
		DataService.Sync(player)
	end
end)

game:BindToClose(function()
	local ok, err = pcall(DataService.SaveAll)
	if not ok then
		warn("[Server] SaveAll 오류:", err)
	end
end)
