-- 들판 코인 (플레이어마다 따로): 서버는 파트를 만들지 않고 메모리에만 코인 목록을 둬요.
-- 그리기/자석은 클라이언트(CoinField)가 하고, 먹기 요청(PickupCoin)은 여기서 거리·상태를 검증해요.
-- 코인 값 = 기본값 × (1 + 집 초당 수익 / IncomeScale) × (1 + 펫 보너스) × 환생 코인 배율
-- (집 초당 수익은 DataService.GetIncome 이라 환생 수익 배율이 이미 들어 있어요)
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
local MIN_SPACING = 4 -- 같은 플레이어 코인끼리 최소 간격
local DECO_RADIUS = 2.2 -- 장식 겹침 검사 반경
local DECO_TOP_MAX = 0.6 -- 이보다 높이 솟은 파트가 있으면 장식이라 보고 피함
local PICKUP_SLACK = 8 -- 서버 거리 판정 여유 (지연 대비)
local MAX_HEIGHT_DIFF = 14 -- 코인과 캐릭터 높이 차 허용치
local LOAD_TIMEOUT = 20 -- 데이터 로딩 기다리는 최대 초
local MAX_PICKUPS_PER_SEC = 20

type CoinKind = { Name: string, Value: number, Weight: number, Color: Color3, Size: number }
type Coin = { Id: number, Kind: string, Position: Vector3, Alive: boolean }
type Field = {
	coins: { Coin }, -- 인덱스 = Id
	rng: Random,
	windowStart: number,
	windowCount: number,
}

local fields: { [Player]: Field } = {}
local hooked: { [Player]: RBXScriptConnection } = {}
local started = false

----------------------------------------------------------------------
-- 도우미
----------------------------------------------------------------------

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

local function tooClose(field: Field, pos: Vector3, selfId: number?): boolean
	for _, c in field.coins do
		if c.Id ~= selfId then
			local d = c.Position - pos
			if d.X * d.X + d.Z * d.Z < MIN_SPACING * MIN_SPACING then
				return true
			end
		end
	end
	return false
end

-- 장식(나무, 꽃 등) 위에 놓이는지: workspace.World 파트 중 0.6 보다 높이 솟은 게 반경 안에 있으면 안 돼요
local function onDecoration(pos: Vector3): boolean
	local world = workspace:FindFirstChild("World")
	if not world then
		return false
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { world }
	local hits = workspace:GetPartBoundsInRadius(pos + Vector3.new(0, 2, 0), DECO_RADIUS, params)
	for _, part in hits do
		if part.Position.Y + part.Size.Y / 2 > DECO_TOP_MAX then
			return true
		end
	end
	return false
end

-- 컨베이어 여유 구역 밖의 z 값 하나 고르기
local function randomZ(rng: Random): number
	local clear = Layout.FieldConveyorClearance
	local zMin, zMax = Layout.FieldMin.Z, Layout.FieldMax.Z
	-- 구간 [zMin, -clear] 와 [clear, zMax]
	local lowLen = math.max(0, math.min(zMax, -clear) - zMin)
	local highLen = math.max(0, zMax - math.max(zMin, clear))
	if lowLen + highLen <= 0 then
		return rng:NextNumber(zMin, zMax)
	end
	local r = rng:NextNumber(0, lowLen + highLen)
	if r < lowLen then
		return zMin + r
	end
	return math.max(zMin, clear) + (r - lowLen)
end

local function randomPosition(field: Field, selfId: number?): Vector3
	local rng = field.rng
	local fallback: Vector3? = nil
	for _ = 1, 40 do
		local pos = Vector3.new(rng:NextNumber(Layout.FieldMin.X, Layout.FieldMax.X), 0, randomZ(rng))
		if not insidePlot(pos) and not onDecoration(pos) then
			if not tooClose(field, pos, selfId) then
				return pos
			end
			fallback = fallback or pos
		end
	end
	return fallback or Vector3.new(0, 0, Layout.FieldConveyorClearance + 2)
end

-- 집 초당 수익. DataService.GetIncome 이 있으면 그걸 쓰고, 없으면 직접 더해요
local function getIncome(player: Player): number
	local fn = (DataService :: any).GetIncome
	if type(fn) == "function" then
		local ok, n = pcall(fn, player)
		if ok and type(n) == "number" and n == n then
			return math.max(0, n)
		end
	end
	local data = DataService.Get(player)
	if not data then
		return 0
	end
	local total = 0
	for _, item in data.Items do
		if item.Loc == "Slot" then
			total += Config.ItemIncome(item)
		end
	end
	return total
end

local function getHRP(player: Player): BasePart?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

local function payload(coin: Coin)
	return { Id = coin.Id, Kind = coin.Kind, Position = coin.Position }
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

local function buildField(player: Player): Field
	local seed = (math.floor(os.clock() * 1000) % 1000000) + player.UserId % 100000 * 31
	local field: Field = { coins = {}, rng = Random.new(seed), windowStart = os.clock(), windowCount = 0 }
	for id = 1, FC.Count do
		local kind = pickKind(field.rng)
		local coin: Coin = { Id = id, Kind = kind.Name, Position = Vector3.zero, Alive = true }
		field.coins[id] = coin
		coin.Position = randomPosition(field, id)
	end
	fields[player] = field
	return field
end

local function respawnCoin(player: Player, field: Field, coin: Coin)
	if fields[player] ~= field or player.Parent == nil then
		return
	end
	coin.Kind = pickKind(field.rng).Name
	coin.Position = randomPosition(field, coin.Id)
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
	local kind = kindByName(coin.Kind)
	if not kind then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = getHRP(player)
	if not hrp or not hum or hum.Health <= 0 then
		return
	end

	-- 거리 검증: 자석 반경 + 여유
	local radius = FC.MagnetRadius + FC.MagnetPerFollower * FollowService.GetFollowerCount(player) + PICKUP_SLACK
	local d = hrp.Position - coin.Position
	local flat = Vector3.new(d.X, 0, d.Z).Magnitude
	if flat > radius or math.abs(d.Y) > MAX_HEIGHT_DIFF then
		return
	end

	local income = getIncome(player)
	local boost = FollowService.GetBoost(player)
	local rebirthMult = Config.RebirthCoinMult(DataService.GetRebirths(player))
	local value = math.floor(kind.Value * (1 + income / FC.IncomeScale) * (1 + boost) * rebirthMult)
	if value < 1 then
		value = 1
	end

	coin.Alive = false
	DataService.AddCoins(player, value)
	Remotes.CoinFx:FireClient(player, value, coin.Position)
	DataService.Sync(player)
	Remotes.CoinField:FireClient(player, "Remove", coin.Id)

	task.delay(FC.RespawnTime, respawnCoin, player, field, coin)
end

----------------------------------------------------------------------
-- 공개 API
----------------------------------------------------------------------

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
		if fields[player] then
			sendReset(player)
		end
	end)
end

return CoinFieldService
