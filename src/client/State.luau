-- 클라이언트 상태: 서버 스냅샷(DataSync) + 코인만 바뀔 때 가벼운 갱신(CoinSync) + 내 집(플롯) 모델 찾기
-- 창들이 같이 쓰는 계산(정렬, 합성 가능 수, 열린 지역, 옷장, 가구, 지금 몇 층인지)도 여기 모아 둬요.
-- 스냅샷은 서버가 보낸 그대로 쓰고, 클라이언트는 CoinSync 의 코인 3개 값만 덮어써요.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer

export type Item = {
	Kind: string, -- "Egg" | "Pet"
	Id: string,
	Tier: number?, -- 펫 등급 1..7
	Size: number?, -- 펫 크기 (수익 × 크기)
	Acc: string?, -- 펫이 입은 옷 id
	Loc: string, -- "Slot" | "Follow" | "Ride" | "Hold" | "Bag"
	Slot: number?,
	HatchAt: number?,
	HatchLeft: number?,
}

export type FurniturePiece = { Id: string, Floor: number, X: number, Z: number, R: number }

export type Snapshot = {
	Version: number?,
	Coins: number,
	Pending: number,
	SlotsUnlocked: number,
	Floors: number, -- 1..Config.House.MaxFloors
	Theme: string,
	Themes: { [string]: boolean },
	Items: { [string]: Item },
	Index: { [string]: any }, -- 펫별 최고 등급 (예전 데이터는 true)
	PlotIndex: number?,
	Income: number, -- 진짜 초당 코인 (환생·테마 보너스 포함)
	Rebirths: number,
	RebirthCost: number,
	MaxZone: number, -- 열린 가장 먼 지역
	BagCount: number, -- Loc == "Bag" 인 아이템 수
	Wardrobe: { [string]: boolean }, -- 산 옷
	Furniture: { [string]: FurniturePiece }, -- 집에 놓인 가구 (fid → 정보)
	FurnitureInv: { [string]: number }, -- 가구 가방 (furnId → 개수)
	Stats: { [string]: number },
	Settings: { [string]: any }, -- 켜고 끄는 버튼 (Config.Settings 키만, 없으면 기본값. ★v7 AlertLevel 은 숫자)
}

export type SortedEntry = { Uid: string, Item: Item }
export type BoardRow = { Rank: number, UserId: number, Name: string, Value: number }
export type Board = { Income: { BoardRow }, Rebirths: { BoardRow }, Global: boolean, UpdatedAt: number }

local State = {}
State.Snapshot = nil :: Snapshot?
State.Plot = nil :: Model?
State.Board = nil :: Board? -- 마지막 순위표 (LeaderboardSync)

local syncListeners: { (Snapshot, Snapshot?) -> () } = {}
local coinListeners: { (number, number, number) -> () } = {}
local plotListeners: { (Model?) -> () } = {}
local boardListeners: { (Board) -> () } = {}
local settingListeners: { (string, any) -> () } = {}
local plotsFolder: Instance? = nil

-- 켜고 끄는 버튼: 방금 누른 값 (서버 스냅샷이 같은 값으로 올 때까지 이걸 보여 줘요)
local SETTING_WAIT = 4
type SettingWant = { Value: any, Until: number }
local settingWant: { [string]: SettingWant } = {}
local settingShown: { [string]: any } = {}

-- 숫자 정리 (NaN/무한대/숫자 아님 → nil)
local function num(v: any): number?
	local n = tonumber(v)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	return n
end

----------------------------------------------------------------------
-- 구독
----------------------------------------------------------------------

-- 전체 스냅샷이 올 때마다 (snap, 이전 snap)
function State.OnSync(fn: (Snapshot, Snapshot?) -> ())
	table.insert(syncListeners, fn)
end

-- 코인이 바뀔 때마다 (coins, pending, income). CoinSync 와 전체 DataSync 뒤에 모두 불려요
function State.OnCoins(fn: (number, number, number) -> ())
	table.insert(coinListeners, fn)
end

-- 내 집 모델이 바뀌면 (없으면 nil)
function State.OnPlot(fn: (Model?) -> ())
	table.insert(plotListeners, fn)
end

-- 순위표가 오면
function State.OnBoard(fn: (Board) -> ())
	table.insert(boardListeners, fn)
end

-- 켜고 끄는 버튼 값이 (보이는 값 기준으로) 바뀌면 (key, value). ★v7 AlertLevel 의 value 는 숫자
function State.OnSetting(fn: (string, any) -> ())
	table.insert(settingListeners, fn)
end

----------------------------------------------------------------------
-- 기본 값
----------------------------------------------------------------------

function State.Items(): { [string]: Item }
	local snap = State.Snapshot
	if snap and type(snap.Items) == "table" then
		return snap.Items
	end
	return {}
end

function State.Coins(): number
	local snap = State.Snapshot
	return if snap then snap.Coins else 0
end

function State.Income(): number
	local snap = State.Snapshot
	return if snap then snap.Income else 0
end

function State.Rebirths(): number
	local snap = State.Snapshot
	return if snap then snap.Rebirths else 0
end

function State.Floors(): number
	local snap = State.Snapshot
	return if snap then snap.Floors else 1
end

function State.SlotsUnlocked(): number
	local snap = State.Snapshot
	return if snap then snap.SlotsUnlocked else Config.Plot.StartSlots
end

function State.Theme(): string
	local snap = State.Snapshot
	return if snap then snap.Theme else "Basic"
end

-- 집 받침대 수익에 곱하는 배율 (환생 × 테마 보너스)
function State.IncomeMultiplier(): number
	return Config.IncomeMultiplier(State.Rebirths(), State.Theme())
end

-- 이 아이템이 집 받침대에서 버는 진짜 초당 코인 (알은 0)
function State.RealIncome(item: Item?): number
	if not item then
		return 0
	end
	return Config.ItemIncome(item) * State.IncomeMultiplier()
end

-- 열린 가장 먼 지역 번호 (1..Config.MaxZone)
function State.MaxZone(): number
	local snap = State.Snapshot
	local z = if snap then snap.MaxZone else 1
	return math.clamp(z, 1, Config.MaxZone)
end

-- 그 지역에 들어갈 수 있나
function State.ZoneUnlocked(zone: number): boolean
	return Config.ZoneUnlocked(zone, State.Rebirths())
end

----------------------------------------------------------------------
-- 켜고 끄는 버튼 (Config.Settings: HideHatch / AutoCollect / Magnet / SuperMagnet, ★v7 AlertLevel 숫자)
----------------------------------------------------------------------

-- 지금 값: 방금 누른 값 → 서버 스냅샷 → Config 기본값. AlertLevel 은 숫자 (0..4), 나머지는 true/false
function State.GetSetting(key: string): any
	local want = settingWant[key]
	if want then
		return want.Value
	end
	local snap = State.Snapshot
	local v = if snap and type(snap.Settings) == "table" then Config.SettingValue(key, snap.Settings[key]) else nil
	if v == nil then
		v = (Config.Settings :: any)[key]
	end
	if type(v) == "number" then
		return v
	end
	return v == true
end

local function fireSettings()
	for key in Config.Settings do
		local v = State.GetSetting(key)
		if settingShown[key] ~= v then
			local first = settingShown[key] == nil
			settingShown[key] = v
			if not (first and v == (Config.Settings :: any)[key]) then
				for _, fn in settingListeners do
					task.spawn(fn, key, v)
				end
			end
		end
	end
end

-- 서버 스냅샷이 방금 누른 값을 따라잡았나 (시간이 지나면 서버 값으로 돌아가요)
local function settleSettings()
	local snap = State.Snapshot
	local saved = if snap and type(snap.Settings) == "table" then snap.Settings else {}
	local now = os.clock()
	for key, want in settingWant do
		local v = Config.SettingValue(key, saved[key])
		if v == nil then
			v = Config.SettingValue(key, (Config.Settings :: any)[key])
		end
		if v == want.Value or now >= want.Until then
			settingWant[key] = nil
		end
	end
end

-- 버튼을 누르면 바로 바꿔 보여 줘요 (서버로 보내는 건 부르는 쪽: Remotes.SetSetting)
function State.SetSettingLocal(key: string, value: any)
	if Config.SettingValue(key, value) == nil then
		return
	end
	local want: SettingWant = { Value = value, Until = os.clock() + SETTING_WAIT }
	settingWant[key] = want
	fireSettings()
	-- 서버 답이 끝내 안 오면 서버 값으로 돌아가요
	task.delay(SETTING_WAIT + 0.1, function()
		if settingWant[key] == want then
			settleSettings()
			fireSettings()
		end
	end)
end

----------------------------------------------------------------------
-- 아이템 계산
----------------------------------------------------------------------

-- 펫 등급 (없으면 1)
function State.ItemTier(item: Item?): number
	if not item then
		return 1
	end
	return math.clamp(math.floor(tonumber(item.Tier) or 1), 1, Config.MaxTier)
end

-- 정렬된 아이템 목록 (Config.CompareItems: 펫 수익 높은 순 → 알). filter(uid, item) 로 고를 수 있어요
function State.SortedItems(filter: ((string, Item) -> boolean)?): { SortedEntry }
	local list: { SortedEntry } = {}
	for uid, item in State.Items() do
		if type(item) == "table" and (filter == nil or filter(uid, item)) then
			table.insert(list, { Uid = uid, Item = item })
		end
	end
	table.sort(list, function(a, b)
		return Config.CompareItems(a.Uid, a.Item, b.Uid, b.Item)
	end)
	return list
end

-- 같은 펫·같은 등급이 몇 마리인지 (집 받침대 포함 전부)
function State.CountSame(petId: string, tier: number?): number
	local want = math.max(1, math.floor(tonumber(tier) or 1))
	local n = 0
	for _, item in State.Items() do
		if type(item) == "table" and item.Kind == "Pet" and item.Id == petId and State.ItemTier(item) == want then
			n += 1
		end
	end
	return n
end

-- 합성 재료로 쓸 수 있는 같은 펫·같은 등급 수 (가방/따라옴/타기/들기만, 집 받침대 펫은 빼요)
function State.CountFusable(petId: string, tier: number?): number
	local want = math.max(1, math.floor(tonumber(tier) or 1))
	local n = 0
	for _, item in State.Items() do
		if
			type(item) == "table"
			and item.Kind == "Pet"
			and item.Id == petId
			and State.ItemTier(item) == want
			and Config.CanFuseLoc(item.Loc)
		then
			n += 1
		end
	end
	return n
end

-- 이 펫으로 지금 합성할 수 있나 (집 받침대 펫은 안 돼요)
function State.CanFuse(item: Item?): boolean
	if not item or item.Kind ~= "Pet" or not Config.CanFuseLoc(item.Loc) then
		return false
	end
	local tier = State.ItemTier(item)
	return tier < Config.MaxTier and State.CountFusable(item.Id, tier) >= Config.FuseCount
end

-- 그 위치에 있는 아이템 수
function State.CountLoc(loc: string): number
	local n = 0
	for _, item in State.Items() do
		if type(item) == "table" and item.Loc == loc then
			n += 1
		end
	end
	return n
end

-- 가방 칸 수 (Loc == "Bag")
function State.BagCount(): number
	local snap = State.Snapshot
	return if snap then snap.BagCount else 0
end

function State.BagSpace(): number
	return math.max(0, Config.MaxBagItems - State.BagCount())
end

-- 집 받침대 위 펫 수 (알 제외)
function State.SlotPetCount(): number
	local n = 0
	for _, item in State.Items() do
		if type(item) == "table" and item.Loc == "Slot" and item.Kind == "Pet" then
			n += 1
		end
	end
	return n
end

-- 타고 있는 펫의 uid (없으면 nil)
function State.RideItem(): string?
	for uid, item in State.Items() do
		if type(item) == "table" and item.Loc == "Ride" then
			return uid
		end
	end
	return nil
end

-- 머리 위에 들고 있는 펫의 uid (없으면 nil)
function State.HoldItem(): string?
	for uid, item in State.Items() do
		if type(item) == "table" and item.Loc == "Hold" then
			return uid
		end
	end
	return nil
end

-- 따라오는 펫 수
function State.FollowCount(): number
	return State.CountLoc("Follow")
end

----------------------------------------------------------------------
-- 옷장 / 가구
----------------------------------------------------------------------

function State.Wardrobe(): { [string]: boolean }
	local snap = State.Snapshot
	return if snap then snap.Wardrobe else {}
end

function State.OwnsAccessory(accId: string): boolean
	return State.Wardrobe()[accId] == true
end

-- 산 옷 id 목록 (Config.AccessoryOrder 순서)
function State.OwnedAccessories(): { string }
	local list: { string } = {}
	local wardrobe = State.Wardrobe()
	for _, accId in Config.AccessoryOrder do
		if wardrobe[accId] == true and Config.Accessories[accId] then
			table.insert(list, accId)
		end
	end
	return list
end

-- 가구 가방 (furnId → 개수)
function State.FurnitureInv(): { [string]: number }
	local snap = State.Snapshot
	return if snap then snap.FurnitureInv else {}
end

-- 집에 놓인 가구 (fid → { Id, Floor, X, Z, R })
function State.Furniture(): { [string]: FurniturePiece }
	local snap = State.Snapshot
	return if snap then snap.Furniture else {}
end

function State.CountPlacedFurniture(): number
	local n = 0
	for _ in State.Furniture() do
		n += 1
	end
	return n
end

-- 가구 가방에 든 가구 총 개수
function State.CountFurnitureInv(): number
	local n = 0
	for _, count in State.FurnitureInv() do
		n += tonumber(count) or 0
	end
	return n
end

----------------------------------------------------------------------
-- 내 집 위치
----------------------------------------------------------------------

-- 내 집 번호 (없으면 nil)
function State.PlotIndex(): number?
	local plot = State.Plot
	local idx = if plot then tonumber(plot:GetAttribute("PlotIndex")) else nil
	if not idx then
		idx = tonumber(player:GetAttribute("PlotIndex"))
	end
	if not idx then
		local snap = State.Snapshot
		idx = if snap then snap.PlotIndex else nil
	end
	if idx and idx >= 1 and Config.Layout.Plots[idx] then
		return idx
	end
	return nil
end

-- 내 집 땅 중심 CFrame (집 로컬 좌표의 원점, 입구 = -Z). 집이 없으면 nil
function State.PlotOrigin(): CFrame?
	local idx = State.PlotIndex()
	return if idx then Config.Layout.Plots[idx] else nil
end

-- 내 캐릭터가 내 집 안에 있으면 지금 층 (1..Floors), 아니면 nil
function State.CurrentFloor(): number?
	local origin = State.PlotOrigin()
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not origin or not root or not root:IsA("BasePart") then
		return nil
	end
	local p = origin:PointToObjectSpace(root.Position)
	local half = Config.Layout.PlotSize / 2 + 1
	if math.abs(p.X) > half or math.abs(p.Z) > half or p.Y < -4 then
		return nil
	end
	-- f 층 바닥 윗면 = 0.2 + (f - 1) × FloorHeight, 서 있으면 루트는 그보다 3 정도 위
	local f = math.floor((p.Y - 0.7) / Config.House.FloorHeight) + 1
	return math.clamp(f, 1, State.Floors())
end

----------------------------------------------------------------------
-- 플롯(내 집) 찾기
----------------------------------------------------------------------

function State.RescanPlot()
	local folder = plotsFolder
	if not folder then
		return
	end
	local found: Model? = nil
	for _, m in folder:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("OwnerUserId") == player.UserId then
			found = m
			break
		end
	end
	if not found then
		-- 속성이 아직 안 왔으면 스냅샷의 PlotIndex 로
		local snap = State.Snapshot
		local idx = player:GetAttribute("PlotIndex") or (snap and snap.PlotIndex)
		if idx then
			local m = folder:FindFirstChild("Plot" .. tostring(idx))
			local owner = if m then m:GetAttribute("OwnerUserId") else nil
			if m and m:IsA("Model") and (owner == nil or owner == 0 or owner == player.UserId) then
				found = m
			end
		end
	end
	if found ~= State.Plot then
		State.Plot = found
		for _, fn in plotListeners do
			task.spawn(fn, found)
		end
	end
end

----------------------------------------------------------------------
-- 서버에서 온 값 넣기 (init.client 가 불러요)
----------------------------------------------------------------------

local function fireCoins()
	local snap = State.Snapshot
	if not snap then
		return
	end
	for _, fn in coinListeners do
		task.spawn(fn, snap.Coins, snap.Pending, snap.Income)
	end
end

local function tableOr(v: any, default: { [any]: any }): { [any]: any }
	return if type(v) == "table" then v else default
end

-- 전체 스냅샷 (Remotes.DataSync)
function State.SetSnapshot(snap: any)
	if type(snap) ~= "table" then
		return
	end
	snap.Items = tableOr(snap.Items, {})
	-- 모양이 이상한 아이템은 버려요 (가방·코인 루프가 item.Loc / item.Id 를 바로 읽어요)
	for uid, item in snap.Items do
		if type(uid) ~= "string" or type(item) ~= "table" or type(item.Kind) ~= "string" or type(item.Id) ~= "string" or type(item.Loc) ~= "string" then
			snap.Items[uid] = nil
		end
	end
	snap.Index = tableOr(snap.Index, {})
	snap.Themes = tableOr(snap.Themes, { Basic = true })
	snap.Wardrobe = tableOr(snap.Wardrobe, {})
	snap.Furniture = tableOr(snap.Furniture, {})
	snap.FurnitureInv = tableOr(snap.FurnitureInv, {})
	snap.Stats = tableOr(snap.Stats, {})
	-- 버튼 값: Config.Settings 에 있는 키의 맞는 값만 (true/false, ★v7 AlertLevel 은 0..4 정수. 없는 키 = 기본값)
	local settings: { [string]: any } = {}
	if type(snap.Settings) == "table" then
		for key in Config.Settings do
			local v = Config.SettingValue(key, snap.Settings[key])
			if v ~= nil then
				settings[key] = v
			end
		end
	end
	snap.Settings = settings
	if type(snap.Theme) ~= "string" or not Config.House.Themes[snap.Theme] then
		snap.Theme = "Basic"
	end
	snap.Coins = math.max(0, num(snap.Coins) or 0)
	snap.Pending = math.max(0, num(snap.Pending) or 0)
	snap.Floors = math.clamp(math.floor(num(snap.Floors) or 1), 1, Config.House.MaxFloors)
	snap.SlotsUnlocked = math.clamp(
		math.floor(num(snap.SlotsUnlocked) or Config.Plot.StartSlots),
		Config.Plot.StartSlots,
		snap.Floors * Config.Plot.SlotsPerFloor
	)
	snap.Income = math.max(0, num(snap.Income) or 0)
	snap.Rebirths = math.max(0, math.floor(num(snap.Rebirths) or 0))
	snap.RebirthCost = num(snap.RebirthCost) or Config.RebirthCost(snap.Rebirths)
	snap.MaxZone = math.clamp(math.floor(num(snap.MaxZone) or Config.MaxZoneFor(snap.Rebirths)), 1, Config.MaxZone)
	local bag = num(snap.BagCount)
	if not bag then
		bag = 0
		for _, item in snap.Items do
			if type(item) == "table" and item.Loc == "Bag" then
				bag += 1
			end
		end
	end
	snap.BagCount = math.max(0, math.floor(bag))
	local prev = State.Snapshot
	State.Snapshot = snap
	settleSettings()
	fireSettings()
	for _, fn in syncListeners do
		task.spawn(fn, snap, prev)
	end
	fireCoins()
	State.RescanPlot()
end

-- 코인만 바뀌었을 때 (Remotes.CoinSync). 다음 전체 스냅샷까지 이 값으로 보여요
function State.ApplyCoins(coins: any, pending: any, income: any)
	local snap = State.Snapshot
	if not snap then
		return -- 아직 첫 스냅샷 전 (곧 전체 스냅샷이 와요)
	end
	local c, p, i = num(coins), num(pending), num(income)
	if c then
		snap.Coins = math.max(0, c)
	end
	if p then
		snap.Pending = math.max(0, p)
	end
	if i then
		snap.Income = math.max(0, i)
	end
	fireCoins()
end

-- 순위표 (Remotes.LeaderboardSync)
function State.SetBoard(board: any)
	if type(board) ~= "table" then
		return
	end
	board.Income = tableOr(board.Income, {})
	board.Rebirths = tableOr(board.Rebirths, {})
	board.Global = board.Global == true
	board.UpdatedAt = num(board.UpdatedAt) or os.time()
	State.Board = board
	for _, fn in boardListeners do
		task.spawn(fn, board)
	end
end

local function watchPlot(m: Instance)
	m:GetAttributeChangedSignal("OwnerUserId"):Connect(State.RescanPlot)
end

player:GetAttributeChangedSignal("PlotIndex"):Connect(State.RescanPlot)

task.spawn(function()
	local folder = workspace:FindFirstChild("Plots")
	while not folder do
		task.wait(0.5)
		folder = workspace:FindFirstChild("Plots")
	end
	plotsFolder = folder
	for _, m in folder:GetChildren() do
		watchPlot(m)
	end
	folder.ChildAdded:Connect(function(m)
		watchPlot(m)
		State.RescanPlot()
	end)
	folder.ChildRemoved:Connect(function()
		State.RescanPlot()
	end)
	State.RescanPlot()
end)

return State
