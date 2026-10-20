-- 지역 서비스: 지금 어느 지역에 있는지(플레이어 속성 Zone), 잠긴 지역에 들어간 사람 돌려보내기,
-- 떨어지면 마지막 지역 스폰으로, 그리고 Teleport 리모트 ("Zone" n / "Floor" n / "Home").
-- 문(Gate)은 서버에서는 안 막아요. 그래서 여기서 환생 수를 꼭 다시 확인해요.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local HouseBuilder = require(script.Parent.HouseBuilder)

local ZoneService = {}

local LOOP_INTERVAL = 0.5
local TELEPORT_COOLDOWN = 1.5 -- 순간이동 사이 최소 간격
local REQUEST_COOLDOWN = 0.25 -- 실패한 요청도 이보다 자주는 안 받아요
local LOCK_NOTIFY_GAP = 3 -- 잠긴 지역에서 돌려보낼 때 알림 간격

local lastZone: { [Player]: number } = {}
local lastTeleport: { [Player]: number } = {}
local lastRequest: { [Player]: number } = {}
local lastLockNotify: { [Player]: number } = {}
local started = false

local function notify(player: Player, text: string, kind: string)
	Remotes.Notify:FireClient(player, text, kind)
end

local function lockedText(zone: number): string
	local def = Config.Zones[zone]
	return "🔒 환생 " .. (if def then def.MinRebirth else 0) .. "회가 필요해요!"
end

-- 살아 있는 캐릭터 (아니면 nil)
local function aliveCharacter(player: Player): (Model?, BasePart?, Humanoid?)
	local char = player.Character
	if not char then
		return nil, nil, nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not (hrp and hrp:IsA("BasePart") and hum and hum.Health > 0) then
		return nil, nil, nil
	end
	return char, hrp, hum
end

local function setZone(player: Player, zone: number)
	lastZone[player] = zone
	if player:GetAttribute("Zone") ~= zone then
		player:SetAttribute("Zone", zone)
	end
end

-- 지역 스폰 자리 (+3 위, 섬 안쪽 +X 를 바라봐요)
local function zoneSpawnCFrame(zone: number): CFrame
	local def = Config.Zones[zone] or Config.Zones[1]
	local pos = def.Spawn + Vector3.new(0, 3, 0)
	return CFrame.lookAt(pos, pos + Vector3.xAxis)
end

-- 캐릭터 옮기기 (타는 펫은 용접돼 있어서 같이 와요)
local function moveCharacter(player: Player, cf: CFrame): boolean
	local char, hrp, hum = aliveCharacter(player)
	if not char or not hrp or not hum then
		return false
	end
	if hum.Sit then
		hum.Sit = false
	end
	hrp.AssemblyLinearVelocity = Vector3.zero
	char:PivotTo(cf)
	return true
end

-- 우리 집 1층 입구 자리 (집이 없으면 nil)
local function homeCFrame(player: Player): CFrame?
	local plot: any = PlotService.GetPlot(player)
	if not plot then
		return nil
	end
	local sp = plot.SpawnPoint
	if not (typeof(sp) == "Instance" and sp:IsA("BasePart")) and typeof(plot.Model) == "Instance" then
		sp = plot.Model:FindFirstChild("SpawnPoint")
	end
	if typeof(sp) == "Instance" and sp:IsA("BasePart") then
		return sp.CFrame * CFrame.new(0, 3, 0)
	end
	return nil
end

-- 우리 집 n 층 자리 (HouseBuilder.FloorSpawn, 없으면 1층 입구 + 층 높이)
local function floorCFrame(player: Player, floor: number): CFrame?
	local data = DataService.Get(player)
	local plot: any = PlotService.GetPlot(player)
	if not data or not plot then
		return nil
	end
	local fn = (HouseBuilder :: any).FloorSpawn
	if type(fn) == "function" and typeof(plot.Origin) == "CFrame" then
		local ok, cf = pcall(fn, plot.Origin, data.Theme, floor)
		if ok and typeof(cf) == "CFrame" then
			return cf
		end
	end
	local home = homeCFrame(player)
	if home then
		return home + Vector3.new(0, (floor - 1) * Config.House.FloorHeight, 0)
	end
	return nil
end

----------------------------------------------------------------------
-- 공개 API
----------------------------------------------------------------------

-- 지금 있는 지역 (길 위에서는 마지막 지역, 모르면 1)
function ZoneService.GetPlayerZone(player: Player): number
	local z = lastZone[player] or player:GetAttribute("Zone")
	return if type(z) == "number" and Config.Zones[z] then z else 1
end

-- 위치가 어느 지역인지 (길/물 위면 nil) = Config.ZoneAt
function ZoneService.ZoneAt(position: Vector3): number?
	return Config.ZoneAt(position)
end

-- 그 지역에 들어갈 수 있나 (환생 수 확인)
function ZoneService.CanEnter(player: Player, zone: number): boolean
	return Config.ZoneUnlocked(zone, DataService.GetRebirths(player))
end

function ZoneService.TeleportToZone(player: Player, zone: number): boolean
	if type(zone) ~= "number" or zone ~= math.floor(zone) or not Config.Zones[zone] then
		return false
	end
	if not ZoneService.CanEnter(player, zone) then
		return false
	end
	if moveCharacter(player, zoneSpawnCFrame(zone)) then
		setZone(player, zone)
		return true
	end
	return false
end

function ZoneService.TeleportToFloor(player: Player, floor: number): boolean
	local data = DataService.Get(player)
	if not data or type(floor) ~= "number" or floor ~= math.floor(floor) then
		return false
	end
	if floor < 1 or floor > data.Floors then
		return false
	end
	local cf = floorCFrame(player, floor)
	if cf and moveCharacter(player, cf) then
		setZone(player, 1)
		return true
	end
	return false
end

function ZoneService.TeleportHome(player: Player): boolean
	local cf = homeCFrame(player) or zoneSpawnCFrame(1)
	if moveCharacter(player, cf) then
		setZone(player, 1)
		return true
	end
	return false
end

----------------------------------------------------------------------
-- Teleport 리모트
----------------------------------------------------------------------

local function onTeleport(player: Player, kind: any, n: any)
	if type(kind) ~= "string" or #kind > 32 then
		return
	end
	if kind ~= "Zone" and kind ~= "Floor" and kind ~= "Home" then
		return
	end
	if kind ~= "Home" then
		if type(n) ~= "number" or n ~= n or n ~= math.floor(n) or math.abs(n) > 1000 then
			return
		end
	end
	local now = os.clock()
	if (lastRequest[player] or 0) + REQUEST_COOLDOWN > now then
		return
	end
	lastRequest[player] = now
	if not DataService.Get(player) then
		return
	end
	if (lastTeleport[player] or 0) + TELEPORT_COOLDOWN > now then
		notify(player, "잠깐만요! 조금 뒤에 다시 해 봐요 ⏳", "info")
		return
	end
	if not aliveCharacter(player) then
		return
	end

	local ok = false
	if kind == "Zone" then
		if n < 1 or n > Config.MaxZone then
			return
		end
		if not ZoneService.CanEnter(player, n) then
			notify(player, lockedText(n), "warn")
			return
		end
		ok = ZoneService.TeleportToZone(player, n)
	elseif kind == "Floor" then
		local data = DataService.Get(player)
		if not PlotService.GetPlot(player) then
			notify(player, "아직 내 집이 없어요! 🏠", "warn")
			return
		end
		if not data or n < 1 or n > data.Floors then
			notify(player, "🏠 " .. tostring(n) .. "층은 아직 없어요!", "warn")
			return
		end
		ok = ZoneService.TeleportToFloor(player, n)
	else
		ok = ZoneService.TeleportHome(player)
	end
	if ok then
		lastTeleport[player] = now
	end
end

----------------------------------------------------------------------
-- 0.5초마다: 지역 표시, 잠긴 지역 돌려보내기, 떨어짐 복구
----------------------------------------------------------------------

local function checkPlayer(player: Player)
	local _, hrp = aliveCharacter(player)
	if not hrp then
		return
	end
	local pos = hrp.Position
	local loaded = DataService.Get(player) ~= nil

	-- 바다/우주로 떨어졌어요: 마지막 지역 스폰으로
	if pos.Y < Config.Layout.FallResetY then
		local back = ZoneService.GetPlayerZone(player)
		if loaded and not ZoneService.CanEnter(player, back) then
			back = DataService.GetMaxZone(player)
		end
		if moveCharacter(player, zoneSpawnCFrame(back)) then
			setZone(player, back)
		end
		return
	end

	local zone = Config.ZoneAt(pos)
	if not zone then
		return -- 길 위: 마지막 값 그대로
	end
	if loaded and not ZoneService.CanEnter(player, zone) then
		-- 잠긴 지역: 열린 가장 먼 지역 스폰으로 돌려보내요
		local back = DataService.GetMaxZone(player)
		if moveCharacter(player, zoneSpawnCFrame(back)) then
			setZone(player, back)
		end
		local now = os.clock()
		if (lastLockNotify[player] or 0) + LOCK_NOTIFY_GAP <= now then
			lastLockNotify[player] = now
			notify(player, lockedText(zone), "warn")
		end
		return
	end
	setZone(player, zone)
end

function ZoneService.Start()
	if started then
		return
	end
	started = true

	Remotes.Teleport.OnServerEvent:Connect(onTeleport)

	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute("Zone", 1)
	end)
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Zone") == nil then
			player:SetAttribute("Zone", 1)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		lastZone[player] = nil
		lastTeleport[player] = nil
		lastRequest[player] = nil
		lastLockNotify[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(LOOP_INTERVAL)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(checkPlayer, player)
				if not ok then
					warn("[ZoneService] 지역 확인 오류:", err)
				end
			end
		end
	end)
end

return ZoneService
