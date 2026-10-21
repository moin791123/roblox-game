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
Config.Settings = {
	HideHatch = false, -- 알 까는 화면 숨기기 (작은 알림만)
	AutoCollect = false, -- 집에 모인 돈 자동으로 먹기
	Magnet = false, -- 맵 돈 자석 (넓은 범위 자동으로 먹기)
}
Config.MaxFollow = 3 -- 데리고 다닐 수 있는 펫 수
Config.MaxBagItems = 150 -- 가방 최대 칸 (Loc == "Bag" 인 아이템 수)
Config.BaseWalkSpeed = 18
Config.WalkSpeedPerFollower = 0.5
Config.MaxWalkSpeed = 64 -- FollowService.UpdateSpeed 가 이 값으로 잘라요

-- 희귀도 (Order: 낮을수록 흔함). Income/Boost = 지역 1 기준 비율 (실제 값은 펫마다 적혀 있어요)
Config.Rarities = {
	Common = { Name = "보통", Color = RGB(170, 175, 185), Order = 1, Boost = 0.03 },
	Uncommon = { Name = "고급", Color = RGB(95, 205, 110), Order = 2, Boost = 0.05 },
	Rare = { Name = "희귀", Color = RGB(70, 150, 255), Order = 3, Boost = 0.08 },
	Epic = { Name = "영웅", Color = RGB(180, 90, 255), Order = 4, Boost = 0.12 },
	Legendary = { Name = "전설", Color = RGB(255, 180, 30), Order = 5, Boost = 0.18 },
	Mythic = { Name = "신화", Color = RGB(255, 80, 160), Order = 6, Boost = 0.25 },
	Secret = { Name = "비밀", Color = RGB(120, 240, 255), Order = 7, Boost = 0.4 }, -- 지역마다 1마리
}
Config.RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

----------------------------------------------------------------------
-- 지역 (맵). v4: 숲 마을(집 6채 + 로비 + 컨베이어)이 가운데 있고, 지역 2~8 은 그 둘레의 섬이에요.
-- 환생 MinRebirth 번 이상이면 들어갈 수 있어요. 바닥 윗면은 어디나 y = 0. Size.Y = 땅 두께 (윗면 y = 0).
-- 섬마다 짧은 길(Trail, 30 스터드)이 숲 마을 가장자리에서 바로 시작하고, 길이 시작하는 곳(숲 마을 쪽 끝)에
-- 입구 문(Gate)이 있어서 집 앞에서도 잠긴 문("🔒 환생 N회")이 다 보여요.
-- 로비(서쪽, 스폰이 +X 를 봐요)에서 보면 왼쪽 뒤부터 시계 방향으로 한 바퀴:
--   2 호수 (서쪽 왼편) → 3 정글 (왼쪽) → 4 겨울 산 (왼쪽 앞) → 5 바다 (정면 끝) → 6 캔디 랜드 (오른쪽 앞)
--   → 7 구름 왕국 (오른쪽) → 8 우주 (서쪽 오른편)
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
		Size = V3(315, 4, 250), -- x -180..135, z -125..125 (집 6채 + 로비 + 컨베이어). 둘레에 섬 7개
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
	}, { Mouth = V3(-150, 0, -125), Dir = SOUTH, Center = V3(-105, 0, -235) }),
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
	}, { Mouth = V3(120, 0, -125), Dir = SOUTH, Center = V3(125, 0, -235) }),
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
	}, { Mouth = V3(120, 0, 125), Dir = NORTH, Center = V3(125, 0, 235) }),
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
	}, { Mouth = V3(-150, 0, 125), Dir = NORTH, Center = V3(-105, 0, 235) }),
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
}
Config.MaxZone = #Config.Zones

----------------------------------------------------------------------
-- 펫. Zone = 지역 번호. Income = 집 받침대 위에서 1초마다 버는 코인 (지역마다 ×5 정도라서
-- 다음 지역의 보통 펫이 이전 지역의 전설 펫보다 세요). Boost 는 아래에서 희귀도·지역으로 채워요.
-- Color 는 UI 강조색 (모델 색은 PetModels 가 정함). ★ = v3 새 펫
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

	-- 2. 호수
	Duck = { Name = "오리", Rarity = "Common", Zone = 2, Income = 10, Color = RGB(255, 240, 150) },
	Frog = { Name = "개구리", Rarity = "Common", Zone = 2, Income = 12, Color = RGB(120, 210, 90) },
	Hedgehog = { Name = "고슴도치", Rarity = "Uncommon", Zone = 2, Income = 15, Color = RGB(150, 110, 80) },
	Squirrel = { Name = "다람쥐", Rarity = "Rare", Zone = 2, Income = 22, Color = RGB(200, 130, 70) },
	Raccoon = { Name = "라쿤", Rarity = "Epic", Zone = 2, Income = 32, Color = RGB(140, 140, 150) },
	Turtle = { Name = "거북이", Rarity = "Legendary", Zone = 2, Income = 45, Color = RGB(110, 190, 120) },
	Axolotl = { Name = "우파루파", Rarity = "Mythic", Zone = 2, Income = 70, Color = RGB(255, 160, 200) },
	MoonKoi = { Name = "달빛 잉어", Rarity = "Secret", Zone = 2, Income = 120, Color = RGB(255, 245, 200) }, -- ★

	-- 3. 정글
	Monkey = { Name = "원숭이", Rarity = "Common", Zone = 3, Income = 50, Color = RGB(170, 120, 80) },
	Parrot = { Name = "앵무새", Rarity = "Common", Zone = 3, Income = 60, Color = RGB(90, 200, 110) },
	Koala = { Name = "코알라", Rarity = "Uncommon", Zone = 3, Income = 75, Color = RGB(160, 165, 175) },
	Bear = { Name = "곰돌이", Rarity = "Rare", Zone = 3, Income = 110, Color = RGB(165, 110, 70) },
	Lion = { Name = "사자", Rarity = "Epic", Zone = 3, Income = 160, Color = RGB(240, 185, 80) },
	Panda = { Name = "판다", Rarity = "Legendary", Zone = 3, Income = 225, Color = RGB(245, 245, 245) },
	Peacock = { Name = "공작새", Rarity = "Mythic", Zone = 3, Income = 350, Color = RGB(60, 170, 220) }, -- ★
	WhiteTiger = { Name = "백호", Rarity = "Secret", Zone = 3, Income = 600, Color = RGB(235, 245, 255) }, -- ★

	-- 4. 겨울 산
	Penguin = { Name = "펭귄", Rarity = "Common", Zone = 4, Income = 240, Color = RGB(70, 90, 130) },
	Seal = { Name = "바다표범", Rarity = "Common", Zone = 4, Income = 290, Color = RGB(225, 230, 240) },
	SnowBunny = { Name = "눈토끼", Rarity = "Uncommon", Zone = 4, Income = 360, Color = RGB(240, 245, 255) },
	Snowman = { Name = "눈사람", Rarity = "Rare", Zone = 4, Income = 530, Color = RGB(250, 250, 255) },
	PolarBear = { Name = "북극곰", Rarity = "Epic", Zone = 4, Income = 770, Color = RGB(245, 245, 250) },
	Reindeer = { Name = "순록", Rarity = "Legendary", Zone = 4, Income = 1080, Color = RGB(180, 130, 90) },
	FrostFox = { Name = "눈꽃 여우", Rarity = "Mythic", Zone = 4, Income = 1700, Color = RGB(170, 220, 255) }, -- ★
	Yeti = { Name = "예티", Rarity = "Secret", Zone = 4, Income = 2900, Color = RGB(200, 230, 255) }, -- ★

	-- 5. 바다
	Crab = { Name = "게", Rarity = "Common", Zone = 5, Income = 1200, Color = RGB(255, 120, 90) },
	Jellyfish = { Name = "해파리", Rarity = "Common", Zone = 5, Income = 1450, Color = RGB(190, 160, 255) },
	Octopus = { Name = "문어", Rarity = "Uncommon", Zone = 5, Income = 1800, Color = RGB(255, 130, 160) },
	BabyShark = { Name = "아기 상어", Rarity = "Rare", Zone = 5, Income = 2650, Color = RGB(120, 170, 230) },
	Dolphin = { Name = "돌고래", Rarity = "Epic", Zone = 5, Income = 3850, Color = RGB(120, 180, 240) },
	Narwhal = { Name = "일각고래", Rarity = "Legendary", Zone = 5, Income = 5400, Color = RGB(150, 200, 240) }, -- ★
	MermaidCat = { Name = "인어 냥이", Rarity = "Mythic", Zone = 5, Income = 8400, Color = RGB(100, 220, 210) }, -- ★
	DragonKing = { Name = "용왕", Rarity = "Secret", Zone = 5, Income = 14500, Color = RGB(60, 200, 170) }, -- ★

	-- 6. 캔디 랜드
	CottonSheep = { Name = "솜사탕 양", Rarity = "Common", Zone = 6, Income = 6000, Color = RGB(255, 190, 230) },
	DonutPuppy = { Name = "도넛 강아지", Rarity = "Common", Zone = 6, Income = 7200, Color = RGB(255, 160, 190) },
	JellyBear = { Name = "젤리곰", Rarity = "Uncommon", Zone = 6, Income = 9000, Color = RGB(255, 90, 110) },
	CupcakeCat = { Name = "컵케이크 냥이", Rarity = "Rare", Zone = 6, Income = 13000, Color = RGB(255, 210, 230) },
	MacaronBunny = { Name = "마카롱 토끼", Rarity = "Epic", Zone = 6, Income = 19000, Color = RGB(190, 240, 210) },
	GummyDragon = { Name = "젤리 용", Rarity = "Legendary", Zone = 6, Income = 27000, Color = RGB(255, 120, 80) }, -- ★
	CandyUnicorn = { Name = "사탕 유니콘", Rarity = "Mythic", Zone = 6, Income = 42000, Color = RGB(255, 175, 215) }, -- ★
	CookieKing = { Name = "쿠키 왕", Rarity = "Secret", Zone = 6, Income = 72000, Color = RGB(205, 140, 80) }, -- ★

	-- 7. 구름 왕국
	Sheep = { Name = "양", Rarity = "Common", Zone = 7, Income = 30000, Color = RGB(250, 245, 235) },
	CloudPuppy = { Name = "구름 강아지", Rarity = "Common", Zone = 7, Income = 36000, Color = RGB(235, 245, 255) }, -- ★
	BabyCloud = { Name = "아기 구름", Rarity = "Uncommon", Zone = 7, Income = 45000, Color = RGB(220, 235, 255) }, -- ★
	Dragon = { Name = "아기 용", Rarity = "Rare", Zone = 7, Income = 66000, Color = RGB(110, 215, 140) },
	Unicorn = { Name = "유니콘", Rarity = "Epic", Zone = 7, Income = 96000, Color = RGB(250, 225, 255) },
	Pegasus = { Name = "페가수스", Rarity = "Legendary", Zone = 7, Income = 135000, Color = RGB(240, 248, 255) }, -- ★
	Phoenix = { Name = "불사조", Rarity = "Mythic", Zone = 7, Income = 210000, Color = RGB(255, 110, 50) },
	AngelBunny = { Name = "천사 토끼", Rarity = "Secret", Zone = 7, Income = 360000, Color = RGB(255, 240, 170) }, -- ★

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
	"Chick", "Bunny", "Hamster", "Piglet", "Puppy", "Cat", "Owl", "Fox", "RainbowCat", "SpiritDeer",
	"Duck", "Frog", "Hedgehog", "Squirrel", "Raccoon", "Turtle", "Axolotl", "MoonKoi",
	"Monkey", "Parrot", "Koala", "Bear", "Lion", "Panda", "Peacock", "WhiteTiger",
	"Penguin", "Seal", "SnowBunny", "Snowman", "PolarBear", "Reindeer", "FrostFox", "Yeti",
	"Crab", "Jellyfish", "Octopus", "BabyShark", "Dolphin", "Narwhal", "MermaidCat", "DragonKing",
	"CottonSheep", "DonutPuppy", "JellyBear", "CupcakeCat", "MacaronBunny", "GummyDragon", "CandyUnicorn", "CookieKing",
	"Sheep", "CloudPuppy", "BabyCloud", "Dragon", "Unicorn", "Pegasus", "Phoenix", "AngelBunny",
	"Alien", "RobotPuppy", "MoonBunny", "SpaceCat", "AstroBear", "CometFox", "StarSlime", "CosmicWhale",
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
	egg.Premium = egg.Rung >= rungs - 1 -- 위 2칸 = 좋은 알
	-- 알의 MinRebirth = 지역 MinRebirth (예전 코드가 egg.MinRebirth 를 읽어도 맞게)
	egg.MinRebirth = Config.Zones[egg.Zone].MinRebirth
end
for k, zone in Config.Zones do
	zone.Eggs = Config.ZoneEggOrder[k] or {}
end

----------------------------------------------------------------------
-- 환생: 코인(수금 대기 포함)을 0으로 돌리는 대신 영구 보너스. 펫·집·받침대·테마·옷·가구는 그대로.
-- Costs[n] = n 번째 환생 비용 (지금 환생 수가 n-1 일 때). sim3.py 로 맞춘 값이에요.
----------------------------------------------------------------------
Config.Rebirth = {
	Costs = {
		8e5, 1.2e7, 2.4e8, 2e9, 8e9, 4e10, 1.2e11, 5e11, 1.2e12, 3e12, -- 1~10 (지역 2,3,4 는 환생 1,2,3)
		6e12, 2e13, 3e13, 6e13, 1.2e14, 2.4e14, 5e14, 1e15, 1.5e15, 2.4e15, -- 11~20 (지역 5,6,7,8 은 환생 5,7,10,14)
		4e15, 6e15, 8e15, 1.2e16, 1.6e16, -- 21~25
	},
	MaxRebirths = 25,
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
	Scale = 1.45, -- 탈 때 펫 모델 크기 배율
	HipHeightAdd = 2.2, -- 캐릭터가 펫 위에 올라앉은 것처럼 보이게 HipHeight 추가
	MaxStandHeight = 8.5, -- 문/천장 설계용 (탄 채로 머리 꼭대기 높이 대략)
}

-- 컨베이어 (지역마다 1개, 값은 벨트 하나 기준)
Config.Conveyor = {
	SpawnInterval = 2.6, -- 몇 초마다 새 알
	TravelTime = 26, -- 끝까지 가는 데 걸리는 초 (끝에 닿으면 사라짐)
	MaxEggs = 12,
	FlyMaxDistance = 400, -- 이보다 먼 집으로는 날아가지 않고 "뿅" 하고 바로 받침대에 나타나요
	BeaconHeight = 70, -- 좋은 알(위 2칸) 위로 솟는 빛기둥 높이 (숲 마을에서도 보여요)
}

-- 좋은 알 알림 (Remotes.EggAlert). 지역의 맨 위 알 2칸이 벨트에 나오면 그 지역이 열린 사람에게 보내요.
-- 맨 위 칸은 언제나, 둘째 칸은 벨트마다 Gap 초에 한 번만. 받는 사람: 그 지역이 열렸고,
-- (그 지역이 내 열린 지역 중 위에서 ZoneWindow 개 안에 있거나, 지금 그 지역 섬에 서 있을 때) → 다 큰 아이에게 숲 마을 알림이 쏟아지지 않게
Config.EggAlert = {
	Gap = 15,
	ZoneWindow = 2,
}

----------------------------------------------------------------------
-- 집(플롯). 한 층에 받침대 12개, 최대 10층 = 120개. 받침대 s 는 ceil(s / 12) 층.
-- 1층: 1~6 무료, 7~12 구매. 새 층을 올리면 그 층 첫 6개는 바로 열리고 나머지 6개는 구매.
----------------------------------------------------------------------
Config.Plot = {
	TotalSlots = 120,
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
	MaxFloors = 10,
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
	CountPerZone = 30, -- 열린 지역마다 이만큼
	Count = 30, -- (예전 이름) = CountPerZone
	RespawnTime = 5,
	IncomeScale = 30,
	MaxBoost = 3, -- 펫 보너스 합 최대 +300%
	MagnetRadius = 6, -- 기본 자석 반경
	MagnetPerFollower = 2, -- 따라오는 펫 1마리당 자석 반경 추가
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
local function plotCFrame(x: number, north: boolean): CFrame
	local z = if north then PLOT_ROW_Z else -PLOT_ROW_Z
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

-- 좋은 알 알림 대상 알인가 ("Top" = 맨 위 칸, "Second" = 둘째 칸, nil = 아님)
function Config.EggAlertKind(eggId: string): string?
	local egg = Config.Eggs[eggId]
	if not egg then
		return nil
	end
	if egg.Rung == egg.Rungs then
		return "Top"
	elseif egg.Rung == egg.Rungs - 1 then
		return "Second"
	end
	return nil
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

-- 펫 크기 뽑기 (보통 크기 근처가 많이 나오게 두 번 뽑아 평균)
function Config.RollPetSize(rng: Random?): number
	local r = rng or Random.new()
	local a = r:NextNumber(Config.PetSize.Min, Config.PetSize.Max)
	local b = r:NextNumber(Config.PetSize.Min, Config.PetSize.Max)
	return math.floor((a + b) / 2 * 100 + 0.5) / 100
end

-- 크기 정리 (없으면 1)
function Config.SizeOf(item: any): number
	local v = if type(item) == "table" then tonumber(item.Size) else nil
	if not v or v ~= v then
		return 1
	end
	return math.clamp(v, Config.PetSize.Min, Config.PetSize.Max)
end

-- "거대" / "꼬마" / "" 표시
function Config.SizeLabel(size: number): string
	if size >= Config.PetSize.HugeFrom then
		return "거대"
	elseif size <= Config.PetSize.TinyUntil then
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

-- 펫 타기 속도 배율
function Config.RideSpeedMultiplier(petId: string, tier: number?): number
	local def = Config.Pets[petId]
	local order = if def and Config.Rarities[def.Rarity] then Config.Rarities[def.Rarity].Order else 1
	local t = math.clamp(math.floor(tonumber(tier) or 1), 1, Config.MaxTier)
	return Config.Ride.BaseMultiplier + Config.Ride.PerRarityOrder * (order - 1) + Config.Ride.PerTier * (t - 1)
end

-- 펫 판매 가격
function Config.SellPrice(petId: string, tier: number?): number
	return Config.PetIncome(petId, tier) * 20
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

-- 받침대가 몇 층에 있는지 (1..MaxFloors)
function Config.SlotFloor(slot: number): number
	return math.max(1, math.ceil(slot / Config.Plot.SlotsPerFloor))
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
	if not info or nextFloor > Config.House.MaxFloors then
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

-- 1234567 -> "1.2M" 같은 짧은 표기 (K, M, B, T, Qa, Qi)
local SUFFIXES = { { 1e18, "Qi" }, { 1e15, "Qa" }, { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e4, "K" } }
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
