-- 컨베이어(알 공장 벨트): 지역마다 벨트 1개 (workspace.Conveyors.Zone<k>.Belt), 그 지역 알 5~6종이 SpawnWeight 비율로 나와요.
-- ★v5 알은 사람마다 따로예요! 서버는 알 파트를 만들지 않고 플레이어마다 메모리에 알 목록만 둬요 (Uid, EggId, Zone, Born).
-- 알 자리는 나온 시각으로 정해져요 (Config.BeltEggSpot): 그리기·흔들기·빛기둥·간판·사기 프롬프트는 클라이언트(EggBelt)가 하고,
-- 사기 요청(Remotes.BuyEgg)은 여기서 검증해요. 남이 사도 내 알은 그대로, 남의 알은 보이지도 사지지도 않아요.
-- 그 사람에게 열린 지역 벨트마다 알이 나와요 (숲 마을은 항상). 메모리만 써서 가볍고, 멀리 있어도 좋은 알 알림이 와요.
-- 산 알은 집 받침대로 날아가요 (나는 모습은 클라이언트, 받침대에 놓기는 날아간 뒤 서버). 집이 아주 멀면 "뿅" 하고 바로 나타나요.
-- 벨트 줄무늬 애니메이션은 클라이언트(ZoneClient)가 해요.
-- ★v4 좋은 알(지역 맨 위 2칸, egg.Premium): Remotes.EggAlert(zone, eggId) 를 그 사람에게만 보내요 (Config.EggAlert 규칙).
-- ★v6 아주 희귀한 알 (egg.Special: 시크릿/천상/이터널): 보통 알이 나올 때마다 따로 굴려서 (Config.RollSpecialEgg)
-- 반 칸 뒤에 하나 더 나와요. 벨트 끝에서 옆으로 비켜 오래 기다리고 (Config.BeltEggSpot/BeltEggLife 에 eggId),
-- 알림은 간격·지역 창 규칙 없이 늘 보내요 ("Rare"). 보통 알 사다리(비율·개수·알림)는 그대로예요.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

local ConveyorService = {}

local CV = Config.Conveyor
local BELT_TOP = CV.BeltTop
local DROP_HEIGHT = CV.DropHeight -- 슈트 안에서 알이 나오는 높이
local FLY_TIME = 0.9 -- 산 알이 집으로 날아가는 시간 (가까울 때)
local FLY_TIME_MAX = 1.8
local STRIPE_SPACING = 8
local EGG_CENTER = 1.2 -- 알 피벗(바닥)에서 몸통 가운데까지 (거리 검사용)
local LOAD_TIMEOUT = 20 -- 데이터 로딩 기다리는 최대 초
local LOOP_INTERVAL = 0.25
local LANE_CHECK = 0.5 -- 새로 열린 지역 확인 간격

type Belt = {
	Zone: number,
	Folder: Folder,
	Start: Vector3,
	Dir: Vector3,
	Length: number,
	Base: CFrame,
	Speed: number,
	Center: Vector3,
}

-- 한 사람의 벨트 알 하나
type Egg = { Uid: number, EggId: string, Zone: number, Born: number }
-- 곧 나올 희귀 알 (보통 알 사이 반 칸 뒤)
type Queued = { EggId: string, At: number }
-- 한 사람의 벨트 하나
type Lane = {
	Zone: number,
	Eggs: { Egg },
	NextSpawn: number,
	LastAlert: number, -- 마지막 EggAlert 시각 (둘째 칸 알은 Config.EggAlert.Gap 초에 한 번)
	Queued: { Queued }, -- ★v6
}
-- 한 사람의 모든 벨트
type Stream = {
	Lanes: { [number]: Lane },
	ById: { [number]: Egg },
	Rng: Random,
	SpecialRng: Random, -- ★v6 희귀 알은 따로 굴려요 (보통 알 순서가 그대로)
	NextLaneCheck: number,
}

local belts: { [number]: Belt } = {}
local streams: { [Player]: Stream } = {}
local hooked: { [Player]: boolean } = {}
local buyDebounce: { [Player]: number } = {}
local nextUid = 1 -- 서버 전체에서 하나뿐인 알 번호 (남의 번호를 보내도 내 목록에는 없어요)
local started = false

local function notify(player: Player, text: string, kind: string)
	Remotes.Notify:FireClient(player, text, kind)
end

-- 알 시계 (클라이언트도 workspace:GetServerTimeNow() 로 같은 자리를 계산해요)
local function clockNow(): number
	return workspace:GetServerTimeNow()
end

local function makePart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

-- 벨트 위 거리 s, 높이 y 의 CFrame
local function beltCFrame(belt: Belt, s: number, y: number): CFrame
	return belt.Base * CFrame.new(0, y, -s)
end

----------------------------------------------------------------------
-- 벨트 만들기
----------------------------------------------------------------------
local function buildBelt(belt: Belt)
	local beltFolder = Instance.new("Folder")
	beltFolder.Name = "Belt"
	-- ZoneClient 가 줄무늬를 움직일 때 쓰는 값
	beltFolder:SetAttribute("Start", belt.Start)
	beltFolder:SetAttribute("Dir", belt.Dir)
	beltFolder:SetAttribute("Length", belt.Length)
	beltFolder:SetAttribute("Speed", belt.Speed)
	beltFolder:SetAttribute("StripeSpacing", STRIPE_SPACING)
	beltFolder:SetAttribute("StripeY", BELT_TOP + 0.02)
	beltFolder.Parent = belt.Folder

	local W = Config.Layout.ConveyorWidth
	local L = belt.Length

	-- 받침 프레임
	makePart({
		Name = "Frame",
		Size = Vector3.new(W + 1.2, 0.9, L + 1),
		CFrame = beltCFrame(belt, L / 2, 0.45),
		Color = Color3.fromRGB(150, 170, 210),
		Parent = beltFolder,
	})
	-- 벨트 (진짜로 위에 선 사람을 실어 날라요!)
	local top = makePart({
		Name = "BeltTop",
		Size = Vector3.new(W, 0.3, L),
		CFrame = beltCFrame(belt, L / 2, BELT_TOP - 0.15),
		Color = Color3.fromRGB(55, 58, 75),
		Material = Enum.Material.Fabric,
		Parent = beltFolder,
	})
	top.AssemblyLinearVelocity = belt.Dir * belt.Speed

	-- 옆 난간 (보기용, 통과 가능)
	local railColors = { Color3.fromRGB(255, 140, 190), Color3.fromRGB(110, 210, 230) }
	for i, side in { -1, 1 } do
		makePart({
			Name = "Rail",
			Size = Vector3.new(0.5, 0.5, L),
			CFrame = beltCFrame(belt, L / 2, BELT_TOP + 0.35) * CFrame.new(side * (W / 2 + 0.3), 0, 0),
			Color = railColors[i],
			CanCollide = false,
			Parent = beltFolder,
		})
		local posts = math.floor(L / 20)
		for k = 0, posts do
			makePart({
				Name = "Post",
				Size = Vector3.new(0.4, 0.9, 0.4),
				CFrame = beltCFrame(belt, k * (L / posts), BELT_TOP - 0.1) * CFrame.new(side * (W / 2 + 0.3), 0, 0),
				Color = Color3.fromRGB(255, 255, 255),
				CanCollide = false,
				Parent = beltFolder,
			})
		end
	end

	-- 양 끝 롤러
	for _, s in { 0, L } do
		makePart({
			Name = "Roller",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(W + 0.4, 1.3, 1.3),
			CFrame = beltCFrame(belt, s, BELT_TOP - 0.6),
			Color = Color3.fromRGB(255, 210, 80),
			CanCollide = false,
			Parent = beltFolder,
		})
	end

	-- 줄무늬 (네온). 움직이는 건 클라이언트가 해요
	local stripeColors = { Color3.fromRGB(255, 230, 120), Color3.fromRGB(140, 230, 255), Color3.fromRGB(255, 160, 210) }
	local count = math.floor(L / STRIPE_SPACING)
	for i = 1, count do
		local stripe = makePart({
			Name = "Stripe",
			Size = Vector3.new(W - 1.2, 0.06, 0.8),
			CFrame = beltCFrame(belt, (i - 1) * STRIPE_SPACING, BELT_TOP + 0.02),
			Color = stripeColors[(i - 1) % #stripeColors + 1],
			Material = Enum.Material.Neon,
			Transparency = 0.25,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
			Parent = beltFolder,
		})
		stripe:SetAttribute("StripeIndex", i)
	end

	-- 시작점 알 슈트
	local chute = Instance.new("Model")
	chute.Name = "Chute"
	chute.Parent = beltFolder
	local cw = 5
	local chuteBottom = BELT_TOP + 3.6
	local chuteTop = DROP_HEIGHT + 3
	local chuteH = chuteTop - chuteBottom
	local chuteCenter = beltCFrame(belt, 0, chuteBottom + chuteH / 2)
	local chuteColor = Color3.fromRGB(255, 190, 220)
	for _, off in { Vector3.new(cw / 2, 0, 0), Vector3.new(-cw / 2, 0, 0), Vector3.new(0, 0, cw / 2), Vector3.new(0, 0, -cw / 2) } do
		local isX = off.X ~= 0
		makePart({
			Name = "ChuteWall",
			Size = if isX then Vector3.new(0.4, chuteH, cw) else Vector3.new(cw, chuteH, 0.4),
			CFrame = chuteCenter * CFrame.new(off),
			Color = chuteColor,
			Material = Enum.Material.Glass,
			Transparency = 0.45,
			CanCollide = false,
			Parent = chute,
		})
	end
	makePart({
		Name = "ChuteCap",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(cw + 1.5, cw + 1.5, cw + 1.5),
		CFrame = beltCFrame(belt, 0, chuteTop + 0.6),
		Color = Color3.fromRGB(255, 120, 170),
		CanCollide = false,
		Parent = chute,
	})
	for _, off in { Vector3.new(cw / 2, 0, cw / 2), Vector3.new(-cw / 2, 0, cw / 2), Vector3.new(cw / 2, 0, -cw / 2), Vector3.new(-cw / 2, 0, -cw / 2) } do
		makePart({
			Name = "ChuteLeg",
			Size = Vector3.new(0.4, chuteBottom - BELT_TOP + 0.2, 0.4),
			CFrame = beltCFrame(belt, 0, (BELT_TOP + chuteBottom) / 2) * CFrame.new(off),
			Color = Color3.fromRGB(255, 255, 255),
			CanCollide = false,
			Parent = chute,
		})
	end

	-- 끝 알 통
	local bin = Instance.new("Model")
	bin.Name = "Bin"
	bin.Parent = beltFolder
	local binLen = 5.5
	local binW = W + 1
	local binH = 1.1
	local binCenter = beltCFrame(belt, L + binLen / 2 + 0.3, 0)
	makePart({
		Name = "BinFloor",
		Size = Vector3.new(binW, 0.2, binLen),
		CFrame = binCenter * CFrame.new(0, 0.1, 0),
		Color = Color3.fromRGB(120, 200, 255),
		Parent = bin,
	})
	for _, data in {
		{ Vector3.new(binW / 2, binH / 2, 0), Vector3.new(0.4, binH, binLen) },
		{ Vector3.new(-binW / 2, binH / 2, 0), Vector3.new(0.4, binH, binLen) },
		{ Vector3.new(0, binH / 2, -binLen / 2), Vector3.new(binW, binH, 0.4) },
	} do
		makePart({
			Name = "BinWall",
			Size = data[2],
			CFrame = binCenter * CFrame.new(data[1]),
			Color = Color3.fromRGB(90, 170, 240),
			Parent = bin,
		})
	end
end

----------------------------------------------------------------------
-- 사람마다 알 목록
----------------------------------------------------------------------

local function payload(egg: Egg)
	return { Uid = egg.Uid, EggId = egg.EggId, Zone = egg.Zone, Born = egg.Born }
end

local function send(player: Player, op: string, arg: any)
	if player.Parent then
		Remotes.EggBelt:FireClient(player, op, arg)
	end
end

local function sendReset(player: Player)
	local stream = streams[player]
	if not stream then
		return
	end
	local list = {}
	for zone = 1, Config.MaxZone do
		local lane = stream.Lanes[zone]
		if lane then
			for _, egg in lane.Eggs do
				table.insert(list, payload(egg))
			end
		end
	end
	send(player, "Reset", list)
end

local function newEgg(stream: Stream, lane: Lane, eggId: string, born: number): Egg
	local egg: Egg = { Uid = nextUid, EggId = eggId, Zone = lane.Zone, Born = born }
	nextUid += 1
	table.insert(lane.Eggs, egg)
	stream.ById[egg.Uid] = egg
	return egg
end

local function removeEgg(stream: Stream, egg: Egg)
	stream.ById[egg.Uid] = nil
	local lane = stream.Lanes[egg.Zone]
	if lane then
		local i = table.find(lane.Eggs, egg)
		if i then
			table.remove(lane.Eggs, i)
		end
	end
end

-- 좋은 알 알림 보내기 (그 사람에게만): 맨 위 칸은 언제나, 둘째 칸은 그 사람의 벨트마다 Gap 초에 한 번.
-- 받는 조건: 그 지역이 열렸고, 그 지역이 내 열린 지역 중 위에서 ZoneWindow 개 안이거나 지금 그 지역에 있을 때
-- (숲 마을은 모두의 집이 있는 곳이라 "거기 있음"으로 치지 않아요: 환생 많이 한 아이에게 숲 알 알림이 계속 오지 않게)
-- ★v7 알림 단계 (Settings.AlertLevel, Config.AlertLevels) 가 먼저 걸러요: 희귀 알은 MinRare 보다 낮은 단계면 안 보내고
-- (이터널은 언제나), 보통 알은 Normal "None" 이면 안 보내고 "Top" 이면 내 최종 테마(열린 가장 먼 지역) 벨트만.
-- 걸러진 알은 Gap 시계를 건드리지 않아요 (다시 "모두 받기" 로 돌아와도 v6 그대로)
local function sendEggAlert(player: Player, lane: Lane, eggId: string, now: number)
	local kind = Config.EggAlertKind(eggId)
	if not kind then
		return
	end
	local level = Config.AlertLevelInfo(DataService.GetAlertLevel(player))
	if kind == "Rare" then
		local tier = Config.EggSpecial(eggId)
		local info = if tier then Config.Rarities[tier] else nil
		local min = Config.Rarities[level.MinRare]
		if tier ~= "Eternal" and info and min and info.Order < min.Order then
			return
		end
		-- ★v6 희귀 알: 그 지역이 열렸으면 언제나 (Gap 시계도 그대로 둬요)
		if DataService.Get(player) and Config.ZoneUnlocked(lane.Zone, DataService.GetRebirths(player)) then
			Remotes.EggAlert:FireClient(player, lane.Zone, eggId)
		end
		return
	end
	if level.Normal == "None" then
		return
	elseif level.Normal == "Top" then
		if not DataService.Get(player) or lane.Zone ~= Config.MaxZoneFor(DataService.GetRebirths(player)) then
			return
		end
	end
	local rules = Config.EggAlert
	if kind ~= "Top" and now - lane.LastAlert < rules.Gap then
		return
	end
	lane.LastAlert = now
	if not DataService.Get(player) then
		return
	end
	local rebirths = DataService.GetRebirths(player)
	if not Config.ZoneUnlocked(lane.Zone, rebirths) then
		return
	end
	local here = lane.Zone ~= 1 and player:GetAttribute("Zone") == lane.Zone
	if here or lane.Zone > Config.MaxZoneFor(rebirths) - rules.ZoneWindow then
		Remotes.EggAlert:FireClient(player, lane.Zone, eggId)
	end
end

-- 벨트 위 보통 알 / 희귀 알 수
local function countEggs(lane: Lane): (number, number)
	local normal, special = 0, 0
	for _, egg in lane.Eggs do
		if Config.IsSpecialEgg(egg.EggId) then
			special += 1
		else
			normal += 1
		end
	end
	return normal, special
end

-- 새 알 하나 (그 사람에게 "Add" + 좋은 알이면 알림). ★v6 같이 희귀 알도 굴려서 반 칸 뒤로 예약해요
local function spawnEgg(player: Player, stream: Stream, lane: Lane, now: number, belts: number)
	local normal, special = countEggs(lane)
	if normal >= CV.MaxEggs then
		return
	end
	local eggId = Config.RollEgg(stream.Rng, lane.Zone)
	if not Config.Eggs[eggId] then
		return
	end
	local egg = newEgg(stream, lane, eggId, now)
	send(player, "Add", payload(egg))
	sendEggAlert(player, lane, eggId, now)

	local rare = Config.RollSpecialEgg(stream.SpecialRng, lane.Zone, belts)
	if rare and Config.Eggs[rare] and special + #lane.Queued < Config.SpecialEggs.MaxPerBelt then
		table.insert(lane.Queued, { EggId = rare, At = now + CV.SpawnInterval / 2 })
	end
end

-- ★v6 예약한 희귀 알 내보내기 (나온 시각 = 예약 시각, 늘 알림)
local function releaseQueued(player: Player, stream: Stream, lane: Lane, now: number)
	local queue = lane.Queued
	local i = 1
	while i <= #queue do
		local q = queue[i]
		if now >= q.At then
			table.remove(queue, i)
			local egg = newEgg(stream, lane, q.EggId, q.At)
			send(player, "Add", payload(egg))
			sendEggAlert(player, lane, q.EggId, now)
		else
			i += 1
		end
	end
end

-- 벨트를 처음 열 때: 이미 알이 지나가고 있는 것처럼 채워요 (알림은 안 보내요)
local function addLane(stream: Stream, zone: number, now: number): Lane
	local lane: Lane = { Zone = zone, Eggs = {}, NextSpawn = now, LastAlert = -math.huge, Queued = {} }
	stream.Lanes[zone] = lane
	local interval = CV.SpawnInterval
	local phase = stream.Rng:NextNumber(0, interval)
	local maxAge = CV.DropTime + CV.TravelTime - 1
	local ages = {}
	local age = phase
	while age < maxAge and #ages < CV.MaxEggs do
		table.insert(ages, 1, age) -- 오래된 알부터
		age += interval
	end
	for _, a in ages do
		local eggId = Config.RollEgg(stream.Rng, zone)
		if Config.Eggs[eggId] then
			newEgg(stream, lane, eggId, now - a)
		end
	end
	lane.NextSpawn = now + (interval - phase)
	return lane
end

-- 열린 지역마다 벨트가 있는지 (새로 열렸으면 채워서 "Add")
local function ensureLanes(player: Player, stream: Stream, now: number, announce: boolean)
	if not DataService.Get(player) then
		return
	end
	for zone = 1, DataService.GetMaxZone(player) do
		if not stream.Lanes[zone] and belts[zone] then
			local lane = addLane(stream, zone, now)
			if announce then
				for _, egg in lane.Eggs do
					send(player, "Add", payload(egg))
				end
			end
		end
	end
end

local function buildStream(player: Player): Stream
	local seed = (math.floor(os.clock() * 1000) % 1000000) + player.UserId % 100000 * 37
	local stream: Stream = {
		Lanes = {},
		ById = {},
		Rng = Random.new(seed),
		SpecialRng = Random.new(seed * 7 + 12345),
		NextLaneCheck = 0,
	}
	streams[player] = stream
	ensureLanes(player, stream, clockNow(), false)
	return stream
end

-- 데이터가 로딩될 때까지 기다렸다가 벨트를 채워요
local function setupPlayer(player: Player)
	if hooked[player] then
		return
	end
	hooked[player] = true
	task.spawn(function()
		local waited = 0
		while player.Parent and DataService.Get(player) == nil and waited < LOAD_TIMEOUT do
			waited += task.wait(0.25)
		end
		if player.Parent == nil or DataService.Get(player) == nil or streams[player] then
			return
		end
		buildStream(player)
		sendReset(player)
	end)
end

local function cleanupPlayer(player: Player)
	streams[player] = nil
	hooked[player] = nil
	buyDebounce[player] = nil
end

-- 한 사람의 벨트들: 끝난 알 지우기 + 새 알
local function tickStream(player: Player, stream: Stream, now: number)
	if now >= stream.NextLaneCheck then
		stream.NextLaneCheck = now + LANE_CHECK
		ensureLanes(player, stream, now, true)
	end
	local rebirths = DataService.GetRebirths(player)
	local belts = Config.MaxZoneFor(rebirths) -- 열린 벨트 수 (희귀 알 확률을 나눠요)
	for zone, lane in stream.Lanes do
		local eggs = lane.Eggs
		for i = #eggs, 1, -1 do
			local egg = eggs[i]
			if now - egg.Born > Config.BeltEggLife(egg.EggId) then
				stream.ById[egg.Uid] = nil
				table.remove(eggs, i) -- 클라이언트도 시간으로 알아서 지워요 (메시지 없음)
			end
		end
		if #lane.Queued > 0 then
			releaseQueued(player, stream, lane, now)
		end
		if now >= lane.NextSpawn then
			lane.NextSpawn += CV.SpawnInterval -- 고리 간격(0.25초)에 밀리지 않게 정확히 SpawnInterval 마다
			if lane.NextSpawn <= now then
				lane.NextSpawn = now + CV.SpawnInterval -- 오래 멈췄으면 몰아서 내지 않아요
			end
			if Config.ZoneUnlocked(zone, rebirths) then
				spawnEgg(player, stream, lane, now, belts)
			end
		end
	end
end

----------------------------------------------------------------------
-- 사기
----------------------------------------------------------------------

local function placeIfStillThere(player: Player, uid: string)
	if player.Parent == nil then
		return
	end
	local item = DataService.GetItem(player, uid)
	if item and item.Loc == "Slot" then
		PlotService.PlaceItem(player, uid)
	end
end

local function onBuy(player: Player, uid: any)
	if type(uid) ~= "number" or uid ~= uid or uid ~= math.floor(uid) then
		return
	end
	local stream = streams[player]
	if not stream then
		return
	end
	local egg = stream.ById[uid]
	if not egg then
		return -- 내 알이 아니거나 이미 없어요
	end
	local clock = os.clock()
	if (buyDebounce[player] or 0) > clock then
		return
	end
	buyDebounce[player] = clock + 0.3

	local age = clockNow() - egg.Born
	if age > Config.BeltEggBuyEnd(egg.EggId) + CV.BuyGrace then
		return -- 벨트 끝을 지났어요 (★v6 희귀 알은 끝에서 더 기다려요)
	end
	if not DataService.Get(player) then
		return
	end
	if not PlotService.GetPlot(player) then
		notify(player, "아직 내 집이 없어요! 🏠", "warn")
		return
	end
	local def = Config.Eggs[egg.EggId]
	local rebirths = DataService.GetRebirths(player)
	if not Config.ZoneUnlocked(egg.Zone, rebirths) then
		notify(player, "🔒 환생 " .. Config.Zones[egg.Zone].MinRebirth .. "회가 필요해요!", "warn")
		return
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		return
	end
	local spot = Config.BeltEggSpot(egg.Zone, age, egg.EggId)
	local center = spot + Vector3.new(0, EGG_CENTER, 0)
	if (hrp.Position - center).Magnitude > CV.BuyDistance then
		return
	end

	-- 빈 받침대 먼저 확인하고 돈을 빼요 (반대 순서면 돈만 빠질 수 있어요)
	local slot = PlotService.FreeSlot(player)
	if not slot then
		notify(player, "집에 빈 받침대가 없어요! 🐾 '하위 펫 한 개 가방으로'를 눌러 보세요", "warn") -- ★v7.2 Hud 버튼 (Remotes.StashEgg)
		return
	end
	if not DataService.TrySpend(player, def.Price) then
		notify(player, "코인이 부족해요! 💰 " .. Config.FormatNumber(def.Price) .. " 필요", "warn")
		return
	end

	-- 여기부터는 이 알은 이 플레이어 것 (중간에 yield 없음)
	removeEgg(stream, egg)
	local itemUid = DataService.AddItem(player, {
		Kind = "Egg",
		Id = egg.EggId,
		Loc = "Slot",
		Slot = slot,
		HatchAt = os.time() + Config.RebirthHatchTime(egg.EggId, rebirths), -- 환생할수록 빨리 부화
	})
	if not itemUid or itemUid == "" then
		-- 혹시 실패하면 환불
		DataService.AddCoins(player, def.Price)
		send(player, "Remove", egg.Uid)
		DataService.Sync(player)
		return
	end

	local target = PlotService.GetSlotCFrame(player, slot)
	local dist = (target.Position - center).Magnitude
	if dist <= CV.FlyMaxDistance then
		local flyTime = math.clamp(FLY_TIME + dist / 500, FLY_TIME, FLY_TIME_MAX)
		send(player, "Bought", { Uid = egg.Uid, Target = target, FlyTime = flyTime, Poof = false })
		-- 날아가는 동안 상황이 바뀌었을 수 있으니 도착할 때 다시 확인
		task.delay(flyTime, placeIfStillThere, player, itemUid)
		if def.Special then
			notify(player, "🌟 " .. def.Name .. "을 샀어요! 집에서 부화를 기다려요 🥚", "good")
		else
			notify(player, "알을 샀어요! 집에서 부화를 기다려요 🥚", "good")
		end
	else
		-- 너무 먼 집: 그 자리에서 뿅! 하고 받침대에 바로 나타나요
		send(player, "Bought", { Uid = egg.Uid, Target = target, FlyTime = 0, Poof = true })
		placeIfStillThere(player, itemUid)
		if def.Special then
			notify(player, "🌟 뿅! " .. def.Name .. "이 집 받침대로 갔어요 🥚", "good")
		else
			notify(player, "✨ 뿅! 알이 집 받침대로 갔어요 🥚", "good")
		end
	end
	DataService.Sync(player)
end

----------------------------------------------------------------------
-- 공개 API
----------------------------------------------------------------------

-- 지역 k 의 벨트 폴더 (workspace.Conveyors.Zone<k>)
function ConveyorService.GetZoneFolder(zone: number): Folder?
	local belt = belts[zone]
	return if belt then belt.Folder else nil
end

-- 그 사람 벨트에 지금 있는 알 (테스트·디버그용, 복사본)
function ConveyorService.GetEggs(player: Player, zone: number?): { Egg }
	local out = {}
	local stream = streams[player]
	if stream then
		for z, lane in stream.Lanes do
			if zone == nil or z == zone then
				for _, egg in lane.Eggs do
					table.insert(out, table.clone(egg))
				end
			end
		end
	end
	return out
end

-- ★v6 그 사람 벨트에 희귀 알 하나 예약 (테스트·관리자용). 굴린 것처럼 다음 보통 알 사이 반 칸에 나와요
-- (그 지역 희귀 알이어야 하고, 벨트가 있고, MaxPerBelt 를 넘지 않을 때만 true)
function ConveyorService.SpawnSpecial(player: Player, zone: number, eggId: string): boolean
	local stream = streams[player]
	local lane = stream and stream.Lanes[zone]
	local egg = Config.Eggs[eggId]
	if not (lane and egg and egg.Special and egg.Zone == zone) then
		return false
	end
	local _, special = countEggs(lane)
	if special + #lane.Queued >= Config.SpecialEggs.MaxPerBelt then
		return false
	end
	local now = clockNow()
	local at = lane.NextSpawn - CV.SpawnInterval / 2
	if at < now then
		at += CV.SpawnInterval
	end
	table.insert(lane.Queued, { EggId = eggId, At = at })
	return true
end

function ConveyorService.Start()
	if started then
		return
	end
	started = true
	for _, name in { "Conveyor", "Conveyors" } do
		local old = workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local root = Instance.new("Folder")
	root.Name = "Conveyors"

	for k, def in Config.Zones do
		local startPos, endPos = def.ConveyorStart, def.ConveyorEnd
		local zoneFolder = Instance.new("Folder")
		zoneFolder.Name = "Zone" .. k
		zoneFolder:SetAttribute("ZoneIndex", k)
		zoneFolder.Parent = root
		local length = (endPos - startPos).Magnitude
		local dir = (endPos - startPos).Unit
		local belt: Belt = {
			Zone = k,
			Folder = zoneFolder,
			Start = startPos,
			Dir = dir,
			Length = length,
			Base = CFrame.lookAt(startPos, startPos + dir),
			Speed = length / CV.TravelTime,
			Center = (startPos + endPos) / 2,
		}
		buildBelt(belt)
		belts[k] = belt
	end
	root.Parent = workspace

	Players.PlayerAdded:Connect(setupPlayer)
	for _, p in Players:GetPlayers() do
		setupPlayer(p)
	end
	Players.PlayerRemoving:Connect(cleanupPlayer)

	Remotes.BuyEgg.OnServerEvent:Connect(function(player, uid)
		local ok, err = pcall(onBuy, player, uid)
		if not ok then
			warn("[ConveyorService] 알 사기 오류:", err)
		end
	end)

	-- 클라이언트가 동기화를 요청하면 알 목록도 다시 보내요
	Remotes.RequestSync.OnServerEvent:Connect(function(player)
		if not streams[player] and player.Parent and DataService.Get(player) then
			buildStream(player)
		end
		sendReset(player)
	end)

	task.spawn(function()
		while true do
			local now = clockNow()
			for player, stream in streams do
				if player.Parent then
					local ok, err = pcall(tickStream, player, stream, now)
					if not ok then
						warn("[ConveyorService] 알 생성 오류:", err)
					end
				end
			end
			task.wait(LOOP_INTERVAL)
		end
	end)
end

return ConveyorService
