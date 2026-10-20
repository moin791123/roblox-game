--!strict
-- 플레이어 데이터: 불러오기/저장/코인/아이템. (설계: docs/DESIGN.md "DataService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

export type Item = {
	Kind: string, -- "Egg" | "Pet"
	Id: string,
	Loc: string, -- "Slot" | "Follow" | "Bag"
	Slot: number?,
	HatchAt: number?,
	HatchLeft: number?,
}

export type Data = {
	Coins: number,
	Pending: number,
	SlotsUnlocked: number,
	Items: { [string]: Item },
	Index: { [string]: boolean },
	NextUid: number,
	LastOnline: number,
	Stats: { Hatched: number, Steals: number },
}

local DataService = {}

local AUTOSAVE_INTERVAL = 90
local MAX_RETRIES = 3

local store: DataStore? = nil
local storeDisabled = false -- Studio 에서 API 접근이 꺼져 있으면 true
local warnedDisabled = false

local cache: { [Player]: Data } = {}
local noSave: { [Player]: boolean } = {}
local saving: { [Player]: boolean } = {}
local syncQueued: { [Player]: boolean } = {}

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
		Coins = Config.StartCoins,
		Pending = 0,
		SlotsUnlocked = Config.Plot.StartSlots,
		Items = {},
		Index = {},
		NextUid = 1,
		LastOnline = os.time(),
		Stats = { Hatched = 0, Steals = 0 },
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

-- 저장된 값을 믿지 않고 하나하나 검사해요. 모르는 id 는 버려요.
local function sanitize(raw: any): Data
	local data = defaultData()
	if type(raw) ~= "table" then
		return data
	end
	local now = os.time()
	data.Coins = math.floor(num(raw.Coins, Config.StartCoins, 0))
	data.Pending = math.floor(num(raw.Pending, 0, 0))
	data.SlotsUnlocked =
		math.floor(num(raw.SlotsUnlocked, Config.Plot.StartSlots, Config.Plot.StartSlots, Config.Plot.TotalSlots))
	data.NextUid = math.floor(num(raw.NextUid, 1, 1))
	data.LastOnline = num(raw.LastOnline, now, 0, now)
	if type(raw.Stats) == "table" then
		data.Stats.Hatched = math.floor(num(raw.Stats.Hatched, 0, 0))
		data.Stats.Steals = math.floor(num(raw.Stats.Steals, 0, 0))
	end
	if type(raw.Index) == "table" then
		for petId, v in raw.Index do
			if type(petId) == "string" and Config.Pets[petId] and v then
				data.Index[petId] = true
			end
		end
	end

	local usedSlots: { [number]: boolean } = {}
	local followCount = 0
	local maxUid = 0
	if type(raw.Items) == "table" then
		-- 정렬해서 처리하면 같은 슬롯 충돌 때 결과가 항상 같아요
		local uids = {}
		for uid in raw.Items do
			if type(uid) == "string" then
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
				data.Index[id] = true
			end
			data.Items[uid] = item
			local n = tonumber(string.match(uid, "^i(%d+)$"))
			if n and n > maxUid then
				maxUid = n
			end
		end
	end
	if data.NextUid <= maxUid then
		data.NextUid = maxUid + 1
	end
	return data
end

-- 접속 안 한 동안 받침대 펫이 번 코인 (OfflineRate 비율)
local function applyOffline(data: Data)
	local elapsed = math.clamp(os.time() - data.LastOnline, 0, Config.Plot.OfflineMaxSeconds)
	if elapsed < 30 then
		return
	end
	local income = 0
	for _, item in data.Items do
		if item.Kind == "Pet" and item.Loc == "Slot" then
			income += Config.Pets[item.Id].Income
		end
	end
	local earned = math.floor(income * elapsed * Config.Plot.OfflineRate)
	if earned > 0 then
		data.Pending += earned
	end
end

local function makeLeaderstats(player: Player)
	local old = player:FindFirstChild("leaderstats")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "💰 코인"
	coins.Parent = folder
	local pets = Instance.new("IntValue")
	pets.Name = "🐾 펫"
	pets.Parent = folder
	folder.Parent = player
end

local function updateLeaderstats(player: Player, data: Data)
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		return
	end
	local coins = folder:FindFirstChild("💰 코인")
	if coins and coins:IsA("IntValue") then
		coins.Value = math.floor(data.Coins)
	end
	local pets = folder:FindFirstChild("🐾 펫")
	if pets and pets:IsA("IntValue") then
		local n = 0
		for _, item in data.Items do
			if item.Kind == "Pet" then
				n += 1
			end
		end
		pets.Value = n
	end
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

function DataService.Start()
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

function DataService.AddCoins(player: Player, n: number)
	local data = cache[player]
	if not data or type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
		return
	end
	data.Coins = math.max(0, math.floor(data.Coins + n))
	DataService.Sync(player)
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
	DataService.Sync(player)
	return true
end

function DataService.AddItem(player: Player, item: Item): string
	local data = cache[player]
	if not data then
		return ""
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

function DataService.MarkDiscovered(player: Player, petId: string): boolean
	local data = cache[player]
	if not data or not Config.Pets[petId] then
		return false
	end
	if data.Index[petId] then
		return false
	end
	data.Index[petId] = true
	return true
end

-- 한 프레임에 한 번만 보내요
function DataService.Sync(player: Player)
	if syncQueued[player] or not cache[player] then
		return
	end
	syncQueued[player] = true
	task.defer(function()
		syncQueued[player] = nil
		local data = cache[player]
		if not data or player.Parent == nil then
			return
		end
		updateLeaderstats(player, data)
		local plotIndex = player:GetAttribute("PlotIndex")
		Remotes.DataSync:FireClient(player, {
			Coins = data.Coins,
			Pending = data.Pending,
			SlotsUnlocked = data.SlotsUnlocked,
			Items = data.Items,
			Index = data.Index,
			PlotIndex = if type(plotIndex) == "number" and plotIndex > 0 then plotIndex else nil,
		})
	end)
end

Players.PlayerRemoving:Connect(function(player)
	-- Release 가 안 불린 경우 대비 (메모리 누수 방지): 조금 뒤 정리
	task.delay(60, function()
		if cache[player] and player.Parent == nil and not saving[player] then
			cache[player] = nil
			noSave[player] = nil
			syncQueued[player] = nil
		end
	end)
end)

return DataService
