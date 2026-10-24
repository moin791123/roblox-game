-- ★v7.4 🛠 관리자 페이지 (서버): Remotes.Admin(op, payload) 를 받아요. 관리자인지는 서버가 UserId 로만 봐요
-- (Config.IsAdminUserId: Config.AdminUserIds + 사람이 만든 게임의 주인 game.CreatorId). 클라이언트가 보낸 건 하나도 안 믿어요.
-- 관리자가 아니면 아무것도 안 하고 서버 경고만 남겨요 (한 사람당 Config.Admin.WarnGap 초에 한 번).
-- 관리자에게만 플레이어 속성 IsAdmin = true (클라이언트는 그걸 보고 🛠 버튼을 보여 줘요. 그래도 부를 때마다 서버가 다시 봐요).
-- 대상(payload.Target) = 지금 이 서버에 있고 데이터가 다 불러진 사람의 UserId (없으면 나). 값은 모두 검사해요 (타입·범위·아는 id).
-- op: "Refresh" (정보만) · "Coins" (+정해진 값 / ×10, Config.Admin.CoinCap 까지) · "Pet" (아무 펫, 등급 1..7, 크기는 그 펫 범위 → 가방)
--   · "Egg" (아무 알 → 가방, 가방이 차면 빈 받침대) · "RareEgg" (열린 지역 벨트에 희귀 알 소환, 알림은 그대로)
--   · "Grant" (🧲 ⚡ 🏦 ★v7.5 ♾ 공짜 선물 켜기/끄기, 저장 AdminGrants) · "Rebirth" (+1 공짜, 코인 그대로) · "Announce" (📢 글자 검사 후 모두에게).
-- 끝나면 관리자에게 짧은 말풍선, 다른 사람에게 줬으면 그 사람에게 "🎁 관리자 선물: …", 관리자 창에는 "State" (사람마다 코인·환생·가방·선물).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local PassService = require(script.Parent.PassService)
local PlotService = require(script.Parent.PlotService)

local AdminService = {}

local A = Config.Admin
local ATTR = "IsAdmin"
local SPECIAL_TIERS = { Hidden = true, Celestial = true, Eternal = true }
local LOAD_WAIT = 60 -- 들어온 사람 데이터를 기다리는 최대 초 (관리자 창 목록 새로 고침용)

local lastOp: { [Player]: number } = {}
local lastRefresh: { [Player]: number } = {}
local lastAnnounce: { [Player]: number } = {}
local lastWarn: { [Player]: number } = {}
local stateQueued: { [Player]: boolean } = {}
local started = false

-- 컨베이어는 없을 수도 있어서 (init.server 처럼) 처음 쓸 때 pcall 로 불러요
local conveyor: any = nil
local function getConveyor(): any
	if conveyor == nil then
		local ok, result = pcall(function()
			return require(script.Parent:FindFirstChild("ConveyorService") :: any)
		end)
		conveyor = if ok and type(result) == "table" then result else false
	end
	return if conveyor then conveyor else nil
end

local function notify(player: Player, text: string, kind: string)
	if player.Parent then
		Remotes.Notify:FireClient(player, text, kind)
	end
end

-- 마지막 글자 받침이 있으면 a ("곰이"), 없으면 b ("꼬마가")
local function josa(name: string, a: string, b: string): string
	local last: number? = nil
	for _, cp in utf8.codes(name) do
		last = cp
	end
	if last and last >= 0xAC00 and last <= 0xD7A3 and (last - 0xAC00) % 28 ~= 0 then
		return name .. a
	end
	return name .. b
end

local function isAdmin(player: Player): boolean
	return Config.IsAdminUserId(player.UserId)
end

-- 말풍선에 쓰는 이름 ("나" = 관리자 자신)
local function nameOf(admin: Player, target: Player): string
	return if target == admin then "나" else target.DisplayName
end

-- 다른 사람에게 줬으면 그 사람에게 귀여운 말풍선
local function gift(admin: Player, target: Player, what: string)
	if target ~= admin then
		notify(target, "🎁 관리자 선물: " .. what .. "!", "good")
	end
end

local function intIn(v: any, lo: number, hi: number): number?
	if type(v) ~= "number" or v ~= v or v ~= math.floor(v) or v < lo or v > hi then
		return nil
	end
	return v
end

-- 아는 id 인가 (짧은 글자 + 그 표에 있어야 해요)
local function idIn(v: any, list: { [string]: any }): string?
	if type(v) ~= "string" or #v == 0 or #v > 32 then
		return nil
	end
	return if list[v] ~= nil then v else nil
end

local function badValue(admin: Player)
	notify(admin, "⚠️ 이상한 값이라 안 했어요", "warn")
end

----------------------------------------------------------------------
-- 관리자 창 정보 ("State")
----------------------------------------------------------------------
local function stateOf(p: Player): { [string]: any }?
	local data = DataService.Get(p)
	if not data or p.Parent ~= Players then
		return nil
	end
	local grants: { [string]: boolean } = {}
	local bought: { [string]: boolean } = {}
	for _, key in Config.PassOrder do
		grants[key] = DataService.HasGrant(p, key)
		bought[key] = PassService.Bought(p, key)
	end
	return {
		UserId = p.UserId,
		Name = p.DisplayName,
		User = p.Name,
		Coins = data.Coins,
		Rebirths = data.Rebirths,
		Bag = DataService.BagCount(p),
		BagCap = DataService.BagCapacity(p),
		Admin = isAdmin(p),
		Grants = grants,
		Bought = bought,
	}
end

-- 이 관리자에게 지금 서버 사람들 정보 (나 먼저, 그다음 이름 순)
local function sendState(admin: Player)
	if admin.Parent ~= Players or not isAdmin(admin) then
		return
	end
	local list: { { [string]: any } } = {}
	for _, p in Players:GetPlayers() do
		local s = stateOf(p)
		if s then
			table.insert(list, s)
		end
	end
	table.sort(list, function(a, b)
		local am, bm = a.UserId == admin.UserId, b.UserId == admin.UserId
		if am ~= bm then
			return am
		end
		if a.Name ~= b.Name then
			return a.Name < b.Name
		end
		return a.UserId < b.UserId
	end)
	Remotes.Admin:FireClient(admin, "State", { Players = list })
end

-- 한 프레임에 한 번만 보내요 (op 를 여러 번 해도)
local function queueState(admin: Player)
	if stateQueued[admin] then
		return
	end
	stateQueued[admin] = true
	task.defer(function()
		stateQueued[admin] = nil
		sendState(admin)
	end)
end

-- 이 서버의 관리자 모두에게 (누가 들어오거나 나갔을 때)
local function queueAll()
	for _, p in Players:GetPlayers() do
		if isAdmin(p) then
			queueState(p)
		end
	end
end

----------------------------------------------------------------------
-- op 들 (admin = 관리자, target = 데이터가 있는 이 서버 사람)
----------------------------------------------------------------------
type Payload = { [any]: any }

-- 💰 코인: Add = Config.Admin.CoinAdds 중 하나, 또는 Times = 10 (지금 코인 ×10, 적어도 TimesMinAdd). CoinCap 까지만
local function opCoins(admin: Player, target: Player, payload: Payload)
	local data = DataService.Get(target)
	if not data then
		return
	end
	local add: number
	if payload.Times ~= nil then
		if payload.Times ~= 10 or payload.Add ~= nil then
			badValue(admin)
			return
		end
		add = math.max(A.TimesMinAdd, data.Coins * 9)
	else
		local n = payload.Add
		if type(n) ~= "number" or not table.find(A.CoinAdds, n) then
			badValue(admin)
			return
		end
		add = n
	end
	add = math.floor(math.min(add, A.CoinCap - data.Coins))
	if add <= 0 then
		notify(admin, "💰 " .. josa(nameOf(admin, target), "은", "는") .. " 이미 최대 코인이에요! (" .. Config.FormatNumber(A.CoinCap) .. ")", "info")
		return
	end
	DataService.AddCoins(target, add)
	local character = target.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		Remotes.CoinFx:FireClient(target, add, hrp.Position + Vector3.new(0, 3, 0))
	end
	local amount = Config.FormatNumber(add)
	notify(admin, "✅ " .. nameOf(admin, target) .. "에게 💰 +" .. amount .. " 코인!", "good")
	gift(admin, target, "💰 " .. amount .. " 코인")
end

-- 🐾 펫: 아무 펫 (희귀 펫도), 등급 1..MaxTier, 크기는 그 펫 범위 안 (0.01 단위로) → 가방. 가방이 차면 안 줘요
local function opPet(admin: Player, target: Player, payload: Payload)
	local petId = idIn(payload.PetId, Config.Pets)
	local tier = intIn(payload.Tier, 1, Config.MaxTier)
	local size = payload.Size
	if not petId or not tier or type(size) ~= "number" or size ~= size then
		badValue(admin)
		return
	end
	local range = Config.PetSizeRange(petId)
	if size < range.Min - 1e-6 or size > range.Max + 1e-6 then
		badValue(admin)
		return
	end
	size = math.clamp(math.floor(size * 100 + 0.5) / 100, range.Min, range.Max)
	if DataService.BagSpace(target) <= 0 then
		notify(admin, "🎒 " .. nameOf(admin, target) .. " 가방이 가득 찼어요! 조금 비워 주세요", "warn")
		return
	end
	local uid = DataService.AddItem(target, { Kind = "Pet", Id = petId, Tier = tier, Size = size, Loc = "Bag" })
	if uid == "" then
		return
	end
	local isNew = DataService.MarkDiscovered(target, petId, tier)
	DataService.Sync(target)
	local label = Config.SizeLabel(size, petId)
	local name = (if label ~= "" then label .. " " else "") .. Config.PetDisplayName(petId, tier)
	notify(admin, "✅ " .. nameOf(admin, target) .. "에게 🐾 " .. name .. (if isNew then " 🆕" else "") .. " (가방)", "good")
	gift(admin, target, "🐾 " .. name .. (if isNew then " 🆕 NEW" else ""))
end

-- 🥚 알: 아무 알 (희귀 알도) → 가방 (부화 시간은 산 알과 같아요). 가방이 차면 빈 받침대에 바로
local function opEgg(admin: Player, target: Player, payload: Payload)
	local eggId = idIn(payload.EggId, Config.Eggs)
	local data = DataService.Get(target)
	if not eggId or not data then
		badValue(admin)
		return
	end
	local egg = Config.Eggs[eggId]
	local hatch = Config.RebirthHatchTime(eggId, data.Rebirths)
	local where: string
	if DataService.BagSpace(target) > 0 then
		DataService.AddItem(target, { Kind = "Egg", Id = eggId, Loc = "Bag", HatchLeft = hatch })
		where = "가방"
	else
		local slot = if PlotService.GetPlot(target) then PlotService.FreeSlot(target) else nil
		if not slot then
			notify(admin, "🎒 " .. nameOf(admin, target) .. " 가방도 받침대도 가득 찼어요!", "warn")
			return
		end
		local uid = DataService.AddItem(target, { Kind = "Egg", Id = eggId, Loc = "Slot", Slot = slot, HatchAt = os.time() + hatch })
		if uid == "" then
			return
		end
		PlotService.PlaceItem(target, uid)
		where = "받침대"
	end
	DataService.Sync(target)
	notify(admin, "✅ " .. nameOf(admin, target) .. "에게 🥚 " .. egg.Name .. " (" .. where .. ")", "good")
	gift(admin, target, "🥚 " .. egg.Name .. " (" .. where .. "에 있어요)")
end

-- 🌟 희귀 알 소환: 대상에게 열린 지역 벨트에 (ConveyorService.SpawnSpecial, 알림은 보통 희귀 알처럼)
local function opRareEgg(admin: Player, target: Player, payload: Payload)
	local zone = intIn(payload.Zone, 1, Config.MaxZone)
	local tier = payload.Tier
	if not zone or type(tier) ~= "string" or not SPECIAL_TIERS[tier] then
		badValue(admin)
		return
	end
	local eggId = Config.SpecialEggOf(zone, tier)
	local zoneDef = Config.Zones[zone]
	if not eggId then
		badValue(admin)
		return
	end
	if not Config.ZoneUnlocked(zone, DataService.GetRebirths(target)) then
		notify(admin, "🔒 " .. josa(nameOf(admin, target), "은", "는") .. " 아직 " .. zoneDef.Name .. "에 못 가요! (환생 " .. zoneDef.MinRebirth .. "회)", "warn")
		return
	end
	local cs = getConveyor()
	if not cs or type(cs.SpawnSpecial) ~= "function" then
		notify(admin, "😢 컨베이어가 없어서 소환할 수 없어요", "warn")
		return
	end
	if not cs.SpawnSpecial(target, zone, eggId) then
		notify(admin, "🌟 벨트에 희귀 알이 가득하거나 아직 준비 중이에요! 조금 뒤에 다시 해 봐요", "warn")
		return
	end
	local egg = Config.Eggs[eggId]
	notify(admin, "✅ " .. zoneDef.Name .. " 벨트에 🌟 " .. egg.Name .. " 소환! (" .. nameOf(admin, target) .. ")", "good")
	gift(admin, target, "🌟 " .. zoneDef.Name .. " 벨트에 " .. egg.Name)
end

-- 🎟 유료 기능 공짜 선물 켜기/끄기 (저장: AdminGrants). 속성 Pass_<키> 를 바로 바꿔서 Hud 가 풀려요
local function opGrant(admin: Player, target: Player, payload: Payload)
	local key = payload.Key
	local on = payload.On
	if type(key) ~= "string" or not table.find(Config.PassOrder, key) or type(on) ~= "boolean" then
		badValue(admin)
		return
	end
	local pass = (Config.Passes :: any)[key]
	local title = pass.Emoji .. " " .. pass.Name
	local had = DataService.HasGrant(target, key)
	local could = PassService.Has(target, key) -- ★v7.5 선물 전에도 쓸 수 있었나 (산 패스 · 관리자 · 공짜)
	if not DataService.SetGrant(target, key, on) then
		return
	end
	PassService.Refresh(target)
	if on then
		notify(admin, "✅ " .. nameOf(admin, target) .. ": " .. title .. " 공짜 선물 켜짐" .. (if had then " (이미 켜져 있었어요)" else "!"), "good")
		if not had then
			gift(admin, target, pass.Emoji .. " " .. josa(pass.Name, "을", "를") .. " 공짜로 쓸 수 있어요")
		end
		if not could then
			PassService.AutoOn(target, key) -- ★v7.5 ♾ 가방 무한 확장은 바로 켜져요 (끄면 칸만 150, 펫은 그대로)
		end
	else
		notify(admin, "✅ " .. nameOf(admin, target) .. ": " .. title .. " 공짜 선물 꺼짐", "info")
		if had and target ~= admin then
			local tail = ""
			if key == "InfiniteBag" and not PassService.Has(target, key) and DataService.BagCount(target) > Config.MaxBagItems then
				tail = " · 펫은 그대로예요! " .. Config.MaxBagItems .. "마리보다 적어지면 다시 넣을 수 있어요" -- ★v7.5 하나도 안 지워요
			end
			notify(target, title .. " 선물이 끝났어요" .. tail, "info")
		end
	end
end

-- 🔄 환생 +1 공짜 (PlotService.GrantRebirth: 진짜 환생과 같은 보너스·알림, 코인은 그대로)
local function opRebirth(admin: Player, target: Player, _payload: Payload)
	if not PlotService.GrantRebirth(target) then
		notify(admin, "🔄 " .. josa(nameOf(admin, target), "은", "는") .. " 이미 최대 환생이에요! 🌟", "info")
		return
	end
	local r = DataService.GetRebirths(target)
	notify(admin, "✅ " .. nameOf(admin, target) .. " 🔄 환생 +1 (지금 " .. r .. "회, 코인은 그대로)", "good")
	gift(admin, target, "🔄 환생 +1 (지금 " .. r .. "회)")
end

-- 📢 공지: 한 줄로 정리 (60자까지) → TextService 글자 검사 (pcall) → 모두에게 말풍선. 검사가 안 되면 안 보내요
local function announce(admin: Player, payload: Payload)
	local raw = payload.Text
	if type(raw) ~= "string" or #raw > A.AnnounceMax * 4 then
		badValue(admin)
		return
	end
	local text = string.gsub(string.gsub(raw, "%s+", " "), "^ ", "")
	text = string.gsub(text, " $", "")
	local len = utf8.len(text)
	if not len or len < 1 or len > A.AnnounceMax then
		notify(admin, "📢 공지는 1~" .. A.AnnounceMax .. "자로 써 주세요", "warn")
		return
	end
	local now = os.clock()
	if now - (lastAnnounce[admin] or -math.huge) < A.AnnounceGap then
		notify(admin, "📢 공지는 잠깐 쉬었다가 보내요 ⏳", "info")
		return
	end
	lastAnnounce[admin] = now
	local ok, result = pcall(function(): any
		local filtered = TextService:FilterStringAsync(text, admin.UserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or type(result) ~= "string" or result == "" then
		if not ok then
			warn("[AdminService] 공지 글자 검사 실패:", result)
		end
		notify(admin, "📢 지금은 공지를 보낼 수 없어요 (글자 검사가 안 돼요) 😢", "warn")
		return
	end
	if admin.Parent ~= Players then
		return -- 검사하는 동안 나갔어요
	end
	for _, p in Players:GetPlayers() do
		notify(p, "📢 " .. result, "alert")
	end
	notify(admin, "✅ 📢 공지를 보냈어요!", "good")
end

local OPS: { [string]: (Player, Player, Payload) -> () } = {
	Coins = opCoins,
	Pet = opPet,
	Egg = opEgg,
	RareEgg = opRareEgg,
	Grant = opGrant,
	Rebirth = opRebirth,
}

----------------------------------------------------------------------
-- 리모트
----------------------------------------------------------------------
-- 관리자가 아닌 사람: 아무것도 안 하고 경고만 (한 사람당 WarnGap 초에 한 번)
local function refuse(player: Player, op: any)
	local now = os.clock()
	if now - (lastWarn[player] or -math.huge) < A.WarnGap then
		return
	end
	lastWarn[player] = now
	local opText = if type(op) == "string" then string.sub(op, 1, 24) else typeof(op)
	warn("[AdminService] 관리자가 아닌 사람이 관리자 기능을 불렀어요 (무시):", player.Name, player.UserId, opText)
end

-- 대상: payload.Target (UserId) 이 지금 이 서버에 있고 데이터가 있어야 해요. 없으면 나
local function targetOf(admin: Player, payload: Payload): Player?
	local id = payload.Target
	if id == nil then
		return if DataService.Get(admin) then admin else nil
	end
	if type(id) ~= "number" or id ~= id or id ~= math.floor(id) then
		return nil
	end
	local p = Players:GetPlayerByUserId(id)
	if p and p.Parent == Players and DataService.Get(p) then
		return p
	end
	return nil
end

local function onAdmin(player: any, op: any, payload: any)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	local admin = player :: Player
	if not isAdmin(admin) then
		refuse(admin, op)
		return
	end
	if type(op) ~= "string" or (op ~= "Refresh" and op ~= "Announce" and OPS[op] == nil) then
		return
	end
	if payload == nil then
		payload = {}
	elseif type(payload) ~= "table" then
		badValue(admin)
		return
	end
	local now = os.clock()
	if op == "Refresh" then
		if now - (lastRefresh[admin] or -math.huge) < A.RefreshGap then
			return
		end
		lastRefresh[admin] = now
		queueState(admin)
		return
	end
	if now - (lastOp[admin] or -math.huge) < A.Gap then
		return -- 아주 빠른 연타는 한 번으로
	end
	lastOp[admin] = now
	if op == "Announce" then
		announce(admin, payload)
		return
	end
	local target = targetOf(admin, payload)
	if not target then
		notify(admin, "😢 그 친구는 지금 이 서버에 없어요", "warn")
		queueState(admin)
		return
	end
	local fn = OPS[op]
	local ok, err = pcall(fn, admin, target, payload)
	if not ok then
		warn("[AdminService] " .. op .. " 오류:", err)
		notify(admin, "😢 잘 안 됐어요 (" .. op .. ")", "warn")
	end
	queueState(admin)
end

-- 들어온 사람: 관리자면 IsAdmin 속성. 데이터가 다 불러지면 관리자 창 목록을 새로 보내요
local function onPlayerAdded(player: Player)
	if isAdmin(player) then
		player:SetAttribute(ATTR, true)
	end
	task.spawn(function()
		local waited = 0
		while player.Parent == Players and not DataService.Get(player) and waited < LOAD_WAIT do
			waited += task.wait(0.5)
		end
		if player.Parent == Players then
			queueAll()
		end
	end)
end

function AdminService.IsAdmin(player: Player): boolean
	return isAdmin(player)
end

function AdminService.Start()
	if started then
		return
	end
	started = true
	Remotes.Admin.OnServerEvent:Connect(onAdmin)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		lastOp[player] = nil
		lastRefresh[player] = nil
		lastAnnounce[player] = nil
		lastWarn[player] = nil
		stateQueued[player] = nil
		task.defer(queueAll) -- 나간 사람은 목록에서 빠져요 (Parent 가 바뀐 뒤)
	end)
end

return AdminService
