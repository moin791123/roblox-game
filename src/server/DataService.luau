--!strict
-- 플레이어 데이터: 불러오기/저장/코인/아이템/옷장/가구. (설계: docs/DESIGN.md "DataService", v3)
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

export type Item = {
	Kind: string, -- "Egg" | "Pet"
	Id: string,
	Tier: number?, -- 펫만: 1..Config.MaxTier (알은 없음)
	Size: number?, -- 펫만: Config.PetSizeRange(Id) 의 Min..Max (부화 때 뽑음, 없으면 1. ★v7 희귀 펫은 최대 1.5 / 1.7 / 2.0)
	Acc: string?, -- 펫만: 입은 옷 id (Config.Accessories 에 있고 옷장에 있어야 함). 없으면 nil
	Loc: string, -- "Slot" | "Follow" | "Ride" | "Hold" | "Bag" (알은 Slot | Bag)
	Slot: number?,
	HatchAt: number?,
	HatchLeft: number?,
}

-- 집에 놓인 가구 하나. X/Z = 플롯 로컬 좌표 (origin 기준 스터드), R = 0 | 90 | 180 | 270
export type Furniture = { Id: string, Floor: number, X: number, Z: number, R: number }

export type Data = {
	Version: number, -- Config.DataVersion (3)
	Coins: number,
	Pending: number,
	SlotsUnlocked: number, -- Config.Plot.StartSlots .. Floors × 12
	Floors: number, -- 1..Config.House.MaxFloors
	Theme: string, -- 현재 집 테마 id
	Themes: { [string]: boolean }, -- 가진 테마 (Basic 은 항상)
	Items: { [string]: Item },
	Index: { [string]: number }, -- 도감: 펫별 본 적 있는 최고 등급
	NextUid: number,
	LastOnline: number,
	Stats: { Hatched: number, Fused: number },
	Rebirths: number, -- 환생 횟수 (0..Config.Rebirth.MaxRebirths)
	Wardrobe: { [string]: boolean }, -- 산 옷 (accId = true)
	Furniture: { [string]: Furniture }, -- 놓인 가구 (fid "f12" → 가구)
	FurnitureInv: { [string]: number }, -- 가구 가방 (furnId → 개수, 0 이면 키 없음)
	NextFid: number,
	Settings: { [string]: any }, -- ★v5 켜고 끄는 버튼 (Config.Settings 키만, ★v7 AlertLevel 은 숫자)
}

local DataService = {}

local AUTOSAVE_INTERVAL = 90
local MAX_RETRIES = 3
local MIN_SYNC_INTERVAL = 0.2 -- 전체 스냅샷은 최대 초당 5번 (아이템이 많아서)
local INT_MAX = 2 ^ 53 -- leaderstats IntValue 에 넣을 수 있는 안전한 최대값

local store: DataStore? = nil
local storeDisabled = false -- Studio 에서 API 접근이 꺼져 있으면 true
local warnedDisabled = false

local cache: { [Player]: Data } = {}
local noSave: { [Player]: boolean } = {}
local saving: { [Player]: boolean } = {}
local syncQueued: { [Player]: boolean } = {}
local coinQueued: { [Player]: boolean } = {}
local lastSync: { [Player]: number } = {}

do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		storeDisabled = true
		warn("[DataService] DataStore 를 쓸 수 없어요 (저장 안 됨):", result)
	end
end

local function warnDisabledOnce(reason: any)
	if not warnedDisabled then
		warnedDisabled = true
		warn("[DataService] DataStore 사용 불가 - 저장 없이 플레이해요:", reason)
	end
end

-- Studio 에서 API 접근이 꺼져 있을 때 나오는 에러인지
-- (라이브 서버에서는 일시적인 403도 있을 수 있어서 절대 영구 비활성화하지 않음)
local function isAccessError(err: any): boolean
	if not RunService:IsStudio() then
		return false
	end
	local s = tostring(err)
	return string.find(s, "403", 1, true) ~= nil
		or string.find(s, "Studio", 1, true) ~= nil
		or string.find(s, "publish", 1, true) ~= nil
end

local function keyFor(player: Player): string
	return "u_" .. tostring(player.UserId)
end

local function deepCopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local t = {}
	for k, x in v do
		t[k] = deepCopy(x)
	end
	return t
end

local function defaultData(): Data
	return {
		Version = Config.DataVersion,
		Coins = Config.StartCoins,
		Pending = 0,
		SlotsUnlocked = Config.Plot.StartSlots,
		Floors = 1,
		Theme = "Basic",
		Themes = { Basic = true },
		Items = {},
		Index = {},
		NextUid = 1,
		LastOnline = os.time(),
		Stats = { Hatched = 0, Fused = 0 },
		Rebirths = 0,
		Wardrobe = {},
		Furniture = {},
		FurnitureInv = {},
		NextFid = 1,
		Settings = {},
	}
end

local function num(v: any, default: number, min: number?, max: number?): number
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return default
	end
	local n = v :: number
	if min and n < min then
		n = min
	end
	if max and n > max then
		n = max
	end
	return n
end

-- 등급을 1..MaxTier 정수로
local function tierOf(v: any): number
	return math.clamp(math.floor(num(v, 1)), 1, Config.MaxTier)
end

-- v2 이하 저장: 등급 2(황금) → 4(골드), 3(무지개) → 5(레인보우)
local function migrateTier(v: any, oldSave: boolean): number
	local t = math.floor(num(v, 1))
	if oldSave then
		if t == 2 then
			t = 4
		elseif t == 3 then
			t = 5
		end
	end
	return math.clamp(t, 1, Config.MaxTier)
end

-- 옷 id 가 진짜 있고 옷장에 있으면 그대로, 아니면 nil
local function accOf(v: any, wardrobe: { [string]: boolean }): string?
	if type(v) == "string" and Config.Accessories[v] and wardrobe[v] then
		return v
	end
	return nil
end

-- 가구 회전값을 0/90/180/270 으로
local function rotOf(v: any): number
	local r = num(v, 0)
	return (math.floor(r / 90 + 0.5) % 4) * 90
end

local function uidNumber(uid: string, prefix: string): number?
	return tonumber((string.match(uid, "^" .. prefix .. "(%d+)$")))
end

-- 저장된 값을 믿지 않고 하나하나 검사해요. 모르는 id 는 버려요.
local function sanitize(raw: any): Data
	local data = defaultData()
	if type(raw) ~= "table" then
		return data
	end
	local now = os.time()
	local oldSave = num(raw.Version, 0) < 3 -- v2 이하: 등급 번호 옮기기
	local perFloor = Config.Plot.SlotsPerFloor

	data.Coins = math.floor(num(raw.Coins, Config.StartCoins, 0))
	data.Pending = math.floor(num(raw.Pending, 0, 0))
	data.Floors = math.floor(num(raw.Floors, 1, 1, Config.House.MaxFloors))
	-- 받침대: 지금 층까지만, 그리고 맨 위층의 무료 받침대(첫 6개)는 항상 열려 있어요
	data.SlotsUnlocked = math.floor(
		num(raw.SlotsUnlocked, Config.Plot.StartSlots, Config.Plot.StartSlots, data.Floors * perFloor)
	)
	data.SlotsUnlocked = math.max(data.SlotsUnlocked, Config.FloorStartSlots(data.Floors))
	data.NextUid = math.floor(num(raw.NextUid, 1, 1))
	data.NextFid = math.floor(num(raw.NextFid, 1, 1))
	data.LastOnline = num(raw.LastOnline, now, 0, now)
	data.Rebirths = math.floor(num(raw.Rebirths, 0, 0, Config.Rebirth.MaxRebirths))
	if type(raw.Stats) == "table" then
		data.Stats.Hatched = math.floor(num(raw.Stats.Hatched, 0, 0))
		data.Stats.Fused = math.floor(num(raw.Stats.Fused, 0, 0))
	end

	-- 테마: 아는 것만, Basic 은 항상 보유
	if type(raw.Themes) == "table" then
		for themeId, v in raw.Themes do
			if type(themeId) == "string" and Config.House.Themes[themeId] and v then
				data.Themes[themeId] = true
			end
		end
	end
	data.Themes.Basic = true
	if type(raw.Theme) == "string" and Config.House.Themes[raw.Theme] and data.Themes[raw.Theme] then
		data.Theme = raw.Theme
	else
		data.Theme = "Basic"
	end

	-- 옷장: 아는 옷만
	if type(raw.Wardrobe) == "table" then
		for accId, v in raw.Wardrobe do
			if Config.AccessoryValid(accId) and v then
				data.Wardrobe[accId] = true
			end
		end
	end

	-- 도감: 옛 저장(true) 은 1등급으로, 옛 등급 번호는 옮기기
	if type(raw.Index) == "table" then
		for petId, v in raw.Index do
			if type(petId) == "string" and Config.Pets[petId] then
				if v == true then
					data.Index[petId] = 1
				elseif type(v) == "number" then
					data.Index[petId] = migrateTier(v, oldSave)
				end
			end
		end
	end

	local usedSlots: { [number]: boolean } = {}
	local followCount = 0
	local hasRide = false
	local hasHold = false
	local maxUid = 0
	if type(raw.Items) == "table" then
		-- 정렬해서 처리하면 같은 슬롯 충돌 때 결과가 항상 같아요
		local uids = {}
		for uid in raw.Items do
			if type(uid) == "string" and #uid <= 32 then
				table.insert(uids, uid)
			end
		end
		table.sort(uids)
		for _, uid in uids do
			local it = raw.Items[uid]
			if type(it) ~= "table" then
				continue
			end
			local kind = it.Kind
			local id = it.Id
			if type(id) ~= "string" then
				continue
			end
			if kind == "Egg" then
				if not Config.Eggs[id] then
					continue
				end
			elseif kind == "Pet" then
				if not Config.Pets[id] then
					continue
				end
			else
				continue
			end
			local item: Item = { Kind = kind, Id = id, Loc = "Bag" }
			if kind == "Pet" then
				item.Tier = migrateTier(it.Tier, oldSave)
				item.Size = Config.SizeOf(it)
				item.Acc = accOf(it.Acc, data.Wardrobe)
			end
			local loc = it.Loc
			if loc == "Slot" then
				local slot = it.Slot
				if
					type(slot) == "number"
					and slot == math.floor(slot)
					and slot >= 1
					and slot <= data.SlotsUnlocked
					and not usedSlots[slot]
				then
					usedSlots[slot] = true
					item.Loc = "Slot"
					item.Slot = slot
				end
			elseif loc == "Follow" and kind == "Pet" and followCount < Config.MaxFollow then
				followCount += 1
				item.Loc = "Follow"
			elseif loc == "Ride" and kind == "Pet" and not hasRide then
				-- 타는 펫은 딱 한 마리 (나머지는 가방으로)
				hasRide = true
				item.Loc = "Ride"
			elseif loc == "Hold" and kind == "Pet" and not hasHold then
				-- 들고 있는 펫도 딱 한 마리
				hasHold = true
				item.Loc = "Hold"
			end
			if kind == "Egg" then
				local hatchTime = Config.Eggs[id].HatchTime
				if item.Loc == "Slot" then
					if type(it.HatchAt) == "number" and it.HatchAt == it.HatchAt then
						item.HatchAt = math.min(it.HatchAt, now + hatchTime)
					elseif type(it.HatchLeft) == "number" then
						item.HatchAt = now + num(it.HatchLeft, hatchTime, 0, hatchTime)
					else
						item.HatchAt = now + hatchTime
					end
				else
					if type(it.HatchLeft) == "number" then
						item.HatchLeft = num(it.HatchLeft, hatchTime, 0, hatchTime)
					elseif type(it.HatchAt) == "number" then
						item.HatchLeft = num(it.HatchAt - now, hatchTime, 0, hatchTime)
					else
						item.HatchLeft = hatchTime
					end
				end
			else
				local tier = item.Tier or 1
				if (data.Index[id] or 0) < tier then
					data.Index[id] = tier
				end
			end
			data.Items[uid] = item
			local n = uidNumber(uid, "i")
			if n and n > maxUid then
				maxUid = n
			end
		end
	end
	if data.NextUid <= maxUid then
		data.NextUid = maxUid + 1
	end

	-- 가구 가방: 아는 가구만, 정수 1..MaxPerItem
	if type(raw.FurnitureInv) == "table" then
		for furnId, v in raw.FurnitureInv do
			if type(furnId) == "string" and Config.Furniture[furnId] then
				local n = math.floor(num(v, 0, 0, Config.Decor.MaxPerItem))
				if n > 0 then
					data.FurnitureInv[furnId] = n
				end
			end
		end
	end

	-- 놓인 가구: 모양만 검사 (집 크기·계단 겹침은 ShopService.Validate 가 집을 받은 뒤에 다시 검사)
	-- 이상한 건 가구 가방으로 돌려보내요
	local maxFid = 0
	if type(raw.Furniture) == "table" then
		local fids = {}
		for fid in raw.Furniture do
			if type(fid) == "string" and uidNumber(fid, "f") then
				table.insert(fids, fid)
			end
		end
		table.sort(fids, function(a, b)
			return (uidNumber(a, "f") or 0) < (uidNumber(b, "f") or 0)
		end)
		local half = Config.Layout.PlotSize / 2
		local placed = 0
		for _, fid in fids do
			local f = raw.Furniture[fid]
			if type(f) ~= "table" or type(f.Id) ~= "string" or not Config.Furniture[f.Id] then
				continue
			end
			local furnId = f.Id :: string
			local n = uidNumber(fid, "f") or 0
			if n > maxFid then
				maxFid = n
			end
			local floorNum = num(f.Floor, 0)
			local x = num(f.X, math.huge)
			local z = num(f.Z, math.huge)
			local ok = placed < Config.Decor.MaxPlaced
				and floorNum == math.floor(floorNum)
				and floorNum >= 1
				and floorNum <= data.Floors
				and math.abs(x) <= half
				and math.abs(z) <= half
			if ok then
				placed += 1
				data.Furniture[fid] = { Id = furnId, Floor = floorNum, X = x, Z = z, R = rotOf(f.R) }
			else
				data.FurnitureInv[furnId] = math.min((data.FurnitureInv[furnId] or 0) + 1, Config.Decor.MaxPerItem)
			end
		end
	end
	if data.NextFid <= maxFid then
		data.NextFid = maxFid + 1
	end

	if type(raw.Settings) == "table" then
		for key in Config.Settings do
			local v = Config.SettingValue(key, raw.Settings[key]) -- ★v7 AlertLevel 은 0..4 정수, 나머지는 true/false
			if v ~= nil then
				data.Settings[key] = v
			end
		end
	end

	data.Version = Config.DataVersion
	return data
end

-- 받침대 위 펫들의 초당 수익 합계 (등급·크기 × 환생 배율 × (1 + 집 테마 보너스))
local function incomeOf(data: Data): number
	local income = 0
	for _, item in data.Items do
		if item.Loc == "Slot" then
			income += Config.ItemIncome(item)
		end
	end
	return income * Config.IncomeMultiplier(data.Rebirths, data.Theme)
end

-- 접속 안 한 동안 받침대 펫이 번 코인 (OfflineRate 비율)
local function applyOffline(data: Data)
	local elapsed = math.clamp(os.time() - data.LastOnline, 0, Config.Plot.OfflineMaxSeconds)
	if elapsed < 30 then
		return
	end
	local earned = math.floor(incomeOf(data) * elapsed * Config.Plot.OfflineRate)
	if earned > 0 then
		data.Pending += earned
	end
end

-- 플레이어 목록 점수: 💰 코인, ⚡ 초당, 🔄 환생
local STAT_COINS = "💰 코인"
local STAT_INCOME = "⚡ 초당"
local STAT_REBIRTHS = "🔄 환생"

local function makeLeaderstats(player: Player)
	local old = player:FindFirstChild("leaderstats")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	for _, name in { STAT_COINS, STAT_INCOME, STAT_REBIRTHS } do
		local v = Instance.new("IntValue")
		v.Name = name
		v.Parent = folder
	end
	folder.Parent = player
end

local function setStat(folder: Instance, name: string, value: number)
	local v = folder:FindFirstChild(name)
	if v and v:IsA("IntValue") then
		v.Value = math.clamp(math.floor(value), 0, INT_MAX)
	end
end

local function updateLeaderstats(player: Player, data: Data)
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		return
	end
	setStat(folder, STAT_COINS, data.Coins)
	setStat(folder, STAT_INCOME, incomeOf(data))
	setStat(folder, STAT_REBIRTHS, data.Rebirths)
end

local function countBag(data: Data): number
	local n = 0
	for _, item in data.Items do
		if item.Loc == "Bag" then
			n += 1
		end
	end
	return n
end

----------------------------------------------------------------------
-- 공개 API
----------------------------------------------------------------------

function DataService.Load(player: Player): Data?
	if cache[player] then
		return cache[player]
	end
	local raw: any = nil
	local failed = false
	local currentStore = store
	if storeDisabled or not currentStore then
		failed = true
		warnDisabledOnce("DataStore 없음")
	else
		local s = currentStore :: DataStore
		local loaded = false
		for attempt = 1, MAX_RETRIES do
			local ok, result = pcall(function()
				return s:GetAsync(keyFor(player))
			end)
			if ok then
				raw = result
				loaded = true
				break
			end
			if isAccessError(result) then
				storeDisabled = true
				warnDisabledOnce(result)
				break
			end
			warn(string.format("[DataService] %s 불러오기 실패 (%d/%d): %s", player.Name, attempt, MAX_RETRIES, tostring(result)))
			if player.Parent == nil then
				break
			end
			if attempt < MAX_RETRIES then
				task.wait(attempt * 1.5)
			end
		end
		failed = not loaded
	end

	if player.Parent == nil then
		return nil -- 불러오는 동안 나갔어요
	end

	local data = sanitize(raw)
	applyOffline(data)
	data.LastOnline = os.time()
	cache[player] = data
	if failed then
		-- 진짜 데이터를 기본값으로 덮어쓰지 않도록 저장 금지
		noSave[player] = true
		if not storeDisabled then
			task.defer(function()
				if player.Parent then
					Remotes.Notify:FireClient(player, "데이터를 못 불러왔어요. 이번 판은 저장되지 않아요 😢", "warn")
				end
			end)
		end
	end
	makeLeaderstats(player)
	updateLeaderstats(player, data)
	return data
end

function DataService.Get(player: Player): Data?
	return cache[player]
end

-- 이 사람 데이터를 저장해도 되나 (불러오기에 실패한 판은 false: 기본값으로 진짜 저장/순위를 덮지 않게)
function DataService.CanSave(player: Player): boolean
	return cache[player] ~= nil and not noSave[player]
end

function DataService.Save(player: Player)
	local data = cache[player]
	if not data or noSave[player] or storeDisabled or not store then
		return
	end
	-- 이미 저장 중이면 끝날 때까지 기다렸다가 최신 값으로 다시 저장
	local waited = 0
	while saving[player] and waited < 30 do
		waited += task.wait(0.2)
	end
	data = cache[player]
	if not data then
		return
	end
	saving[player] = true
	data.LastOnline = os.time()
	data.Version = Config.DataVersion
	local payload = deepCopy(data)
	local s = store :: DataStore
	for attempt = 1, MAX_RETRIES do
		local ok, err = pcall(function()
			s:UpdateAsync(keyFor(player), function()
				return payload
			end)
		end)
		if ok then
			break
		end
		if isAccessError(err) then
			storeDisabled = true
			warnDisabledOnce(err)
			break
		end
		warn(string.format("[DataService] %s 저장 실패 (%d/%d): %s", player.Name, attempt, MAX_RETRIES, tostring(err)))
		if attempt < MAX_RETRIES then
			task.wait(attempt)
		end
	end
	saving[player] = nil
end

function DataService.Release(player: Player)
	if cache[player] then
		DataService.Save(player)
	end
	cache[player] = nil
	noSave[player] = nil
	saving[player] = nil
	syncQueued[player] = nil
	coinQueued[player] = nil
	lastSync[player] = nil
end

function DataService.SaveAll()
	local list = {}
	for player in cache do
		table.insert(list, player)
	end
	local remaining = #list
	for _, player in list do
		task.spawn(function()
			local ok, err = pcall(function()
				DataService.Save(player)
			end)
			if not ok then
				warn("[DataService] SaveAll 오류:", err)
			end
			remaining -= 1
		end)
	end
	local t = 0
	while remaining > 0 and t < 25 do
		t += task.wait(0.1)
	end
end

-- ★v5 켜고 끄는 버튼 값 (저장 안 된 키는 Config.Settings 기본값). ★v7 AlertLevel 은 숫자, 나머지는 true/false
function DataService.GetSetting(player: Player, key: string): any
	local data = cache[player]
	local v = Config.SettingValue(key, if data then data.Settings[key] else nil)
	if v == nil then
		v = Config.SettingValue(key, (Config.Settings :: any)[key])
	end
	if type(v) == "number" then
		return v
	end
	return v == true
end

-- ★v7 알 알림 단계 (0 = 모두 받기 .. #Config.AlertLevels - 1)
function DataService.GetAlertLevel(player: Player): number
	local v = DataService.GetSetting(player, "AlertLevel")
	return if type(v) == "number" then v else 0
end

local settingListeners: { (Player, string, any) -> () } = {}

-- 버튼 값이 바뀔 때 (다른 서비스가 바로 반응하고 싶을 때)
function DataService.OnSettingChanged(fn: (Player, string, any) -> ())
	table.insert(settingListeners, fn)
end

-- 값 검사는 Config.SettingValue (모르는 키 / 맞지 않는 값이면 false)
function DataService.SetSetting(player: Player, key: string, value: any): boolean
	local data = cache[player]
	local v = Config.SettingValue(key, value)
	if not data or v == nil then
		return false
	end
	data.Settings[key] = v
	for _, fn in settingListeners do
		task.spawn(fn, player, key, v)
	end
	DataService.Sync(player)
	return true
end

function DataService.Start()
	Remotes.SetSetting.OnServerEvent:Connect(function(player, key, value)
		if type(key) == "string" then
			DataService.SetSetting(player, key, value) -- ★v7 값 검사는 SetSetting 안에서 (AlertLevel 은 숫자)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			-- 기다리는 동안 cache 가 바뀔 수 있어서 목록을 먼저 복사 (next() 오류 방지)
			local list = {}
			for player in cache do
				table.insert(list, player)
			end
			for _, player in list do
				if player.Parent and cache[player] then
					task.spawn(function()
						local ok, err = pcall(function()
							DataService.Save(player)
						end)
						if not ok then
							warn("[DataService] 자동 저장 오류:", err)
						end
					end)
					task.wait(0.5)
				end
			end
		end
	end)
end

-- 코인 더하기 (빼기는 TrySpend). 코인만 바뀌므로 가벼운 CoinSync 를 보내요
function DataService.AddCoins(player: Player, n: number)
	local data = cache[player]
	if not data or type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
		return
	end
	data.Coins = math.max(0, math.floor(data.Coins + n))
	DataService.SyncCoins(player)
end

function DataService.TrySpend(player: Player, n: number): boolean
	local data = cache[player]
	if not data or type(n) ~= "number" or n ~= n or n < 0 or n == math.huge then
		return false
	end
	if data.Coins < n then
		return false
	end
	data.Coins -= n
	DataService.SyncCoins(player)
	return true
end

function DataService.AddItem(player: Player, item: Item): string
	local data = cache[player]
	if not data then
		return ""
	end
	if item.Kind == "Pet" then
		item.Tier = tierOf(item.Tier)
		item.Size = Config.SizeOf(item)
		item.Acc = accOf(item.Acc, data.Wardrobe)
	else
		item.Tier = nil
		item.Size = nil
		item.Acc = nil
	end
	local uid = "i" .. tostring(data.NextUid)
	while data.Items[uid] do
		data.NextUid += 1
		uid = "i" .. tostring(data.NextUid)
	end
	data.NextUid += 1
	data.Items[uid] = item
	return uid
end

function DataService.RemoveItem(player: Player, uid: string): Item?
	local data = cache[player]
	if not data or type(uid) ~= "string" then
		return nil
	end
	local item = data.Items[uid]
	data.Items[uid] = nil
	return item
end

function DataService.GetItem(player: Player, uid: string): Item?
	local data = cache[player]
	if not data or type(uid) ~= "string" then
		return nil
	end
	return data.Items[uid]
end

function DataService.CountItems(player: Player, loc: string?): number
	local data = cache[player]
	if not data then
		return 0
	end
	local n = 0
	for _, item in data.Items do
		if loc == nil or item.Loc == loc then
			n += 1
		end
	end
	return n
end

-- 위치별 아이템 수 { Bag = n, Slot = n, Follow = n, Ride = n, Hold = n } (없는 곳도 0)
function DataService.CountByLoc(player: Player): { [string]: number }
	local counts: { [string]: number } = { Bag = 0, Slot = 0, Follow = 0, Ride = 0, Hold = 0 }
	local data = cache[player]
	if not data then
		return counts
	end
	for _, item in data.Items do
		counts[item.Loc] = (counts[item.Loc] or 0) + 1
	end
	return counts
end

-- 가방 안 아이템 수 / 남은 칸
function DataService.BagCount(player: Player): number
	local data = cache[player]
	return if data then countBag(data) else 0
end

-- ★v7.1 가방 칸 수: ♾ 가방 무한이 켜져 있으면 Config.InfiniteBagItems, 아니면 Config.MaxBagItems
function DataService.BagCapacity(player: Player): number
	local data = cache[player]
	return Config.BagCapacity(data ~= nil and data.Settings.InfiniteBag == true)
end

-- 남은 칸 (★v7.1 무한을 끄면 칸을 넘은 만큼은 그대로 두고 0: 칸 아래로 줄 때까지 "가득")
function DataService.BagSpace(player: Player): number
	local data = cache[player]
	if not data then
		return 0
	end
	return math.max(0, DataService.BagCapacity(player) - countBag(data))
end

-- 받침대 번호 → uid (알·펫 모두)
function DataService.GetSlotMap(player: Player): { [number]: string }
	local map: { [number]: string } = {}
	local data = cache[player]
	if not data then
		return map
	end
	for uid, item in data.Items do
		if item.Loc == "Slot" and type(item.Slot) == "number" then
			map[item.Slot :: number] = uid
		end
	end
	return map
end

-- 정렬된 아이템 목록 (Config.CompareItems: 펫 수익 높은 순 → 알). filter 로 고를 수 있어요
function DataService.GetItemsSorted(player: Player, filter: ((uid: string, item: Item) -> boolean)?): { { Uid: string, Item: Item } }
	local list: { { Uid: string, Item: Item } } = {}
	local data = cache[player]
	if not data then
		return list
	end
	for uid, item in data.Items do
		if filter == nil or filter(uid, item) then
			table.insert(list, { Uid = uid, Item = item })
		end
	end
	table.sort(list, function(a, b)
		return Config.CompareItems(a.Uid, a.Item, b.Uid, b.Item)
	end)
	return list
end

-- 같은 펫·같은 등급이 몇 마리인지 (어디 있든)
function DataService.CountSame(player: Player, petId: string, tier: number): number
	local data = cache[player]
	if not data then
		return 0
	end
	local want = tierOf(tier)
	local n = 0
	for _, item in data.Items do
		if item.Kind == "Pet" and item.Id == petId and (item.Tier or 1) == want then
			n += 1
		end
	end
	return n
end

-- 합성 재료로 쓸 수 있는 같은 펫·같은 등급 uid 목록 (집 받침대 펫 제외).
-- 먼저 쓸 순서: 가방 → 따라옴 → 들기 → 타기, 같은 곳이면 오래된(uid 작은) 것부터
local FUSE_RANK = { Bag = 1, Follow = 2, Hold = 3, Ride = 4 }
function DataService.FusableUids(player: Player, petId: string, tier: number): { string }
	local list: { string } = {}
	local data = cache[player]
	if not data then
		return list
	end
	local want = tierOf(tier)
	for uid, item in data.Items do
		if item.Kind == "Pet" and item.Id == petId and (item.Tier or 1) == want and Config.CanFuseLoc(item.Loc) then
			table.insert(list, uid)
		end
	end
	local items = data.Items
	table.sort(list, function(a, b)
		local ra = FUSE_RANK[items[a].Loc] or 9
		local rb = FUSE_RANK[items[b].Loc] or 9
		if ra ~= rb then
			return ra < rb
		end
		return (uidNumber(a, "i") or 0) < (uidNumber(b, "i") or 0)
	end)
	return list
end

-- 도감 기록. 새 펫이거나 더 높은 등급이면 true
function DataService.MarkDiscovered(player: Player, petId: string, tier: number?): boolean
	local data = cache[player]
	if not data or not Config.Pets[petId] then
		return false
	end
	local t = tierOf(tier)
	local seen = data.Index[petId] or 0
	if seen >= t then
		return false
	end
	data.Index[petId] = t
	return true
end

-- 집 받침대 펫들의 초당 수익 (환생 배율 × 집 테마 보너스 포함 = 진짜 초당 코인)
function DataService.GetIncome(player: Player): number
	local data = cache[player]
	if not data then
		return 0
	end
	return incomeOf(data)
end

-- 환생 횟수 (데이터가 없으면 0)
function DataService.GetRebirths(player: Player): number
	local data = cache[player]
	if not data then
		return 0
	end
	return data.Rebirths
end

-- 열린 가장 먼 지역 번호 (환생 수로 계산)
function DataService.GetMaxZone(player: Player): number
	return Config.MaxZoneFor(DataService.GetRebirths(player))
end

-- 옷장에 그 옷이 있나
function DataService.HasAccessory(player: Player, accId: string): boolean
	local data = cache[player]
	return data ~= nil and Config.AccessoryValid(accId) and data.Wardrobe[accId] == true
end

-- 놓인 가구 수
function DataService.CountPlacedFurniture(player: Player): number
	local data = cache[player]
	if not data then
		return 0
	end
	local n = 0
	for _ in data.Furniture do
		n += 1
	end
	return n
end

-- 새 가구 id ("f12")
function DataService.NewFurnitureId(player: Player): string
	local data = cache[player]
	if not data then
		return ""
	end
	local fid = "f" .. tostring(data.NextFid)
	while data.Furniture[fid] do
		data.NextFid += 1
		fid = "f" .. tostring(data.NextFid)
	end
	data.NextFid += 1
	return fid
end

-- 가구 가방에 n 개 넣기 (MaxPerItem 을 넘으면 false, 아무것도 안 바뀜)
function DataService.AddFurnitureInv(player: Player, furnId: string, n: number?): boolean
	local data = cache[player]
	if not data or not Config.Furniture[furnId] then
		return false
	end
	local add = math.max(1, math.floor(n or 1))
	local have = data.FurnitureInv[furnId] or 0
	if have + add > Config.Decor.MaxPerItem then
		return false
	end
	data.FurnitureInv[furnId] = have + add
	return true
end

-- 가구 가방에서 1개 꺼내기 (없으면 false)
function DataService.TakeFurnitureInv(player: Player, furnId: string): boolean
	local data = cache[player]
	if not data then
		return false
	end
	local have = data.FurnitureInv[furnId] or 0
	if have <= 0 then
		return false
	end
	if have == 1 then
		data.FurnitureInv[furnId] = nil
	else
		data.FurnitureInv[furnId] = have - 1
	end
	return true
end

-- 코인/수금 대기/초당 수익만 가볍게 보내요 (전체 스냅샷이 곧 가면 생략). 한 프레임에 한 번
function DataService.SyncCoins(player: Player)
	if coinQueued[player] or syncQueued[player] or not cache[player] then
		return
	end
	coinQueued[player] = true
	task.defer(function()
		coinQueued[player] = nil
		local data = cache[player]
		if not data or player.Parent == nil or syncQueued[player] then
			return
		end
		updateLeaderstats(player, data)
		Remotes.CoinSync:FireClient(player, data.Coins, math.floor(data.Pending), incomeOf(data))
	end)
end

-- 전체 스냅샷 (아이템/집/옷장/가구가 바뀌었을 때). 여러 번 불러도 모아서 최대 초당 5번 보내요
function DataService.Sync(player: Player)
	if syncQueued[player] or not cache[player] then
		return
	end
	syncQueued[player] = true
	local function send()
		syncQueued[player] = nil
		lastSync[player] = os.clock()
		local data = cache[player]
		if not data or player.Parent == nil then
			return
		end
		updateLeaderstats(player, data)
		local plotIndex = player:GetAttribute("PlotIndex")
		Remotes.DataSync:FireClient(player, {
			Version = data.Version,
			Coins = data.Coins,
			Pending = math.floor(data.Pending),
			SlotsUnlocked = data.SlotsUnlocked,
			Floors = data.Floors,
			Theme = data.Theme,
			Themes = data.Themes,
			Items = data.Items,
			Index = data.Index,
			PlotIndex = if type(plotIndex) == "number" and plotIndex > 0 then plotIndex else nil,
			Income = incomeOf(data),
			Rebirths = data.Rebirths,
			RebirthCost = Config.RebirthCost(data.Rebirths),
			MaxZone = Config.MaxZoneFor(data.Rebirths),
			BagCount = countBag(data),
			Wardrobe = data.Wardrobe,
			Furniture = data.Furniture,
			FurnitureInv = data.FurnitureInv,
			Stats = data.Stats,
			Settings = data.Settings, -- ★v5 (없는 키는 Config.Settings 기본값)
		})
	end
	local waitLeft = MIN_SYNC_INTERVAL - (os.clock() - (lastSync[player] or 0))
	if waitLeft > 0 then
		task.delay(waitLeft, send)
	else
		task.defer(send)
	end
end

Players.PlayerRemoving:Connect(function(player)
	-- Release 가 안 불린 경우 대비 (메모리 누수 방지): 조금 뒤 정리
	task.delay(60, function()
		if cache[player] and player.Parent == nil and not saving[player] then
			cache[player] = nil
			noSave[player] = nil
			syncQueued[player] = nil
			coinQueued[player] = nil
			lastSync[player] = nil
		end
	end)
end)

return DataService
