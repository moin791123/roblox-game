-- 게임 전체 설정 (v3). 숫자/펫/알/지역/집/옷/가구를 바꾸고 싶으면 여기만 고치면 돼요.
-- 설계: docs/DESIGN.md. 진행 곡선은 scratchpad 의 sim3.py 로 맞췄어요 (수익·가격을 같이 바꿔야 해요).
local Config = {}

local RGB = Color3.fromRGB
local V3 = Vector3.new

Config.GameName = "펫 월드"
Config.DataStoreName = "EggThiefPets_v1" -- 절대 바꾸지 마세요 (예전 저장을 못 불러와요)
Config.DataVersion = 3 -- v3: 등급 7단계 (예전 2→4, 3→5 로 옮겨요)
Config.StartCoins = 200

-- ★v5 켜고 끄는 버튼 (플레이어마다 저장, Remotes.SetSetting). 값은 기본값.
-- ★v7 AlertLevel 만 숫자 (0 .. #AlertLevels - 1), 나머지는 모두 true/false (Config.SettingValue 로 검사)
-- ★v7.1 숫자 설정 더: SellZoneMax (테마 1..MaxZone), SellRarityMax (등급 1..SellRarityTop). 범위는 Config.SettingRange
Config.Settings = {
	HideHatch = false, -- 알 까는 화면 숨기기 (작은 알림만)
	AutoCollect = false, -- 집에 모인 돈 자동으로 먹기 (★v7.2 게임 패스 Config.Passes.AutoCollect)
	Magnet = false, -- 맵 돈 자석 (넓은 범위 자동으로 먹기, ★v7.2 게임 패스 Config.Passes.Magnet)
	SuperMagnet = false, -- ★v6 슈퍼 자석 (지금 있는 지역 코인 대부분, ★v7.2 게임 패스 Config.Passes.SuperMagnet)
	AlertLevel = 0, -- ★v7 알 알림 단계 (Config.AlertLevels, 0 = 모두 받기)
	InfiniteBag = false, -- ★v7.1 ♾ 가방 무한 (가방 칸 = Config.InfiniteBagItems, ★v7.5 게임 패스 Config.Passes.InfiniteBag)
	AutoSell = false, -- ★v7.1 🤖 자동 판매 (새로 태어난 펫이 아래 조건이면 바로 팔아요)
	SellZoneMax = 1, -- ★v7.1 💰 한꺼번에 팔기·자동 판매: 이 테마(지역 번호) 이하 펫만
	SellRarityMax = 2, -- ★v7.1 이 등급(희귀도 Order, 2 = 고급) 이하 펫만
}

-- ★v7 알 알림 단계: 한 칸 내려갈수록 더 꺼요 ("어디까지 받을지"). [n + 1] = 단계 n
-- Normal: 보통 좋은 알 알림 ("All" = v6 규칙, "Top" = 내 최종 테마(열린 가장 먼 지역)만, "None" = 안 받기)
-- MinRare: 받는 희귀 알의 가장 낮은 단계 (Hidden < Celestial < Eternal). 이터널 알 알림은 언제나 와요
-- 걸러 내는 곳은 서버 ConveyorService.sendEggAlert (희귀 알 자체·빛기둥·지도 알약은 그대로 나와요)
Config.AlertLevels = {
	{ Name = "모두 받기", Short = "모두", Emoji = "🔔", Normal = "All", MinRare = "Hidden",
		Desc = "좋은 알이 나오면 다 알려 줘요", Toast = "🔔 이제 좋은 알을 모두 알려 줘요" },
	{ Name = "최종 테마 좋은 알만 받기", Short = "최종만", Emoji = "🎯", Normal = "Top", MinRare = "Hidden",
		Desc = "가장 먼 지역 좋은 알 + 희귀 알", Toast = "🎯 이제 최종 테마 좋은 알만 알려 줘요" },
	{ Name = "최종 테마도 안 받기", Short = "희귀만", Emoji = "🌟", Normal = "None", MinRare = "Hidden",
		Desc = "시크릿·천상·이터널 알만", Toast = "🌟 이제 희귀 알만 알려 줘요" },
	{ Name = "시크릿 안 받기", Short = "천상+", Emoji = "💛", Normal = "None", MinRare = "Celestial",
		Desc = "천상·이터널 알만", Toast = "💛 이제 천상·이터널 알만 알려 줘요" },
	{ Name = "천상 안 받기", Short = "이터널", Emoji = "💜", Normal = "None", MinRare = "Eternal",
		Desc = "이터널 알만", Toast = "💜 이제 이터널 알만 알려 줘요" },
}

-- ★v7.1 숫자 설정의 범위 (정수 min..max). 숫자 설정이 아니면 nil
function Config.SettingRange(key: any): (number?, number?)
	if key == "AlertLevel" then
		return 0, #Config.AlertLevels - 1
	elseif key == "SellZoneMax" then
		return 1, Config.MaxZone
	elseif key == "SellRarityMax" then
		return 1, Config.SellRarityTop
	end
	return nil, nil
end

-- ★v7 설정 값 검사: 맞는 값이면 그 값, 아니면 nil (숫자 설정 = Config.SettingRange 안 정수, 나머지 키 = true/false)
function Config.SettingValue(key: any, value: any): any
	local default = if type(key) == "string" then (Config.Settings :: any)[key] else nil
	if default == nil then
		return nil
	end
	if type(default) == "number" then
		local lo, hi = Config.SettingRange(key)
		if type(value) == "number" and value == math.floor(value) and lo and hi and value >= lo and value <= hi then
			return value
		end
		return nil
	end
	return if type(value) == "boolean" then value else nil
end

-- ★v7 알림 단계 정보 (이상한 값이면 0 단계 "모두 받기")
function Config.AlertLevelInfo(level: any): { [string]: any }
	local n = Config.SettingValue("AlertLevel", level) or 0
	return Config.AlertLevels[n + 1]
end

-- ★v7.2 게임 패스 (로벅스): 🧲 자석 R$50 · ⚡ 슈퍼 자석 R$100 · 🏦 자동 수금 R$150 · ★v7.5 ♾ 가방 무한 확장 R$150.
-- Id 에 Creator Hub 에서 만든 게임 패스 번호를 넣어요. Id = 0 (아직 안 만듦) 이면 모두에게 공짜예요 (v7.1 처럼).
-- Price 는 버튼에 보여 주기만 해요 (진짜 가격은 Roblox 에서 정해요). 켜 둔 설정 값은 언제나 저장되고,
-- 패스가 없으면 아무 일도 안 해요. 확인은 서버 PassService (플레이어 속성 Pass_<키> = true 면 쓸 수 있음)
Config.Passes = {
	Magnet = { Id = 2055622545, Price = 50, Emoji = "🧲", Name = "자석" }, -- ★v7.3
	SuperMagnet = { Id = 2053366693, Price = 100, Emoji = "⚡", Name = "슈퍼 자석" }, -- ★v7.3
	AutoCollect = { Id = 2052736713, Price = 150, Emoji = "🏦", Name = "자동 수금" }, -- ★v7.3
	-- ★v7.5 ♾ 가방 무한 확장: 패스가 있어야 Settings.InfiniteBag 이 칸을 Config.InfiniteBagItems 로 늘려요 (Roblox 이름 "가방무한")
	InfiniteBag = { Id = 2053007328, Price = 150, Emoji = "♾", Name = "가방 무한 확장" }, -- ★v7.5 패스 ID
}
Config.PassOrder = { "Magnet", "SuperMagnet", "AutoCollect", "InfiniteBag" } -- ★v7.5 InfiniteBag 은 맨 뒤

-- ★v7.2 그 기능의 게임 패스 번호 (패스가 없는 기능이거나 아직 0 이면 0 = 공짜)
function Config.PassId(key: any): number
	local pass = if type(key) == "string" then (Config.Passes :: any)[key] else nil
	local id = if type(pass) == "table" then tonumber(pass.Id) else nil
	if id and id > 0 and id == math.floor(id) then
		return id
	end
	return 0
end

-- ★v7.2 게임 패스 번호 → 기능 키 (모르는 번호면 nil)
function Config.PassKeyOf(passId: any): string?
	if type(passId) ~= "number" or passId <= 0 then
		return nil
	end
	for _, key in Config.PassOrder do
		if Config.PassId(key) == passId then
			return key
		end
	end
	return nil
end

-- ★v7.2 서버가 켜는 플레이어 속성 이름 (true = 패스가 있거나 공짜)
function Config.PassAttribute(key: string): string
	return "Pass_" .. key
end

-- ★v7.4 🛠 관리자 페이지: 이 UserId 들 + 이 게임을 만든 사람(개인 게임일 때 game.CreatorId) 만 써요.
-- 서버가 UserId 로만 확인해요 (클라이언트가 보낸 건 안 믿어요). 관리자는 유료 기능 (🧲 ⚡ 🏦 ★v7.5 ♾) 을 늘 쓸 수 있어요
Config.AdminUserIds = { 981565959 } -- 게임 만든 사람 (beragom)
Config.Admin = {
	CoinCap = 1e22, -- 선물로 이만큼 넘게는 안 줘요 (★v8 환생 30회 비용 9e19 도 넉넉)
	CoinAdds = { 1e3, 1e6, 1e9, 1e12, 1e15 }, -- 💰 버튼 (+1K / +1M / +1B / +1T / +1Qa). 서버는 이 값만 받아요
	TimesMinAdd = 1e3, -- ×10 인데 코인이 거의 없으면 적어도 이만큼
	Gap = 0.2, -- 관리자 버튼 사이 최소 초 (연타 막기)
	RefreshGap = 0.5, -- 정보 다시 받기 사이 최소 초
	AnnounceGap = 8, -- 📢 공지 사이 최소 초
	AnnounceMax = 60, -- 📢 공지 글자 수 (최대)
	WarnGap = 30, -- 관리자가 아닌 사람이 부르면 경고는 이 초마다 한 번만
}

-- ★v7.4 관리자인가 (AdminUserIds 에 있거나, 사람이 만든 게임의 주인). Studio 테스트에서도 진짜 계정 번호라 돼요
function Config.IsAdminUserId(userId: any): boolean
	if type(userId) ~= "number" or userId <= 0 or userId ~= math.floor(userId) then
		return false
	end
	for _, id in Config.AdminUserIds do
		if id == userId then
			return true
		end
	end
	local ok, creator = pcall(function(): boolean
		local creatorId = (game :: any).CreatorId
		return game.CreatorType == Enum.CreatorType.User and type(creatorId) == "number" and creatorId > 0 and creatorId == userId
	end)
	return ok and creator == true
end

Config.MaxFollow = 3 -- 데리고 다닐 수 있는 펫 수
Config.MaxBagItems = 150 -- 가방 최대 칸 (Loc == "Bag" 인 아이템 수)
-- ★v7.1 ♾ 가방 무한 (Settings.InfiniteBag) 일 때 칸. 진짜 무한은 안 돼요: 저장과 DataSync 스냅샷이 아이템을 다 보내요.
-- 재어 보니 (긴 id + 옷 + 갤럭시, 받침대 120 + 데리고 다니는 5) 가방 1마리 ≈ 115 B: 150 → 저장/스냅샷 42 KB,
-- 500 → 82 KB (DataStore 4 MB 의 2 %, 스냅샷은 지금 가방 150 의 2 배), 1000 → 139 KB. 스냅샷이 초당 5번까지 가서 500 으로 해요.
-- 끄면 아무것도 안 지워요: 150 마리 넘게 있으면 150 아래로 줄 때까지 "가득" 이에요
-- ★v7.5 게임 패스 (Config.Passes.InfiniteBag) 가 있을 때만 500. 패스 없이 켜 둔 예전 저장도 펫은 그대로, 칸만 150
Config.InfiniteBagItems = 500

-- ★v7.1 지금 가방 칸 수 (infinite = Settings.InfiniteBag ★v7.5 그리고 패스가 있나: 부르는 쪽이 둘 다 봐요)
function Config.BagCapacity(infinite: any): number
	return if infinite == true then Config.InfiniteBagItems else Config.MaxBagItems
end
Config.BaseWalkSpeed = 18
Config.WalkSpeedPerFollower = 0.5
Config.MaxWalkSpeed = 64 -- FollowService.UpdateSpeed 가 이 값으로 잘라요
Config.MaxRareRideWalkSpeed = 80 -- ★v7 희귀 펫(시크릿/천상/이터널)을 탈 때만: 64 위로는 이 값까지 부드럽게 (Config.SoftSpeedCap)

-- 희귀도 (Order: 낮을수록 흔함). Income/Boost = 지역 1 기준 비율 (실제 값은 펫마다 적혀 있어요)
Config.Rarities = {
	Common = { Name = "보통", Color = RGB(170, 175, 185), Order = 1, Boost = 0.03 },
	Uncommon = { Name = "고급", Color = RGB(95, 205, 110), Order = 2, Boost = 0.05 },
	Rare = { Name = "희귀", Color = RGB(70, 150, 255), Order = 3, Boost = 0.08 },
	Epic = { Name = "영웅", Color = RGB(180, 90, 255), Order = 4, Boost = 0.12 },
	Legendary = { Name = "전설", Color = RGB(255, 180, 30), Order = 5, Boost = 0.18 },
	Mythic = { Name = "신화", Color = RGB(255, 80, 160), Order = 6, Boost = 0.25 },
	Secret = { Name = "비밀", Color = RGB(120, 240, 255), Order = 7, Boost = 0.4 }, -- 지역마다 1마리
	-- ★v6 아주 희귀한 알(시크릿/천상/이터널 알)에서만 나오는 3단계. 지역마다 1마리씩, Special = 단계 키
	-- ★v7 ModelScale: 월드 모델이 크기(Size) × 이만큼 커요 (Config.PetDisplayScale. 없으면 1)
	Hidden = { Name = "시크릿", Color = RGB(60, 230, 170), Order = 8, Boost = 0.5, Special = true, ModelScale = 1.2 },
	Celestial = { Name = "천상", Color = RGB(255, 214, 60), Order = 9, Boost = 0.6, Special = true, ModelScale = 1.4 },
	Eternal = { Name = "이터널", Color = RGB(215, 105, 255), Order = 10, Boost = 0.8, Special = true, Rainbow = true, ModelScale = 1.6 },
}
Config.RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret", "Hidden", "Celestial", "Eternal" }

-- ★v7.1 💰 한꺼번에 팔기 / 🤖 자동 판매 (Config.SellMatch 로 같이 검사해요)
Config.SellRarityTop = 7 -- 고를 수 있는 가장 높은 등급 (7 = 비밀). 시크릿·천상·이터널 (Special) 은 절대 안 팔아요
Config.BulkSell = {
	KeepTier = 4, -- 이 등급(🥇 골드) 이상은 지켜요
	Gap = 1, -- 한꺼번에 팔기 사이 최소 초 (연타 막기)
	ConfirmCount = 20, -- 이만큼 이상이면 "팔기" 를 한 번 더 눌러야 해요
	ConfirmCoins = 1e6, -- 또는 합계가 이 이상이면
}

----------------------------------------------------------------------
-- 지역 (맵). v4: 숲 마을(집 6채 + 로비 + 컨베이어)이 가운데 있고, 지역 2~8 은 그 둘레의 섬이에요.
-- 환생 MinRebirth 번 이상이면 들어갈 수 있어요. 바닥 윗면은 어디나 y = 0. Size.Y = 땅 두께 (윗면 y = 0).
-- 섬마다 짧은 길(Trail, 30 스터드)이 숲 마을 가장자리에서 바로 시작하고, 길이 시작하는 곳(숲 마을 쪽 끝)에
-- 입구 문(Gate)이 있어서 집 앞에서도 잠긴 문("🔒 환생 N회")이 다 보여요.
-- 로비(서쪽, 스폰이 +X 를 봐요)에서 보면 왼쪽 뒤부터 시계 방향으로 한 바퀴:
--   2 호수 (서쪽 왼편) → 3 정글 (왼쪽) → 4 겨울 산 (왼쪽 앞) → 5 바다 (정면 끝) → 6 캔디 랜드 (오른쪽 앞)
--   → 7 구름 왕국 (오른쪽) → 8 우주 (서쪽 오른편)
-- ★v8 바깥 섬 8개 (9~16): 안쪽 섬 맨 끝에서 길이 하나 더 나가요 (Zone.Parent = 길이 시작하는 섬).
--   9 벚꽃 정원 (호수 뒤) · 10 공룡 섬 (정글 뒤) · 11 보석 동굴 (겨울 산 뒤) · 12 사막 오아시스 (바다 뒤)
--   · 13 장난감 나라 (캔디 랜드 뒤) · 14 꿈나라 (구름 왕국 뒤) · 15 불꽃 화산 (우주 뒤) · 16 황금 왕국 (사막 뒤)
-- ★v8 숲 마을은 z ±200 으로 넓어졌어요 (집 줄 뒤에 2번 집 줄). 그래서 섬 3·4·6·7 은 75 더 바깥에 있어요
-- 섬 안: 입구 → 스폰 → 큰길. 컨베이어는 큰길 옆으로 나란히 (입구 쪽에서 알이 나와요), 코인 들판은 큰길 둘레.
----------------------------------------------------------------------
local TRAIL_LENGTH = 30 -- 숲 마을 가장자리 → 섬 입구
local TRAIL_WIDTH = 16
local ISLAND = 160 -- 지역 2~8 섬 한 변
local BELT_LENGTH = 100 -- 지역 2~8 컨베이어 길이
local BELT_FROM = 26 -- 섬 입구에서 컨베이어 시작(알 슈트)까지
local BELT_EDGE = 38 -- 컨베이어와 섬 옆 가장자리 사이 (컨베이어 뒤 장식 자리)
local SPAWN_IN = 16 -- 섬 입구에서 스폰까지
local HOME_CENTER = V3(-22.5, 0, 0)

-- 지역 2~8 섬 배치. o.Mouth = 숲 마을 가장자리의 길 시작점, o.Dir = 섬 쪽 방향 (X 나 Z 축), o.Center = 섬 가운데.
-- 섬 안 좌표: u = 섬 입구에서 Dir 쪽으로, v = 길 중심선에서 Side 쪽으로 (Side = Dir 을 90° 돌린 방향)
local function island(def: { [string]: any }, o: { [string]: any }): { [string]: any }
	local dir: Vector3 = o.Dir
	local side = V3(-dir.Z, 0, dir.X)
	local mouth: Vector3 = o.Mouth
	local entry = mouth + dir * TRAIL_LENGTH -- 섬 입구 (섬 가장자리 위, 길 끝)
	local function at(u: number, v: number): Vector3
		return entry + dir * u + side * v
	end
	local half = ISLAND / 2
	local vc = (o.Center - entry):Dot(side) -- 섬 가운데의 v
	-- 컨베이어는 길에서 더 넓은 쪽에 (똑같으면 숲 마을 반대쪽)
	local roomPos, roomNeg = vc + half, half - vc
	local beltSide = if roomPos > roomNeg + 1
		then 1
		elseif roomNeg > roomPos + 1 then -1
		elseif (HOME_CENTER - entry):Dot(side) > 0 then -1
		else 1
	local vb = vc + beltSide * (half - BELT_EDGE)
	-- 코인 들판: 컨베이어 앞(길 쪽) ~ 반대편 가장자리, 입구 12 ~ 끝 30 (맨 끝 띠와 컨베이어 뒤는 큰 장식 자리)
	local f1 = at(12, vb - beltSide * 12)
	local f2 = at(ISLAND - 30, vc - beltSide * (half - 10))
	def.Center = o.Center
	def.Size = V3(ISLAND, 4, ISLAND)
	def.ConveyorStart = at(BELT_FROM, vb)
	def.ConveyorEnd = at(BELT_FROM + BELT_LENGTH, vb)
	def.FieldMin = V3(math.min(f1.X, f2.X), 0, math.min(f1.Z, f2.Z))
	def.FieldMax = V3(math.max(f1.X, f2.X), 0, math.max(f1.Z, f2.Z))
	def.Spawn = at(SPAWN_IN, 0)
	def.SpawnLook = dir -- 스폰/순간이동하면 섬 안쪽을 봐요
	-- 길: From(숲 마을 가장자리) → To(섬 입구). Side/BeltSide 는 WorldBuilder 가 섬 안 길을 그릴 때 써요
	def.Trail = { From = mouth, To = entry, Dir = dir, Side = side, BeltSide = beltSide }
	-- ★v8 길이 시작하는 땅 (1 = 숲 마을, 바깥 섬 9~16 은 안쪽 섬 번호). 문 간판 뒷면·울타리 틈·큰길을 이걸로 그려요
	def.Parent = o.Parent or 1
	-- 입구 문: 길이 시작하는 곳 (숲 마을 쪽 끝). 환생이 모자란 사람만 클라이언트에서 막혀요
	local gatePos = mouth + dir * 1.5 + V3(0, 8, 0)
	def.Gate = { CFrame = CFrame.lookAt(gatePos, gatePos + dir), Size = V3(TRAIL_WIDTH + 4, 16, 2) }
	return def
end

local WEST, EAST, NORTH, SOUTH = V3(-1, 0, 0), V3(1, 0, 0), V3(0, 0, 1), V3(0, 0, -1)

Config.Zones = {
	{
		Id = "Village",
		Name = "숲 마을",
		Emoji = "🌳",
		MinRebirth = 0,
		CoinMult = 1,
		Center = HOME_CENTER,
		Size = V3(315, 4, 400), -- x -180..135, z -200..200 (집 6채 + ★v8 뒤쪽 2번 집 6채 + 로비 + 컨베이어). 둘레에 섬 7개
		Palette = {
			Ground = RGB(125, 210, 105),
			Path = RGB(250, 232, 198),
			Accent = RGB(255, 160, 200),
			Trim = RGB(205, 155, 115),
			Sky = RGB(165, 215, 255),
			Deco = { "Tree", "Flower", "Mushroom", "Bush", "Cloud" },
		},
		Eggs = { "Basic", "Flower", "Mushroom", "Forest", "Fairy", "Spirit" },
		ConveyorStart = V3(-56, 0, 0),
		ConveyorEnd = V3(56, 0, 0),
		FieldMin = V3(-110, 0, -42),
		FieldMax = V3(110, 0, 42),
		Spawn = V3(-140, 0, 0), -- = Layout.LobbySpawn
		SpawnLook = EAST,
		Gate = nil, -- 첫 지역은 문이 없어요
		Trail = nil,
	},
	island({
		Id = "Lake",
		Name = "호수",
		Emoji = "🦆",
		MinRebirth = 1,
		CoinMult = 1.15,
		Palette = {
			Ground = RGB(140, 215, 120),
			Path = RGB(235, 225, 195),
			Accent = RGB(110, 200, 245),
			Trim = RGB(160, 120, 85),
			Water = RGB(90, 180, 235),
			Sky = RGB(175, 225, 255),
			Deco = { "Pond", "LilyPad", "Reed", "Rock", "Tree" },
		},
		Eggs = { "Lake", "Lily", "Bubble", "Moonlight", "Crystal" },
	}, { Mouth = V3(-180, 0, -80), Dir = WEST, Center = V3(-290, 0, -90) }),
	island({
		Id = "Jungle",
		Name = "정글",
		Emoji = "🌴",
		MinRebirth = 2,
		CoinMult = 1.3,
		Palette = {
			Ground = RGB(85, 175, 80),
			Path = RGB(205, 170, 120),
			Accent = RGB(255, 200, 60),
			Trim = RGB(120, 85, 55),
			Sky = RGB(190, 235, 200),
			Deco = { "PalmTree", "BigLeaf", "Vine", "Rock", "Flower" },
		},
		Eggs = { "Jungle", "Leaf", "Spotted", "Tropical", "Tiger" },
	}, { Mouth = V3(-150, 0, -200), Dir = SOUTH, Center = V3(-105, 0, -310) }), -- ★v8 숲 마을이 넓어져서 75 더 바깥
	island({
		Id = "Snow",
		Name = "겨울 산",
		Emoji = "🏔",
		MinRebirth = 3,
		CoinMult = 1.45,
		Palette = {
			Ground = RGB(240, 245, 255),
			Path = RGB(200, 220, 240),
			Accent = RGB(130, 200, 255),
			Trim = RGB(150, 110, 85),
			Sky = RGB(215, 230, 250),
			Deco = { "PineTree", "SnowPile", "IceCrystal", "Snowman", "Rock" },
		},
		Eggs = { "Snow", "Ice", "Snowflake", "Aurora", "Twilight" },
	}, { Mouth = V3(120, 0, -200), Dir = SOUTH, Center = V3(125, 0, -310) }), -- ★v8
	island({
		Id = "Ocean",
		Name = "바다",
		Emoji = "🌊",
		MinRebirth = 5,
		CoinMult = 1.6,
		Palette = {
			Ground = RGB(245, 225, 170),
			Path = RGB(255, 240, 205),
			Accent = RGB(255, 140, 120),
			Trim = RGB(80, 170, 220),
			Water = RGB(60, 160, 230),
			Sky = RGB(160, 215, 255),
			Deco = { "PalmTree", "Shell", "Starfish", "Coral", "Umbrella" },
		},
		Eggs = { "Ocean", "Shell", "Coral", "Pearl", "DragonPalace" },
	}, { Mouth = V3(135, 0, 0), Dir = EAST, Center = V3(245, 0, 0) }),
	island({
		Id = "Candy",
		Name = "캔디 랜드",
		Emoji = "🍭",
		MinRebirth = 7,
		CoinMult = 1.75,
		Palette = {
			Ground = RGB(255, 200, 225),
			Path = RGB(255, 245, 250),
			Accent = RGB(150, 230, 200),
			Trim = RGB(255, 120, 170),
			Sky = RGB(255, 220, 240),
			Deco = { "Lollipop", "CandyCane", "Cupcake", "GumDrop", "Donut" },
		},
		Eggs = { "Candy", "Jelly", "Lollipop", "Cake", "Rainbow" },
	}, { Mouth = V3(120, 0, 200), Dir = NORTH, Center = V3(125, 0, 310) }), -- ★v8
	island({
		Id = "Cloud",
		Name = "구름 왕국",
		Emoji = "☁️",
		MinRebirth = 10,
		CoinMult = 1.9,
		Palette = {
			Ground = RGB(245, 242, 255),
			Path = RGB(255, 235, 160),
			Accent = RGB(200, 170, 255),
			Trim = RGB(255, 210, 90),
			Sky = RGB(230, 225, 255),
			Deco = { "Cloud", "Castle", "RainbowArch", "Star", "Pillar" },
		},
		Eggs = { "Cloud", "Breeze", "Feather", "Angel", "Golden" },
	}, { Mouth = V3(-150, 0, 200), Dir = NORTH, Center = V3(-105, 0, 310) }), -- ★v8
	island({
		Id = "Space",
		Name = "우주",
		Emoji = "🚀",
		MinRebirth = 14,
		CoinMult = 2,
		Palette = {
			Ground = RGB(70, 60, 110),
			Path = RGB(130, 120, 180),
			Accent = RGB(120, 240, 255),
			Trim = RGB(200, 210, 230),
			Sky = RGB(25, 20, 60),
			Deco = { "Crater", "Planet", "SpaceCrystal", "Rocket", "Star" },
		},
		Eggs = { "Space", "Moon", "Planet", "Comet", "Starlight" },
	}, { Mouth = V3(-180, 0, 80), Dir = WEST, Center = V3(-290, 0, 90) }),
	-- ★v8 바깥 섬 8개 (지역 9~16): 안쪽 섬의 맨 끝(숲 마을 반대쪽) 가장자리에서 길이 시작해요 (Parent = 그 섬).
	-- 9~15 는 섬 2~8 뒤에 하나씩, 16 은 12 (사막) 뒤. 환생 16, 18, … 30 회에 열려요
	island({
		Id = "Blossom",
		Name = "벚꽃 정원",
		Emoji = "🌸",
		MinRebirth = 16,
		CoinMult = 2.1,
		Palette = {
			Ground = RGB(175, 225, 145),
			Path = RGB(255, 236, 242),
			Accent = RGB(255, 150, 195),
			Trim = RGB(175, 115, 95),
			Water = RGB(150, 210, 245),
			Sky = RGB(255, 225, 240),
			Deco = { "CherryTree", "Lantern", "Flower", "Pond", "Butterfly" },
		},
		Eggs = { "Sakura", "Tulip", "HoneyPot", "Bloom", "SpringQueen" },
	}, { Mouth = V3(-370, 0, -80), Dir = WEST, Center = V3(-480, 0, -90), Parent = 2 }),
	island({
		Id = "Dino",
		Name = "공룡 섬",
		Emoji = "🦕",
		MinRebirth = 18,
		CoinMult = 2.2,
		Palette = {
			Ground = RGB(125, 185, 90),
			Path = RGB(215, 185, 140),
			Accent = RGB(255, 170, 70),
			Trim = RGB(130, 95, 65),
			Water = RGB(90, 180, 200),
			Sky = RGB(205, 235, 210),
			Deco = { "Fern", "Bones", "DinoEgg", "PalmTree", "Rock" },
		},
		Eggs = { "Dino", "Fern", "Fossil", "Amber", "Jurassic" },
	}, { Mouth = V3(-150, 0, -390), Dir = SOUTH, Center = V3(-105, 0, -500), Parent = 3 }),
	island({
		Id = "Crystal",
		Name = "보석 동굴",
		Emoji = "💎",
		MinRebirth = 20,
		CoinMult = 2.3,
		Palette = {
			Ground = RGB(105, 95, 140),
			Path = RGB(185, 175, 215),
			Accent = RGB(120, 240, 230),
			Trim = RGB(80, 70, 105),
			Sky = RGB(175, 165, 225),
			Deco = { "BigCrystal", "Geode", "Mushroom", "Rock", "Lantern" },
		},
		Eggs = { "Cave", "Ruby", "Sapphire", "Amethyst", "DiamondEgg" },
	}, { Mouth = V3(120, 0, -390), Dir = SOUTH, Center = V3(125, 0, -500), Parent = 4 }),
	island({
		Id = "Desert",
		Name = "사막 오아시스",
		Emoji = "🏜",
		MinRebirth = 22,
		CoinMult = 2.4,
		Palette = {
			Ground = RGB(245, 215, 155),
			Path = RGB(255, 240, 210),
			Accent = RGB(80, 190, 200),
			Trim = RGB(190, 140, 80),
			Water = RGB(80, 190, 220),
			Sky = RGB(255, 235, 200),
			Deco = { "Cactus", "Pyramid", "PalmTree", "Oasis", "Rock" },
		},
		Eggs = { "Sand", "Oasis", "CactusEgg", "Pyramid", "Pharaoh" },
	}, { Mouth = V3(325, 0, 0), Dir = EAST, Center = V3(435, 0, 0), Parent = 5 }),
	island({
		Id = "Toy",
		Name = "장난감 나라",
		Emoji = "🧸",
		MinRebirth = 24,
		CoinMult = 2.5,
		Palette = {
			Ground = RGB(255, 232, 175),
			Path = RGB(255, 255, 255),
			Accent = RGB(255, 95, 115),
			Trim = RGB(90, 160, 255),
			Sky = RGB(220, 240, 255),
			Deco = { "ToyBlock", "Balloon", "Ball", "SpinningTop", "Teddy" },
		},
		Eggs = { "ToyEgg", "Block", "Balloon", "MusicBox", "Carousel" },
	}, { Mouth = V3(120, 0, 390), Dir = NORTH, Center = V3(125, 0, 500), Parent = 6 }),
	island({
		Id = "Dream",
		Name = "꿈나라",
		Emoji = "🌙",
		MinRebirth = 26,
		CoinMult = 2.6,
		Palette = {
			Ground = RGB(125, 125, 195),
			Path = RGB(222, 216, 255),
			Accent = RGB(255, 225, 120),
			Trim = RGB(160, 150, 230),
			Sky = RGB(45, 45, 100),
			Night = true, -- ★v8 우주처럼 밤 하늘 (ZoneClient)
			Deco = { "Moon", "Pillow", "Star", "Cloud", "Lamp" },
		},
		Eggs = { "DreamEgg", "Pillow", "Crescent", "Lullaby", "Starry" },
	}, { Mouth = V3(-150, 0, 390), Dir = NORTH, Center = V3(-105, 0, 500), Parent = 7 }),
	island({
		Id = "Volcano",
		Name = "불꽃 화산",
		Emoji = "🌋",
		MinRebirth = 28,
		CoinMult = 2.7,
		Palette = {
			Ground = RGB(85, 70, 70),
			Path = RGB(155, 125, 115),
			Accent = RGB(255, 120, 50),
			Trim = RGB(55, 45, 50),
			Sky = RGB(255, 190, 150),
			Deco = { "Volcano", "LavaPool", "Obsidian", "Rock", "Ember" },
		},
		Eggs = { "Lava", "Ember", "Magma", "Obsidian", "Blaze" },
	}, { Mouth = V3(-370, 0, 80), Dir = WEST, Center = V3(-480, 0, 90), Parent = 8 }),
	island({
		Id = "Gold",
		Name = "황금 왕국",
		Emoji = "👑",
		MinRebirth = 30,
		CoinMult = 2.8,
		Palette = {
			Ground = RGB(250, 240, 205),
			Path = RGB(255, 225, 125),
			Accent = RGB(255, 200, 50),
			Trim = RGB(200, 60, 80),
			Water = RGB(90, 200, 240),
			Sky = RGB(255, 245, 210),
			Deco = { "GoldCastle", "CoinPile", "Treasure", "Fountain", "Pillar" },
		},
		Eggs = { "Coin", "Treasure", "Royal", "Jewel", "Emperor" },
	}, { Mouth = V3(515, 0, 0), Dir = EAST, Center = V3(625, 0, 0), Parent = 12 }),
}
Config.MaxZone = #Config.Zones

----------------------------------------------------------------------
-- 펫. Zone = 지역 번호. Income = 집 받침대 위에서 1초마다 버는 코인 (지역마다 ×5 정도라서
-- 다음 지역의 보통 펫이 이전 지역의 전설 펫보다 세요). Boost 는 아래에서 희귀도·지역으로 채워요.
-- Color 는 UI 강조색 (모델 색은 PetModels 가 정함). ★ = v3 새 펫
-- ★v6 = 아주 희귀한 알에서만 나오는 펫 (시크릿 / 천상 / 이터널, 지역마다 3마리)
-- ★v7 수익 = 그 지역 신화 펫 × 25 / 60 / 150 (🥇 골드 ×20 · 🌈 레인보우 ×50 · 💎 다이아 ×120 신화보다 세요). 크기도 더 커요 (PetSize.Special)
----------------------------------------------------------------------
Config.Pets = {
	-- 1. 숲 마을
	Chick = { Name = "병아리", Rarity = "Common", Zone = 1, Income = 2, Color = RGB(255, 225, 80) },
	Bunny = { Name = "토끼", Rarity = "Common", Zone = 1, Income = 2, Color = RGB(255, 205, 220) },
	Hamster = { Name = "햄스터", Rarity = "Common", Zone = 1, Income = 3, Color = RGB(240, 180, 110) },
	Piglet = { Name = "아기돼지", Rarity = "Common", Zone = 1, Income = 3, Color = RGB(255, 170, 190) },
	Puppy = { Name = "강아지", Rarity = "Uncommon", Zone = 1, Income = 4, Color = RGB(210, 165, 115) },
	Cat = { Name = "고양이", Rarity = "Rare", Zone = 1, Income = 5, Color = RGB(255, 165, 80) },
	Owl = { Name = "부엉이", Rarity = "Epic", Zone = 1, Income = 7, Color = RGB(150, 110, 80) },
	Fox = { Name = "여우", Rarity = "Legendary", Zone = 1, Income = 9, Color = RGB(245, 120, 45) },
	RainbowCat = { Name = "무지개 냥이", Rarity = "Mythic", Zone = 1, Income = 14, Color = RGB(255, 120, 220) },
	SpiritDeer = { Name = "정령 사슴", Rarity = "Secret", Zone = 1, Income = 25, Color = RGB(170, 255, 210) }, -- ★
	CloverFox = { Name = "네잎클로버 여우", Rarity = "Hidden", Zone = 1, Income = 350, Color = RGB(255, 150, 70) }, -- ★v6 ★v7 신화 ×25
	BlossomFawn = { Name = "꽃사슴 요정", Rarity = "Celestial", Zone = 1, Income = 840, Color = RGB(255, 190, 215) }, -- ★v6 ★v7 신화 ×60
	WorldTreeDragon = { Name = "세계수 용", Rarity = "Eternal", Zone = 1, Income = 2100, Color = RGB(120, 210, 110) }, -- ★v6 ★v7 신화 ×150

	-- 2. 호수
	Duck = { Name = "오리", Rarity = "Common", Zone = 2, Income = 10, Color = RGB(255, 240, 150) },
	Frog = { Name = "개구리", Rarity = "Common", Zone = 2, Income = 12, Color = RGB(120, 210, 90) },
	Hedgehog = { Name = "고슴도치", Rarity = "Uncommon", Zone = 2, Income = 15, Color = RGB(150, 110, 80) },
	Squirrel = { Name = "다람쥐", Rarity = "Rare", Zone = 2, Income = 22, Color = RGB(200, 130, 70) },
	Raccoon = { Name = "라쿤", Rarity = "Epic", Zone = 2, Income = 32, Color = RGB(140, 140, 150) },
	Turtle = { Name = "거북이", Rarity = "Legendary", Zone = 2, Income = 45, Color = RGB(110, 190, 120) },
	Axolotl = { Name = "우파루파", Rarity = "Mythic", Zone = 2, Income = 70, Color = RGB(255, 160, 200) },
	MoonKoi = { Name = "달빛 잉어", Rarity = "Secret", Zone = 2, Income = 120, Color = RGB(255, 245, 200) }, -- ★
	PearlOtter = { Name = "진주 수달", Rarity = "Hidden", Zone = 2, Income = 1750, Color = RGB(175, 125, 90) }, -- ★v6 ★v7 신화 ×25
	MoonSwan = { Name = "달빛 백조", Rarity = "Celestial", Zone = 2, Income = 4200, Color = RGB(235, 240, 255) }, -- ★v6 ★v7 신화 ×60
	RainbowKoiDragon = { Name = "무지개 잉어 용", Rarity = "Eternal", Zone = 2, Income = 10500, Color = RGB(255, 140, 110) }, -- ★v6 ★v7 신화 ×150

	-- 3. 정글
	Monkey = { Name = "원숭이", Rarity = "Common", Zone = 3, Income = 50, Color = RGB(170, 120, 80) },
	Parrot = { Name = "앵무새", Rarity = "Common", Zone = 3, Income = 60, Color = RGB(90, 200, 110) },
	Koala = { Name = "코알라", Rarity = "Uncommon", Zone = 3, Income = 75, Color = RGB(160, 165, 175) },
	Bear = { Name = "곰돌이", Rarity = "Rare", Zone = 3, Income = 110, Color = RGB(165, 110, 70) },
	Lion = { Name = "사자", Rarity = "Epic", Zone = 3, Income = 160, Color = RGB(240, 185, 80) },
	Panda = { Name = "판다", Rarity = "Legendary", Zone = 3, Income = 225, Color = RGB(245, 245, 245) },
	Peacock = { Name = "공작새", Rarity = "Mythic", Zone = 3, Income = 350, Color = RGB(60, 170, 220) }, -- ★
	WhiteTiger = { Name = "백호", Rarity = "Secret", Zone = 3, Income = 600, Color = RGB(235, 245, 255) }, -- ★
	RainbowChameleon = { Name = "무지개 카멜레온", Rarity = "Hidden", Zone = 3, Income = 8750, Color = RGB(130, 225, 110) }, -- ★v6 ★v7 신화 ×25
	GoldenJaguar = { Name = "황금 재규어", Rarity = "Celestial", Zone = 3, Income = 21000, Color = RGB(255, 200, 70) }, -- ★v6 ★v7 신화 ×60
	EmeraldDragon = { Name = "에메랄드 용", Rarity = "Eternal", Zone = 3, Income = 52500, Color = RGB(40, 200, 120) }, -- ★v6 ★v7 신화 ×150

	-- 4. 겨울 산
	Penguin = { Name = "펭귄", Rarity = "Common", Zone = 4, Income = 240, Color = RGB(70, 90, 130) },
	Seal = { Name = "바다표범", Rarity = "Common", Zone = 4, Income = 290, Color = RGB(225, 230, 240) },
	SnowBunny = { Name = "눈토끼", Rarity = "Uncommon", Zone = 4, Income = 360, Color = RGB(240, 245, 255) },
	Snowman = { Name = "눈사람", Rarity = "Rare", Zone = 4, Income = 530, Color = RGB(250, 250, 255) },
	PolarBear = { Name = "북극곰", Rarity = "Epic", Zone = 4, Income = 770, Color = RGB(245, 245, 250) },
	Reindeer = { Name = "순록", Rarity = "Legendary", Zone = 4, Income = 1080, Color = RGB(180, 130, 90) },
	FrostFox = { Name = "눈꽃 여우", Rarity = "Mythic", Zone = 4, Income = 1700, Color = RGB(170, 220, 255) }, -- ★
	Yeti = { Name = "예티", Rarity = "Secret", Zone = 4, Income = 2900, Color = RGB(200, 230, 255) }, -- ★
	CrystalPenguin = { Name = "수정 펭귄", Rarity = "Hidden", Zone = 4, Income = 42500, Color = RGB(150, 215, 255) }, -- ★v6 ★v7 신화 ×25
	AuroraWolf = { Name = "오로라 늑대", Rarity = "Celestial", Zone = 4, Income = 102000, Color = RGB(140, 240, 210) }, -- ★v6 ★v7 신화 ×60
	IcePhoenix = { Name = "얼음 불사조", Rarity = "Eternal", Zone = 4, Income = 255000, Color = RGB(130, 210, 255) }, -- ★v6 ★v7 신화 ×150

	-- 5. 바다
	Crab = { Name = "게", Rarity = "Common", Zone = 5, Income = 1200, Color = RGB(255, 120, 90) },
	Jellyfish = { Name = "해파리", Rarity = "Common", Zone = 5, Income = 1450, Color = RGB(190, 160, 255) },
	Octopus = { Name = "문어", Rarity = "Uncommon", Zone = 5, Income = 1800, Color = RGB(255, 130, 160) },
	BabyShark = { Name = "아기 상어", Rarity = "Rare", Zone = 5, Income = 2650, Color = RGB(120, 170, 230) },
	Dolphin = { Name = "돌고래", Rarity = "Epic", Zone = 5, Income = 3850, Color = RGB(120, 180, 240) },
	Narwhal = { Name = "일각고래", Rarity = "Legendary", Zone = 5, Income = 5400, Color = RGB(150, 200, 240) }, -- ★
	MermaidCat = { Name = "인어 냥이", Rarity = "Mythic", Zone = 5, Income = 8400, Color = RGB(100, 220, 210) }, -- ★
	DragonKing = { Name = "용왕", Rarity = "Secret", Zone = 5, Income = 14500, Color = RGB(60, 200, 170) }, -- ★
	RainbowJelly = { Name = "무지개 해파리", Rarity = "Hidden", Zone = 5, Income = 210000, Color = RGB(255, 170, 230) }, -- ★v6 ★v7 신화 ×25
	PearlSeahorse = { Name = "진주 해마", Rarity = "Celestial", Zone = 5, Income = 504000, Color = RGB(255, 200, 225) }, -- ★v6 ★v7 신화 ×60
	BabyKraken = { Name = "아기 크라켄", Rarity = "Eternal", Zone = 5, Income = 1260000, Color = RGB(150, 90, 210) }, -- ★v6 ★v7 신화 ×150

	-- 6. 캔디 랜드
	CottonSheep = { Name = "솜사탕 양", Rarity = "Common", Zone = 6, Income = 6000, Color = RGB(255, 190, 230) },
	DonutPuppy = { Name = "도넛 강아지", Rarity = "Common", Zone = 6, Income = 7200, Color = RGB(255, 160, 190) },
	JellyBear = { Name = "젤리곰", Rarity = "Uncommon", Zone = 6, Income = 9000, Color = RGB(255, 90, 110) },
	CupcakeCat = { Name = "컵케이크 냥이", Rarity = "Rare", Zone = 6, Income = 13000, Color = RGB(255, 210, 230) },
	MacaronBunny = { Name = "마카롱 토끼", Rarity = "Epic", Zone = 6, Income = 19000, Color = RGB(190, 240, 210) },
	GummyDragon = { Name = "젤리 용", Rarity = "Legendary", Zone = 6, Income = 27000, Color = RGB(255, 120, 80) }, -- ★
	CandyUnicorn = { Name = "사탕 유니콘", Rarity = "Mythic", Zone = 6, Income = 42000, Color = RGB(255, 175, 215) }, -- ★
	CookieKing = { Name = "쿠키 왕", Rarity = "Secret", Zone = 6, Income = 72000, Color = RGB(205, 140, 80) }, -- ★
	LollipopPanda = { Name = "막대사탕 판다", Rarity = "Hidden", Zone = 6, Income = 1050000, Color = RGB(255, 150, 200) }, -- ★v6 ★v7 신화 ×25
	MarshmallowBear = { Name = "마시멜로 곰", Rarity = "Celestial", Zone = 6, Income = 2520000, Color = RGB(255, 240, 225) }, -- ★v6 ★v7 신화 ×60
	SweetQueenCat = { Name = "사탕 여왕 냥이", Rarity = "Eternal", Zone = 6, Income = 6300000, Color = RGB(255, 120, 190) }, -- ★v6 ★v7 신화 ×150

	-- 7. 구름 왕국
	Sheep = { Name = "양", Rarity = "Common", Zone = 7, Income = 30000, Color = RGB(250, 245, 235) },
	CloudPuppy = { Name = "구름 강아지", Rarity = "Common", Zone = 7, Income = 36000, Color = RGB(235, 245, 255) }, -- ★
	BabyCloud = { Name = "아기 구름", Rarity = "Uncommon", Zone = 7, Income = 45000, Color = RGB(220, 235, 255) }, -- ★
	Dragon = { Name = "아기 용", Rarity = "Rare", Zone = 7, Income = 66000, Color = RGB(110, 215, 140) },
	Unicorn = { Name = "유니콘", Rarity = "Epic", Zone = 7, Income = 96000, Color = RGB(250, 225, 255) },
	Pegasus = { Name = "페가수스", Rarity = "Legendary", Zone = 7, Income = 135000, Color = RGB(240, 248, 255) }, -- ★
	Phoenix = { Name = "불사조", Rarity = "Mythic", Zone = 7, Income = 210000, Color = RGB(255, 110, 50) },
	AngelBunny = { Name = "천사 토끼", Rarity = "Secret", Zone = 7, Income = 360000, Color = RGB(255, 240, 170) }, -- ★
	ThunderPup = { Name = "번개 강아지", Rarity = "Hidden", Zone = 7, Income = 5250000, Color = RGB(150, 175, 215) }, -- ★v6 ★v7 신화 ×25
	SunGriffin = { Name = "해님 그리핀", Rarity = "Celestial", Zone = 7, Income = 12600000, Color = RGB(255, 205, 80) }, -- ★v6 ★v7 신화 ×60
	NineTailFox = { Name = "구미호", Rarity = "Eternal", Zone = 7, Income = 31500000, Color = RGB(250, 245, 255) }, -- ★v6 ★v7 신화 ×150

	-- 8. 우주
	Alien = { Name = "외계인", Rarity = "Common", Zone = 8, Income = 150000, Color = RGB(140, 240, 150) },
	RobotPuppy = { Name = "로봇 강아지", Rarity = "Common", Zone = 8, Income = 180000, Color = RGB(200, 210, 230) },
	MoonBunny = { Name = "달토끼", Rarity = "Uncommon", Zone = 8, Income = 225000, Color = RGB(255, 245, 190) },
	SpaceCat = { Name = "우주 냥이", Rarity = "Rare", Zone = 8, Income = 330000, Color = RGB(120, 90, 200) },
	AstroBear = { Name = "우주곰", Rarity = "Epic", Zone = 8, Income = 480000, Color = RGB(190, 150, 110) }, -- ★
	CometFox = { Name = "혜성 여우", Rarity = "Legendary", Zone = 8, Income = 675000, Color = RGB(90, 150, 255) }, -- ★
	StarSlime = { Name = "별 슬라임", Rarity = "Mythic", Zone = 8, Income = 1050000, Color = RGB(150, 230, 255) },
	-- 마지막 비밀 펫: 우주의 별빛 알에서만 0.1%
	CosmicWhale = { Name = "우주 고래", Rarity = "Secret", Zone = 8, Income = 2000000, Color = RGB(120, 200, 255) },
	MeteorHamster = { Name = "운석 햄스터", Rarity = "Hidden", Zone = 8, Income = 26250000, Color = RGB(255, 160, 80) }, -- ★v6 ★v7 신화 ×25
	GalaxyUnicorn = { Name = "은하 유니콘", Rarity = "Celestial", Zone = 8, Income = 63000000, Color = RGB(80, 90, 200) }, -- ★v6 ★v7 신화 ×60
	CosmoDragon = { Name = "은하 용", Rarity = "Eternal", Zone = 8, Income = 157500000, Color = RGB(40, 50, 130) }, -- ★v6 ★v7 신화 ×150

	-- 9. 벚꽃 ★v8
	Ladybug = { Name = "무당벌레", Rarity = "Common", Zone = 9, Income = 750000, Color = RGB(235, 70, 70) }, -- ★v8
	HoneyBee = { Name = "꿀벌", Rarity = "Common", Zone = 9, Income = 900000, Color = RGB(255, 210, 60) }, -- ★v8
	Butterfly = { Name = "나비", Rarity = "Uncommon", Zone = 9, Income = 1.12e6, Color = RGB(255, 170, 220) }, -- ★v8
	PetalHamster = { Name = "꽃잎 햄스터", Rarity = "Rare", Zone = 9, Income = 1.65e6, Color = RGB(255, 200, 215) }, -- ★v8
	SakuraCat = { Name = "벚꽃 냥이", Rarity = "Epic", Zone = 9, Income = 2.4e6, Color = RGB(255, 185, 210) }, -- ★v8
	FlowerFairy = { Name = "꽃 요정", Rarity = "Legendary", Zone = 9, Income = 3.38e6, Color = RGB(190, 240, 170) }, -- ★v8
	SakuraSpirit = { Name = "벚꽃 정령", Rarity = "Mythic", Zone = 9, Income = 5.25e6, Color = RGB(255, 215, 235) }, -- ★v8
	ButterflyQueen = { Name = "나비 여왕", Rarity = "Secret", Zone = 9, Income = 9e6, Color = RGB(200, 150, 255) }, -- ★v8
	HoneyBear = { Name = "꿀단지 곰", Rarity = "Hidden", Zone = 9, Income = 1.3125e8, Color = RGB(240, 170, 70) }, -- ★v8 신화 ×25
	SakuraCrane = { Name = "벚꽃 두루미", Rarity = "Celestial", Zone = 9, Income = 3.15e8, Color = RGB(255, 235, 245) }, -- ★v8 신화 ×60
	BlossomDragon = { Name = "벚꽃 용", Rarity = "Eternal", Zone = 9, Income = 7.875e8, Color = RGB(255, 150, 200) }, -- ★v8 신화 ×150

	-- 10. 공룡 ★v8
	BabyDino = { Name = "아기 공룡", Rarity = "Common", Zone = 10, Income = 3.75e6, Color = RGB(130, 210, 110) }, -- ★v8
	Ptero = { Name = "아기 익룡", Rarity = "Common", Zone = 10, Income = 4.5e6, Color = RGB(240, 160, 110) }, -- ★v8
	Stego = { Name = "스테고", Rarity = "Uncommon", Zone = 10, Income = 5.62e6, Color = RGB(130, 190, 230) }, -- ★v8
	Tricera = { Name = "트리케라", Rarity = "Rare", Zone = 10, Income = 8.25e6, Color = RGB(250, 190, 90) }, -- ★v8
	Bronto = { Name = "브론토", Rarity = "Epic", Zone = 10, Income = 1.2e7, Color = RGB(170, 200, 140) }, -- ★v8
	Ankylo = { Name = "안킬로", Rarity = "Legendary", Zone = 10, Income = 1.69e7, Color = RGB(190, 150, 110) }, -- ★v8
	TRex = { Name = "꼬마 티렉스", Rarity = "Mythic", Zone = 10, Income = 2.62e7, Color = RGB(110, 180, 90) }, -- ★v8
	AmberRaptor = { Name = "호박 랩터", Rarity = "Secret", Zone = 10, Income = 4.5e7, Color = RGB(255, 180, 60) }, -- ★v8
	DinoPuppy = { Name = "공룡 옷 강아지", Rarity = "Hidden", Zone = 10, Income = 6.55e8, Color = RGB(120, 210, 120) }, -- ★v8 신화 ×25
	SkyPtera = { Name = "하늘 익룡", Rarity = "Celestial", Zone = 10, Income = 1.572e9, Color = RGB(255, 210, 120) }, -- ★v8 신화 ×60
	AncientDragon = { Name = "고대 용", Rarity = "Eternal", Zone = 10, Income = 3.93e9, Color = RGB(90, 150, 110) }, -- ★v8 신화 ×150

	-- 11. 보석 ★v8
	CaveBat = { Name = "동굴 박쥐", Rarity = "Common", Zone = 11, Income = 1.88e7, Color = RGB(150, 120, 200) }, -- ★v8
	Mole = { Name = "광부 두더지", Rarity = "Common", Zone = 11, Income = 2.25e7, Color = RGB(150, 110, 90) }, -- ★v8
	GemSnail = { Name = "보석 달팽이", Rarity = "Uncommon", Zone = 11, Income = 2.81e7, Color = RGB(150, 230, 255) }, -- ★v8
	GeodeTurtle = { Name = "정동 거북", Rarity = "Rare", Zone = 11, Income = 4.12e7, Color = RGB(170, 140, 230) }, -- ★v8
	RubyFox = { Name = "루비 여우", Rarity = "Epic", Zone = 11, Income = 6e7, Color = RGB(240, 60, 90) }, -- ★v8
	SapphireWolf = { Name = "사파이어 늑대", Rarity = "Legendary", Zone = 11, Income = 8.44e7, Color = RGB(70, 120, 240) }, -- ★v8
	AmethystOwl = { Name = "자수정 부엉이", Rarity = "Mythic", Zone = 11, Income = 1.31e8, Color = RGB(170, 100, 230) }, -- ★v8
	GemGolem = { Name = "보석 골렘", Rarity = "Secret", Zone = 11, Income = 2.25e8, Color = RGB(120, 230, 220) }, -- ★v8
	OpalBunny = { Name = "오팔 토끼", Rarity = "Hidden", Zone = 11, Income = 3.275e9, Color = RGB(230, 240, 255) }, -- ★v8 신화 ×25
	CrystalDeer = { Name = "크리스탈 사슴", Rarity = "Celestial", Zone = 11, Income = 7.86e9, Color = RGB(170, 230, 255) }, -- ★v8 신화 ×60
	DiamondDragon = { Name = "다이아몬드 용", Rarity = "Eternal", Zone = 11, Income = 1.965e10, Color = RGB(200, 240, 255) }, -- ★v8 신화 ×150

	-- 12. 사막 ★v8
	Fennec = { Name = "사막여우", Rarity = "Common", Zone = 12, Income = 9.38e7, Color = RGB(245, 205, 150) }, -- ★v8
	BabyCamel = { Name = "아기 낙타", Rarity = "Common", Zone = 12, Income = 1.12e8, Color = RGB(215, 170, 110) }, -- ★v8
	Meerkat = { Name = "미어캣", Rarity = "Uncommon", Zone = 12, Income = 1.41e8, Color = RGB(210, 175, 125) }, -- ★v8
	CactusPal = { Name = "선인장 친구", Rarity = "Rare", Zone = 12, Income = 2.06e8, Color = RGB(110, 190, 100) }, -- ★v8
	Armadillo = { Name = "아르마딜로", Rarity = "Epic", Zone = 12, Income = 3e8, Color = RGB(180, 150, 130) }, -- ★v8
	SphinxCat = { Name = "스핑크스 냥이", Rarity = "Legendary", Zone = 12, Income = 4.22e8, Color = RGB(240, 200, 120) }, -- ★v8
	PharaohPup = { Name = "파라오 강아지", Rarity = "Mythic", Zone = 12, Income = 6.56e8, Color = RGB(60, 60, 80) }, -- ★v8
	SandDragon = { Name = "모래 용", Rarity = "Secret", Zone = 12, Income = 1.12e9, Color = RGB(230, 190, 120) }, -- ★v8
	LampGenie = { Name = "램프 요정", Rarity = "Hidden", Zone = 12, Income = 1.64e10, Color = RGB(120, 170, 255) }, -- ★v8 신화 ×25
	SunScarab = { Name = "태양 풍뎅이", Rarity = "Celestial", Zone = 12, Income = 3.936e10, Color = RGB(60, 200, 180) }, -- ★v8 신화 ×60
	MirageDragon = { Name = "신기루 용", Rarity = "Eternal", Zone = 12, Income = 9.84e10, Color = RGB(255, 170, 110) }, -- ★v8 신화 ×150

	-- 13. 장난감 ★v8
	TeddyBear = { Name = "곰인형", Rarity = "Common", Zone = 13, Income = 4.69e8, Color = RGB(200, 140, 90) }, -- ★v8
	RubberDuck = { Name = "고무 오리", Rarity = "Common", Zone = 13, Income = 5.62e8, Color = RGB(255, 220, 60) }, -- ★v8
	WindUpMouse = { Name = "태엽 생쥐", Rarity = "Uncommon", Zone = 13, Income = 7.03e8, Color = RGB(190, 195, 210) }, -- ★v8
	BlockPuppy = { Name = "블록 강아지", Rarity = "Rare", Zone = 13, Income = 1.03e9, Color = RGB(90, 170, 255) }, -- ★v8
	BalloonDog = { Name = "풍선 강아지", Rarity = "Epic", Zone = 13, Income = 1.5e9, Color = RGB(255, 110, 160) }, -- ★v8
	RockingHorse = { Name = "흔들 목마", Rarity = "Legendary", Zone = 13, Income = 2.11e9, Color = RGB(240, 120, 90) }, -- ★v8
	MusicBoxCat = { Name = "오르골 냥이", Rarity = "Mythic", Zone = 13, Income = 3.28e9, Color = RGB(255, 200, 230) }, -- ★v8
	ToyKing = { Name = "장난감 왕", Rarity = "Secret", Zone = 13, Income = 5.62e9, Color = RGB(230, 60, 70) }, -- ★v8
	ClockworkFox = { Name = "태엽 여우", Rarity = "Hidden", Zone = 13, Income = 8.2e10, Color = RGB(230, 170, 80) }, -- ★v8 신화 ×25
	CarouselUnicorn = { Name = "회전목마 유니콘", Rarity = "Celestial", Zone = 13, Income = 1.968e11, Color = RGB(255, 230, 245) }, -- ★v8 신화 ×60
	MechaDragon = { Name = "메카 용", Rarity = "Eternal", Zone = 13, Income = 4.92e11, Color = RGB(120, 160, 220) }, -- ★v8 신화 ×150

	-- 14. 꿈나라 ★v8
	SleepySheep = { Name = "졸린 양", Rarity = "Common", Zone = 14, Income = 2.34e9, Color = RGB(240, 235, 255) }, -- ★v8
	SnoozeHamster = { Name = "잠꾸러기 햄스터", Rarity = "Common", Zone = 14, Income = 2.81e9, Color = RGB(230, 200, 170) }, -- ★v8
	PillowCat = { Name = "베개 냥이", Rarity = "Uncommon", Zone = 14, Income = 3.52e9, Color = RGB(200, 205, 255) }, -- ★v8
	Firefly = { Name = "반딧불이", Rarity = "Rare", Zone = 14, Income = 5.16e9, Color = RGB(200, 255, 120) }, -- ★v8
	MoonBear = { Name = "달곰", Rarity = "Epic", Zone = 14, Income = 7.5e9, Color = RGB(90, 90, 140) }, -- ★v8
	Baku = { Name = "꿈먹는 맥", Rarity = "Legendary", Zone = 14, Income = 1.05e10, Color = RGB(180, 160, 230) }, -- ★v8
	SandmanPup = { Name = "꿈 요정 강아지", Rarity = "Mythic", Zone = 14, Income = 1.64e10, Color = RGB(150, 170, 255) }, -- ★v8
	StarlightLion = { Name = "별빛 사자", Rarity = "Secret", Zone = 14, Income = 2.81e10, Color = RGB(255, 230, 150) }, -- ★v8
	SnoozePanda = { Name = "낮잠 판다", Rarity = "Hidden", Zone = 14, Income = 4.1e11, Color = RGB(245, 245, 255) }, -- ★v8 신화 ×25
	CrescentFox = { Name = "초승달 여우", Rarity = "Celestial", Zone = 14, Income = 9.84e11, Color = RGB(255, 240, 180) }, -- ★v8 신화 ×60
	DreamDragon = { Name = "꿈의 용", Rarity = "Eternal", Zone = 14, Income = 2.46e12, Color = RGB(160, 140, 255) }, -- ★v8 신화 ×150

	-- 15. 화산 ★v8
	MagmaSlime = { Name = "용암 슬라임", Rarity = "Common", Zone = 15, Income = 1.17e10, Color = RGB(255, 120, 50) }, -- ★v8
	Salamander = { Name = "불도롱뇽", Rarity = "Common", Zone = 15, Income = 1.41e10, Color = RGB(255, 90, 70) }, -- ★v8
	EmberPup = { Name = "불씨 강아지", Rarity = "Uncommon", Zone = 15, Income = 1.76e10, Color = RGB(90, 80, 85) }, -- ★v8
	FlameFox = { Name = "불꽃 여우", Rarity = "Rare", Zone = 15, Income = 2.58e10, Color = RGB(255, 110, 40) }, -- ★v8
	LavaTurtle = { Name = "용암 거북", Rarity = "Epic", Zone = 15, Income = 3.75e10, Color = RGB(110, 90, 90) }, -- ★v8
	MagmaRhino = { Name = "마그마 코뿔소", Rarity = "Legendary", Zone = 15, Income = 5.27e10, Color = RGB(120, 100, 105) }, -- ★v8
	FlameLion = { Name = "불꽃 사자", Rarity = "Mythic", Zone = 15, Income = 8.2e10, Color = RGB(255, 150, 60) }, -- ★v8
	Haetae = { Name = "불꽃 해태", Rarity = "Secret", Zone = 15, Income = 1.41e11, Color = RGB(255, 200, 90) }, -- ★v8
	CinderCat = { Name = "불씨 냥이", Rarity = "Hidden", Zone = 15, Income = 2.05e12, Color = RGB(70, 60, 70) }, -- ★v8 신화 ×25
	MagmaWyvern = { Name = "마그마 와이번", Rarity = "Celestial", Zone = 15, Income = 4.92e12, Color = RGB(230, 80, 50) }, -- ★v8 신화 ×60
	InfernoDragon = { Name = "불꽃 용", Rarity = "Eternal", Zone = 15, Income = 1.23e13, Color = RGB(255, 90, 40) }, -- ★v8 신화 ×150

	-- 16. 황금 ★v8
	CoinPig = { Name = "동전 돼지", Rarity = "Common", Zone = 16, Income = 5.86e10, Color = RGB(255, 190, 200) }, -- ★v8
	GoldHamster = { Name = "금빛 햄스터", Rarity = "Common", Zone = 16, Income = 7.03e10, Color = RGB(255, 215, 110) }, -- ★v8
	RoyalCorgi = { Name = "왕실 코기", Rarity = "Uncommon", Zone = 16, Income = 8.79e10, Color = RGB(245, 175, 95) }, -- ★v8
	CrownFrog = { Name = "왕관 개구리", Rarity = "Rare", Zone = 16, Income = 1.29e11, Color = RGB(120, 210, 110) }, -- ★v8
	KnightCat = { Name = "기사 냥이", Rarity = "Epic", Zone = 16, Income = 1.88e11, Color = RGB(200, 205, 220) }, -- ★v8
	RoyalLion = { Name = "왕실 사자", Rarity = "Legendary", Zone = 16, Income = 2.64e11, Color = RGB(250, 200, 100) }, -- ★v8
	GoldenPegasus = { Name = "황금 페가수스", Rarity = "Mythic", Zone = 16, Income = 4.1e11, Color = RGB(255, 220, 120) }, -- ★v8
	KingPenguin = { Name = "임금 펭귄", Rarity = "Secret", Zone = 16, Income = 7.03e11, Color = RGB(60, 70, 110) }, -- ★v8
	TreasureMimic = { Name = "보물상자 친구", Rarity = "Hidden", Zone = 16, Income = 1.025e13, Color = RGB(190, 120, 60) }, -- ★v8 신화 ×25
	CrownGriffin = { Name = "왕관 그리핀", Rarity = "Celestial", Zone = 16, Income = 2.46e13, Color = RGB(255, 215, 90) }, -- ★v8 신화 ×60
	EmperorDragon = { Name = "황제 용", Rarity = "Eternal", Zone = 16, Income = 6.15e13, Color = RGB(255, 200, 60) }, -- ★v8 신화 ×150
}

-- Boost (데리고 다닐 때 들판 코인 보너스, 0.1 = +10%) = 희귀도 Boost × (1 + 0.15 × (지역 - 1))
for _, def in Config.Pets do
	if def.Boost == nil then
		local base = Config.Rarities[def.Rarity].Boost
		def.Boost = math.floor(base * (1 + 0.15 * (def.Zone - 1)) * 1000 + 0.5) / 1000
	end
end

-- 도감/UI 표시 순서 (지역 순, 지역 안에서는 희귀도 순)
Config.PetOrder = {
	"Chick", "Bunny", "Hamster", "Piglet", "Puppy", "Cat", "Owl", "Fox", "RainbowCat", "SpiritDeer", "CloverFox", "BlossomFawn", "WorldTreeDragon",
	"Duck", "Frog", "Hedgehog", "Squirrel", "Raccoon", "Turtle", "Axolotl", "MoonKoi", "PearlOtter", "MoonSwan", "RainbowKoiDragon",
	"Monkey", "Parrot", "Koala", "Bear", "Lion", "Panda", "Peacock", "WhiteTiger", "RainbowChameleon", "GoldenJaguar", "EmeraldDragon",
	"Penguin", "Seal", "SnowBunny", "Snowman", "PolarBear", "Reindeer", "FrostFox", "Yeti", "CrystalPenguin", "AuroraWolf", "IcePhoenix",
	"Crab", "Jellyfish", "Octopus", "BabyShark", "Dolphin", "Narwhal", "MermaidCat", "DragonKing", "RainbowJelly", "PearlSeahorse", "BabyKraken",
	"CottonSheep", "DonutPuppy", "JellyBear", "CupcakeCat", "MacaronBunny", "GummyDragon", "CandyUnicorn", "CookieKing", "LollipopPanda", "MarshmallowBear", "SweetQueenCat",
	"Sheep", "CloudPuppy", "BabyCloud", "Dragon", "Unicorn", "Pegasus", "Phoenix", "AngelBunny", "ThunderPup", "SunGriffin", "NineTailFox",
	"Alien", "RobotPuppy", "MoonBunny", "SpaceCat", "AstroBear", "CometFox", "StarSlime", "CosmicWhale", "MeteorHamster", "GalaxyUnicorn", "CosmoDragon",
	"Ladybug", "HoneyBee", "Butterfly", "PetalHamster", "SakuraCat", "FlowerFairy", "SakuraSpirit", "ButterflyQueen", "HoneyBear", "SakuraCrane", "BlossomDragon",
	"BabyDino", "Ptero", "Stego", "Tricera", "Bronto", "Ankylo", "TRex", "AmberRaptor", "DinoPuppy", "SkyPtera", "AncientDragon",
	"CaveBat", "Mole", "GemSnail", "GeodeTurtle", "RubyFox", "SapphireWolf", "AmethystOwl", "GemGolem", "OpalBunny", "CrystalDeer", "DiamondDragon",
	"Fennec", "BabyCamel", "Meerkat", "CactusPal", "Armadillo", "SphinxCat", "PharaohPup", "SandDragon", "LampGenie", "SunScarab", "MirageDragon",
	"TeddyBear", "RubberDuck", "WindUpMouse", "BlockPuppy", "BalloonDog", "RockingHorse", "MusicBoxCat", "ToyKing", "ClockworkFox", "CarouselUnicorn", "MechaDragon",
	"SleepySheep", "SnoozeHamster", "PillowCat", "Firefly", "MoonBear", "Baku", "SandmanPup", "StarlightLion", "SnoozePanda", "CrescentFox", "DreamDragon",
	"MagmaSlime", "Salamander", "EmberPup", "FlameFox", "LavaTurtle", "MagmaRhino", "FlameLion", "Haetae", "CinderCat", "MagmaWyvern", "InfernoDragon",
	"CoinPig", "GoldHamster", "RoyalCorgi", "CrownFrog", "KnightCat", "RoyalLion", "GoldenPegasus", "KingPenguin", "TreasureMimic", "CrownGriffin", "EmperorDragon",
}

----------------------------------------------------------------------
-- 알. v4: 지역마다 5개 (숲 마을은 6개) 의 "사다리": 싼 알은 늘 나오고, 비싸고 반짝이는 알은 가끔 나와요.
-- SpawnWeight = 그 지역 컨베이어 안에서 나오는 비율 (약 40 → 24 → 11 → 5 → 2). HatchTime = 부화까지 초 (환생하면 빨라짐).
-- Pets = 부화 확률 가중치 (합 100 → %로 읽으면 돼요). 사다리를 올라갈수록 그 지역의 더 좋은 펫 쪽으로 밀려요.
-- 비밀 펫은 자기 지역의 맨 위 알 2개에서만 (우주 고래는 별빛 알에서만 0.25%).
-- Look = 손으로 만든 모델이 없는 새 알의 모양 (PetModels/EggsPattern.luau 가 읽어요):
--   { Base, Accent, Accent2?, Pattern = "Plain"|"Spots"|"Stripes"|"Zigzag"|"Stars"|"Hearts"|"Dots"|"Swirl"|"Gems"|"Crown"|
--     "Flames"|"Leaves"|"Bubbles"|"Snow"|"Candy"|"Planets", Shine?, Glow? }
-- 아래에서 자동으로 채워요: MinRebirth (= 지역 MinRebirth), Rung (지역 안 사다리 칸, 1 = 제일 싼 알),
-- Rungs (그 지역 알 수), Premium (위 2칸 = 좋은 알: 큰 간판·반짝임·알림·빛기둥). ★ v4 = 새 알
-- 가격·확률은 scratchpad 의 v4/sim4.py (eggs4.py) 로 맞췄어요.
-- ★v6 맨 아래 24개 = 아주 희귀한 알 (Special = "Hidden" | "Celestial" | "Eternal", 지역마다 3개). 사다리 밖이라
-- SpawnWeight = 0, Rung = 0, Premium = false. 벨트에 따로 굴려서 나와요 (Config.SpecialEggs, v6/sim6.py 로 맞춤).
-- ★v7 펫 수익이 세져서 가격도 올렸어요 (v7/sim7.py: 시크릿 ×1.5 (숲 마을은 그대로) · 천상 ×1.5 · 이터널 ×1.2 쯤).
----------------------------------------------------------------------
Config.Eggs = {
	-- 1. 숲 마을
	Basic = {
		Name = "기본 알", Rarity = "Common", Zone = 1, Price = 50, HatchTime = 8, SpawnWeight = 40,
		Pets = { Chick = 17, Bunny = 17, Hamster = 16, Piglet = 16, Puppy = 27, Cat = 7 },
	},
	Flower = { -- ★ v4
		Name = "꽃 알", Rarity = "Uncommon", Zone = 1, Price = 150, HatchTime = 10, SpawnWeight = 24,
		Pets = { Chick = 7, Bunny = 7, Hamster = 9, Piglet = 9, Puppy = 32, Cat = 26, Owl = 8, Fox = 2 },
		Look = { Base = RGB(255, 222, 236), Accent = RGB(255, 125, 175), Accent2 = RGB(255, 228, 95), Pattern = "Dots" },
	},
	Mushroom = { -- ★ v4
		Name = "버섯 알", Rarity = "Rare", Zone = 1, Price = 500, HatchTime = 14, SpawnWeight = 12,
		Pets = { Hamster = 4, Piglet = 4, Puppy = 22, Cat = 34, Owl = 26, Fox = 9, RainbowCat = 1 },
		Look = { Base = RGB(240, 95, 95), Accent = RGB(255, 250, 242), Accent2 = RGB(255, 225, 200), Pattern = "Spots" },
	},
	Forest = {
		Name = "숲속 알", Rarity = "Epic", Zone = 1, Price = 1500, HatchTime = 20, SpawnWeight = 6,
		Pets = { Puppy = 10, Cat = 28, Owl = 34, Fox = 22, RainbowCat = 6 },
	},
	Fairy = { -- ★ v4
		Name = "요정 알", Rarity = "Legendary", Zone = 1, Price = 5000, HatchTime = 28, SpawnWeight = 3,
		Pets = { Cat = 14, Owl = 34, Fox = 34, RainbowCat = 17.5, SpiritDeer = 0.5 },
		Look = { Base = RGB(215, 192, 255), Accent = RGB(165, 245, 215), Accent2 = RGB(255, 225, 120), Pattern = "Stars", Shine = true },
	},
	Spirit = { -- ★ v4
		Name = "정령 알", Rarity = "Mythic", Zone = 1, Price = 15000, HatchTime = 36, SpawnWeight = 1.5,
		Pets = { Owl = 23, Fox = 42, RainbowCat = 33, SpiritDeer = 2 },
		Look = { Base = RGB(205, 255, 228), Accent = RGB(110, 230, 160), Accent2 = RGB(255, 232, 140), Pattern = "Leaves", Shine = true, Glow = true },
	},
	-- 2. 호수
	Lake = {
		Name = "호수 알", Rarity = "Common", Zone = 2, Price = 2000, HatchTime = 12, SpawnWeight = 40,
		Pets = { Duck = 35, Frog = 31, Hedgehog = 28, Squirrel = 6 },
	},
	Lily = { -- ★ v4
		Name = "연꽃 알", Rarity = "Rare", Zone = 2, Price = 6000, HatchTime = 16, SpawnWeight = 24,
		Pets = { Duck = 12, Frog = 12, Hedgehog = 32, Squirrel = 28, Raccoon = 13, Turtle = 3 },
		Look = { Base = RGB(195, 235, 175), Accent = RGB(255, 165, 205), Accent2 = RGB(255, 240, 150), Pattern = "Leaves" },
	},
	Bubble = { -- ★ v4
		Name = "물방울 알", Rarity = "Epic", Zone = 2, Price = 20000, HatchTime = 22, SpawnWeight = 11,
		Pets = { Hedgehog = 16, Squirrel = 34, Raccoon = 32, Turtle = 15, Axolotl = 3 },
		Look = { Base = RGB(150, 215, 250), Accent = RGB(240, 250, 255), Accent2 = RGB(100, 185, 245), Pattern = "Bubbles" },
	},
	Moonlight = { -- ★ v4
		Name = "달빛 알", Rarity = "Legendary", Zone = 2, Price = 40000, HatchTime = 29, SpawnWeight = 5,
		Pets = { Squirrel = 16, Raccoon = 36, Turtle = 32, Axolotl = 15.7, MoonKoi = 0.3 },
		Look = { Base = RGB(60, 80, 165), Accent = RGB(255, 244, 185), Accent2 = RGB(215, 228, 255), Pattern = "Stars", Shine = true },
	},
	Crystal = {
		Name = "크리스탈 알", Rarity = "Mythic", Zone = 2, Price = 100000, HatchTime = 36, SpawnWeight = 2,
		Pets = { Raccoon = 24, Turtle = 42, Axolotl = 33, MoonKoi = 1 },
	},
	-- 3. 정글
	Jungle = {
		Name = "정글 알", Rarity = "Common", Zone = 3, Price = 24000, HatchTime = 15, SpawnWeight = 40,
		Pets = { Monkey = 35, Parrot = 31, Koala = 28, Bear = 6 },
	},
	Leaf = { -- ★ v4
		Name = "나뭇잎 알", Rarity = "Rare", Zone = 3, Price = 75000, HatchTime = 20, SpawnWeight = 24,
		Pets = { Monkey = 12, Parrot = 12, Koala = 32, Bear = 28, Lion = 13, Panda = 3 },
		Look = { Base = RGB(175, 228, 115), Accent = RGB(55, 145, 70), Accent2 = RGB(255, 210, 70), Pattern = "Leaves" },
	},
	Spotted = {
		Name = "점박이 알", Rarity = "Epic", Zone = 3, Price = 200000, HatchTime = 27, SpawnWeight = 11,
		Pets = { Koala = 16, Bear = 34, Lion = 32, Panda = 15, Peacock = 3 },
	},
	Tropical = { -- ★ v4
		Name = "열대 알", Rarity = "Legendary", Zone = 3, Price = 500000, HatchTime = 36, SpawnWeight = 5,
		Pets = { Bear = 16, Lion = 36, Panda = 32, Peacock = 15.7, WhiteTiger = 0.3 },
		Look = { Base = RGB(255, 175, 75), Accent = RGB(255, 85, 160), Accent2 = RGB(85, 200, 110), Pattern = "Zigzag", Shine = true },
	},
	Tiger = { -- ★ v4
		Name = "호랑이 알", Rarity = "Mythic", Zone = 3, Price = 1200000, HatchTime = 45, SpawnWeight = 2,
		Pets = { Lion = 24, Panda = 42, Peacock = 33, WhiteTiger = 1 },
		Look = { Base = RGB(246, 248, 255), Accent = RGB(80, 100, 145), Accent2 = RGB(140, 215, 255), Pattern = "Stripes", Shine = true, Glow = true },
	},
	-- 4. 겨울 산
	Snow = {
		Name = "겨울 알", Rarity = "Common", Zone = 4, Price = 300000, HatchTime = 18, SpawnWeight = 40,
		Pets = { Penguin = 35, Seal = 31, SnowBunny = 28, Snowman = 6 },
	},
	Ice = { -- ★ v4
		Name = "얼음 알", Rarity = "Rare", Zone = 4, Price = 1000000, HatchTime = 24, SpawnWeight = 24,
		Pets = { Penguin = 12, Seal = 12, SnowBunny = 32, Snowman = 28, PolarBear = 13, Reindeer = 3 },
		Look = { Base = RGB(185, 228, 255), Accent = RGB(240, 250, 255), Accent2 = RGB(120, 190, 245), Pattern = "Zigzag" },
	},
	Snowflake = { -- ★ v4
		Name = "눈꽃 알", Rarity = "Epic", Zone = 4, Price = 2500000, HatchTime = 32, SpawnWeight = 11,
		Pets = { SnowBunny = 16, Snowman = 34, PolarBear = 32, Reindeer = 15, FrostFox = 3 },
		Look = { Base = RGB(236, 245, 255), Accent = RGB(105, 175, 245), Accent2 = RGB(255, 255, 255), Pattern = "Snow" },
	},
	Aurora = { -- ★ v4
		Name = "오로라 알", Rarity = "Legendary", Zone = 4, Price = 6000000, HatchTime = 43, SpawnWeight = 5,
		Pets = { Snowman = 16, PolarBear = 36, Reindeer = 32, FrostFox = 15.7, Yeti = 0.3 },
		Look = { Base = RGB(40, 70, 115), Accent = RGB(120, 255, 190), Accent2 = RGB(200, 140, 255), Pattern = "Swirl", Shine = true },
	},
	Twilight = {
		Name = "황혼 알", Rarity = "Mythic", Zone = 4, Price = 15000000, HatchTime = 54, SpawnWeight = 2,
		Pets = { PolarBear = 24, Reindeer = 42, FrostFox = 33, Yeti = 1 },
	},
	-- 5. 바다
	Ocean = {
		Name = "바다 알", Rarity = "Common", Zone = 5, Price = 3000000, HatchTime = 22, SpawnWeight = 40,
		Pets = { Crab = 35, Jellyfish = 31, Octopus = 28, BabyShark = 6 },
	},
	Shell = { -- ★ v4
		Name = "조개 알", Rarity = "Rare", Zone = 5, Price = 10000000, HatchTime = 30, SpawnWeight = 24,
		Pets = { Crab = 12, Jellyfish = 12, Octopus = 32, BabyShark = 28, Dolphin = 13, Narwhal = 3 },
		Look = { Base = RGB(255, 218, 192), Accent = RGB(255, 140, 120), Accent2 = RGB(255, 245, 225), Pattern = "Stripes" },
	},
	Coral = { -- ★ v4
		Name = "산호 알", Rarity = "Epic", Zone = 5, Price = 25000000, HatchTime = 40, SpawnWeight = 11,
		Pets = { Octopus = 16, BabyShark = 34, Dolphin = 32, Narwhal = 15, MermaidCat = 3 },
		Look = { Base = RGB(255, 132, 145), Accent = RGB(255, 195, 105), Accent2 = RGB(255, 240, 220), Pattern = "Spots" },
	},
	Pearl = {
		Name = "진주 알", Rarity = "Legendary", Zone = 5, Price = 60000000, HatchTime = 53, SpawnWeight = 5,
		Pets = { BabyShark = 16, Dolphin = 36, Narwhal = 32, MermaidCat = 15.7, DragonKing = 0.3 },
	},
	DragonPalace = { -- ★ v4
		Name = "용궁 알", Rarity = "Mythic", Zone = 5, Price = 150000000, HatchTime = 66, SpawnWeight = 2,
		Pets = { Dolphin = 24, Narwhal = 42, MermaidCat = 33, DragonKing = 1 },
		Look = { Base = RGB(60, 190, 170), Accent = RGB(255, 210, 80), Accent2 = RGB(250, 248, 240), Pattern = "Crown", Shine = true, Glow = true },
	},
	-- 6. 캔디 랜드
	Candy = {
		Name = "캔디 알", Rarity = "Common", Zone = 6, Price = 30000000, HatchTime = 26, SpawnWeight = 40,
		Pets = { CottonSheep = 35, DonutPuppy = 31, JellyBear = 28, CupcakeCat = 6 },
	},
	Jelly = { -- ★ v4
		Name = "젤리 알", Rarity = "Rare", Zone = 6, Price = 100000000, HatchTime = 35, SpawnWeight = 24,
		Pets = { CottonSheep = 12, DonutPuppy = 12, JellyBear = 32, CupcakeCat = 28, MacaronBunny = 13, GummyDragon = 3 },
		Look = { Base = RGB(255, 120, 150), Accent = RGB(255, 205, 222), Accent2 = RGB(255, 255, 255), Pattern = "Hearts" },
	},
	Lollipop = { -- ★ v4
		Name = "막대사탕 알", Rarity = "Epic", Zone = 6, Price = 250000000, HatchTime = 47, SpawnWeight = 11,
		Pets = { JellyBear = 16, CupcakeCat = 34, MacaronBunny = 32, GummyDragon = 15, CandyUnicorn = 3 },
		Look = { Base = RGB(255, 252, 252), Accent = RGB(255, 90, 140), Accent2 = RGB(150, 230, 200), Pattern = "Swirl" },
	},
	Cake = { -- ★ v4
		Name = "케이크 알", Rarity = "Legendary", Zone = 6, Price = 600000000, HatchTime = 62, SpawnWeight = 5,
		Pets = { CupcakeCat = 16, MacaronBunny = 36, GummyDragon = 32, CandyUnicorn = 15.7, CookieKing = 0.3 },
		Look = { Base = RGB(255, 240, 222), Accent = RGB(255, 130, 170), Accent2 = RGB(140, 85, 55), Pattern = "Candy", Shine = true },
	},
	Rainbow = {
		Name = "무지개 알", Rarity = "Mythic", Zone = 6, Price = 1.5e9, HatchTime = 78, SpawnWeight = 2,
		Pets = { MacaronBunny = 24, GummyDragon = 42, CandyUnicorn = 33, CookieKing = 1 },
	},
	-- 7. 구름 왕국
	Cloud = {
		Name = "구름 알", Rarity = "Common", Zone = 7, Price = 300000000, HatchTime = 30, SpawnWeight = 40,
		Pets = { Sheep = 35, CloudPuppy = 31, BabyCloud = 28, Dragon = 6 },
	},
	Breeze = { -- ★ v4
		Name = "바람 알", Rarity = "Rare", Zone = 7, Price = 1e9, HatchTime = 40, SpawnWeight = 24,
		Pets = { Sheep = 12, CloudPuppy = 12, BabyCloud = 32, Dragon = 28, Unicorn = 13, Pegasus = 3 },
		Look = { Base = RGB(190, 225, 255), Accent = RGB(255, 255, 255), Accent2 = RGB(200, 170, 255), Pattern = "Swirl" },
	},
	Feather = { -- ★ v4
		Name = "깃털 알", Rarity = "Epic", Zone = 7, Price = 2.5e9, HatchTime = 54, SpawnWeight = 11,
		Pets = { BabyCloud = 16, Dragon = 34, Unicorn = 32, Pegasus = 15, Phoenix = 3 },
		Look = { Base = RGB(250, 248, 255), Accent = RGB(200, 170, 255), Accent2 = RGB(255, 210, 90), Pattern = "Leaves" },
	},
	Angel = { -- ★ v4
		Name = "천사 알", Rarity = "Legendary", Zone = 7, Price = 6e9, HatchTime = 72, SpawnWeight = 5,
		Pets = { Dragon = 16, Unicorn = 36, Pegasus = 32, Phoenix = 15.7, AngelBunny = 0.3 },
		Look = { Base = RGB(255, 248, 228), Accent = RGB(255, 205, 85), Accent2 = RGB(255, 255, 255), Pattern = "Hearts", Shine = true },
	},
	Golden = {
		Name = "황금 알", Rarity = "Mythic", Zone = 7, Price = 1.5e10, HatchTime = 90, SpawnWeight = 2,
		Pets = { Unicorn = 24, Pegasus = 42, Phoenix = 33, AngelBunny = 1 },
	},
	-- 8. 우주
	Space = {
		Name = "우주 알", Rarity = "Common", Zone = 8, Price = 3e9, HatchTime = 35, SpawnWeight = 40,
		Pets = { Alien = 35, RobotPuppy = 31, MoonBunny = 28, SpaceCat = 6 },
	},
	Moon = { -- ★ v4
		Name = "달 알", Rarity = "Rare", Zone = 8, Price = 1e10, HatchTime = 47, SpawnWeight = 24,
		Pets = { Alien = 12, RobotPuppy = 12, MoonBunny = 32, SpaceCat = 28, AstroBear = 13, CometFox = 3 },
		Look = { Base = RGB(236, 232, 205), Accent = RGB(165, 160, 155), Accent2 = RGB(255, 250, 220), Pattern = "Spots" },
	},
	Planet = { -- ★ v4
		Name = "행성 알", Rarity = "Epic", Zone = 8, Price = 2.5e10, HatchTime = 63, SpawnWeight = 11,
		Pets = { MoonBunny = 16, SpaceCat = 34, AstroBear = 32, CometFox = 15, StarSlime = 3 },
		Look = { Base = RGB(130, 90, 200), Accent = RGB(255, 170, 110), Accent2 = RGB(120, 240, 255), Pattern = "Planets" },
	},
	Comet = { -- ★ v4
		Name = "혜성 알", Rarity = "Legendary", Zone = 8, Price = 6e10, HatchTime = 84, SpawnWeight = 5,
		Pets = { SpaceCat = 16, AstroBear = 36, CometFox = 32, StarSlime = 16 },
		Look = { Base = RGB(40, 50, 120), Accent = RGB(120, 240, 255), Accent2 = RGB(255, 255, 255), Pattern = "Flames", Shine = true },
	},
	Starlight = {
		Name = "별빛 알", Rarity = "Mythic", Zone = 8, Price = 1.5e11, HatchTime = 105, SpawnWeight = 2,
		Pets = { AstroBear = 24, CometFox = 42, StarSlime = 33.75, CosmicWhale = 0.25 },
	},
	-- 9. 벚꽃 ★v8
	Sakura = { -- ★v8
		Name = "벚꽃 알", Rarity = "Common", Zone = 9, Price = 2e10, HatchTime = 40, SpawnWeight = 40,
		Pets = { Ladybug = 35, HoneyBee = 31, Butterfly = 28, PetalHamster = 6 },
		Look = { Base = RGB(255, 225, 235), Accent = RGB(255, 140, 185), Accent2 = RGB(255, 250, 250), Pattern = "Dots" },
	},
	Tulip = { -- ★v8
		Name = "튤립 알", Rarity = "Rare", Zone = 9, Price = 6e10, HatchTime = 54, SpawnWeight = 24,
		Pets = { Ladybug = 12, HoneyBee = 12, Butterfly = 32, PetalHamster = 28, SakuraCat = 13, FlowerFairy = 3 },
		Look = { Base = RGB(255, 245, 210), Accent = RGB(255, 100, 120), Accent2 = RGB(120, 200, 100), Pattern = "Hearts" },
	},
	HoneyPot = { -- ★v8
		Name = "꿀단지 알", Rarity = "Epic", Zone = 9, Price = 1.5e11, HatchTime = 72, SpawnWeight = 11,
		Pets = { Butterfly = 16, PetalHamster = 34, SakuraCat = 32, FlowerFairy = 15, SakuraSpirit = 3 },
		Look = { Base = RGB(255, 205, 80), Accent = RGB(200, 120, 40), Accent2 = RGB(255, 245, 200), Pattern = "Zigzag" },
	},
	Bloom = { -- ★v8
		Name = "만개 알", Rarity = "Legendary", Zone = 9, Price = 4e11, HatchTime = 96, SpawnWeight = 5,
		Pets = { PetalHamster = 16, SakuraCat = 36, FlowerFairy = 32, SakuraSpirit = 15.7, ButterflyQueen = 0.3 },
		Look = { Base = RGB(250, 210, 255), Accent = RGB(255, 120, 190), Accent2 = RGB(130, 220, 140), Pattern = "Leaves", Shine = true },
	},
	SpringQueen = { -- ★v8
		Name = "봄의 여왕 알", Rarity = "Mythic", Zone = 9, Price = 1e12, HatchTime = 120, SpawnWeight = 2,
		Pets = { SakuraCat = 24, FlowerFairy = 42, SakuraSpirit = 33, ButterflyQueen = 1 },
		Look = { Base = RGB(255, 240, 248), Accent = RGB(255, 120, 180), Accent2 = RGB(255, 215, 90), Pattern = "Crown", Shine = true, Glow = true },
	},
	-- 10. 공룡 ★v8
	Dino = { -- ★v8
		Name = "공룡 알", Rarity = "Common", Zone = 10, Price = 1.2e11, HatchTime = 45, SpawnWeight = 40,
		Pets = { BabyDino = 35, Ptero = 31, Stego = 28, Tricera = 6 },
		Look = { Base = RGB(205, 235, 175), Accent = RGB(90, 160, 80), Accent2 = RGB(250, 245, 220), Pattern = "Spots" },
	},
	Fern = { -- ★v8
		Name = "고사리 알", Rarity = "Rare", Zone = 10, Price = 4e11, HatchTime = 61, SpawnWeight = 24,
		Pets = { BabyDino = 12, Ptero = 12, Stego = 32, Tricera = 28, Bronto = 13, Ankylo = 3 },
		Look = { Base = RGB(170, 220, 140), Accent = RGB(60, 140, 70), Accent2 = RGB(230, 210, 150), Pattern = "Leaves" },
	},
	Fossil = { -- ★v8
		Name = "화석 알", Rarity = "Epic", Zone = 10, Price = 1e12, HatchTime = 81, SpawnWeight = 11,
		Pets = { Stego = 16, Tricera = 34, Bronto = 32, Ankylo = 15, TRex = 3 },
		Look = { Base = RGB(230, 215, 190), Accent = RGB(150, 120, 90), Accent2 = RGB(255, 250, 235), Pattern = "Swirl" },
	},
	Amber = { -- ★v8
		Name = "호박 알", Rarity = "Legendary", Zone = 10, Price = 2.5e12, HatchTime = 108, SpawnWeight = 5,
		Pets = { Tricera = 16, Bronto = 36, Ankylo = 32, TRex = 15.7, AmberRaptor = 0.3 },
		Look = { Base = RGB(255, 185, 70), Accent = RGB(200, 110, 30), Accent2 = RGB(255, 240, 180), Pattern = "Gems", Shine = true },
	},
	Jurassic = { -- ★v8
		Name = "쥬라기 알", Rarity = "Mythic", Zone = 10, Price = 6e12, HatchTime = 135, SpawnWeight = 2,
		Pets = { Bronto = 24, Ankylo = 42, TRex = 33, AmberRaptor = 1 },
		Look = { Base = RGB(90, 140, 80), Accent = RGB(255, 140, 60), Accent2 = RGB(250, 230, 150), Pattern = "Zigzag", Shine = true, Glow = true },
	},
	-- 11. 보석 ★v8
	Cave = { -- ★v8
		Name = "동굴 알", Rarity = "Common", Zone = 11, Price = 7.5e11, HatchTime = 50, SpawnWeight = 40,
		Pets = { CaveBat = 35, Mole = 31, GemSnail = 28, GeodeTurtle = 6 },
		Look = { Base = RGB(120, 110, 140), Accent = RGB(180, 160, 230), Accent2 = RGB(230, 225, 245), Pattern = "Spots" },
	},
	Ruby = { -- ★v8
		Name = "루비 알", Rarity = "Rare", Zone = 11, Price = 2.5e12, HatchTime = 67, SpawnWeight = 24,
		Pets = { CaveBat = 12, Mole = 12, GemSnail = 32, GeodeTurtle = 28, RubyFox = 13, SapphireWolf = 3 },
		Look = { Base = RGB(255, 120, 140), Accent = RGB(200, 30, 70), Accent2 = RGB(255, 230, 235), Pattern = "Gems" },
	},
	Sapphire = { -- ★v8
		Name = "사파이어 알", Rarity = "Epic", Zone = 11, Price = 6e12, HatchTime = 90, SpawnWeight = 11,
		Pets = { GemSnail = 16, GeodeTurtle = 34, RubyFox = 32, SapphireWolf = 15, AmethystOwl = 3 },
		Look = { Base = RGB(120, 160, 255), Accent = RGB(40, 70, 200), Accent2 = RGB(220, 235, 255), Pattern = "Gems" },
	},
	Amethyst = { -- ★v8
		Name = "자수정 알", Rarity = "Legendary", Zone = 11, Price = 1.5e13, HatchTime = 120, SpawnWeight = 5,
		Pets = { GeodeTurtle = 16, RubyFox = 36, SapphireWolf = 32, AmethystOwl = 15.7, GemGolem = 0.3 },
		Look = { Base = RGB(190, 140, 245), Accent = RGB(120, 60, 190), Accent2 = RGB(245, 230, 255), Pattern = "Stars", Shine = true },
	},
	DiamondEgg = { -- ★v8
		Name = "다이아몬드 알", Rarity = "Mythic", Zone = 11, Price = 4e13, HatchTime = 150, SpawnWeight = 2,
		Pets = { RubyFox = 24, SapphireWolf = 42, AmethystOwl = 33, GemGolem = 1 },
		Look = { Base = RGB(230, 248, 255), Accent = RGB(130, 220, 255), Accent2 = RGB(255, 255, 255), Pattern = "Gems", Shine = true, Glow = true },
	},
	-- 12. 사막 ★v8
	Sand = { -- ★v8
		Name = "모래 알", Rarity = "Common", Zone = 12, Price = 4e12, HatchTime = 55, SpawnWeight = 40,
		Pets = { Fennec = 35, BabyCamel = 31, Meerkat = 28, CactusPal = 6 },
		Look = { Base = RGB(245, 225, 170), Accent = RGB(210, 170, 100), Accent2 = RGB(255, 245, 220), Pattern = "Dots" },
	},
	Oasis = { -- ★v8
		Name = "오아시스 알", Rarity = "Rare", Zone = 12, Price = 1.5e13, HatchTime = 74, SpawnWeight = 24,
		Pets = { Fennec = 12, BabyCamel = 12, Meerkat = 32, CactusPal = 28, Armadillo = 13, SphinxCat = 3 },
		Look = { Base = RGB(130, 210, 220), Accent = RGB(80, 170, 110), Accent2 = RGB(250, 240, 200), Pattern = "Bubbles" },
	},
	CactusEgg = { -- ★v8
		Name = "선인장 알", Rarity = "Epic", Zone = 12, Price = 4e13, HatchTime = 99, SpawnWeight = 11,
		Pets = { Meerkat = 16, CactusPal = 34, Armadillo = 32, SphinxCat = 15, PharaohPup = 3 },
		Look = { Base = RGB(130, 200, 110), Accent = RGB(70, 140, 70), Accent2 = RGB(255, 140, 180), Pattern = "Stripes" },
	},
	Pyramid = { -- ★v8
		Name = "피라미드 알", Rarity = "Legendary", Zone = 12, Price = 1e14, HatchTime = 132, SpawnWeight = 5,
		Pets = { CactusPal = 16, Armadillo = 36, SphinxCat = 32, PharaohPup = 15.7, SandDragon = 0.3 },
		Look = { Base = RGB(240, 205, 120), Accent = RGB(170, 120, 60), Accent2 = RGB(60, 160, 200), Pattern = "Zigzag", Shine = true },
	},
	Pharaoh = { -- ★v8
		Name = "파라오 알", Rarity = "Mythic", Zone = 12, Price = 2e14, HatchTime = 165, SpawnWeight = 2,
		Pets = { Armadillo = 24, SphinxCat = 42, PharaohPup = 33, SandDragon = 1 },
		Look = { Base = RGB(40, 70, 140), Accent = RGB(255, 200, 60), Accent2 = RGB(250, 245, 230), Pattern = "Stripes", Shine = true, Glow = true },
	},
	-- 13. 장난감 ★v8
	ToyEgg = { -- ★v8
		Name = "장난감 알", Rarity = "Common", Zone = 13, Price = 2.5e13, HatchTime = 60, SpawnWeight = 40,
		Pets = { TeddyBear = 35, RubberDuck = 31, WindUpMouse = 28, BlockPuppy = 6 },
		Look = { Base = RGB(255, 240, 200), Accent = RGB(255, 90, 90), Accent2 = RGB(90, 170, 255), Pattern = "Dots" },
	},
	Block = { -- ★v8
		Name = "블록 알", Rarity = "Rare", Zone = 13, Price = 1e14, HatchTime = 81, SpawnWeight = 24,
		Pets = { TeddyBear = 12, RubberDuck = 12, WindUpMouse = 32, BlockPuppy = 28, BalloonDog = 13, RockingHorse = 3 },
		Look = { Base = RGB(120, 190, 255), Accent = RGB(255, 210, 60), Accent2 = RGB(255, 100, 100), Pattern = "Stripes" },
	},
	Balloon = { -- ★v8
		Name = "풍선 알", Rarity = "Epic", Zone = 13, Price = 2e14, HatchTime = 108, SpawnWeight = 11,
		Pets = { WindUpMouse = 16, BlockPuppy = 34, BalloonDog = 32, RockingHorse = 15, MusicBoxCat = 3 },
		Look = { Base = RGB(255, 160, 200), Accent = RGB(255, 90, 150), Accent2 = RGB(255, 255, 255), Pattern = "Hearts" },
	},
	MusicBox = { -- ★v8
		Name = "오르골 알", Rarity = "Legendary", Zone = 13, Price = 5e14, HatchTime = 144, SpawnWeight = 5,
		Pets = { BlockPuppy = 16, BalloonDog = 36, RockingHorse = 32, MusicBoxCat = 15.7, ToyKing = 0.3 },
		Look = { Base = RGB(255, 225, 240), Accent = RGB(200, 140, 255), Accent2 = RGB(255, 215, 90), Pattern = "Stars", Shine = true },
	},
	Carousel = { -- ★v8
		Name = "회전목마 알", Rarity = "Mythic", Zone = 13, Price = 1.2e15, HatchTime = 180, SpawnWeight = 2,
		Pets = { BalloonDog = 24, RockingHorse = 42, MusicBoxCat = 33, ToyKing = 1 },
		Look = { Base = RGB(255, 250, 245), Accent = RGB(255, 110, 160), Accent2 = RGB(100, 200, 255), Pattern = "Candy", Shine = true, Glow = true },
	},
	-- 14. 꿈나라 ★v8
	DreamEgg = { -- ★v8
		Name = "꿈 알", Rarity = "Common", Zone = 14, Price = 1.5e14, HatchTime = 65, SpawnWeight = 40,
		Pets = { SleepySheep = 35, SnoozeHamster = 31, PillowCat = 28, Firefly = 6 },
		Look = { Base = RGB(60, 60, 130), Accent = RGB(255, 240, 160), Accent2 = RGB(190, 200, 255), Pattern = "Stars" },
	},
	Pillow = { -- ★v8
		Name = "베개 알", Rarity = "Rare", Zone = 14, Price = 5e14, HatchTime = 88, SpawnWeight = 24,
		Pets = { SleepySheep = 12, SnoozeHamster = 12, PillowCat = 32, Firefly = 28, MoonBear = 13, Baku = 3 },
		Look = { Base = RGB(220, 225, 255), Accent = RGB(160, 170, 240), Accent2 = RGB(255, 255, 255), Pattern = "Dots" },
	},
	Crescent = { -- ★v8
		Name = "초승달 알", Rarity = "Epic", Zone = 14, Price = 1.2e15, HatchTime = 117, SpawnWeight = 11,
		Pets = { PillowCat = 16, Firefly = 34, MoonBear = 32, Baku = 15, SandmanPup = 3 },
		Look = { Base = RGB(40, 50, 110), Accent = RGB(255, 230, 120), Accent2 = RGB(160, 190, 255), Pattern = "Stars" },
	},
	Lullaby = { -- ★v8
		Name = "자장가 알", Rarity = "Legendary", Zone = 14, Price = 3e15, HatchTime = 156, SpawnWeight = 5,
		Pets = { Firefly = 16, MoonBear = 36, Baku = 32, SandmanPup = 15.7, StarlightLion = 0.3 },
		Look = { Base = RGB(200, 180, 255), Accent = RGB(255, 200, 240), Accent2 = RGB(255, 255, 255), Pattern = "Swirl", Shine = true },
	},
	Starry = { -- ★v8
		Name = "별밤 알", Rarity = "Mythic", Zone = 14, Price = 7.5e15, HatchTime = 195, SpawnWeight = 2,
		Pets = { MoonBear = 24, Baku = 42, SandmanPup = 33, StarlightLion = 1 },
		Look = { Base = RGB(25, 25, 80), Accent = RGB(255, 240, 150), Accent2 = RGB(150, 220, 255), Pattern = "Stars", Shine = true, Glow = true },
	},
	-- 15. 화산 ★v8
	Lava = { -- ★v8
		Name = "용암 알", Rarity = "Common", Zone = 15, Price = 1e15, HatchTime = 70, SpawnWeight = 40,
		Pets = { MagmaSlime = 35, Salamander = 31, EmberPup = 28, FlameFox = 6 },
		Look = { Base = RGB(90, 70, 70), Accent = RGB(255, 120, 40), Accent2 = RGB(255, 210, 80), Pattern = "Flames" },
	},
	Ember = { -- ★v8
		Name = "불씨 알", Rarity = "Rare", Zone = 15, Price = 3e15, HatchTime = 94, SpawnWeight = 24,
		Pets = { MagmaSlime = 12, Salamander = 12, EmberPup = 32, FlameFox = 28, LavaTurtle = 13, MagmaRhino = 3 },
		Look = { Base = RGB(60, 55, 60), Accent = RGB(255, 140, 60), Accent2 = RGB(255, 220, 120), Pattern = "Dots" },
	},
	Magma = { -- ★v8
		Name = "마그마 알", Rarity = "Epic", Zone = 15, Price = 7.5e15, HatchTime = 126, SpawnWeight = 11,
		Pets = { EmberPup = 16, FlameFox = 34, LavaTurtle = 32, MagmaRhino = 15, FlameLion = 3 },
		Look = { Base = RGB(200, 60, 40), Accent = RGB(255, 190, 70), Accent2 = RGB(80, 60, 60), Pattern = "Zigzag" },
	},
	Obsidian = { -- ★v8
		Name = "흑요석 알", Rarity = "Legendary", Zone = 15, Price = 2e16, HatchTime = 168, SpawnWeight = 5,
		Pets = { FlameFox = 16, LavaTurtle = 36, MagmaRhino = 32, FlameLion = 15.7, Haetae = 0.3 },
		Look = { Base = RGB(30, 25, 40), Accent = RGB(180, 120, 255), Accent2 = RGB(255, 120, 60), Pattern = "Gems", Shine = true },
	},
	Blaze = { -- ★v8
		Name = "불꽃 알", Rarity = "Mythic", Zone = 15, Price = 5e16, HatchTime = 210, SpawnWeight = 2,
		Pets = { LavaTurtle = 24, MagmaRhino = 42, FlameLion = 33, Haetae = 1 },
		Look = { Base = RGB(255, 90, 40), Accent = RGB(255, 230, 100), Accent2 = RGB(255, 255, 230), Pattern = "Flames", Shine = true, Glow = true },
	},
	-- 16. 황금 ★v8
	Coin = { -- ★v8
		Name = "동전 알", Rarity = "Common", Zone = 16, Price = 6e15, HatchTime = 75, SpawnWeight = 40,
		Pets = { CoinPig = 35, GoldHamster = 31, RoyalCorgi = 28, CrownFrog = 6 },
		Look = { Base = RGB(255, 220, 110), Accent = RGB(220, 160, 40), Accent2 = RGB(255, 250, 220), Pattern = "Dots" },
	},
	Treasure = { -- ★v8
		Name = "보물 알", Rarity = "Rare", Zone = 16, Price = 2e16, HatchTime = 101, SpawnWeight = 24,
		Pets = { CoinPig = 12, GoldHamster = 12, RoyalCorgi = 32, CrownFrog = 28, KnightCat = 13, RoyalLion = 3 },
		Look = { Base = RGB(170, 110, 60), Accent = RGB(255, 210, 70), Accent2 = RGB(120, 220, 255), Pattern = "Gems" },
	},
	Royal = { -- ★v8
		Name = "왕실 알", Rarity = "Epic", Zone = 16, Price = 5e16, HatchTime = 135, SpawnWeight = 11,
		Pets = { RoyalCorgi = 16, CrownFrog = 34, KnightCat = 32, RoyalLion = 15, GoldenPegasus = 3 },
		Look = { Base = RGB(180, 40, 70), Accent = RGB(255, 210, 70), Accent2 = RGB(255, 250, 240), Pattern = "Crown" },
	},
	Jewel = { -- ★v8
		Name = "보석함 알", Rarity = "Legendary", Zone = 16, Price = 1.2e17, HatchTime = 180, SpawnWeight = 5,
		Pets = { CrownFrog = 16, KnightCat = 36, RoyalLion = 32, GoldenPegasus = 15.7, KingPenguin = 0.3 },
		Look = { Base = RGB(255, 240, 200), Accent = RGB(255, 90, 160), Accent2 = RGB(100, 220, 255), Pattern = "Gems", Shine = true },
	},
	Emperor = { -- ★v8
		Name = "황제 알", Rarity = "Mythic", Zone = 16, Price = 3e17, HatchTime = 225, SpawnWeight = 2,
		Pets = { KnightCat = 24, RoyalLion = 42, GoldenPegasus = 33, KingPenguin = 1 },
		Look = { Base = RGB(255, 215, 80), Accent = RGB(255, 255, 240), Accent2 = RGB(200, 60, 90), Pattern = "Crown", Shine = true, Glow = true },
	},
	-- ★v6 아주 희귀한 알 (지역마다 3개: 시크릿 → 천상 → 이터널). 사다리(ZoneEggOrder)에 없어요.
	-- 보통 알이 나올 때마다 따로 굴려서 아주 가끔 나와요 (Config.SpecialEggs). 까면 Pet 이 꼭 나와요 (Pets = { Pet = 100 }).
	-- 1. 숲
	ForestHidden = {
		Name = "숲 시크릿 알", Rarity = "Hidden", Special = "Hidden", Zone = 1, Price = 5000, HatchTime = 45, SpawnWeight = 0,
		Pet = "CloverFox", Pets = { CloverFox = 100 },
		Look = { Base = RGB(30, 75, 50), Accent = RGB(120, 255, 170), Accent2 = RGB(255, 210, 80), Pattern = "Gems", Shine = true, Glow = true },
	},
	ForestCelestial = {
		Name = "숲 천상 알", Rarity = "Celestial", Special = "Celestial", Zone = 1, Price = 100000, HatchTime = 60, SpawnWeight = 0,
		Pet = "BlossomFawn", Pets = { BlossomFawn = 100 },
		Look = { Base = RGB(255, 230, 240), Accent = RGB(255, 210, 80), Accent2 = RGB(120, 220, 150), Pattern = "Crown", Shine = true, Glow = true },
	},
	ForestEternal = {
		Name = "숲 이터널 알", Rarity = "Eternal", Special = "Eternal", Zone = 1, Price = 400000, HatchTime = 80, SpawnWeight = 0,
		Pet = "WorldTreeDragon", Pets = { WorldTreeDragon = 100 },
		Look = { Base = RGB(40, 120, 60), Accent = RGB(255, 215, 80), Accent2 = RGB(170, 255, 140), Pattern = "Flames", Shine = true, Glow = true },
	},
	-- 2. 호수
	LakeHidden = {
		Name = "호수 시크릿 알", Rarity = "Hidden", Special = "Hidden", Zone = 2, Price = 250000, HatchTime = 45, SpawnWeight = 0,
		Pet = "PearlOtter", Pets = { PearlOtter = 100 },
		Look = { Base = RGB(25, 50, 95), Accent = RGB(130, 220, 255), Accent2 = RGB(235, 240, 255), Pattern = "Gems", Shine = true, Glow = true },
	},
	LakeCelestial = {
		Name = "호수 천상 알", Rarity = "Celestial", Special = "Celestial", Zone = 2, Price = 2500000, HatchTime = 60, SpawnWeight = 0,
		Pet = "MoonSwan", Pets = { MoonSwan = 100 },
		Look = { Base = RGB(240, 245, 255), Accent = RGB(215, 225, 245), Accent2 = RGB(140, 200, 255), Pattern = "Crown", Shine = true, Glow = true },
	},
	LakeEternal = {
		Name = "호수 이터널 알", Rarity = "Eternal", Special = "Eternal", Zone = 2, Price = 6000000, HatchTime = 80, SpawnWeight = 0,
		Pet = "RainbowKoiDragon", Pets = { RainbowKoiDragon = 100 },
		Look = { Base = RGB(30, 90, 170), Accent = RGB(255, 140, 60), Accent2 = RGB(120, 230, 255), Pattern = "Flames", Shine = true, Glow = true },
	},
	-- 3. 정글
	JungleHidden = {
		Name = "정글 시크릿 알", Rarity = "Hidden", Special = "Hidden", Zone = 3, Price = 4000000, HatchTime = 55, SpawnWeight = 0,
		Pet = "RainbowChameleon", Pets = { RainbowChameleon = 100 },
		Look = { Base = RGB(45, 70, 30), Accent = RGB(255, 170, 60), Accent2 = RGB(60, 200, 110), Pattern = "Gems", Shine = true, Glow = true },
	},
	JungleCelestial = {
		Name = "정글 천상 알", Rarity = "Celestial", Special = "Celestial", Zone = 3, Price = 40000000, HatchTime = 70, SpawnWeight = 0,
		Pet = "GoldenJaguar", Pets = { GoldenJaguar = 100 },
		Look = { Base = RGB(255, 240, 200), Accent = RGB(255, 200, 50), Accent2 = RGB(40, 180, 110), Pattern = "Crown", Shine = true, Glow = true },
	},
	JungleEternal = {
		Name = "정글 이터널 알", Rarity = "Eternal", Special = "Eternal", Zone = 3, Price = 120000000, HatchTime = 100, SpawnWeight = 0,
		Pet = "EmeraldDragon", Pets = { EmeraldDragon = 100 },
		Look = { Base = RGB(20, 110, 70), Accent = RGB(60, 255, 150), Accent2 = RGB(255, 230, 100), Pattern = "Flames", Shine = true, Glow = true },
	},
	-- 4. 겨울
	SnowHidden = {
		Name = "겨울 시크릿 알", Rarity = "Hidden", Special = "Hidden", Zone = 4, Price = 60000000, HatchTime = 70, SpawnWeight = 0,
		Pet = "CrystalPenguin", Pets = { CrystalPenguin = 100 },
		Look = { Base = RGB(35, 55, 100), Accent = RGB(170, 235, 255), Accent2 = RGB(235, 245, 255), Pattern = "Gems", Shine = true, Glow = true },
	},
	SnowCelestial = {
		Name = "겨울 천상 알", Rarity = "Celestial", Special = "Celestial", Zone = 4, Price = 600000000, HatchTime = 85, SpawnWeight = 0,
		Pet = "AuroraWolf", Pets = { AuroraWolf = 100 },
		Look = { Base = RGB(230, 245, 255), Accent = RGB(220, 230, 250), Accent2 = RGB(120, 255, 200), Pattern = "Crown", Shine = true, Glow = true },
	},
	SnowEternal = {
		Name = "겨울 이터널 알", Rarity = "Eternal", Special = "Eternal", Zone = 4, Price = 2e9, HatchTime = 120, SpawnWeight = 0,
		Pet = "IcePhoenix", Pets = { IcePhoenix = 100 },
		Look = { Base = RGB(40, 90, 160), Accent = RGB(140, 230, 255), Accent2 = RGB(255, 255, 255), Pattern = "Flames", Shine = true, Glow = true },
	},
	-- 5. 바다
	OceanHidden = {
		Name = "바다 시크릿 알", Rarity = "Hidden", Special = "Hidden", Zone = 5, Price = 1.2e9, HatchTime = 80, SpawnWeight = 0,
		Pet = "RainbowJelly", Pets = { RainbowJelly = 100 },
		Look = { Base = RGB(15, 70, 95), Accent = RGB(255, 240, 250), Accent2 = RGB(255, 200, 90), Pattern = "Gems", Shine = true, Glow = true },
	},
	OceanCelestial = {
		Name = "바다 천상 알", Rarity = "Celestial", Special = "Celestial", Zone = 5, Price = 1.2e10, HatchTime = 105, SpawnWeight = 0,
		Pet = "PearlSeahorse", Pets = { PearlSeahorse = 100 },
		Look = { Base = RGB(220, 250, 245), Accent = RGB(255, 215, 90), Accent2 = RGB(255, 170, 200), Pattern = "Crown", Shine = true, Glow = true },
	},
	OceanEternal = {
		Name = "바다 이터널 알", Rarity = "Eternal", Special = "Eternal", Zone = 5, Price = 4e10, HatchTime = 145, SpawnWeight = 0,
		Pet = "BabyKraken", Pets = { BabyKraken = 100 },
		Look = { Base = RGB(70, 40, 120), Accent = RGB(110, 220, 255), Accent2 = RGB(255, 210, 90), Pattern = "Flames", Shine = true, Glow = true },
	},
	-- 6. 캔디
	CandyHidden = {
		Name = "캔디 시크릿 알", Rarity = "Hidden", Special = "Hidden", Zone = 6, Price = 2.5e10, HatchTime = 100, SpawnWeight = 0,
		Pet = "LollipopPanda", Pets = { LollipopPanda = 100 },
		Look = { Base = RGB(120, 40, 90), Accent = RGB(255, 150, 220), Accent2 = RGB(150, 240, 210), Pattern = "Gems", Shine = true, Glow = true },
	},
	CandyCelestial = {
		Name = "캔디 천상 알", Rarity = "Celestial", Special = "Celestial", Zone = 6, Price = 2.5e11, HatchTime = 125, SpawnWeight = 0,
		Pet = "MarshmallowBear", Pets = { MarshmallowBear = 100 },
		Look = { Base = RGB(255, 250, 240), Accent = RGB(255, 200, 100), Accent2 = RGB(255, 120, 180), Pattern = "Crown", Shine = true, Glow = true },
	},
	CandyEternal = {
		Name = "캔디 이터널 알", Rarity = "Eternal", Special = "Eternal", Zone = 6, Price = 7.5e11, HatchTime = 170, SpawnWeight = 0,
		Pet = "SweetQueenCat", Pets = { SweetQueenCat = 100 },
		Look = { Base = RGB(200, 60, 140), Accent = RGB(255, 220, 90), Accent2 = RGB(255, 180, 230), Pattern = "Flames", Shine = true, Glow = true },
	},
	-- 7. 구름
	CloudHidden = {
		Name = "구름 시크릿 알", Rarity = "Hidden", Special = "Hidden", Zone = 7, Price = 5e11, HatchTime = 110, SpawnWeight = 0,
		Pet = "ThunderPup", Pets = { ThunderPup = 100 },
		Look = { Base = RGB(70, 75, 120), Accent = RGB(255, 235, 90), Accent2 = RGB(230, 235, 255), Pattern = "Gems", Shine = true, Glow = true },
	},
	CloudCelestial = {
		Name = "구름 천상 알", Rarity = "Celestial", Special = "Celestial", Zone = 7, Price = 5e12, HatchTime = 145, SpawnWeight = 0,
		Pet = "SunGriffin", Pets = { SunGriffin = 100 },
		Look = { Base = RGB(255, 248, 220), Accent = RGB(255, 200, 60), Accent2 = RGB(255, 150, 60), Pattern = "Crown", Shine = true, Glow = true },
	},
	CloudEternal = {
		Name = "구름 이터널 알", Rarity = "Eternal", Special = "Eternal", Zone = 7, Price = 1.5e13, HatchTime = 200, SpawnWeight = 0,
		Pet = "NineTailFox", Pets = { NineTailFox = 100 },
		Look = { Base = RGB(40, 35, 90), Accent = RGB(245, 240, 255), Accent2 = RGB(170, 130, 255), Pattern = "Flames", Shine = true, Glow = true },
	},
	-- 8. 우주
	SpaceHidden = {
		Name = "우주 시크릿 알", Rarity = "Hidden", Special = "Hidden", Zone = 8, Price = 7.5e12, HatchTime = 130, SpawnWeight = 0,
		Pet = "MeteorHamster", Pets = { MeteorHamster = 100 },
		Look = { Base = RGB(25, 20, 55), Accent = RGB(255, 150, 70), Accent2 = RGB(170, 180, 210), Pattern = "Gems", Shine = true, Glow = true },
	},
	SpaceCelestial = {
		Name = "우주 천상 알", Rarity = "Celestial", Special = "Celestial", Zone = 8, Price = 6e13, HatchTime = 170, SpawnWeight = 0,
		Pet = "GalaxyUnicorn", Pets = { GalaxyUnicorn = 100 },
		Look = { Base = RGB(215, 210, 255), Accent = RGB(255, 210, 80), Accent2 = RGB(120, 240, 255), Pattern = "Crown", Shine = true, Glow = true },
	},
	SpaceEternal = {
		Name = "우주 이터널 알", Rarity = "Eternal", Special = "Eternal", Zone = 8, Price = 2e14, HatchTime = 230, SpawnWeight = 0,
		Pet = "CosmoDragon", Pets = { CosmoDragon = 100 },
		Look = { Base = RGB(15, 15, 45), Accent = RGB(180, 110, 255), Accent2 = RGB(120, 240, 255), Pattern = "Flames", Shine = true, Glow = true },
	},
	-- 9. 벚꽃 ★v8
	BlossomHidden = { -- ★v8
		Name = "벚꽃 시크릿 알", Rarity = "Hidden", Special = "Hidden", Zone = 9, Price = 5e13, HatchTime = 150, SpawnWeight = 0,
		Pet = "HoneyBear", Pets = { HoneyBear = 100 },
		Look = { Base = RGB(80, 30, 60), Accent = RGB(255, 160, 210), Accent2 = RGB(255, 230, 120), Pattern = "Gems", Shine = true, Glow = true },
	},
	BlossomCelestial = { -- ★v8
		Name = "벚꽃 천상 알", Rarity = "Celestial", Special = "Celestial", Zone = 9, Price = 4e14, HatchTime = 195, SpawnWeight = 0,
		Pet = "SakuraCrane", Pets = { SakuraCrane = 100 },
		Look = { Base = RGB(255, 245, 250), Accent = RGB(255, 190, 220), Accent2 = RGB(255, 215, 90), Pattern = "Crown", Shine = true, Glow = true },
	},
	BlossomEternal = { -- ★v8
		Name = "벚꽃 이터널 알", Rarity = "Eternal", Special = "Eternal", Zone = 9, Price = 1.5e15, HatchTime = 260, SpawnWeight = 0,
		Pet = "BlossomDragon", Pets = { BlossomDragon = 100 },
		Look = { Base = RGB(150, 40, 100), Accent = RGB(255, 200, 230), Accent2 = RGB(120, 230, 160), Pattern = "Flames", Shine = true, Glow = true },
	},
	-- 10. 공룡 ★v8
	DinoHidden = { -- ★v8
		Name = "공룡 시크릿 알", Rarity = "Hidden", Special = "Hidden", Zone = 10, Price = 3e14, HatchTime = 170, SpawnWeight = 0,
		Pet = "DinoPuppy", Pets = { DinoPuppy = 100 },
		Look = { Base = RGB(40, 70, 40), Accent = RGB(140, 255, 140), Accent2 = RGB(255, 200, 80), Pattern = "Gems", Shine = true, Glow = true },
	},
	DinoCelestial = { -- ★v8
		Name = "공룡 천상 알", Rarity = "Celestial", Special = "Celestial", Zone = 10, Price = 2.5e15, HatchTime = 220, SpawnWeight = 0,
		Pet = "SkyPtera", Pets = { SkyPtera = 100 },
		Look = { Base = RGB(255, 245, 225), Accent = RGB(255, 200, 90), Accent2 = RGB(120, 200, 255), Pattern = "Crown", Shine = true, Glow = true },
	},
	DinoEternal = { -- ★v8
		Name = "공룡 이터널 알", Rarity = "Eternal", Special = "Eternal", Zone = 10, Price = 1e16, HatchTime = 290, SpawnWeight = 0,
		Pet = "AncientDragon", Pets = { AncientDragon = 100 },
		Look = { Base = RGB(40, 90, 60), Accent = RGB(255, 190, 80), Accent2 = RGB(170, 255, 170), Pattern = "Flames", Shine = true, Glow = true },
	},
	-- 11. 보석 ★v8
	CrystalHidden = { -- ★v8
		Name = "보석 시크릿 알", Rarity = "Hidden", Special = "Hidden", Zone = 11, Price = 2e15, HatchTime = 190, SpawnWeight = 0,
		Pet = "OpalBunny", Pets = { OpalBunny = 100 },
		Look = { Base = RGB(30, 30, 60), Accent = RGB(150, 255, 240), Accent2 = RGB(255, 200, 255), Pattern = "Gems", Shine = true, Glow = true },
	},
	CrystalCelestial = { -- ★v8
		Name = "보석 천상 알", Rarity = "Celestial", Special = "Celestial", Zone = 11, Price = 2e16, HatchTime = 245, SpawnWeight = 0,
		Pet = "CrystalDeer", Pets = { CrystalDeer = 100 },
		Look = { Base = RGB(240, 250, 255), Accent = RGB(170, 230, 255), Accent2 = RGB(255, 215, 90), Pattern = "Crown", Shine = true, Glow = true },
	},
	CrystalEternal = { -- ★v8
		Name = "보석 이터널 알", Rarity = "Eternal", Special = "Eternal", Zone = 11, Price = 6e16, HatchTime = 320, SpawnWeight = 0,
		Pet = "DiamondDragon", Pets = { DiamondDragon = 100 },
		Look = { Base = RGB(40, 60, 110), Accent = RGB(220, 250, 255), Accent2 = RGB(180, 140, 255), Pattern = "Flames", Shine = true, Glow = true },
	},
	-- 12. 사막 ★v8
	DesertHidden = { -- ★v8
		Name = "사막 시크릿 알", Rarity = "Hidden", Special = "Hidden", Zone = 12, Price = 1e16, HatchTime = 210, SpawnWeight = 0,
		Pet = "LampGenie", Pets = { LampGenie = 100 },
		Look = { Base = RGB(60, 40, 20), Accent = RGB(255, 210, 120), Accent2 = RGB(110, 230, 230), Pattern = "Gems", Shine = true, Glow = true },
	},
	DesertCelestial = { -- ★v8
		Name = "사막 천상 알", Rarity = "Celestial", Special = "Celestial", Zone = 12, Price = 1e17, HatchTime = 270, SpawnWeight = 0,
		Pet = "SunScarab", Pets = { SunScarab = 100 },
		Look = { Base = RGB(255, 245, 220), Accent = RGB(255, 200, 60), Accent2 = RGB(60, 200, 180), Pattern = "Crown", Shine = true, Glow = true },
	},
	DesertEternal = { -- ★v8
		Name = "사막 이터널 알", Rarity = "Eternal", Special = "Eternal", Zone = 12, Price = 3e17, HatchTime = 350, SpawnWeight = 0,
		Pet = "MirageDragon", Pets = { MirageDragon = 100 },
		Look = { Base = RGB(140, 60, 30), Accent = RGB(255, 220, 140), Accent2 = RGB(255, 140, 90), Pattern = "Flames", Shine = true, Glow = true },
	},
	-- 13. 장난감 ★v8
	ToyHidden = { -- ★v8
		Name = "장난감 시크릿 알", Rarity = "Hidden", Special = "Hidden", Zone = 13, Price = 6e16, HatchTime = 230, SpawnWeight = 0,
		Pet = "ClockworkFox", Pets = { ClockworkFox = 100 },
		Look = { Base = RGB(60, 40, 80), Accent = RGB(255, 210, 90), Accent2 = RGB(120, 200, 255), Pattern = "Gems", Shine = true, Glow = true },
	},
	ToyCelestial = { -- ★v8
		Name = "장난감 천상 알", Rarity = "Celestial", Special = "Celestial", Zone = 13, Price = 5e17, HatchTime = 295, SpawnWeight = 0,
		Pet = "CarouselUnicorn", Pets = { CarouselUnicorn = 100 },
		Look = { Base = RGB(255, 245, 250), Accent = RGB(255, 150, 200), Accent2 = RGB(255, 215, 90), Pattern = "Crown", Shine = true, Glow = true },
	},
	ToyEternal = { -- ★v8
		Name = "장난감 이터널 알", Rarity = "Eternal", Special = "Eternal", Zone = 13, Price = 2e18, HatchTime = 380, SpawnWeight = 0,
		Pet = "MechaDragon", Pets = { MechaDragon = 100 },
		Look = { Base = RGB(40, 60, 110), Accent = RGB(130, 220, 255), Accent2 = RGB(255, 120, 120), Pattern = "Flames", Shine = true, Glow = true },
	},
	-- 14. 꿈나라 ★v8
	DreamHidden = { -- ★v8
		Name = "꿈나라 시크릿 알", Rarity = "Hidden", Special = "Hidden", Zone = 14, Price = 4e17, HatchTime = 250, SpawnWeight = 0,
		Pet = "SnoozePanda", Pets = { SnoozePanda = 100 },
		Look = { Base = RGB(20, 20, 55), Accent = RGB(190, 170, 255), Accent2 = RGB(255, 240, 160), Pattern = "Gems", Shine = true, Glow = true },
	},
	DreamCelestial = { -- ★v8
		Name = "꿈나라 천상 알", Rarity = "Celestial", Special = "Celestial", Zone = 14, Price = 3e18, HatchTime = 320, SpawnWeight = 0,
		Pet = "CrescentFox", Pets = { CrescentFox = 100 },
		Look = { Base = RGB(240, 240, 255), Accent = RGB(255, 230, 120), Accent2 = RGB(160, 180, 255), Pattern = "Crown", Shine = true, Glow = true },
	},
	DreamEternal = { -- ★v8
		Name = "꿈나라 이터널 알", Rarity = "Eternal", Special = "Eternal", Zone = 14, Price = 1e19, HatchTime = 410, SpawnWeight = 0,
		Pet = "DreamDragon", Pets = { DreamDragon = 100 },
		Look = { Base = RGB(30, 20, 80), Accent = RGB(255, 210, 120), Accent2 = RGB(170, 150, 255), Pattern = "Flames", Shine = true, Glow = true },
	},
	-- 15. 화산 ★v8
	VolcanoHidden = { -- ★v8
		Name = "화산 시크릿 알", Rarity = "Hidden", Special = "Hidden", Zone = 15, Price = 2.5e18, HatchTime = 270, SpawnWeight = 0,
		Pet = "CinderCat", Pets = { CinderCat = 100 },
		Look = { Base = RGB(30, 15, 15), Accent = RGB(255, 120, 60), Accent2 = RGB(255, 220, 120), Pattern = "Gems", Shine = true, Glow = true },
	},
	VolcanoCelestial = { -- ★v8
		Name = "화산 천상 알", Rarity = "Celestial", Special = "Celestial", Zone = 15, Price = 2e19, HatchTime = 345, SpawnWeight = 0,
		Pet = "MagmaWyvern", Pets = { MagmaWyvern = 100 },
		Look = { Base = RGB(255, 235, 210), Accent = RGB(255, 140, 60), Accent2 = RGB(255, 220, 90), Pattern = "Crown", Shine = true, Glow = true },
	},
	VolcanoEternal = { -- ★v8
		Name = "화산 이터널 알", Rarity = "Eternal", Special = "Eternal", Zone = 15, Price = 7.5e19, HatchTime = 440, SpawnWeight = 0,
		Pet = "InfernoDragon", Pets = { InfernoDragon = 100 },
		Look = { Base = RGB(70, 15, 10), Accent = RGB(255, 200, 80), Accent2 = RGB(255, 100, 40), Pattern = "Flames", Shine = true, Glow = true },
	},
	-- 16. 황금 ★v8
	GoldHidden = { -- ★v8
		Name = "황금 시크릿 알", Rarity = "Hidden", Special = "Hidden", Zone = 16, Price = 1.5e19, HatchTime = 290, SpawnWeight = 0,
		Pet = "TreasureMimic", Pets = { TreasureMimic = 100 },
		Look = { Base = RGB(70, 45, 15), Accent = RGB(255, 220, 100), Accent2 = RGB(255, 120, 180), Pattern = "Gems", Shine = true, Glow = true },
	},
	GoldCelestial = { -- ★v8
		Name = "황금 천상 알", Rarity = "Celestial", Special = "Celestial", Zone = 16, Price = 1.2e20, HatchTime = 370, SpawnWeight = 0,
		Pet = "CrownGriffin", Pets = { CrownGriffin = 100 },
		Look = { Base = RGB(255, 250, 230), Accent = RGB(255, 215, 80), Accent2 = RGB(120, 220, 255), Pattern = "Crown", Shine = true, Glow = true },
	},
	GoldEternal = { -- ★v8
		Name = "황금 이터널 알", Rarity = "Eternal", Special = "Eternal", Zone = 16, Price = 4e20, HatchTime = 470, SpawnWeight = 0,
		Pet = "EmperorDragon", Pets = { EmperorDragon = 100 },
		Look = { Base = RGB(90, 60, 10), Accent = RGB(255, 235, 140), Accent2 = RGB(255, 90, 120), Pattern = "Flames", Shine = true, Glow = true },
	},
}

-- 지역 순, 지역 안에서는 사다리 순 (싼 알 → 비싼 알)
Config.EggOrder = {
	"Basic", "Flower", "Mushroom", "Forest", "Fairy", "Spirit",
	"Lake", "Lily", "Bubble", "Moonlight", "Crystal",
	"Jungle", "Leaf", "Spotted", "Tropical", "Tiger",
	"Snow", "Ice", "Snowflake", "Aurora", "Twilight",
	"Ocean", "Shell", "Coral", "Pearl", "DragonPalace",
	"Candy", "Jelly", "Lollipop", "Cake", "Rainbow",
	"Cloud", "Breeze", "Feather", "Angel", "Golden",
	"Space", "Moon", "Planet", "Comet", "Starlight",
	"Sakura", "Tulip", "HoneyPot", "Bloom", "SpringQueen",
	"Dino", "Fern", "Fossil", "Amber", "Jurassic",
	"Cave", "Ruby", "Sapphire", "Amethyst", "DiamondEgg",
	"Sand", "Oasis", "CactusEgg", "Pyramid", "Pharaoh",
	"ToyEgg", "Block", "Balloon", "MusicBox", "Carousel",
	"DreamEgg", "Pillow", "Crescent", "Lullaby", "Starry",
	"Lava", "Ember", "Magma", "Obsidian", "Blaze",
	"Coin", "Treasure", "Royal", "Jewel", "Emperor",
}

-- 지역별 알 목록 (사다리 순) + 자동으로 채우는 값
Config.ZoneEggOrder = {} :: { [number]: { string } }
for _, id in Config.EggOrder do
	local egg = Config.Eggs[id]
	local list = Config.ZoneEggOrder[egg.Zone]
	if not list then
		list = {}
		Config.ZoneEggOrder[egg.Zone] = list
	end
	table.insert(list, id)
	egg.Rung = #list
end
for _, egg in Config.Eggs do
	local rungs = #Config.ZoneEggOrder[egg.Zone]
	egg.Rungs = rungs
	if egg.Special then
		egg.Rung = 0 -- ★v6 희귀 알은 사다리 밖 (좋은 알 Premium 도 아니에요, 대신 egg.Special)
		egg.Premium = false
	else
		egg.Premium = egg.Rung >= rungs - 1 -- 위 2칸 = 좋은 알
	end
	-- 알의 MinRebirth = 지역 MinRebirth (예전 코드가 egg.MinRebirth 를 읽어도 맞게)
	egg.MinRebirth = Config.Zones[egg.Zone].MinRebirth
end

-- ★v6 아주 희귀한 알 순서 (지역 순, 지역 안에서는 시크릿 → 천상 → 이터널). EggOrder / ZoneEggOrder (사다리) 에는 없어요
Config.SpecialEggOrder = {
	"ForestHidden", "ForestCelestial", "ForestEternal",
	"LakeHidden", "LakeCelestial", "LakeEternal",
	"JungleHidden", "JungleCelestial", "JungleEternal",
	"SnowHidden", "SnowCelestial", "SnowEternal",
	"OceanHidden", "OceanCelestial", "OceanEternal",
	"CandyHidden", "CandyCelestial", "CandyEternal",
	"CloudHidden", "CloudCelestial", "CloudEternal",
	"SpaceHidden", "SpaceCelestial", "SpaceEternal",
	"BlossomHidden", "BlossomCelestial", "BlossomEternal",
	"DinoHidden", "DinoCelestial", "DinoEternal",
	"CrystalHidden", "CrystalCelestial", "CrystalEternal",
	"DesertHidden", "DesertCelestial", "DesertEternal",
	"ToyHidden", "ToyCelestial", "ToyEternal",
	"DreamHidden", "DreamCelestial", "DreamEternal",
	"VolcanoHidden", "VolcanoCelestial", "VolcanoEternal",
	"GoldHidden", "GoldCelestial", "GoldEternal",
}
Config.ZoneSpecialEggOrder = {} :: { [number]: { string } } -- [지역] = { 시크릿 알, 천상 알, 이터널 알 }
for _, id in Config.SpecialEggOrder do
	local egg = Config.Eggs[id]
	local list = Config.ZoneSpecialEggOrder[egg.Zone]
	if not list then
		list = {}
		Config.ZoneSpecialEggOrder[egg.Zone] = list
	end
	table.insert(list, id)
end
for k, zone in Config.Zones do
	zone.Eggs = Config.ZoneEggOrder[k] or {}
	zone.SpecialEggs = Config.ZoneSpecialEggOrder[k] or {} -- ★v6
end

----------------------------------------------------------------------
-- 환생: 코인(수금 대기 포함)을 0으로 돌리는 대신 영구 보너스. 펫·집·받침대·테마·옷·가구는 그대로.
-- Costs[n] = n 번째 환생 비용 (지금 환생 수가 n-1 일 때). sim3.py 로 맞춘 값이에요.
----------------------------------------------------------------------
Config.Rebirth = {
	Costs = {
		8e5, 1.2e7, 2.4e8, 2e9, 8e9, 4e10, 1.2e11, 5e11, 1.2e12, 3e12, -- 1~10 (지역 2,3,4 는 환생 1,2,3)
		6e12, 2e13, 3e13, 6e13, 1.2e14, -- 11~15 (지역 5,6,7,8 은 환생 5,7,10,14)
		-- ★v8 16~30: 새 지역 (9~16 = 환생 16, 18, …, 30) 수익에 맞춰 한 번에 ×2.45 쯤 (지역 하나 = 환생 2번 = ×6, 알 가격도 지역마다 ×6)
		3e14, 7.5e14, 1.8e15, 4.5e15, 1.1e16, -- 16~20
		2.7e16, 6.5e16, 1.6e17, 4e17, 1e18, -- 21~25
		2.4e18, 6e18, 1.5e19, 3.6e19, 9e19, -- 26~30
	},
	MaxRebirths = 30, -- ★v8 25 → 30
	IncomePerRebirth = 0.5, -- 집 수익 ×(1 + 0.5 × 환생 수)
	CoinPerRebirth = 0.1, -- 들판 코인 값 ×(1 + 0.1 × 환생 수) (수익이 이미 환생 배율을 받아서 작게)
	SpeedPerRebirth = 0.03, -- 이동 속도 ×(1 + 0.03 × 환생 수)
	LuckPerRebirth = 0.25, -- 부화 때 상위 등급 확률 ×(1 + 0.25 × 환생 수)
	HatchSpeedPerRebirth = 0.1, -- 부화 시간 ÷(1 + 0.1 × 환생 수)
}

-- 부화 시 바로 상위 등급으로 태어날 기본 확률 (환생 운 배율 적용). 부화로는 골드(4)까지만
Config.HatchTierChance = { [2] = 0.05, [3] = 0.01, [4] = 0.002 }
Config.MaxHatchTier = 4

-- 펫 크기/무게: 부화할 때 Size 를 뽑아요. 수익 ×Size. 무게 = BaseWeight × Size³ (kg)
Config.PetSize = {
	Min = 0.8,
	Max = 1.3,
	HugeFrom = 1.22, -- 이 이상이면 "거대" 표시
	TinyUntil = 0.86, -- 이 이하이면 "꼬마" 표시
	BaseWeight = 4, -- 종에 따라 Config.Pets[*].Weight 가 있으면 그걸 씀 (kg, Size 1 기준)
	-- ★v7 아주 희귀한 펫 (희귀도 키) 은 더 넓게 뽑아요 → 더 크고 더 많이 벌어요. 거대 = 위쪽 ~15%, 꼬마 = 아래쪽 ~3%
	-- 위에 없는 펫은 Min..Max 그대로 (Config.PetSizeRange)
	Special = {
		Hidden = { Min = 0.8, Max = 1.5, HugeFrom = 1.31, TinyUntil = 0.88 },
		Celestial = { Min = 0.8, Max = 1.7, HugeFrom = 1.46, TinyUntil = 0.91 },
		Eternal = { Min = 0.8, Max = 2.0, HugeFrom = 1.67, TinyUntil = 0.94 },
	},
}

-- 들고 다니기(자랑): 펫 1마리를 머리 위에 올려요. 보너스는 따라다니는 펫과 같음
Config.Hold = {
	Scale = 0.75,
	HeadOffset = 1.6, -- 머리 꼭대기에서 위로
}

----------------------------------------------------------------------
-- 합성 등급 (7단계). 같은 펫·같은 등급 FuseCount 마리 → 한 단계 위 1마리.
-- 부화로는 골드까지만 나와요. Visual = PetModels.applyTier 가 읽는 모양 정보.
--   Tint/TintAlpha: 색을 이 색 쪽으로 섞기, Gradient: "Rainbow"(아래→위 무지개) | "Galaxy"(남색→보라),
--   Material/Reflectance/Transparency: 몸 파트 재질, Specks: 몸에 붙이는 작은 Neon 별 개수,
--   Particles: 반짝이 초당 개수, ParticleColors: 반짝이 색, Light: PointLight 밝기 (0 이면 없음),
--   Cycle: true 면 클라이언트가 가까운 펫 색을 천천히 돌려요 (레인보우)
--   (집 받침대 위 펫은 한 방에 많이 모여 있어서 클라이언트 WorldFx 가 빛·반짝이를 조금 줄여요: PED_LIGHT_MULT / PED_SPARKLE_MULT.
--    Reflectance 는 눈부시지 않게 살짝만)
-- BoostMult 는 들판 코인만 바꾸고 FieldCoins.MaxBoost 로 잘려서 IncomeMult 보다 천천히 커져요.
----------------------------------------------------------------------
Config.Tiers = {
	{
		Name = "", Label = "", IncomeMult = 1, BoostMult = 1, Color = RGB(255, 255, 255),
		Visual = { Particles = 0, Light = 0 },
	},
	{
		Name = "브론즈", Label = "🥉 브론즈", IncomeMult = 3, BoostMult = 1.5, Color = RGB(215, 135, 70),
		Visual = { Tint = RGB(205, 127, 50), TintAlpha = 0.6, Material = Enum.Material.SmoothPlastic, Reflectance = 0.06, Particles = 2, ParticleColors = { RGB(230, 150, 80), RGB(255, 220, 180) }, Light = 0.3 },
	},
	{
		Name = "실버", Label = "🥈 실버", IncomeMult = 8, BoostMult = 2.2, Color = RGB(200, 210, 225),
		Visual = { Tint = RGB(200, 205, 215), TintAlpha = 0.7, Material = Enum.Material.Metal, Reflectance = 0.15, Particles = 3, ParticleColors = { RGB(230, 235, 245), RGB(255, 255, 255) }, Light = 0.4 },
	},
	{
		Name = "골드", Label = "🥇 골드", IncomeMult = 20, BoostMult = 3, Color = RGB(255, 200, 60),
		Visual = { Tint = RGB(255, 200, 60), TintAlpha = 0.7, Material = Enum.Material.SmoothPlastic, Reflectance = 0.1, Particles = 6, ParticleColors = { RGB(255, 200, 60), RGB(255, 255, 255) }, Light = 0.6 },
	},
	{
		Name = "레인보우", Label = "🌈 레인보우", IncomeMult = 50, BoostMult = 4, Color = RGB(255, 120, 220),
		Visual = { Gradient = "Rainbow", Reflectance = 0.05, Particles = 9, ParticleColors = { RGB(255, 95, 110), RGB(255, 225, 80), RGB(110, 215, 120), RGB(90, 170, 255), RGB(175, 120, 255) }, Light = 1, Cycle = true },
	},
	{
		Name = "다이아", Label = "💎 다이아", IncomeMult = 120, BoostMult = 5.5, Color = RGB(120, 220, 255),
		Visual = { Tint = RGB(170, 230, 255), TintAlpha = 0.8, Material = Enum.Material.Glass, Reflectance = 0.2, Transparency = 0.2, Particles = 12, ParticleColors = { RGB(200, 245, 255), RGB(255, 255, 255) }, Light = 1.2 },
	},
	{
		Name = "갤럭시", Label = "🌌 갤럭시", IncomeMult = 300, BoostMult = 7.5, Color = RGB(140, 90, 255),
		Visual = { Gradient = "Galaxy", Tint = RGB(45, 30, 110), TintAlpha = 0.85, Material = Enum.Material.SmoothPlastic, Reflectance = 0.06, Specks = 10, Particles = 16, ParticleColors = { RGB(180, 140, 255), RGB(120, 200, 255), RGB(255, 255, 255) }, Light = 1.5 },
	},
}
Config.MaxTier = #Config.Tiers
Config.FuseCount = 3
-- 합성 재료가 될 수 있는 위치 (집 받침대 위 "Slot" 펫은 절대 안 써요)
Config.FuseLocs = { Bag = true, Follow = true, Ride = true, Hold = true }

-- 펫 타기. 속도 배율 = 1.2 + 0.1 × (희귀도 순서 - 1) + 0.06 × (등급 - 1)
-- 탄 채로 서 있는 키 ≈ 8.5 스터드 (HipHeight 2 + 2.2 + 몸) → 문 14, 층 사이 11 이면 넉넉해요
Config.Ride = {
	BaseMultiplier = 1.2,
	PerRarityOrder = 0.1,
	PerTier = 0.06,
	SizePower = 0.5, -- ★v7 희귀 펫만: × (Size / 범위 Min) ^ 이만큼 (제일 작으면 v6 그대로, 이터널 2.0 이면 ×1.58)
	Scale = 1.45, -- 탈 때 펫 모델 크기 배율
	HipHeightAdd = 2.2, -- 캐릭터가 펫 위에 올라앉은 것처럼 보이게 HipHeight 추가
	MaxStandHeight = 8.5, -- 문/천장 설계용 (탄 채로 머리 꼭대기 높이 대략)
}

-- 컨베이어 (지역마다 1개, 값은 벨트 하나 기준). ★v5 알은 사람마다 따로 나와요 (남이 사도 내 알은 그대로)
Config.Conveyor = {
	SpawnInterval = 2.6, -- 몇 초마다 새 알 (한 사람의 벨트 하나 기준)
	TravelTime = 26, -- 끝까지 가는 데 걸리는 초 (끝에 닿으면 사라짐)
	MaxEggs = 12, -- 보통 알 (★v6 희귀 알은 따로 Config.SpecialEggs.MaxPerBelt)
	FlyMaxDistance = 400, -- 이보다 먼 집으로는 날아가지 않고 "뿅" 하고 바로 받침대에 나타나요
	BeaconHeight = 70, -- 좋은 알(위 2칸) 위로 솟는 빛기둥 높이 (숲 마을에서도 보여요)
	-- ★v5 알 자리는 나온 시각으로 계산해요 (Config.BeltEggSpot, 서버·클라이언트가 같은 공식)
	BeltTop = 1.2, -- 벨트 윗면 높이 (알 바닥)
	DropTime = 0.7, -- 슈트에서 벨트로 떨어지는 시간
	DropHeight = 9, -- 슈트 안에서 알이 나오는 높이
	FallTime = 0.7, -- 끝에서 통 안으로 떨어지는 시간
	BuyDistance = 20, -- 서버: 계산한 알 자리에서 이 거리 안에 있어야 살 수 있어요
	BuyGrace = 0.5, -- 벨트 끝에 닿은 뒤에도 이만큼은 사기를 받아 줘요 (지연 대비)
	RenderDistance = 200, -- 클라이언트: 이 거리 안 알만 모델로 그려요 (좋은 알 빛기둥은 어디서나 보여요)
	-- ★v6 아주 희귀한 알: 벨트 끝 SpecialStop 스터드 앞에서 코인 들판 쪽으로 SpecialSide 만큼 비켜서 (SpecialSlide 초)
	-- SpecialWait 초 기다렸다가 통으로 가요 → 알림 보고 달려와도 있어요. 뒤에 오는 보통 알은 옆으로 지나가요
	SpecialWait = 60,
	SpecialStop = 3,
	SpecialSide = 2.5,
	SpecialSlide = 0.8,
}

-- ★v6 아주 희귀한 알 (시크릿 → 천상 → 이터널). 벨트에 보통 알이 하나 나올 때마다 단계마다 따로 굴려요
-- (보통 알 사다리는 그대로, 희귀 알은 그 사이 반 칸 뒤에 하나 더 나와요). 둘 이상 맞으면 더 희귀한 것 하나만.
-- 한 번 굴릴 때 확률 = Chance ÷ (열린 벨트 수 ^ BeltPower): 지역이 많이 열려도 알림이 쏟아지지 않게.
-- 보통 알 2.6초마다 → 벨트 1개: 시간당 시크릿 ~4.6 / 천상 ~1.2 / 이터널 ~0.28 개, 벨트 8개 다 합쳐 ~13 / ~3.3 / ~0.8 개.
-- 나오면 그 사람에게 늘 알림 (EggAlertKind "Rare", 간격·지역 창 규칙 없이). 처음 채우는 벨트에는 안 나와요.
Config.SpecialEggs = {
	Tiers = { "Hidden", "Celestial", "Eternal" },
	Chance = { Hidden = 1 / 300, Celestial = 1 / 1200, Eternal = 1 / 5000 },
	BeltPower = 0.5,
	MaxPerBelt = 3, -- 한 사람의 벨트 하나에 동시에 있을 수 있는 희귀 알 수
}

-- ★v6 희귀 알이 벨트 끝에서 더 머무는 시간 (비키기 + 기다리기, 보통 알은 0)
function Config.BeltEggWait(eggId: string?): number
	local egg = if type(eggId) == "string" then Config.Eggs[eggId] else nil
	if egg and egg.Special then
		return Config.Conveyor.SpecialSlide + Config.Conveyor.SpecialWait
	end
	return 0
end

-- ★v5 벨트 위 알 자리: 나온 지 age 초 된 알의 피벗 위치 (흔들기 전) 와 단계
-- (1 = 슈트에서 떨어지는 중, 2 = 벨트 위, 3 = 통으로 떨어지는 중, 4 = 끝). 1~2 단계일 때 살 수 있어요
-- ★v6 eggId 를 주면 희귀 알은 끝 앞에서 옆으로 비켜 기다려요 (그동안도 2 단계). 서버·클라이언트 모두 eggId 를 넘겨요
function Config.BeltEggSpot(zone: number, age: number, eggId: string?): (Vector3, number)
	local def = Config.Zones[zone] or Config.Zones[1]
	local cv = Config.Conveyor
	local start, finish = def.ConveyorStart, def.ConveyorEnd
	local length = (finish - start).Magnitude
	local dir = (finish - start).Unit
	local speed = length / cv.TravelTime
	local t = math.max(0, age)
	local off = 0 -- 옆으로 비킨 거리
	local hold = Config.BeltEggWait(eggId)
	if hold > 0 then
		local stop = math.min(cv.SpecialStop, length)
		local arrive = cv.DropTime + (length - stop) / speed -- 끝 앞 stop 에 닿는 때
		if t >= arrive then
			off = cv.SpecialSide
			if t < arrive + hold then
				local a = math.min((t - arrive) / math.max(cv.SpecialSlide, 0.01), 1)
				off = cv.SpecialSide * a * a * (3 - 2 * a) -- 부드럽게 비켜요
				t = arrive
			else
				t -= hold -- 기다린 만큼 빼면 그다음은 보통 알과 같아요
			end
		end
	end
	local s, y, phase
	if t < cv.DropTime then
		local a = t / cv.DropTime
		s, y, phase = 0, cv.DropHeight + (cv.BeltTop - cv.DropHeight) * (a * a), 1
	elseif t < cv.DropTime + cv.TravelTime then
		s, y, phase = (t - cv.DropTime) * speed, cv.BeltTop, 2
	elseif t < cv.DropTime + cv.TravelTime + cv.FallTime then
		local ft = t - cv.DropTime - cv.TravelTime
		s, y, phase = length + ft * speed, cv.BeltTop - 1.4 * (ft / cv.FallTime) ^ 2, 3
	else
		s, y, phase = length + cv.FallTime * speed, cv.BeltTop - 1.4, 4
	end
	local pos = start + dir * s + Vector3.new(0, y, 0)
	if off > 0 then
		-- 코인 들판 쪽 (벨트와 수직). 숲 마을처럼 가운데면 +Z 쪽
		local side = Vector3.new(-dir.Z, 0, dir.X)
		if ((def.FieldMin + def.FieldMax) / 2 - start):Dot(side) < 0 then
			side = -side
		end
		pos += side * off
	end
	return pos, phase
end

-- ★v5 알이 벨트에 머무는 전체 시간 (이 뒤에는 서버·클라이언트 모두 목록에서 지워요). ★v6 eggId 를 주면 희귀 알은 더 길어요
function Config.BeltEggLife(eggId: string?): number
	local cv = Config.Conveyor
	return cv.DropTime + cv.TravelTime + cv.FallTime + Config.BeltEggWait(eggId)
end

-- ★v6 살 수 있는 마지막 나이 (통으로 떨어지기 시작할 때). 서버는 여기에 BuyGrace 를 더 봐줘요
function Config.BeltEggBuyEnd(eggId: string?): number
	local cv = Config.Conveyor
	return cv.DropTime + cv.TravelTime + Config.BeltEggWait(eggId)
end

-- 좋은 알 알림 (Remotes.EggAlert). 지역의 맨 위 알 2칸이 벨트에 나오면 그 지역이 열린 사람에게 보내요.
-- 맨 위 칸은 언제나, 둘째 칸은 벨트마다 Gap 초에 한 번만. 받는 사람: 그 지역이 열렸고,
-- (그 지역이 내 열린 지역 중 위에서 ZoneWindow 개 안에 있거나, 지금 그 지역 섬에 서 있을 때) → 다 큰 아이에게 숲 마을 알림이 쏟아지지 않게
-- ★v6 아주 희귀한 알 ("Rare") 은 이 규칙 없이 언제나 보내요 (Gap 시계도 건드리지 않아요)
Config.EggAlert = {
	Gap = 15,
	ZoneWindow = 2,
}

----------------------------------------------------------------------
-- 집(플롯). 한 층에 받침대 12개, 최대 10층 = 120개. 받침대 s 는 ceil(s / 12) 층.
-- 1층: 1~6 무료, 7~12 구매. 새 층을 올리면 그 층 첫 6개는 바로 열리고 나머지 6개는 구매.
----------------------------------------------------------------------
Config.Plot = {
	TotalSlots = 240, -- ★v8 1번 집 120 + 2번 집 120 (받침대 121~240 = 2번 집, Config.SlotHouse)
	SlotsPerFloor = 12,
	FreeSlotsPerFloor = 6, -- 층을 올리면 바로 열리는 받침대 수
	StartSlots = 6, -- 처음 열려 있는 받침대
	SlotPrices = {}, -- 아래에서 채워요: [받침대 번호] = 가격 (무료 받침대는 없음)
	OfflineRate = 0.5, -- 접속 안 했을 때 수익 비율
	OfflineMaxSeconds = 2 * 60 * 60,
}

-- 층 정보: Price = 층 올리기 가격, MinRebirth = 필요한 환생 수 (2층은 1층 받침대 12개를 다 열어야 해요.
-- 3층부터도 같은 규칙: 지금 있는 층의 받침대를 모두 연 뒤에 올릴 수 있어요)
Config.FloorInfo = {
	{ Price = 0, MinRebirth = 0 },
	{ Price = 300000, MinRebirth = 0 },
	{ Price = 5000000, MinRebirth = 1 },
	{ Price = 100000000, MinRebirth = 2 },
	{ Price = 800000000, MinRebirth = 3 },
	{ Price = 1.5e10, MinRebirth = 5 },
	{ Price = 2e11, MinRebirth = 7 },
	{ Price = 2.4e12, MinRebirth = 10 },
	{ Price = 2.4e13, MinRebirth = 13 },
	{ Price = 2e14, MinRebirth = 16 },
	-- ★v8 11~20층 = 2번 집 1~10층 (1번 집 옆에 지어요). 11층 = 2번 집 짓기: 1번 집 받침대 120개를 다 열고 환생 18회
	{ Price = 1.5e15, MinRebirth = 18 },
	{ Price = 4e15, MinRebirth = 19 },
	{ Price = 1e16, MinRebirth = 20 },
	{ Price = 2e16, MinRebirth = 21 },
	{ Price = 5e16, MinRebirth = 22 },
	{ Price = 1.2e17, MinRebirth = 23 },
	{ Price = 3e17, MinRebirth = 24 },
	{ Price = 2e18, MinRebirth = 26 },
	{ Price = 1.2e19, MinRebirth = 28 },
	{ Price = 7.5e19, MinRebirth = 30 },
}

-- 받침대 가격표: 1층 7~12 는 손으로, 2층부터는 층 가격 × 8% × 1.5^(k-1) (k = 그 층에서 몇 번째 구매)
do
	local floor1 = { 600, 2000, 6000, 16000, 40000, 100000 }
	for k, price in floor1 do
		Config.Plot.SlotPrices[6 + k] = price
	end
	-- 보기 좋은 숫자로 (1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 7.5 × 10^n)
	local function nice(x: number): number
		local e = 10 ^ math.floor(math.log10(x))
		local m = x / e
		for _, c in { 1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 7.5, 10 } do
			if m <= c * 1.0001 then
				return c * e
			end
		end
		return 10 * e
	end
	for f = 2, #Config.FloorInfo do
		local base = Config.FloorInfo[f].Price * 0.08
		for k = 1, Config.Plot.SlotsPerFloor - Config.Plot.FreeSlotsPerFloor do
			local slot = (f - 1) * Config.Plot.SlotsPerFloor + Config.Plot.FreeSlotsPerFloor + k
			Config.Plot.SlotPrices[slot] = nice(base * 1.5 ^ (k - 1))
		end
	end
end

-- 집 꾸미기. 테마가 비쌀수록 집이 크고(Size = 집 한 변) 수익 보너스(IncomeBonus)가 있어요.
-- 보너스는 집 받침대 수익에만: 초당 수익 = Σ ItemIncome × RebirthIncomeMult × (1 + IncomeBonus)
Config.House = {
	MaxFloors = 10, -- 집 한 채의 층 (1번 집도 2번 집도 10층까지)
	-- ★v8 저장되는 층 수 (data.Floors) 는 1~20: 11~20 = 2번 집 1~10층. 2번 집은 1번 집 테마를 같이 써요
	Houses = 2,
	TotalFloors = 20,
	FloorHeight = 12, -- 층 사이 높이 (f 층 바닥 윗면 = 0.2 + (f - 1) × 12, 슬래브 두께 1 → 천장 아래 11)
	FloorPrice = 300000, -- (예전 이름) = FloorInfo[2].Price
	Themes = {
		Basic = { Name = "기본 집", Price = 0, Size = 26, IncomeBonus = 0, Floor = RGB(190, 235, 170), Wall = RGB(255, 248, 225), Roof = RGB(230, 120, 100), Accent = RGB(255, 225, 90), Deco = "flowers" },
		Candy = { Name = "캔디 하우스", Price = 10000, Size = 30, IncomeBonus = 0.05, Floor = RGB(255, 205, 225), Wall = RGB(255, 240, 245), Roof = RGB(150, 230, 200), Accent = RGB(255, 120, 170), Deco = "candy" },
		Forest = { Name = "숲속 오두막", Price = 100000, Size = 32, IncomeBonus = 0.1, Floor = RGB(150, 200, 120), Wall = RGB(190, 140, 90), Roof = RGB(70, 130, 80), Accent = RGB(255, 160, 80), Deco = "mushrooms" },
		Ocean = { Name = "바다 집", Price = 1200000, Size = 36, IncomeBonus = 0.15, Floor = RGB(245, 230, 180), Wall = RGB(190, 230, 255), Roof = RGB(60, 140, 220), Accent = RGB(255, 150, 120), Deco = "shells" },
		Space = { Name = "우주 기지", Price = 16000000, Size = 40, IncomeBonus = 0.2, Floor = RGB(70, 60, 110), Wall = RGB(205, 210, 230), Roof = RGB(150, 90, 255), Accent = RGB(120, 240, 255), Deco = "stars" },
		Rainbow = { Name = "무지개 궁전", Price = 300000000, Size = 44, IncomeBonus = 0.25, Floor = RGB(255, 255, 255), Wall = RGB(255, 225, 240), Roof = RGB(255, 110, 150), Accent = RGB(255, 220, 80), Deco = "rainbow" },
		Palace = { Name = "왕궁", Price = 40000000000, Size = 48, IncomeBonus = 0.32, Floor = RGB(250, 238, 210), Wall = RGB(255, 252, 245), Roof = RGB(200, 60, 80), Accent = RGB(255, 200, 60), Deco = "royal" }, -- ★
		GalaxyPalace = { Name = "은하 궁전", Price = 4000000000000, Size = 52, IncomeBonus = 0.4, Floor = RGB(40, 30, 80), Wall = RGB(95, 75, 175), Roof = RGB(30, 20, 70), Accent = RGB(150, 230, 255), Deco = "galaxy" }, -- ★
	},
	ThemeOrder = { "Basic", "Candy", "Forest", "Ocean", "Space", "Rainbow", "Palace", "GalaxyPalace" },
}

----------------------------------------------------------------------
-- 펫 옷 (옷장). 한 번 사면 영원히 내 것, 펫 여러 마리가 같은 옷을 입어도 돼요. 펫 1마리 = 옷 1개.
-- Slot: 어디에 붙는지 ("Head" 머리 위 | "Face" 얼굴 앞 | "Neck" 목 | "Back" 등). 보기만 예뻐요 (능력치 없음)
----------------------------------------------------------------------
Config.Accessories = {
	PartyHat = { Name = "고깔모자", Price = 1000, Slot = "Head", Order = 1 },
	Sunglasses = { Name = "선글라스", Price = 3000, Slot = "Face", Order = 2 },
	BowTie = { Name = "나비넥타이", Price = 8000, Slot = "Neck", Order = 3 },
	FlowerCrown = { Name = "꽃 화관", Price = 25000, Slot = "Head", Order = 4 },
	Scarf = { Name = "목도리", Price = 80000, Slot = "Neck", Order = 5 },
	HeartGlasses = { Name = "하트 안경", Price = 250000, Slot = "Face", Order = 6 },
	Mustache = { Name = "콧수염", Price = 1000000, Slot = "Face", Order = 7 },
	TopHat = { Name = "신사 모자", Price = 5000000, Slot = "Head", Order = 8 },
	Backpack = { Name = "꼬마 가방", Price = 25000000, Slot = "Back", Order = 9 },
	Medal = { Name = "금메달", Price = 150000000, Slot = "Neck", Order = 10 },
	WizardHat = { Name = "마법사 모자", Price = 1000000000, Slot = "Head", Order = 11 },
	Cape = { Name = "망토", Price = 10000000000, Slot = "Back", Order = 12 },
	AngelWings = { Name = "천사 날개", Price = 100000000000, Slot = "Back", Order = 13 },
	Crown = { Name = "왕관", Price = 1000000000000, Slot = "Head", Order = 14 },
}
Config.AccessoryOrder = {
	"PartyHat", "Sunglasses", "BowTie", "FlowerCrown", "Scarf", "HeartGlasses", "Mustache",
	"TopHat", "Backpack", "Medal", "WizardHat", "Cape", "AngelWings", "Crown",
}

----------------------------------------------------------------------
-- 가구. 사면 FurnitureInv[id] += 1, 집에 놓으면 data.Furniture[fid] = { Id, Floor, X, Z, R }.
-- Size = (가로 X, 높이 Y, 세로 Z) 스터드, R = 0 일 때 앞쪽 = -Z. Collide = false 면 지나갈 수 있어요(러그).
----------------------------------------------------------------------
Config.Furniture = {
	PottedPlant = { Name = "화분", Price = 400, Size = V3(2, 3.5, 2), Category = "Plant", Order = 1, Collide = true },
	WoodChair = { Name = "나무 의자", Price = 600, Size = V3(2.5, 3.5, 2.5), Category = "Seat", Order = 2, Collide = true },
	PetBed = { Name = "펫 쿠션", Price = 1000, Size = V3(4, 1.2, 4), Category = "Bed", Order = 3, Collide = true },
	Rug = { Name = "동그란 러그", Price = 1500, Size = V3(8, 0.2, 8), Category = "Rug", Order = 4, Collide = false },
	RoundTable = { Name = "둥근 탁자", Price = 2500, Size = V3(4, 3, 4), Category = "Table", Order = 5, Collide = true },
	BeanBag = { Name = "빈백", Price = 4000, Size = V3(3.5, 2.5, 3.5), Category = "Seat", Order = 6, Collide = true },
	ToyBlocks = { Name = "장난감 블록", Price = 6000, Size = V3(3, 2, 3), Category = "Toy", Order = 7, Collide = true },
	Cactus = { Name = "선인장", Price = 10000, Size = V3(2, 4, 2), Category = "Plant", Order = 8, Collide = true },
	FloorLamp = { Name = "스탠드 조명", Price = 15000, Size = V3(1.6, 6, 1.6), Category = "Light", Order = 9, Collide = true },
	Sofa = { Name = "폭신 소파", Price = 25000, Size = V3(7, 3.5, 3), Category = "Seat", Order = 10, Collide = true },
	Bookshelf = { Name = "책장", Price = 50000, Size = V3(6, 7, 2), Category = "Deco", Order = 11, Collide = true },
	CatTower = { Name = "캣타워", Price = 100000, Size = V3(3, 7, 3), Category = "Toy", Order = 12, Collide = true },
	Bed = { Name = "침대", Price = 200000, Size = V3(6, 3, 8), Category = "Bed", Order = 13, Collide = true },
	StarLamp = { Name = "별 조명", Price = 500000, Size = V3(2, 2.5, 2), Category = "Light", Order = 14, Collide = true },
	RainbowRug = { Name = "무지개 러그", Price = 1000000, Size = V3(10, 0.2, 6), Category = "Rug", Order = 15, Collide = false },
	BallPit = { Name = "볼풀", Price = 3000000, Size = V3(8, 2.5, 8), Category = "Toy", Order = 16, Collide = true },
	Aquarium = { Name = "어항", Price = 10000000, Size = V3(5, 4, 2.5), Category = "Deco", Order = 17, Collide = true },
	Slide = { Name = "미끄럼틀", Price = 30000000, Size = V3(4, 6, 10), Category = "Toy", Order = 18, Collide = true },
	Fireplace = { Name = "벽난로", Price = 100000000, Size = V3(6, 6, 2.5), Category = "Deco", Order = 19, Collide = true },
	Piano = { Name = "피아노", Price = 500000000, Size = V3(6, 4.5, 3), Category = "Deco", Order = 20, Collide = true },
	GoldStatue = { Name = "황금 펫 동상", Price = 5000000000, Size = V3(3, 6, 3), Category = "Deco", Order = 21, Collide = true },
	Throne = { Name = "왕좌", Price = 50000000000, Size = V3(4, 7, 4), Category = "Seat", Order = 22, Collide = true },
}
Config.FurnitureOrder = {
	"PottedPlant", "WoodChair", "PetBed", "Rug", "RoundTable", "BeanBag", "ToyBlocks", "Cactus", "FloorLamp", "Sofa", "Bookshelf",
	"CatTower", "Bed", "StarLamp", "RainbowRug", "BallPit", "Aquarium", "Slide", "Fireplace", "Piano", "GoldStatue", "Throne",
}
Config.FurnitureCategories = {
	{ Id = "Seat", Name = "🪑 의자" },
	{ Id = "Table", Name = "🍽 탁자" },
	{ Id = "Bed", Name = "🛏 침대" },
	{ Id = "Light", Name = "💡 조명" },
	{ Id = "Plant", Name = "🪴 식물" },
	{ Id = "Rug", Name = "🟣 러그" },
	{ Id = "Toy", Name = "🧸 놀이" },
	{ Id = "Deco", Name = "🖼 장식" },
}
Config.Decor = {
	MaxPlaced = 80, -- 집 전체에 놓을 수 있는 가구 수
	MaxPerItem = 50, -- 같은 가구를 가방에 가질 수 있는 최대 수
	WallMargin = 0.5, -- 벽에서 띄우는 거리 (FloorBounds 안쪽으로)
	Snap = 0.5, -- X/Z 를 이 단위로 맞춰요
	Rotations = { 0, 90, 180, 270 },
}

-- 순위표 (OrderedDataStore). 못 쓰면 같은 서버 사람끼리만 보여 줘요
Config.Leaderboard = {
	IncomeStore = "PetWorldTopIncome_v3",
	RebirthStore = "PetWorldTopRebirths_v3",
	RefreshSeconds = 60, -- 순위 다시 읽기
	WriteSeconds = 120, -- 내 점수 쓰기 간격 (플레이어마다)
	TopN = 10,
}

-- 들판 코인 (플레이어마다 따로 보이고 따로 먹어요). 지역마다 따로 있어요
-- 코인 값 = Value × 지역 CoinMult × (1 + 집 초당 수익 / IncomeScale) × (1 + min(펫 보너스, MaxBoost)) × RebirthCoinMult
Config.FieldCoins = {
	CountPerZone = 40, -- 열린 지역마다 이만큼 (★v5 30 → 40)
	Count = 40, -- (예전 이름) = CountPerZone
	RespawnTime = 3, -- 먹은 코인이 다시 나오는 초 (★v5 5 → 3)
	IncomeScale = 30,
	MaxBoost = 3, -- 펫 보너스 합 최대 +300%
	MagnetRadius = 6, -- 기본 자석 반경
	MagnetPerFollower = 2, -- 따라오는 펫 1마리당 자석 반경 추가
	-- ★v5 자석 버튼 (Settings.Magnet 켜짐): 기본 자석 밖 BigMagnetRadius 안 코인도 하나씩 빨아들여요.
	-- 서 있기만 해도 너무 빨리 부자가 되지 않게 초당 BigMagnetRate 개까지만 (켜자마자는 BigMagnetBurst 개 한꺼번에)
	-- ★v6 더 넓고 조금 더 빠르게: 반경 45 → 80, 초당 1.2 → 1.6, 한꺼번에 6 → 8
	BigMagnetRadius = 100, -- ★v7.3 80 → 100
	BigMagnetRate = 1.6,
	BigMagnetBurst = 8,
	-- ★v6 슈퍼 자석 (Settings.SuperMagnet): 지금 서 있는 지역 코인만
	-- SuperMagnetRadius 안에서 초당 SuperMagnetRate 개씩 (다른 지역 코인은 절대 안 와요).
	-- 둘 다 켜면 슈퍼 자석이 이겨요 (길 위처럼 지역 밖이면 🧲 자석만). 시뮬: 지역 8 까지 ~10 시간 (v6_magnet/sim4.py)
	-- ★v7.2 환생 잠금 (예전 SuperMagnetMinRebirth = 1) 은 없어졌어요: 🧲 / ⚡ / 🏦 는 게임 패스 (Config.Passes)
	SuperMagnetRadius = 200, -- ★v7.3 150 → 200
	SuperMagnetRate = 2,
	SuperMagnetBurst = 12,
	RenderDistance = 160, -- 클라이언트는 이 거리 안 코인만 그려요
	Kinds = {
		{ Name = "Bronze", Value = 3, Weight = 80, Color = RGB(230, 150, 70), Size = 1.8 },
		{ Name = "Silver", Value = 12, Weight = 17, Color = RGB(215, 225, 240), Size = 2.2 },
		{ Name = "Gold", Value = 50, Weight = 3, Color = RGB(255, 210, 40), Size = 2.8 },
	},
}

----------------------------------------------------------------------
-- 맵 배치 (지역 1 = 숲 마을, 맵 한가운데). 바닥 윗면 y = 0. 컨베이어는 X 축 방향 (z = 0, x -56..56),
-- 집은 북쪽(+Z) 3채 / 남쪽(-Z) 3채, 한 변 64. 로비(스폰·순위표)는 서쪽 (x = -140).
-- 숲 마을 가장자리에서 7개 섬으로 가는 길 입구: 서쪽 z = ±80, 북쪽/남쪽 x = -150 과 120, 동쪽 z = 0 (Config.Zones[k].Trail)
-- 각 집 CFrame: 위치 = 집 땅 중심(y=0), LookVector = 입구 쪽(컨베이어 방향). 집 로컬 입구 = -Z (z = -32)
----------------------------------------------------------------------
local PLOT_SIZE = 64
local PLOT_ROW_Z = 80
local PLOT2_ROW_Z = 160 -- ★v8 2번 집 줄: 1번 집 바로 뒤 (1번 집 뒤 z 112 ~ 2번 집 앞 z 128 = 뒷골목 길)
local function plotCFrame(x: number, north: boolean, rowZ: number?): CFrame
	local row = rowZ or PLOT_ROW_Z
	local z = if north then row else -row
	local pos = V3(x, 0, z)
	return CFrame.lookAt(pos, V3(x, 0, 0))
end

local LOBBY = V3(-140, 0, 0)
Config.Layout = {
	PlotSize = PLOT_SIZE, -- 집 땅 한 변 (가장 큰 집 52 + 마당)
	Plots = {
		plotCFrame(-72, true),
		plotCFrame(0, true),
		plotCFrame(72, true),
		plotCFrame(-72, false),
		plotCFrame(0, false),
		plotCFrame(72, false),
	},
	-- ★v8 2번 집 자리 (Plots[i] 바로 뒤, 같은 쪽을 봐요). 2번 집이 없으면 빈 땅 + 간판
	Plots2 = {
		plotCFrame(-72, true, PLOT2_ROW_Z),
		plotCFrame(0, true, PLOT2_ROW_Z),
		plotCFrame(72, true, PLOT2_ROW_Z),
		plotCFrame(-72, false, PLOT2_ROW_Z),
		plotCFrame(0, false, PLOT2_ROW_Z),
		plotCFrame(72, false, PLOT2_ROW_Z),
	},
	-- (예전 이름) 지역 1 값과 같아요. 새 코드는 Config.Zones[i] 를 쓰세요
	ConveyorStart = Config.Zones[1].ConveyorStart,
	ConveyorEnd = Config.Zones[1].ConveyorEnd,
	FieldMin = Config.Zones[1].FieldMin,
	FieldMax = Config.Zones[1].FieldMax,
	ConveyorWidth = 8,
	FieldConveyorClearance = 7, -- 컨베이어 선분에서 이 거리 안에는 코인을 안 놓아요 (모든 지역)
	LobbySpawn = LOBBY, -- 집이 없을 때 / 지역 1 텔레포트 자리
	GroundSize = 315, -- (예전 이름) 지역 1 땅 가로
	-- 순위표 2개: 로비 서쪽, 앞면(LookVector)이 로비(+X) 쪽. 위치 = 판 아래 가운데 (y = 0)
	Leaderboards = {
		Income = CFrame.lookAt(V3(-165, 0, -28), V3(-140, 0, -28)),
		Rebirths = CFrame.lookAt(V3(-165, 0, 28), V3(-140, 0, 28)),
	},
	TrailLength = TRAIL_LENGTH, -- 숲 마을 가장자리 → 섬 입구 길 길이
	TrailWidth = TRAIL_WIDTH, -- 길 폭 (양옆 난간 높이 ≥ 4)
	SeaY = -3, -- 섬 사이 물 윗면 (CanCollide 끔, 장식)
	FallResetY = -30, -- 이보다 떨어지면 ZoneService 가 마지막 지역 스폰으로 돌려보내요 (물/구름/우주 바닥은 모두 이 위, 통과 가능)
}

-- 소리 (Studio 기본 내장 사운드만 사용. 나중에 rbxassetid 로 바꿔도 됨)
Config.Sounds = {
	Coin = "rbxasset://sounds/volume_slider.ogg",
	Click = "rbxasset://sounds/volume_slider.ogg",
	Hatch = "rbxasset://sounds/action_jump_land.mp3",
	Buy = "rbxasset://sounds/action_jump.mp3",
	Alert = "rbxasset://sounds/impact_water.mp3",
	Steal = "rbxasset://sounds/action_get_up.mp3", -- (예전 이름, 안 써도 남겨 둬요)
	-- ★v7 아주 희귀한 알 알림 소리 (단계마다 다른 소리, 로블록스 무료 효과음 라이브러리. 못 불러오면 UiKit 가 짧은 가락으로 대신)
	RareHidden = "rbxassetid://9116395089", -- 시크릿: 반짝이는 마법 종소리 (ProSoundEffects "Magic Glows Soft Clusters Of Chiming Hits 4")
	RareCelestial = "rbxassetid://1848271884", -- 천상: 하프 같은 동화 왈츠 끝맺음 (APM "Fairytown Waltz - Tag2")
	RareEternal = "rbxassetid://1842335078", -- 이터널: 귀여운 팡파르 (APM "Cartoon Fanfare (c)")
}

----------------------------------------------------------------------
-- 도우미 함수
----------------------------------------------------------------------

-- 가중치 표 { key = weight } 에서 하나 뽑기
function Config.WeightedPick(weights: { [string]: number }, rng: Random?): string
	local r = rng or Random.new()
	local total = 0
	for _, w in weights do
		total += w
	end
	local roll = r:NextNumber() * total
	local last = ""
	for key, w in weights do
		last = key
		roll -= w
		if roll <= 0 then
			return key
		end
	end
	return last
end

function Config.RollPet(eggId: string, rng: Random?): string
	local egg = Config.Eggs[eggId]
	assert(egg, "알 수 없는 알: " .. tostring(eggId))
	return Config.WeightedPick(egg.Pets, rng)
end

-- 컨베이어에 나올 알 뽑기. zoneIndex 를 주면 그 지역 알 중에서 (SpawnWeight 비율), 없으면 전체에서.
-- 늘 EggOrder 순서로 돌아서 같은 rng 면 같은 결과예요
function Config.RollEgg(rng: Random?, zoneIndex: number?): string
	local r = rng or Random.new()
	local list = if zoneIndex then Config.ZoneEggOrder[zoneIndex] or Config.EggOrder else Config.EggOrder
	local total = 0
	for _, id in list do
		total += Config.Eggs[id].SpawnWeight
	end
	local roll = r:NextNumber() * total
	for _, id in list do
		roll -= Config.Eggs[id].SpawnWeight
		if roll <= 0 then
			return id
		end
	end
	return list[#list]
end

-- 지역의 알 목록 (사다리 순, 싼 알 → 비싼 알)
function Config.ZoneEggs(zoneIndex: number): { string }
	return Config.ZoneEggOrder[zoneIndex] or {}
end

-- 사다리 칸 (1 = 제일 싼 알), 그 지역 알 수
function Config.EggRung(eggId: string): (number, number)
	local egg = Config.Eggs[eggId]
	if not egg then
		return 0, 0
	end
	return egg.Rung, egg.Rungs
end

-- 좋은 알 알림 대상 알인가 ("Top" = 맨 위 칸, "Second" = 둘째 칸, ★v6 "Rare" = 아주 희귀한 알, nil = 아님)
function Config.EggAlertKind(eggId: string): string?
	local egg = Config.Eggs[eggId]
	if not egg then
		return nil
	end
	if egg.Special then
		return "Rare"
	end
	if egg.Rung == egg.Rungs then
		return "Top"
	elseif egg.Rung == egg.Rungs - 1 then
		return "Second"
	end
	return nil
end

-- ★v6 아주 희귀한 알 도우미 ---------------------------------------------

-- 알의 희귀 단계 ("Hidden" | "Celestial" | "Eternal", 보통 알이면 nil)
function Config.EggSpecial(eggId: any): string?
	local egg = if type(eggId) == "string" then Config.Eggs[eggId] else nil
	return if egg then egg.Special else nil
end

function Config.IsSpecialEgg(eggId: any): boolean
	return Config.EggSpecial(eggId) ~= nil
end

-- 지역의 희귀 알 3개 { 시크릿, 천상, 이터널 }
function Config.ZoneSpecialEggs(zoneIndex: number): { string }
	return Config.ZoneSpecialEggOrder[zoneIndex] or {}
end

-- 지역 zone 의 tier 단계 희귀 알 id (없으면 nil)
function Config.SpecialEggOf(zoneIndex: number, tier: string): string?
	for _, id in Config.ZoneSpecialEggs(zoneIndex) do
		if Config.Eggs[id].Special == tier then
			return id
		end
	end
	return nil
end

-- 희귀 알에서 꼭 나오는 펫 (보통 알이면 nil)
function Config.SpecialPetOf(eggId: any): string?
	local egg = if type(eggId) == "string" then Config.Eggs[eggId] else nil
	return if egg and egg.Special then egg.Pet else nil
end

-- 보통 알 하나가 나올 때 그 벨트에 tier 단계 희귀 알이 나올 확률 (belts = 그 사람의 열린 벨트 수)
function Config.SpecialEggChance(tier: string, belts: number?): number
	local cfg = Config.SpecialEggs
	local base = cfg.Chance[tier] or 0
	return base / math.max(1, belts or 1) ^ cfg.BeltPower
end

-- 보통 알이 나올 때 같이 굴려요: 희귀 알 id 또는 nil. 단계마다 따로 굴리고, 둘 이상 맞으면 더 희귀한 것
function Config.RollSpecialEgg(rng: Random?, zoneIndex: number, belts: number?): string?
	local r = rng or Random.new()
	local tiers = Config.SpecialEggs.Tiers
	local hit: string? = nil
	for _, tier in tiers do
		if r:NextNumber() < Config.SpecialEggChance(tier, belts) then
			hit = tier -- 뒤(더 희귀한) 단계가 이겨요
		end
	end
	return if hit then Config.SpecialEggOf(zoneIndex, hit) else nil
end

-- 지역 도우미 ----------------------------------------------------------

-- 펫/알이 어느 지역 것인지 (모르면 1)
function Config.ZoneOf(petId: string): number
	local def = Config.Pets[petId]
	return if def and def.Zone then def.Zone else 1
end

function Config.EggZone(eggId: string): number
	local egg = Config.Eggs[eggId]
	return if egg and egg.Zone then egg.Zone else 1
end

-- 환생 rebirths 번이면 그 지역에 들어갈 수 있나
function Config.ZoneUnlocked(zoneIndex: number, rebirths: number?): boolean
	local zone = Config.Zones[zoneIndex]
	if not zone then
		return false
	end
	return (rebirths or 0) >= zone.MinRebirth
end

-- 열린 가장 먼 지역 번호 (1..MaxZone)
function Config.MaxZoneFor(rebirths: number?): number
	local best = 1
	for i, zone in Config.Zones do
		if (rebirths or 0) >= zone.MinRebirth then
			best = i
		end
	end
	return best
end

-- 알을 사려면 필요한 환생 수 (= 지역 MinRebirth)
function Config.EggMinRebirth(eggId: string): number
	return Config.Zones[Config.EggZone(eggId)].MinRebirth
end

-- 위치가 어느 지역 땅 위인지 (XZ 사각형). 길/물 위면 nil
function Config.ZoneAt(position: Vector3): number?
	for i, zone in Config.Zones do
		local d = position - zone.Center
		if math.abs(d.X) <= zone.Size.X / 2 and math.abs(d.Z) <= zone.Size.Z / 2 then
			return i
		end
	end
	return nil
end

-- 환생 도우미 ----------------------------------------------------------

-- 다음 환생 비용 (지금 환생 수 rebirths). 표를 넘으면 마지막 값 × 1.4^n
function Config.RebirthCost(rebirths: number): number
	local costs = Config.Rebirth.Costs
	local n = math.max(math.floor(rebirths or 0), 0) + 1
	if costs[n] then
		return costs[n]
	end
	return math.floor(costs[#costs] * 1.4 ^ (n - #costs))
end

function Config.RebirthIncomeMult(rebirths: number): number
	return 1 + Config.Rebirth.IncomePerRebirth * math.max(rebirths or 0, 0)
end

function Config.RebirthCoinMult(rebirths: number): number
	return 1 + Config.Rebirth.CoinPerRebirth * math.max(rebirths or 0, 0)
end

function Config.RebirthSpeedMult(rebirths: number): number
	return 1 + Config.Rebirth.SpeedPerRebirth * math.max(rebirths or 0, 0)
end

function Config.RebirthLuckMult(rebirths: number): number
	return 1 + Config.Rebirth.LuckPerRebirth * math.max(rebirths or 0, 0)
end

function Config.RebirthHatchTime(eggId: string, rebirths: number): number
	local egg = Config.Eggs[eggId]
	local base = if egg then egg.HatchTime else 10
	return math.max(3, math.floor(base / (1 + Config.Rebirth.HatchSpeedPerRebirth * math.max(rebirths or 0, 0))))
end

-- 부화 시 등급 뽑기 (1..MaxHatchTier). 환생 수만큼 운이 좋아져요 (합 최대 90%)
function Config.RollHatchTier(rebirths: number, rng: Random?): number
	local r = rng or Random.new()
	local luck = Config.RebirthLuckMult(rebirths)
	local roll = r:NextNumber()
	local acc = 0
	for tier = Config.MaxHatchTier, 2, -1 do
		acc += (Config.HatchTierChance[tier] or 0) * luck
		if roll < math.min(acc, 0.9) then
			return tier
		end
	end
	return 1
end

-- ★v7 이 펫의 크기 범위 { Min, Max, HugeFrom, TinyUntil } (희귀 펫은 PetSize.Special, 나머지·모르는 펫은 PetSize)
function Config.PetSizeRange(petId: any): any
	local def = if type(petId) == "string" then Config.Pets[petId] else nil
	local special = if def then Config.PetSize.Special[def.Rarity] else nil
	return special or Config.PetSize
end

-- 펫 크기 뽑기 (보통 크기 근처가 많이 나오게 두 번 뽑아 평균). ★v7 petId 를 주면 그 펫의 범위로 (없으면 보통 범위)
function Config.RollPetSize(rng: Random?, petId: string?): number
	local r = rng or Random.new()
	local range = Config.PetSizeRange(petId)
	local a = r:NextNumber(range.Min, range.Max)
	local b = r:NextNumber(range.Min, range.Max)
	return math.floor((a + b) / 2 * 100 + 0.5) / 100
end

-- 크기 정리 (없으면 1). ★v7 그 펫의 범위로 잘라요 (희귀 펫은 최대 1.5 / 1.7 / 2.0)
function Config.SizeOf(item: any): number
	local v = if type(item) == "table" then tonumber(item.Size) else nil
	if not v or v ~= v then
		return 1
	end
	local range = Config.PetSizeRange(if type(item) == "table" then item.Id else nil)
	return math.clamp(v, range.Min, range.Max)
end

-- ★v7 월드에 보이는 펫 크기 (모델 배율) ---------------------------------
-- 크기(Size) × 희귀도 ModelScale (시크릿 1.2 · 천상 1.4 · 이터널 1.6) × 희귀 펫만 등급마다 조금 (TierStep).
-- 자리(where)마다 상한이 있어요: 집 천장(층 사이 11)·문(14)·받침대 간격에 맞춰요. 보통 펫은 v6 그대로 (Size 배율).
-- 상한 근처에서는 부드럽게 다가가서 (넘지 않아요) 같은 펫이라도 Size 가 크면 조금이라도 더 커요.
Config.PetDisplay = {
	TierStep = 0.04, -- 희귀 펫 (ModelScale > 1) 등급 1단계마다 +4% (갤럭시 ×1.24)
	-- 자리마다 최대 모델 배율. Ride/Hold 는 Ride.Scale / Hold.Scale 을 곱한 뒤의 값
	Caps = {
		Slot = 2.2, -- 받침대 (PlotService 가 이웃·벽·천장에 맞춘 fit 도 같이 줘요)
		Follow = 2.2, -- 따라오기: 모자 쓴 제일 큰 펫도 천장(11) 아래 (0.4 뜸 + 0.7 흔들림 포함)
		Ride = 2.4, -- 타기: 펫 꼭대기 ≤ 10.4, 탄 키 ≈ 6.3 + 3.64 ≈ 9.9 (층 사이 11, 문 14 아래)
		Hold = 1.2, -- 들기 (머리 위)
	},
}

-- 부드러운 상한: knee 까지는 그대로, 그 위는 cap 에 천천히 다가가요 (넘지 않고, 계속 조금씩 커져요)
local function softCap(s: number, knee: number, cap: number): number
	if s <= knee then
		return s
	end
	local room = cap - knee
	if room <= 1e-6 then
		return math.min(s, cap)
	end
	return cap - room * math.exp(-(s - knee) / room)
end

-- 펫 모델 배율. where = "Slot" | "Follow" | "Ride" | "Hold" | nil (상한 없음).
-- fit = 부르는 쪽이 잰 자리 상한 (받침대: 이웃 받침대 간격의 절반·벽·계단 유리·천장). v6 크기보다 작게는 안 해요
function Config.PetDisplayScale(item: any, where: string?, fit: number?): number
	local size = Config.SizeOf(item)
	local def = if type(item) == "table" then Config.Pets[item.Id] else nil
	local info = if def then Config.Rarities[def.Rarity] else nil
	local ms = if info and type(info.ModelScale) == "number" then math.max(info.ModelScale, 1) else 1
	local s = size * ms
	if ms > 1 then
		local tier = math.clamp(math.floor(tonumber(item.Tier) or 1), 1, Config.MaxTier)
		s *= 1 + Config.PetDisplay.TierStep * (tier - 1)
	end
	local mult = if where == "Ride" then Config.Ride.Scale elseif where == "Hold" then Config.Hold.Scale else 1
	s *= mult
	local cap = if where then Config.PetDisplay.Caps[where] else nil
	if not cap then
		return s
	end
	-- v6 크기 (보통 펫 최대 크기까지) 는 그대로 두고, 그 위만 상한에 맞춰요
	local base = math.min(size, Config.PetSize.Max) * mult
	local limit = cap
	if type(fit) == "number" and fit == fit then
		limit = math.min(limit, fit)
	end
	limit = math.max(limit, base)
	local knee = math.min(Config.PetSize.Max * mult, limit)
	return softCap(s, knee, limit)
end

-- ★v7 탈 때 HipHeight 추가: 희귀 펫이 Ride.Scale 보다 크게 보이면 그만큼 등 높이도 올라가요 (보통 펫은 v6 그대로).
-- rideScale = 실제로 쓴 타기 배율 (없으면 PetDisplayScale(item, "Ride"))
function Config.RideHipAdd(item: any, rideScale: number?): number
	local def = if type(item) == "table" then Config.Pets[item.Id] else nil
	local info = if def then Config.Rarities[def.Rarity] else nil
	local add = Config.Ride.HipHeightAdd
	if info and type(info.ModelScale) == "number" and info.ModelScale > 1 then
		local k = if type(rideScale) == "number" then rideScale else Config.PetDisplayScale(item, "Ride")
		add *= math.max(1, k / Config.Ride.Scale)
	end
	return add
end

-- "거대" / "꼬마" / "" 표시. ★v7 petId 를 주면 그 펫의 범위 기준 (희귀 펫은 더 커야 "거대")
function Config.SizeLabel(size: number, petId: string?): string
	local range = Config.PetSizeRange(petId)
	if size >= range.HugeFrom then
		return "거대"
	elseif size <= range.TinyUntil then
		return "꼬마"
	end
	return ""
end

-- 무게 (kg, 소수 1자리)
function Config.PetWeight(petId: string, size: number): number
	local def = Config.Pets[petId]
	local base = if def and def.Weight then def.Weight else Config.PetSize.BaseWeight
	return math.floor(base * size ^ 3 * 10 + 0.5) / 10
end

-- 등급 도우미 ----------------------------------------------------------

-- 등급 정보 (1~MaxTier 로 잘라서)
function Config.TierInfo(tier: number?): any
	local t = math.clamp(math.floor(tonumber(tier) or 1), 1, Config.MaxTier)
	return Config.Tiers[t]
end

-- 등급 모양 정보 (PetModels.applyTier 용)
function Config.TierVisual(tier: number?): any
	return Config.TierInfo(tier).Visual
end

-- "골드 병아리" 같은 표시 이름
function Config.PetDisplayName(petId: string, tier: number?): string
	local def = Config.Pets[petId]
	local name = if def then def.Name else tostring(petId)
	local info = Config.TierInfo(tier)
	return if info.Name ~= "" then info.Name .. " " .. name else name
end

-- 펫 1마리의 초당 수익 (등급 배율 포함, 크기·환생·집 보너스 제외)
function Config.PetIncome(petId: string, tier: number?): number
	local def = Config.Pets[petId]
	if not def then
		return 0
	end
	return def.Income * Config.TierInfo(tier).IncomeMult
end

-- 펫 1마리의 코인 보너스 (등급 배율 포함)
function Config.PetBoost(petId: string, tier: number?): number
	local def = Config.Pets[petId]
	if not def then
		return 0
	end
	return def.Boost * Config.TierInfo(tier).BoostMult
end

-- 아이템(Item 테이블)의 초당 수익 (등급 × 크기). 알은 0.
-- 환생 배율 × 집 테마 보너스는 호출하는 쪽에서 Config.IncomeMultiplier 로 곱해요 (DataService.GetIncome 이 해 줌)
function Config.ItemIncome(item: any): number
	if type(item) ~= "table" or item.Kind ~= "Pet" then
		return 0
	end
	return math.floor(Config.PetIncome(item.Id, item.Tier) * Config.SizeOf(item) * 100 + 0.5) / 100
end

-- 아이템의 코인 보너스 (등급 포함)
function Config.ItemBoost(item: any): number
	if type(item) ~= "table" or item.Kind ~= "Pet" then
		return 0
	end
	return Config.PetBoost(item.Id, item.Tier)
end

-- 가방/자동 배치 정렬: a 가 b 보다 앞이면 true.
-- 펫 먼저 (ItemIncome 큰 순 → 등급 높은 순 → 희귀도 높은 순 → uid 작은 순), 그다음 알 (희귀도 높은 순 → uid)
function Config.CompareItems(aUid: string, a: any, bUid: string, b: any): boolean
	local aPet = type(a) == "table" and a.Kind == "Pet"
	local bPet = type(b) == "table" and b.Kind == "Pet"
	if aPet ~= bPet then
		return aPet
	end
	if aPet then
		local ia, ib = Config.ItemIncome(a), Config.ItemIncome(b)
		if ia ~= ib then
			return ia > ib
		end
		local ta, tb = tonumber(a.Tier) or 1, tonumber(b.Tier) or 1
		if ta ~= tb then
			return ta > tb
		end
	end
	local function order(it: any): number
		local def = if type(it) ~= "table" then nil elseif it.Kind == "Pet" then Config.Pets[it.Id] else Config.Eggs[it.Id]
		local rarity = if def then Config.Rarities[def.Rarity] else nil
		return if rarity then rarity.Order else 0
	end
	local oa, ob = order(a), order(b)
	if oa ~= ob then
		return oa > ob
	end
	local na = tonumber(string.match(aUid, "%d+")) or 0
	local nb = tonumber(string.match(bUid, "%d+")) or 0
	if na ~= nb then
		return na < nb
	end
	return aUid < bUid
end

-- 이 위치의 펫을 합성 재료로 쓸 수 있나 (집 받침대 위 펫은 안 돼요)
function Config.CanFuseLoc(loc: any): boolean
	return type(loc) == "string" and Config.FuseLocs[loc] == true
end

-- ★v7 아주 희귀한 펫인가 (시크릿 / 천상 / 이터널)
function Config.IsRarePet(petId: any): boolean
	local def = if type(petId) == "string" then Config.Pets[petId] else nil
	local info = if def then Config.Rarities[def.Rarity] else nil
	return info ~= nil and info.Special == true
end

-- 펫 타기 속도 배율. ★v7 희귀 펫은 크기만큼 더 빨라요: × (Size / 범위 Min) ^ Ride.SizePower
-- (size 를 안 주면 1). 보통 펫은 v6 그대로 (size 를 봐도 안 바뀌어요)
function Config.RideSpeedMultiplier(petId: string, tier: number?, size: number?): number
	local def = Config.Pets[petId]
	local order = if def and Config.Rarities[def.Rarity] then Config.Rarities[def.Rarity].Order else 1
	local t = math.clamp(math.floor(tonumber(tier) or 1), 1, Config.MaxTier)
	local mult = Config.Ride.BaseMultiplier + Config.Ride.PerRarityOrder * (order - 1) + Config.Ride.PerTier * (t - 1)
	if Config.IsRarePet(petId) then
		local range = Config.PetSizeRange(petId)
		local s = tonumber(size) or 1
		if s ~= s then
			s = 1
		end
		s = math.clamp(s, range.Min, range.Max)
		mult *= (s / range.Min) ^ Config.Ride.SizePower
	end
	return mult
end

-- ★v7 속도 상한: knee 까지는 그대로, 그 위는 cap 에 부드럽게 다가가요 (넘지 않고, 빠를수록 조금이라도 더 빨라요).
-- cap 이 knee 이하이면 knee 에서 딱 잘라요 (보통 펫 = v6 그대로). FollowService.UpdateSpeed 가 걷기·날기에 써요
function Config.SoftSpeedCap(speed: number, knee: number, cap: number?): number
	if speed ~= speed then
		return 0
	end
	if not cap or cap <= knee then
		return math.min(speed, knee)
	end
	if speed <= knee then
		return speed
	end
	local room = cap - knee
	return cap - room * math.exp(-(speed - knee) / room)
end

-- 펫 판매 가격
function Config.SellPrice(petId: string, tier: number?): number
	return Config.PetIncome(petId, tier) * 20
end

-- ★v7.1 한꺼번에 팔기 / 자동 판매 조건 (위치는 안 봐요: 한꺼번에 팔기는 부르는 쪽이 Loc == "Bag" 만).
-- 펫만, 옷 안 입음, 🥇 골드 미만, 시크릿·천상·이터널 아님, 테마(지역) ≤ zoneMax, 등급(희귀도 Order) ≤ rarityMax
function Config.SellMatch(item: any, zoneMax: any, rarityMax: any): boolean
	if type(item) ~= "table" or item.Kind ~= "Pet" or item.Acc ~= nil then
		return false
	end
	local pet = Config.Pets[item.Id]
	local rarity = if pet then Config.Rarities[pet.Rarity] else nil
	if not rarity or rarity.Special then
		return false
	end
	local tier = tonumber(item.Tier) or 1
	if tier >= Config.BulkSell.KeepTier then
		return false
	end
	return type(zoneMax) == "number"
		and type(rarityMax) == "number"
		and Config.ZoneOf(item.Id) <= zoneMax
		and rarity.Order <= math.min(rarityMax, Config.SellRarityTop)
end

-- 집 도우미 ------------------------------------------------------------

-- 테마 정보 (모르는 id 는 Basic)
function Config.ThemeOf(themeId: any): any
	local themes = Config.House.Themes
	return if type(themeId) == "string" and themes[themeId] then themes[themeId] else themes.Basic
end

-- 집 테마 수익 보너스 (0.4 = +40%)
function Config.ThemeIncomeBonus(themeId: any): number
	return Config.ThemeOf(themeId).IncomeBonus or 0
end

-- 집 테마 크기 (집 한 변 스터드)
function Config.ThemeSize(themeId: any): number
	return Config.ThemeOf(themeId).Size or 26
end

-- 집 받침대 수익에 곱하는 전체 배율 = 환생 배율 × (1 + 테마 보너스)
function Config.IncomeMultiplier(rebirths: number, themeId: any): number
	return Config.RebirthIncomeMult(rebirths) * (1 + Config.ThemeIncomeBonus(themeId))
end

-- 받침대가 몇 층에 있는지 (1..TotalFloors. ★v8 11~20 = 2번 집)
function Config.SlotFloor(slot: number): number
	return math.max(1, math.ceil(slot / Config.Plot.SlotsPerFloor))
end

-- ★v8 2번 집 도우미 ---------------------------------------------------
-- 층 번호(1..20)는 집 두 채를 이어서 세요: 1~10 = 1번 집, 11~20 = 2번 집 1~10층. 받침대도 1~120 / 121~240

-- 이 층이 몇 번 집 몇 층인지 (집 번호, 그 집 안 층)
function Config.FloorHouse(floor: number): (number, number)
	local per = Config.House.MaxFloors
	local f = math.max(1, math.floor(tonumber(floor) or 1))
	local house = math.min(math.ceil(f / per), Config.House.Houses)
	return house, f - (house - 1) * per
end

-- 이 받침대가 몇 번 집에 있는지 (집 번호, 그 집 안 받침대 번호 1..120)
function Config.SlotHouse(slot: number): (number, number)
	local perHouse = Config.House.MaxFloors * Config.Plot.SlotsPerFloor
	local s = math.max(1, math.floor(tonumber(slot) or 1))
	local house = math.min(math.ceil(s / perHouse), Config.House.Houses)
	return house, s - (house - 1) * perHouse
end

-- 층 수(data.Floors) 중 house 번 집에 지어진 층 수 (0 = 아직 없음)
function Config.HouseFloorCount(floors: number, house: number): number
	local per = Config.House.MaxFloors
	return math.clamp(math.floor(tonumber(floors) or 1) - (house - 1) * per, 0, per)
end

-- 화면에 보여 줄 층 이름: "3층" / "2번 집 3층"
function Config.FloorName(floor: number): string
	local house, f = Config.FloorHouse(floor)
	if house <= 1 then
		return f .. "층"
	end
	return house .. "번 집 " .. f .. "층"
end

-- 집 자리 (집 로컬 원점, 입구 = -Z). house 2 = 2번 집 자리 (없는 번호면 nil)
function Config.PlotOrigin(plotIndex: number, house: number?): CFrame?
	local list = if house == 2 then Config.Layout.Plots2 else Config.Layout.Plots
	return list[plotIndex]
end

-- floor 층을 올리자마자 열려 있는 받침대 수 (그 층 첫 6개까지)
function Config.FloorStartSlots(floor: number): number
	if floor <= 1 then
		return Config.Plot.StartSlots
	end
	return (floor - 1) * Config.Plot.SlotsPerFloor + Config.Plot.FreeSlotsPerFloor
end

-- floor 층을 올리는 조건 { Price, MinRebirth } (없는 층이면 nil)
function Config.FloorRequirement(floor: number): any
	return Config.FloorInfo[floor]
end

-- 다음 층을 올릴 수 있나: (true) 또는 (false, 이유 "Max" | "Slots" | "Rebirth")
-- 돈은 따로 확인해요 (가격 = Config.FloorInfo[floors + 1].Price)
function Config.CanBuyFloor(floors: number, slotsUnlocked: number, rebirths: number): (boolean, string?)
	local nextFloor = floors + 1
	local info = Config.FloorInfo[nextFloor]
	if not info or nextFloor > Config.House.TotalFloors then -- ★v8 2번 집까지 20층
		return false, "Max"
	end
	if slotsUnlocked < floors * Config.Plot.SlotsPerFloor then
		return false, "Slots"
	end
	if rebirths < info.MinRebirth then
		return false, "Rebirth"
	end
	return true, nil
end

-- 다음 받침대 가격 (더 살 수 없으면 nil: 최대이거나 다음 층을 먼저 올려야 할 때)
function Config.NextSlotPrice(slotsUnlocked: number, floors: number?): number?
	local nextSlot = slotsUnlocked + 1
	if nextSlot > Config.Plot.TotalSlots then
		return nil
	end
	if Config.SlotFloor(nextSlot) > (floors or 1) then
		return nil -- 다음 층을 먼저 올려야 해요
	end
	return Config.Plot.SlotPrices[nextSlot]
end

-- 옷/가구 도우미 -------------------------------------------------------

function Config.AccessoryValid(accId: any): boolean
	return type(accId) == "string" and Config.Accessories[accId] ~= nil
end

-- 회전 R(0/90/180/270)을 적용한 가구 바닥 크기 (가로 X, 세로 Z)
function Config.FurnitureFootprint(furnId: string, r: number?): (number, number)
	local def = Config.Furniture[furnId]
	if not def then
		return 0, 0
	end
	local rot = math.floor(((r or 0) % 360) / 90 + 0.5) % 4
	if rot == 1 or rot == 3 then
		return def.Size.Z, def.Size.X
	end
	return def.Size.X, def.Size.Z
end

-- 숫자 ----------------------------------------------------------------

-- 1234567 -> "1.2M" 같은 짧은 표기 (K, M, B, T, Qa, Qi, ★v8 Sx, Sp, Oc, No, Dc)
-- ★v8 Sx (1e21) · Sp (1e24) · Oc (1e27) · No (1e30) · Dc (1e33) 까지
local SUFFIXES = {
	{ 1e33, "Dc" }, { 1e30, "No" }, { 1e27, "Oc" }, { 1e24, "Sp" }, { 1e21, "Sx" },
	{ 1e18, "Qi" }, { 1e15, "Qa" }, { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e4, "K" },
}
function Config.FormatNumber(n: number): string
	n = math.floor(tonumber(n) or 0)
	for _, s in SUFFIXES do
		if n >= s[1] then
			local div = if s[2] == "K" then 1e3 else s[1]
			local v = n / div
			-- 100 이상은 정수, 아니면 소수 1자리 (".0" 은 떼요): 12.3K, 300K, 2M
			local text = if v >= 100 then string.format("%d", math.floor(v)) else string.format("%.1f", math.floor(v * 10) / 10)
			text = string.gsub(text, "%.0$", "")
			return text .. s[2]
		end
	end
	return tostring(n)
end

return Config
