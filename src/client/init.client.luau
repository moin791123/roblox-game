-- 펫 월드 (v4): 클라이언트 시작점
-- 화면(UI)과 효과를 만들고 서버 이벤트를 연결해요. 창은 한 번에 하나만 열려요.
-- 단축키: B 가방 / N 도감 / H 집 / P 상점 / M 지도 / L 순위 / R 환생
-- (꾸미기 모드 중에는 단축키를 쉬어요. R 회전 · X 치우기 · Esc/Q 끝내기는 DecorateMode 가 직접 받아요)
-- ✨ 좋은 알 알림 (EggAlert): 오른쪽 아래 알림 줄의 배너 + "🗺 바로 가기" (꾸미기 중에는 쉬어요, 희귀 알은 끝나고 보여 줘요)
-- 🏠 HUD "집" 버튼의 빨간 "!": 아직 없는 더 좋은 집을 지금 살 수 있을 때
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local UiKit = require(script.UiKit)
local Config = UiKit.Config
local C = UiKit.Colors
local State = require(script.State)
local Toasts = require(script.Toasts)
local Hud = require(script.Hud)
local BagWindow = require(script.BagWindow)
local IndexWindow = require(script.IndexWindow)
local HouseWindow = require(script.HouseWindow)
local RebirthWindow = require(script.RebirthWindow)
local HatchFx = require(script.HatchFx)
local WorldFx = require(script.WorldFx)
local CoinField = require(script.CoinField)
local Tips = require(script.Tips)

-- 다른 모듈(상점·지도·순위·꾸미기·지역)은 없거나 오류가 나도 나머지 화면이 살아 있게 pcall 로 불러요
local function optionalRequire(name: string): any
	local mod = script:FindFirstChild(name)
	if not mod or not mod:IsA("ModuleScript") then
		warn("[Client] " .. name .. " 모듈이 없어요")
		return nil
	end
	local ok, result = pcall(require, mod)
	if not ok then
		warn("[Client] " .. name .. " 불러오기 실패:", result)
		return nil
	end
	return result
end

local ShopWindow = optionalRequire("ShopWindow") -- Init(gui), Open(tab?), Close, IsOpen, OnSync
local MapWindow = optionalRequire("MapWindow") -- Init(gui), Open, Close, IsOpen, OnSync?
local LeaderboardWindow = optionalRequire("LeaderboardWindow") -- Init(gui), Open, Close, IsOpen, OnSync, SetBoard (LeaderboardSync 는 스스로 받아요)
local DecorateMode = optionalRequire("DecorateMode") -- Init(gui?), Enter(floor?, furnId?), Exit, IsActive, OnSync, OnChanged(fn), SetShopOpener(fn)
local ZoneClient = optionalRequire("ZoneClient") -- Init()
local RideFly = optionalRequire("RideFly") -- Init(gui): 펫 타고 날기 ✈
local OptionsWindow = optionalRequire("OptionsWindow") -- ★v7.2 Init(gui), Open, Close, IsOpen: ⚙️ 게임 옵션 (🙈 부화 숨기기 · 🔔 알 알림)

-- 모듈 함수 안전하게 부르기 (없으면 nil, 오류는 경고만)
local function safeCall(mod: any, fnName: string, ...: any): any
	if type(mod) ~= "table" then
		return nil
	end
	local fn = mod[fnName]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		warn("[Client] " .. fnName .. " 오류:", result)
		return nil
	end
	return result
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 예전 GUI 가 남아 있으면 정리
for _, name in { "PetWorldGui", "PetWorldToasts" } do
	local old = playerGui:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end

local gui: ScreenGui = UiKit.Make("ScreenGui", {
	Name = "PetWorldGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})

-- 알림은 부화 연출(DisplayOrder 20)보다 위에 보이도록 따로
local toastGui: ScreenGui = UiKit.Make("ScreenGui", {
	Name = "PetWorldToasts",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	DisplayOrder = 30,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})
Toasts.Init(toastGui)

----------------------------------------------------------------------
-- 창 목록 (한 번에 하나만 열려요)
----------------------------------------------------------------------
type WindowApi = { Open: (...any) -> (), Close: () -> (), IsOpen: () -> boolean }

local function windowOf(mod: any, missingText: string): WindowApi
	return {
		Open = function(...: any)
			if type(mod) == "table" and type(mod.Open) == "function" then
				safeCall(mod, "Open", ...)
			else
				Toasts.Show(missingText, "info")
			end
		end,
		Close = function()
			safeCall(mod, "Close")
		end,
		IsOpen = function(): boolean
			return safeCall(mod, "IsOpen") == true
		end,
	}
end

local Bag = windowOf(BagWindow, "🎒 가방을 준비 중이에요!")
local Index = windowOf(IndexWindow, "📖 도감을 준비 중이에요!")
local House = windowOf(HouseWindow, "🏠 집 창을 준비 중이에요!")
local Rebirth = windowOf(RebirthWindow, "🔄 환생 창을 준비 중이에요!")
local Shop = windowOf(ShopWindow, "🛍 상점은 곧 열려요!")
local Map = windowOf(MapWindow, "🗺 지도는 곧 열려요!")
local Board = windowOf(LeaderboardWindow, "🏆 순위표는 곧 열려요!")
local Options = windowOf(OptionsWindow, "⚙️ 옵션은 곧 열려요!")
local windows: { WindowApi } = { Bag, Index, House, Rebirth, Shop, Map, Board, Options }

local function decorating(): boolean
	return safeCall(DecorateMode, "IsActive") == true
end

local function closeAll(except: WindowApi?)
	for _, w in windows do
		if w ~= except then
			w.Close()
		end
	end
end

-- 이 창만 열기 (꾸미기 중이면 꾸미기를 끝내고)
local function openOnly(target: WindowApi, ...: any)
	if decorating() then
		safeCall(DecorateMode, "Exit")
	end
	closeAll(target)
	target.Open(...)
end

local function toggle(target: WindowApi)
	if target.IsOpen() then
		target.Close()
		return
	end
	openOnly(target)
end

local function openShop(tab: string?)
	openOnly(Shop, tab)
end

----------------------------------------------------------------------
-- 만들기
----------------------------------------------------------------------
Hud.Init(gui, {
	ToggleBag = function()
		toggle(Bag)
	end,
	ToggleIndex = function()
		toggle(Index)
	end,
	ToggleHouse = function()
		toggle(House)
	end,
	ToggleRebirth = function()
		toggle(Rebirth)
	end,
	ToggleShop = function()
		toggle(Shop)
	end,
	ToggleMap = function()
		toggle(Map)
	end,
	ToggleLeaderboard = function()
		toggle(Board)
	end,
	ToggleOptions = function()
		toggle(Options) -- ★v7.2 ⚙️ 옵션 버튼
	end,
})
BagWindow.Init(gui, { OpenShop = openShop })
IndexWindow.Init(gui)
HouseWindow.Init(gui, {
	-- 🛋️ 꾸미기: 창을 모두 닫고 꾸미기 모드 (floor = 지금 있는 층, 집 밖이면 nil)
	Decorate = function(floor: number?)
		closeAll()
		if DecorateMode then
			safeCall(DecorateMode, "Enter", floor)
		else
			Toasts.Show("🛋️ 꾸미기는 곧 열려요!", "info")
		end
	end,
	OpenShop = openShop,
})
RebirthWindow.Init(gui)
-- 큰 알림 배너는 왼쪽 큰 버튼 칸을 가리지 않게 비켜요
local sideButtons = gui:FindFirstChild("SideButtons")
if sideButtons and sideButtons:IsA("GuiObject") then
	Toasts.SetBannerGuard(sideButtons)
end
safeCall(ShopWindow, "Init", gui)
safeCall(MapWindow, "Init", gui)
safeCall(LeaderboardWindow, "Init", gui)
safeCall(OptionsWindow, "Init", gui)
safeCall(DecorateMode, "Init", gui)
Tips.Init(gui)
HatchFx.Init(playerGui)
pcall(UiKit.PreloadRareSounds) -- ★v7 희귀 알 알림 소리를 미리 불러 둬요
WorldFx.Init()
CoinField.Init()
safeCall(optionalRequire("EggBelt"), "Init") -- ★v5 내 컨베이어 알 (사람마다 따로, 나만 보여요)
safeCall(ZoneClient, "Init")
safeCall(RideFly, "Init", gui)

-- 엘리베이터 프롬프트 → 층 고르기 창
WorldFx.OnElevator(function(floor: number?)
	if decorating() then
		return
	end
	closeAll(House)
	HouseWindow.OpenFloorPicker(floor)
end)

-- 꾸미기 모드 가구 가방이 비었을 때 "🛍 상점" → 상점 가구 탭 (꾸미기는 그대로, 다른 창은 닫아요)
safeCall(DecorateMode, "SetShopOpener", function()
	closeAll(Shop)
	Shop.Open("Furniture")
end)

-- 꾸미기 모드가 켜지면 창을 닫고 왼쪽 버튼을 잠깐 숨겨요 (OnChanged 가 있으면)
safeCall(DecorateMode, "OnChanged", function(on: boolean)
	if on then
		closeAll()
	end
	Hud.SetSideVisible(not on)
	Tips.SetSuppressed(on)
	Toasts.SetBannerSuppressed(on)
end)

----------------------------------------------------------------------
-- 서버 이벤트
----------------------------------------------------------------------
local optionalSync: { [string]: any } = {
	ShopWindow = ShopWindow,
	MapWindow = MapWindow,
	LeaderboardWindow = LeaderboardWindow,
	DecorateMode = DecorateMode,
	ZoneClient = ZoneClient,
}

-- 🏠 "집" 버튼 빨간 "!" (더 좋은 새 집을 살 수 있으면)
local function refreshHouseBadge()
	Hud.SetBadge("집", safeCall(HouseWindow, "ThemeGoal") ~= nil)
end

State.OnSync(function(snap)
	Hud.Update(snap)
	refreshHouseBadge()
	BagWindow.OnSync()
	IndexWindow.OnSync()
	HouseWindow.OnSync()
	RebirthWindow.OnSync()
	for _, mod in optionalSync do
		safeCall(mod, "OnSync")
	end
end)

State.OnCoins(function(coins, pending, income)
	Hud.SetCoins(coins, pending, income)
	refreshHouseBadge()
end)

Remotes.DataSync.OnClientEvent:Connect(function(snap)
	State.SetSnapshot(snap)
end)

-- 코인만 바뀌었을 때 (가벼운 갱신): 스냅샷의 Coins / Pending / Income 만 덮어써요
Remotes.CoinSync.OnClientEvent:Connect(function(coins, pending, income)
	State.ApplyCoins(coins, pending, income)
end)

-- 순위표: LeaderboardWindow 는 LeaderboardSync 를 스스로 받아요. 여기서는 State.Board 에만 넣어요
Remotes.LeaderboardSync.OnClientEvent:Connect(function(board)
	State.SetBoard(board)
end)

Remotes.Notify.OnClientEvent:Connect(function(text, kind)
	Toasts.Show(text, kind)
end)

Remotes.HatchFx.OnClientEvent:Connect(function(petId, position, isNew, tier, mode, size)
	HatchFx.Play(petId, position, isNew, tier, mode, size)
end)

Remotes.CoinFx.OnClientEvent:Connect(function(amount, position, silent)
	WorldFx.CoinFx(amount, position, silent)
end)

----------------------------------------------------------------------
-- ✨ 좋은 알 알림: 서버가 (zone, eggId) 를 보내면 큰 배너
----------------------------------------------------------------------
local lastAlertTeleport = -10

-- 내가 지금 있는 지역 (ZoneClient 가 없으면 플레이어 속성 Zone)
local function myZone(): number
	local z = safeCall(ZoneClient, "CurrentZone")
	if type(z) == "number" then
		return z
	end
	return tonumber(player:GetAttribute("Zone")) or 1
end

local function onEggAlert(zone: any, eggId: any)
	local z = tonumber(zone)
	local zoneDef = if z then Config.Zones[z] else nil
	local egg = if type(eggId) == "string" then Config.Eggs[eggId] else nil
	if not z or not zoneDef or not egg then
		return
	end
	if decorating() and Config.EggAlertKind(eggId) ~= "Rare" then
		return -- 꾸미기 중에는 쉬어요 (★v6 희귀 알은 Toasts 가 줄에 두었다가 꾸미기가 끝나면 보여 줘요)
	end
	if not State.ZoneUnlocked(z) then
		return -- 아직 못 가는 지역이면 알려도 갈 수 없어요
	end
	local rarity = (Config.Rarities :: any)[egg.Rarity]
	local color = UiKit.RarityColor(egg.Rarity)
	local zoneIndex: number = z
	Toasts.Banner({
		Key = "Egg:" .. zoneIndex .. ":" .. eggId,
		Title = "✨ " .. zoneDef.Name .. "에 " .. UiKit.Josa(egg.Name, "이", "가") .. " 나타났어요!",
		Sub = string.format("%s · 💰 %s · 서둘러요! 🏃", if rarity then rarity.Name .. " 알" else "좋은 알", Config.FormatNumber(egg.Price or 0)),
		HiddenSub = "📍 이 지역 컨베이어에 있어요! 얼른 찾아봐요 👀",
		Color = color,
		IconKind = "Egg",
		IconId = eggId,
		Sound = "Alert",
		ButtonText = "🗺 바로 가기",
		ButtonColor = C.Mint,
		ButtonVisible = function(): boolean
			return myZone() ~= zoneIndex
		end,
		OnButton = function(): boolean?
			if decorating() then
				return true
			end
			if not State.ZoneUnlocked(zoneIndex) then
				Toasts.Show("🔒 환생 " .. zoneDef.MinRebirth .. "회가 필요해요!", "warn")
				return true
			end
			if os.clock() - lastAlertTeleport < 1.6 then
				Toasts.Show("잠깐만요! ⏳", "info")
				return false
			end
			lastAlertTeleport = os.clock()
			closeAll()
			Remotes.Teleport:FireServer("Zone", zoneIndex)
			Toasts.Show("🗺 " .. zoneDef.Name .. "에 가요! 알을 찾아봐요 🥚", "good")
			return true
		end,
	})
end

-- EggAlert 리모트는 서버 버전에 따라 없을 수도 있어요: 10초만 기다리고, 없으면 나중에 생길 때 연결해요
task.spawn(function()
	local remote: Instance? = (Remotes :: any).EggAlert
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remote and folder then
		remote = folder:WaitForChild("EggAlert", 10)
	end
	if remote and remote:IsA("RemoteEvent") then
		remote.OnClientEvent:Connect(onEggAlert)
		return
	end
	if folder then
		local conn: RBXScriptConnection? = nil
		conn = folder.ChildAdded:Connect(function(child: Instance)
			if child.Name == "EggAlert" and child:IsA("RemoteEvent") then
				child.OnClientEvent:Connect(onEggAlert)
				if conn then
					conn:Disconnect()
				end
			end
		end)
	end
end)

-- 키보드 단축키 (PC)
local HOTKEYS: { [Enum.KeyCode]: WindowApi } = {
	[Enum.KeyCode.B] = Bag,
	[Enum.KeyCode.N] = Index,
	[Enum.KeyCode.H] = House,
	[Enum.KeyCode.P] = Shop,
	[Enum.KeyCode.M] = Map,
	[Enum.KeyCode.L] = Board,
	[Enum.KeyCode.R] = Rebirth,
}

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or UserInputService:GetFocusedTextBox() then
		return
	end
	if decorating() then
		return -- 꾸미기 모드가 R / X / Esc / Q 를 써요
	end
	local target = HOTKEYS[input.KeyCode]
	if target then
		toggle(target)
	end
end)

Remotes.RequestSync:FireServer()
