-- 들판 코인 (플레이어마다 따로, 열린 지역마다 따로): 서버는 파트를 만들지 않고 메모리에만 코인 목록을 둬요.
-- 그리기/자석은 클라이언트(CoinField)가 하고, 먹기 요청(PickupCoin)은 여기서 거리·지역·상태를 검증해요.
-- 남이 먹어도 내 코인은 그대로예요 (코인 목록·번호가 사람마다 따로).
-- ★v5 자석 버튼 (DataService.GetSetting(player, "Magnet") + ★v7.2 환생 MagnetMinRebirth 번 이상): BigMagnetRadius 안 코인도 먹을 수 있어요.
-- 기본 자석 밖 코인은 초당 BigMagnetRate 개까지만 받아 줘요 (클라이언트도 같은 속도로 끌어와요, 서버는 여유를 둬요).
-- ★v6 슈퍼 자석 (GetSetting "SuperMagnet" + 환생 SuperMagnetMinRebirth 번 이상): 거리 대신 "같은 지역" 으로 검사해요.
-- (★v7.2 잠겨 있으면 켜 둔 값은 저장만 되고 아무 일도 안 해요: Config.SettingUnlocked)
-- 내가 서 있는 지역 코인만 (SuperMagnetRadius 안, 높이 SUPER_MAX_HEIGHT 안), 따로 된 표로 초당 SuperMagnetRate 개까지.
-- 둘 다 켜져 있으면 슈퍼 자석이 이겨요: 지역 안에 있으면 다른 지역 코인은 🧲 자석으로도 안 돼요 (길 위에서만 🧲).
-- 코인 값 = 기본값 × 지역 CoinMult × (1 + 집 초당 수익 / IncomeScale) × (1 + min(펫 보너스, MaxBoost)) × 환생 코인 배율
-- (집 초당 수익은 DataService.GetIncome 이라 환생·테마 수익 배율이 이미 들어 있어요)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local FollowService = require(script.Parent.FollowService)

local CoinFieldService = {}

local FC = Config.FieldCoins
local Layout = Config.Layout
local HALF_PLOT = Layout.PlotSize / 2

local PLOT_MARGIN = 2 -- 집 가장자리에서 띄우는 거리
local MIN_SPACING = 4 -- 같은 지역 코인끼리 최소 간격
local DECO_RADIUS = 2.2 -- 장식 겹침 검사 반경
local DECO_TOP_MAX = 0.6 -- 이보다 높이 솟은 파트가 있으면 장식이라 보고 피함
local BIN_EXTRA = 7 -- 컨베이어 끝 알 통까지 여유
local CHUTE_EXTRA = 3 -- 시작점 슈트 여유
local PICKUP_SLACK = 8 -- 서버 거리 판정 여유 (지연 대비)
local MAX_HEIGHT_DIFF = 14 -- 코인과 캐릭터 높이 차 허용치
local LOAD_TIMEOUT = 20 -- 데이터 로딩 기다리는 최대 초
local MAX_PICKUPS_PER_SEC = 20
local MAGNET_RATE_SLACK = 1.5 -- 큰 자석 속도 여유 (지연으로 몰려 와도 괜찮게)
local MAGNET_BURST_SLACK = 4
local SUPER_RATE_SLACK = 1.25 -- 슈퍼 자석 속도 여유 (범위가 넓어서 여유는 조금만)
local SUPER_BURST_SLACK = 4
local SUPER_MAX_HEIGHT = 30 -- 슈퍼 자석 높이 차 허용치 (펫 타고 조금 날아도 돼요, 클라이언트는 24)
local ZONE_SLACK = 10 -- 지역 경계 여유 (지연 대비)
local ZONE_POLL = 5 -- 새로 열린 지역 확인 간격

type CoinKind = { Name: string, Value: number, Weight: number, Color: Color3, Size: number }
type Coin = { Id: number, Kind: string, Position: Vector3, Zone: number, Alive: boolean }
type Field = {
	coins: { [number]: Coin },
	zones: { [number]: boolean }, -- 코인을 깐 지역
	nextId: number,
	rng: Random,
	windowStart: number,
	windowCount: number,
	magnetTokens: number, -- 큰 자석으로 먹을 수 있는 남은 개수
	magnetAt: number, -- 마지막으로 채운 시각
	superTokens: number, -- ★v6 슈퍼 자석 표
	superAt: number,
}
-- 지역마다 코인 놓는 곳 (들판 상자 + 컨베이어 선분)
type ZoneGeo = { Min: Vector3, Max: Vector3, SegA: Vector3, SegB: Vector3, Fallback: Vector3 }

local fields: { [Player]: Field } = {}
local hooked: { [Player]: RBXScriptConnection } = {}
local geos: { [number]: ZoneGeo } = {}
local started = false

----------------------------------------------------------------------
-- 도우미
----------------------------------------------------------------------

for k, def in Config.Zones do
	local a, b = def.ConveyorStart, def.ConveyorEnd
	local dir = (b - a).Unit
	geos[k] = {
		Min = def.FieldMin,
		Max = def.FieldMax,
		SegA = a - dir * CHUTE_EXTRA,
		SegB = b + dir * BIN_EXTRA,
		Fallback = Vector3.new((def.FieldMin.X + def.FieldMax.X) / 2 + 6, 0, def.FieldMax.Z - 4),
	}
end

local function kindByName(name: string): CoinKind?
	for _, k in FC.Kinds do
		if k.Name == name then
			return k
		end
	end
	return nil
end

local function pickKind(rng: Random): CoinKind
	local total = 0
	for _, k in FC.Kinds do
		total += k.Weight
	end
	local roll = rng:NextNumber() * total
	for _, k in FC.Kinds do
		roll -= k.Weight
		if roll <= 0 then
			return k
		end
	end
	return FC.Kinds[1]
end

local function insidePlot(pos: Vector3): boolean
	for _, cf in Layout.Plots do
		local lp = cf:PointToObjectSpace(Vector3.new(pos.X, cf.Position.Y, pos.Z))
		if math.abs(lp.X) <= HALF_PLOT + PLOT_MARGIN and math.abs(lp.Z) <= HALF_PLOT + PLOT_MARGIN then
			return true
		end
	end
	return false
end

-- 컨베이어 선분까지 수평 거리
local function distToSegment(p: Vector3, a: Vector3, b: Vector3): number
	local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local ap = Vector3.new(p.X - a.X, 0, p.Z - a.Z)
	local len2 = ab:Dot(ab)
	local t = if len2 > 0 then math.clamp(ap:Dot(ab) / len2, 0, 1) else 0
	return (ap - ab * t).Magnitude
end

local function tooClose(field: Field, zone: number, pos: Vector3, selfId: number?): boolean
	for _, c in field.coins do
		if c.Zone == zone and c.Id ~= selfId then
			local d = c.Position - pos
			if d.X * d.X + d.Z * d.Z < MIN_SPACING * MIN_SPACING then
				return true
			end
		end
	end
	return false
end

-- 장식(나무, 꽃 등) 위에 놓이는지: workspace.World 파트 중 0.6 보다 높이 솟은 게 반경 안에 있으면 안 돼요
local overlapParams: OverlapParams? = nil
local function onDecoration(pos: Vector3): boolean
	local world = workspace:FindFirstChild("World")
	if not world then
		return false
	end
	local params = overlapParams
	if not params then
		params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { world }
		overlapParams = params
	end
	local hits = workspace:GetPartBoundsInRadius(pos + Vector3.new(0, 2, 0), DECO_RADIUS, params)
	for _, part in hits do
		if part.Position.Y + part.Size.Y / 2 > DECO_TOP_MAX then
			return true
		end
	end
	return false
end

local function randomPosition(field: Field, zone: number, selfId: number?): Vector3
	local geo = geos[zone] or geos[1]
	local rng = field.rng
	local clearance = Layout.FieldConveyorClearance
	local fallback: Vector3? = nil
	for _ = 1, 40 do
		local pos = Vector3.new(rng:NextNumber(geo.Min.X, geo.Max.X), 0, rng:NextNumber(geo.Min.Z, geo.Max.Z))
		if distToSegment(pos, geo.SegA, geo.SegB) > clearance and not insidePlot(pos) and not onDecoration(pos) then
			if not tooClose(field, zone, pos, selfId) then
				return pos
			end
			fallback = fallback or pos
		end
	end
	return fallback or geo.Fallback
end

local function getHRP(player: Player): BasePart?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

-- 위치가 그 지역 땅 위인지 (경계 여유 slack)
local function inZone(zone: number, pos: Vector3, slack: number): boolean
	local def = Config.Zones[zone]
	if not def then
		return false
	end
	local d = pos - def.Center
	return math.abs(d.X) <= def.Size.X / 2 + slack and math.abs(d.Z) <= def.Size.Z / 2 + slack
end

-- ★v6 슈퍼 자석 / ★v7.2 🧲 자석이 정말 켜져 있나 (버튼 + 환생 조건)
local function settingActive(player: Player, key: string): boolean
	return DataService.GetSetting(player, key) == true and Config.SettingUnlocked(key, DataService.GetRebirths(player))
end

local function superActive(player: Player): boolean
	return settingActive(player, "SuperMagnet")
end

-- 표 하나 꺼내 쓰기 (초당 rate 개씩 cap 개까지 채워져요). 없으면 false
local function takeToken(field: Field, super: boolean, now: number): boolean
	if super then
		local cap = FC.SuperMagnetBurst + SUPER_BURST_SLACK
		field.superTokens = math.min(cap, field.superTokens + (now - field.superAt) * FC.SuperMagnetRate * SUPER_RATE_SLACK)
		field.superAt = now
		if field.superTokens < 1 then
			return false
		end
		field.superTokens -= 1
		return true
	end
	local cap = FC.BigMagnetBurst + MAGNET_BURST_SLACK
	field.magnetTokens = math.min(cap, field.magnetTokens + (now - field.magnetAt) * FC.BigMagnetRate * MAGNET_RATE_SLACK)
	field.magnetAt = now
	if field.magnetTokens < 1 then
		return false
	end
	field.magnetTokens -= 1
	return true
end

local function payload(coin: Coin)
	return { Id = coin.Id, Kind = coin.Kind, Position = coin.Position, Zone = coin.Zone }
end

local function sendReset(player: Player)
	local field = fields[player]
	if not field or player.Parent == nil then
		return
	end
	local list = {}
	for _, coin in field.coins do
		if coin.Alive then
			table.insert(list, payload(coin))
		end
	end
	Remotes.CoinField:FireClient(player, "Reset", list)
end

----------------------------------------------------------------------
-- 플레이어별 코인 만들기 / 정리
----------------------------------------------------------------------

-- 지역 하나에 코인 CountPerZone 개 깔기. 만든 코인 목록을 돌려줘요
local function addZone(field: Field, zone: number): { Coin }
	local made = {}
	if field.zones[zone] or not Config.Zones[zone] then
		return made
	end
	field.zones[zone] = true
	for _ = 1, FC.CountPerZone or FC.Count do
		local id = field.nextId
		field.nextId += 1
		local coin: Coin = { Id = id, Kind = pickKind(field.rng).Name, Position = Vector3.zero, Zone = zone, Alive = true }
		field.coins[id] = coin
		coin.Position = randomPosition(field, zone, id)
		table.insert(made, coin)
	end
	return made
end

local function buildField(player: Player): Field
	local seed = (math.floor(os.clock() * 1000) % 1000000) + player.UserId % 100000 * 31
	local field: Field = {
		coins = {},
		zones = {},
		nextId = 1,
		rng = Random.new(seed),
		windowStart = os.clock(),
		windowCount = 0,
		magnetTokens = FC.BigMagnetBurst + MAGNET_BURST_SLACK,
		magnetAt = os.clock(),
		superTokens = FC.SuperMagnetBurst + SUPER_BURST_SLACK,
		superAt = os.clock(),
	}
	for zone = 1, DataService.GetMaxZone(player) do
		addZone(field, zone)
	end
	fields[player] = field
	return field
end

-- 환생으로 새 지역이 열렸으면 그 지역 코인을 더해요 (클라이언트에 "Add")
local function checkNewZones(player: Player)
	local field = fields[player]
	if not field or player.Parent == nil or not DataService.Get(player) then
		return
	end
	for zone = 1, DataService.GetMaxZone(player) do
		if not field.zones[zone] then
			for _, coin in addZone(field, zone) do
				Remotes.CoinField:FireClient(player, "Add", payload(coin))
			end
		end
	end
end

local function respawnCoin(player: Player, field: Field, coin: Coin)
	if fields[player] ~= field or player.Parent == nil then
		return
	end
	coin.Kind = pickKind(field.rng).Name
	coin.Position = randomPosition(field, coin.Zone, coin.Id)
	coin.Alive = true
	Remotes.CoinField:FireClient(player, "Add", payload(coin))
end

-- 데이터가 로딩될 때까지 기다렸다가 코인을 깔아요
local function setupPlayer(player: Player)
	if hooked[player] then
		return
	end
	hooked[player] = player.CharacterAdded:Connect(function()
		-- 리스폰: 클라이언트 파트가 사라졌을 수 있어서 전체 목록 다시 보냄
		task.delay(0.5, function()
			sendReset(player)
		end)
	end)

	task.spawn(function()
		local waited = 0
		while player.Parent and DataService.Get(player) == nil and waited < LOAD_TIMEOUT do
			waited += task.wait(0.25)
		end
		if player.Parent == nil or DataService.Get(player) == nil or fields[player] then
			return
		end
		buildField(player)
		sendReset(player)
	end)
end

local function cleanupPlayer(player: Player)
	fields[player] = nil
	local conn = hooked[player]
	if conn then
		conn:Disconnect()
		hooked[player] = nil
	end
end

----------------------------------------------------------------------
-- 먹기 요청
----------------------------------------------------------------------

-- 코인 하나 값 (지역 배율 · 집 수익 · 펫 보너스(최대 MaxBoost) · 환생)
function CoinFieldService.CoinValue(player: Player, kindName: string, zone: number): number
	local kind = kindByName(kindName)
	local def = Config.Zones[zone]
	if not kind or not def then
		return 0
	end
	local income = math.max(0, DataService.GetIncome(player))
	local boost = math.clamp(FollowService.GetBoost(player), 0, FC.MaxBoost)
	local rebirthMult = Config.RebirthCoinMult(DataService.GetRebirths(player))
	local value = math.floor(kind.Value * def.CoinMult * (1 + income / FC.IncomeScale) * (1 + boost) * rebirthMult)
	if value ~= value or value < 1 then
		value = 1
	end
	return value
end

local function onPickup(player: Player, coinId: any)
	if type(coinId) ~= "number" or coinId ~= coinId or coinId ~= math.floor(coinId) then
		return
	end
	local field = fields[player]
	if not field then
		return
	end

	-- 너무 자주 보내면 무시 (초당 MAX_PICKUPS_PER_SEC 개)
	local now = os.clock()
	if now - field.windowStart >= 1 then
		field.windowStart = now
		field.windowCount = 0
	end
	field.windowCount += 1
	if field.windowCount > MAX_PICKUPS_PER_SEC then
		return
	end

	local coin = field.coins[coinId]
	if not coin or not coin.Alive then
		return
	end
	-- 잠긴 지역 코인은 못 먹어요
	if not Config.ZoneUnlocked(coin.Zone, DataService.GetRebirths(player)) then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = getHRP(player)
	if not hrp or not hum or hum.Health <= 0 then
		return
	end

	-- 거리 검증: 자석 반경 + 여유. 밖이면 슈퍼 자석(같은 지역) → 자석 버튼(큰 반경), 둘 다 초당 개수 제한
	local radius = FC.MagnetRadius + FC.MagnetPerFollower * FollowService.GetFollowerCount(player) + PICKUP_SLACK
	local pos = hrp.Position
	local d = pos - coin.Position
	local flat = Vector3.new(d.X, 0, d.Z).Magnitude
	local dy = math.abs(d.Y)
	if flat > radius or dy > MAX_HEIGHT_DIFF then
		local super = superActive(player)
		if super and inZone(coin.Zone, pos, ZONE_SLACK) then
			-- ⚡ 슈퍼 자석: 내가 있는 지역 코인 (거리는 넉넉히, 높이는 확인)
			if flat > FC.SuperMagnetRadius + PICKUP_SLACK or dy > SUPER_MAX_HEIGHT then
				return
			end
			if not takeToken(field, true, now) then
				return
			end
		else
			-- 🧲 자석: 슈퍼 자석이 켜져 있고 어느 지역 안이면 다른 지역 코인은 안 돼요 (슈퍼가 이겨요)
			if not settingActive(player, "Magnet") or (super and Config.ZoneAt(pos) ~= nil) then
				return
			end
			if flat > FC.BigMagnetRadius + PICKUP_SLACK or dy > MAX_HEIGHT_DIFF then
				return
			end
			if not takeToken(field, false, now) then
				return
			end
		end
	end

	local value = CoinFieldService.CoinValue(player, coin.Kind, coin.Zone)
	coin.Alive = false
	DataService.AddCoins(player, value) -- CoinSync 는 AddCoins 가 보내요
	Remotes.CoinFx:FireClient(player, value, coin.Position, true) -- 소리는 클라이언트가 자석 때 이미 냄
	Remotes.CoinField:FireClient(player, "Remove", coin.Id)

	task.delay(FC.RespawnTime, respawnCoin, player, field, coin)
end

----------------------------------------------------------------------
-- 공개 API
----------------------------------------------------------------------

-- 새로 열린 지역이 있으면 바로 코인을 깔아요 (환생 직후 불러도 되고, 안 불러도 5초마다 확인해요)
function CoinFieldService.Refresh(player: Player)
	checkNewZones(player)
end

function CoinFieldService.Start()
	if started then
		return
	end
	started = true

	Players.PlayerAdded:Connect(setupPlayer)
	for _, p in Players:GetPlayers() do
		setupPlayer(p)
	end
	Players.PlayerRemoving:Connect(cleanupPlayer)

	Remotes.PickupCoin.OnServerEvent:Connect(onPickup)

	-- 클라이언트가 동기화를 요청하면 코인 목록도 다시 보내요
	Remotes.RequestSync.OnServerEvent:Connect(function(player)
		-- 데이터 로드가 늦어 들판이 아직 없으면 지금 만들어요
		if not fields[player] and player.Parent and DataService.Get(player) then
			buildField(player)
		end
		if fields[player] then
			sendReset(player)
		end
	end)

	-- 환생으로 열린 지역 확인
	task.spawn(function()
		while true do
			task.wait(ZONE_POLL)
			for player in fields do
				local ok, err = pcall(checkNewZones, player)
				if not ok then
					warn("[CoinFieldService] 지역 확인 오류:", err)
				end
			end
		end
	end)
end

return CoinFieldService
