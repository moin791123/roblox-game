-- 게임 전체 설정. 숫자/펫/알을 바꾸고 싶으면 여기만 고치면 돼요.
local Config = {}

Config.GameName = "알 훔치기 펫 월드"
Config.DataStoreName = "EggThiefPets_v1"
Config.StartCoins = 100
Config.MaxFollow = 3 -- 데리고 다닐 수 있는 펫 수
Config.MaxBagItems = 60 -- 가방 최대 칸
Config.BaseWalkSpeed = 18
Config.WalkSpeedPerFollower = 0.5

-- 희귀도 (Order: 낮을수록 흔함)
Config.Rarities = {
	Common = { Name = "보통", Color = Color3.fromRGB(170, 175, 185), Order = 1 },
	Uncommon = { Name = "고급", Color = Color3.fromRGB(95, 205, 110), Order = 2 },
	Rare = { Name = "희귀", Color = Color3.fromRGB(70, 150, 255), Order = 3 },
	Epic = { Name = "영웅", Color = Color3.fromRGB(180, 90, 255), Order = 4 },
	Legendary = { Name = "전설", Color = Color3.fromRGB(255, 180, 30), Order = 5 },
	Mythic = { Name = "신화", Color = Color3.fromRGB(255, 80, 160), Order = 6 },
	Secret = { Name = "비밀", Color = Color3.fromRGB(120, 240, 255), Order = 7 }, -- 마지막 펫 전용
}

-- 펫. Income = 기지 받침대 위에서 1초마다 버는 코인, Boost = 데리고 다닐 때 코인 보너스(0.1 = +10%)
-- Color 는 UI 강조색(모델 색은 PetModels.luau 가 정함)
Config.Pets = {
	Chick = { Name = "병아리", Rarity = "Common", Income = 1, Boost = 0.05, Color = Color3.fromRGB(255, 225, 80) },
	Bunny = { Name = "토끼", Rarity = "Common", Income = 1, Boost = 0.05, Color = Color3.fromRGB(255, 205, 220) },
	Hamster = { Name = "햄스터", Rarity = "Common", Income = 2, Boost = 0.05, Color = Color3.fromRGB(240, 180, 110) },
	Piglet = { Name = "아기돼지", Rarity = "Common", Income = 2, Boost = 0.05, Color = Color3.fromRGB(255, 170, 190) },

	Cat = { Name = "고양이", Rarity = "Uncommon", Income = 5, Boost = 0.1, Color = Color3.fromRGB(255, 165, 80) },
	Puppy = { Name = "강아지", Rarity = "Uncommon", Income = 5, Boost = 0.1, Color = Color3.fromRGB(210, 165, 115) },
	Frog = { Name = "개구리", Rarity = "Uncommon", Income = 6, Boost = 0.1, Color = Color3.fromRGB(120, 210, 90) },
	Penguin = { Name = "펭귄", Rarity = "Uncommon", Income = 6, Boost = 0.1, Color = Color3.fromRGB(70, 90, 130) },

	Bear = { Name = "곰돌이", Rarity = "Rare", Income = 15, Boost = 0.2, Color = Color3.fromRGB(165, 110, 70) },
	Fox = { Name = "여우", Rarity = "Rare", Income = 18, Boost = 0.2, Color = Color3.fromRGB(245, 120, 45) },
	Koala = { Name = "코알라", Rarity = "Rare", Income = 18, Boost = 0.2, Color = Color3.fromRGB(160, 165, 175) },

	Panda = { Name = "판다", Rarity = "Epic", Income = 50, Boost = 0.35, Color = Color3.fromRGB(245, 245, 245) },
	Owl = { Name = "부엉이", Rarity = "Epic", Income = 55, Boost = 0.35, Color = Color3.fromRGB(150, 110, 80) },
	Axolotl = { Name = "우파루파", Rarity = "Epic", Income = 60, Boost = 0.35, Color = Color3.fromRGB(255, 160, 200) },

	Unicorn = { Name = "유니콘", Rarity = "Legendary", Income = 180, Boost = 0.6, Color = Color3.fromRGB(250, 225, 255) },
	Dragon = { Name = "아기 용", Rarity = "Legendary", Income = 200, Boost = 0.6, Color = Color3.fromRGB(110, 215, 140) },

	Phoenix = { Name = "불사조", Rarity = "Mythic", Income = 700, Boost = 1.0, Color = Color3.fromRGB(255, 110, 50) },
	RainbowCat = { Name = "무지개 냥이", Rarity = "Mythic", Income = 800, Boost = 1.0, Color = Color3.fromRGB(255, 120, 220) },

	-- 농장 친구들 (기본/점박이/숲속/크리스탈 알에 추가)
	Duck = { Name = "오리", Rarity = "Common", Income = 2, Boost = 0.05, Color = Color3.fromRGB(255, 240, 150) },
	Sheep = { Name = "양", Rarity = "Common", Income = 2, Boost = 0.05, Color = Color3.fromRGB(250, 245, 235) },
	Squirrel = { Name = "다람쥐", Rarity = "Uncommon", Income = 5, Boost = 0.1, Color = Color3.fromRGB(200, 130, 70) },
	Hedgehog = { Name = "고슴도치", Rarity = "Uncommon", Income = 6, Boost = 0.1, Color = Color3.fromRGB(150, 110, 80) },
	Raccoon = { Name = "라쿤", Rarity = "Rare", Income = 17, Boost = 0.2, Color = Color3.fromRGB(140, 140, 150) },
	Monkey = { Name = "원숭이", Rarity = "Rare", Income = 15, Boost = 0.2, Color = Color3.fromRGB(170, 120, 80) },
	Lion = { Name = "사자", Rarity = "Rare", Income = 16, Boost = 0.2, Color = Color3.fromRGB(240, 185, 80) },
	Parrot = { Name = "앵무새", Rarity = "Epic", Income = 52, Boost = 0.35, Color = Color3.fromRGB(90, 200, 110) },

	-- 바다 알
	Turtle = { Name = "거북이", Rarity = "Uncommon", Income = 6, Boost = 0.1, Color = Color3.fromRGB(110, 190, 120) },
	Crab = { Name = "게", Rarity = "Uncommon", Income = 5, Boost = 0.1, Color = Color3.fromRGB(255, 120, 90) },
	Jellyfish = { Name = "해파리", Rarity = "Rare", Income = 16, Boost = 0.2, Color = Color3.fromRGB(190, 160, 255) },
	Octopus = { Name = "문어", Rarity = "Rare", Income = 18, Boost = 0.2, Color = Color3.fromRGB(255, 130, 160) },
	BabyShark = { Name = "아기 상어", Rarity = "Rare", Income = 18, Boost = 0.2, Color = Color3.fromRGB(120, 170, 230) },
	Dolphin = { Name = "돌고래", Rarity = "Epic", Income = 55, Boost = 0.35, Color = Color3.fromRGB(120, 180, 240) },

	-- 겨울 알
	Seal = { Name = "바다표범", Rarity = "Uncommon", Income = 6, Boost = 0.1, Color = Color3.fromRGB(225, 230, 240) },
	SnowBunny = { Name = "눈토끼", Rarity = "Rare", Income = 15, Boost = 0.2, Color = Color3.fromRGB(240, 245, 255) },
	Snowman = { Name = "눈사람", Rarity = "Rare", Income = 16, Boost = 0.2, Color = Color3.fromRGB(250, 250, 255) },
	PolarBear = { Name = "북극곰", Rarity = "Rare", Income = 18, Boost = 0.2, Color = Color3.fromRGB(245, 245, 250) },
	Reindeer = { Name = "순록", Rarity = "Epic", Income = 58, Boost = 0.35, Color = Color3.fromRGB(180, 130, 90) },

	-- 캔디 알
	CottonSheep = { Name = "솜사탕 양", Rarity = "Rare", Income = 18, Boost = 0.2, Color = Color3.fromRGB(255, 190, 230) },
	DonutPuppy = { Name = "도넛 강아지", Rarity = "Epic", Income = 55, Boost = 0.35, Color = Color3.fromRGB(255, 160, 190) },
	JellyBear = { Name = "젤리곰", Rarity = "Epic", Income = 56, Boost = 0.35, Color = Color3.fromRGB(255, 90, 110) },
	CupcakeCat = { Name = "컵케이크 냥이", Rarity = "Epic", Income = 60, Boost = 0.35, Color = Color3.fromRGB(255, 210, 230) },
	MacaronBunny = { Name = "마카롱 토끼", Rarity = "Legendary", Income = 190, Boost = 0.6, Color = Color3.fromRGB(190, 240, 210) },

	-- 우주 알
	Alien = { Name = "외계인", Rarity = "Epic", Income = 60, Boost = 0.35, Color = Color3.fromRGB(140, 240, 150) },
	RobotPuppy = { Name = "로봇 강아지", Rarity = "Legendary", Income = 185, Boost = 0.6, Color = Color3.fromRGB(200, 210, 230) },
	MoonBunny = { Name = "달토끼", Rarity = "Legendary", Income = 195, Boost = 0.6, Color = Color3.fromRGB(255, 245, 190) },
	SpaceCat = { Name = "우주 냥이", Rarity = "Legendary", Income = 200, Boost = 0.6, Color = Color3.fromRGB(120, 90, 200) },
	StarSlime = { Name = "별 슬라임", Rarity = "Mythic", Income = 750, Boost = 1.0, Color = Color3.fromRGB(150, 230, 255) },

	-- 마지막 비밀 펫: 환생을 여러 번 하고 별빛 알에서만 아주 드물게
	CosmicWhale = { Name = "우주 고래", Rarity = "Secret", Income = 5000, Boost = 2.0, Color = Color3.fromRGB(120, 200, 255) },
}

-- 도감/UI 표시 순서
Config.PetOrder = {
	-- 보통
	"Chick", "Bunny", "Hamster", "Piglet", "Duck", "Sheep",
	-- 고급
	"Cat", "Puppy", "Frog", "Penguin", "Squirrel", "Hedgehog", "Turtle", "Crab", "Seal",
	-- 희귀
	"Bear", "Fox", "Koala", "Raccoon", "Monkey", "Lion", "Jellyfish", "Octopus", "BabyShark", "SnowBunny", "Snowman", "PolarBear", "CottonSheep",
	-- 영웅
	"Panda", "Owl", "Axolotl", "Parrot", "Dolphin", "Reindeer", "DonutPuppy", "JellyBear", "CupcakeCat", "Alien",
	-- 전설
	"Unicorn", "Dragon", "MacaronBunny", "RobotPuppy", "MoonBunny", "SpaceCat",
	-- 신화
	"Phoenix", "RainbowCat", "StarSlime",
	-- 비밀
	"CosmicWhale",
}

-- 알. 컨베이어에 SpawnWeight 비율로 나와요. HatchTime = 기지에서 부화까지 걸리는 초.
-- Pets = 부화 확률 가중치
Config.Eggs = {
	Basic = {
		Name = "기본 알", Rarity = "Common", Price = 25, HatchTime = 8, SpawnWeight = 40,
		Pets = { Chick = 25, Bunny = 25, Hamster = 18, Piglet = 12, Duck = 12, Sheep = 8 },
	},
	Spotted = {
		Name = "점박이 알", Rarity = "Uncommon", Price = 150, HatchTime = 15, SpawnWeight = 24,
		Pets = { Cat = 22, Puppy = 22, Frog = 16, Penguin = 16, Squirrel = 12, Hedgehog = 9, Hamster = 3 },
	},
	Forest = {
		Name = "숲속 알", Rarity = "Rare", Price = 900, HatchTime = 25, SpawnWeight = 11,
		Pets = { Bear = 22, Fox = 20, Koala = 20, Raccoon = 16, Monkey = 12, Lion = 6, Penguin = 4 },
	},
	Ocean = {
		Name = "바다 알", Rarity = "Rare", Price = 1500, HatchTime = 25, SpawnWeight = 10,
		Pets = { Turtle = 25, Crab = 22, Jellyfish = 20, Octopus = 15, BabyShark = 13, Dolphin = 5 },
	},
	Snow = {
		Name = "겨울 알", Rarity = "Rare", Price = 3000, HatchTime = 30, SpawnWeight = 7,
		Pets = { Seal = 30, SnowBunny = 25, Snowman = 22, PolarBear = 17, Reindeer = 6 },
	},
	Crystal = {
		Name = "크리스탈 알", Rarity = "Epic", Price = 5000, HatchTime = 40, SpawnWeight = 5,
		Pets = { Panda = 28, Owl = 28, Axolotl = 24, Parrot = 14, Fox = 6 },
	},
	Candy = {
		Name = "캔디 알", Rarity = "Epic", Price = 12000, HatchTime = 45, SpawnWeight = 3.5,
		Pets = { CottonSheep = 34, DonutPuppy = 25, JellyBear = 22, CupcakeCat = 14, MacaronBunny = 5 },
	},
	Golden = {
		Name = "황금 알", Rarity = "Legendary", Price = 30000, HatchTime = 60, SpawnWeight = 2,
		Pets = { Unicorn = 48, Dragon = 44, Panda = 8 },
	},
	Space = {
		Name = "우주 알", Rarity = "Legendary", Price = 60000, HatchTime = 70, SpawnWeight = 1.3,
		Pets = { Alien = 40, RobotPuppy = 24, MoonBunny = 20, SpaceCat = 12, StarSlime = 4 },
	},
	Rainbow = {
		Name = "무지개 알", Rarity = "Mythic", Price = 200000, HatchTime = 90, SpawnWeight = 0.5,
		Pets = { Phoenix = 46, RainbowCat = 44, Unicorn = 10 },
	},
	-- 환생 알: MinRebirth 번 이상 환생해야 살 수 있어요 (컨베이어에는 환생한 사람이 있을 때만 나와요)
	Twilight = {
		Name = "황혼 알", Rarity = "Legendary", Price = 150000, HatchTime = 75, SpawnWeight = 1.2, MinRebirth = 1,
		Pets = { Reindeer = 20, Alien = 20, Dolphin = 18, Unicorn = 14, Dragon = 14, MoonBunny = 8, SpaceCat = 6 },
	},
	Starlight = {
		Name = "별빛 알", Rarity = "Mythic", Price = 3000000, HatchTime = 120, SpawnWeight = 0.4, MinRebirth = 3,
		Pets = { Phoenix = 40, RainbowCat = 33, StarSlime = 24, CosmicWhale = 3 },
	},
}

Config.EggOrder = { "Basic", "Spotted", "Forest", "Ocean", "Snow", "Crystal", "Candy", "Golden", "Space", "Rainbow", "Twilight", "Starlight" }

-- 환생: 코인(수금 대기 포함)을 0으로 돌리는 대신 영구 보너스를 받아요. 펫·집·받침대는 그대로.
Config.Rebirth = {
	BaseCost = 250000, -- n 번째 환생 비용 = BaseCost × CostGrowth^(n-1)
	CostGrowth = 3,
	MaxRebirths = 20,
	IncomePerRebirth = 0.5, -- 기지 수익 ×(1 + 0.5 × 환생 수)
	CoinPerRebirth = 0.5, -- 들판 코인 값 ×(1 + 0.5 × 환생 수)
	SpeedPerRebirth = 0.05, -- 이동 속도 ×(1 + 0.05 × 환생 수)
	LuckPerRebirth = 1.0, -- 부화 시 황금/무지개로 태어날 확률 ×(1 + 1.0 × 환생 수)
	HatchSpeedPerRebirth = 0.1, -- 부화 시간 ÷(1 + 0.1 × 환생 수)
}

-- 부화 시 바로 상위 등급으로 태어날 기본 확률 (환생 운 배율 적용)
Config.HatchTierChance = { [2] = 0.03, [3] = 0.004 }

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

-- 합성 등급. 같은 펫·같은 등급 FuseCount 마리 → 한 단계 위 등급 1마리
-- 1 = 기본, 2 = 황금(금빛), 3 = 무지개(알록달록). 수익/보너스가 배로 커져요.
Config.Tiers = {
	{ Name = "", Label = "", IncomeMult = 1, BoostMult = 1, Color = Color3.fromRGB(255, 255, 255) },
	{ Name = "황금", Label = "✨ 황금", IncomeMult = 4, BoostMult = 2, Color = Color3.fromRGB(255, 200, 60) },
	{ Name = "무지개", Label = "🌈 무지개", IncomeMult = 12, BoostMult = 4, Color = Color3.fromRGB(255, 120, 220) },
}
Config.MaxTier = #Config.Tiers
Config.FuseCount = 3

-- 펫 타기. 속도 배율 = 1.2 + 0.12 × (희귀도 순서 - 1) + 0.12 × (등급 - 1)
Config.Ride = {
	BaseMultiplier = 1.2,
	PerRarityOrder = 0.12,
	PerTier = 0.12,
	Scale = 1.45, -- 탈 때 펫 모델 크기 배율
	HipHeightAdd = 2.2, -- 캐릭터가 펫 위에 올라앉은 것처럼 보이게 HipHeight 추가
}

-- 컨베이어(알 길)
Config.Conveyor = {
	SpawnInterval = 2.2, -- 몇 초마다 새 알
	TravelTime = 28, -- 끝까지 가는 데 걸리는 초 (끝에 닿으면 사라짐)
	MaxEggs = 16,
}

-- 집(플롯). 1층 받침대 1~12, 2층 받침대 13~24
Config.Plot = {
	TotalSlots = 24, -- 받침대 최대 개수 (2층 포함)
	SlotsPerFloor = 12,
	StartSlots = 6, -- 처음 열려 있는 받침대
	-- 받침대 번호별 가격. 13~18번은 2층을 올리면 바로 열려요.
	SlotPrices = {
		[7] = 500, [8] = 2000, [9] = 8000, [10] = 25000, [11] = 75000, [12] = 200000,
		[19] = 300000, [20] = 500000, [21] = 800000, [22] = 1200000, [23] = 2000000, [24] = 3000000,
	},
	OfflineRate = 0.5, -- 접속 안 했을 때 수익 비율
	OfflineMaxSeconds = 2 * 60 * 60,
}

-- 집 꾸미기
Config.House = {
	FloorPrice = 100000, -- 2층 올리기 (1층 받침대 12개를 다 연 뒤에)
	MaxFloors = 2,
	-- 테마: 바닥/벽/지붕/포인트 색과 장식 종류. Basic 은 무료
	Themes = {
		Basic = { Name = "기본 집", Price = 0, Floor = Color3.fromRGB(190, 235, 170), Wall = Color3.fromRGB(255, 248, 225), Roof = Color3.fromRGB(230, 120, 100), Accent = Color3.fromRGB(255, 225, 90), Deco = "flowers" },
		Candy = { Name = "캔디 하우스", Price = 5000, Floor = Color3.fromRGB(255, 205, 225), Wall = Color3.fromRGB(255, 240, 245), Roof = Color3.fromRGB(150, 230, 200), Accent = Color3.fromRGB(255, 120, 170), Deco = "candy" },
		Forest = { Name = "숲속 오두막", Price = 20000, Floor = Color3.fromRGB(150, 200, 120), Wall = Color3.fromRGB(190, 140, 90), Roof = Color3.fromRGB(70, 130, 80), Accent = Color3.fromRGB(255, 160, 80), Deco = "mushrooms" },
		Ocean = { Name = "바다 집", Price = 50000, Floor = Color3.fromRGB(245, 230, 180), Wall = Color3.fromRGB(190, 230, 255), Roof = Color3.fromRGB(60, 140, 220), Accent = Color3.fromRGB(255, 150, 120), Deco = "shells" },
		Space = { Name = "우주 기지", Price = 150000, Floor = Color3.fromRGB(70, 60, 110), Wall = Color3.fromRGB(205, 210, 230), Roof = Color3.fromRGB(150, 90, 255), Accent = Color3.fromRGB(120, 240, 255), Deco = "stars" },
		Rainbow = { Name = "무지개 궁전", Price = 500000, Floor = Color3.fromRGB(255, 255, 255), Wall = Color3.fromRGB(255, 225, 240), Roof = Color3.fromRGB(255, 110, 150), Accent = Color3.fromRGB(255, 220, 80), Deco = "rainbow" },
	},
	ThemeOrder = { "Basic", "Candy", "Forest", "Ocean", "Space", "Rainbow" },
}

-- 들판 코인 (플레이어마다 따로 보이고 따로 먹어요)
Config.FieldCoins = {
	Count = 45,
	RespawnTime = 5,
	IncomeScale = 4, -- 코인 값 = 기본값 × (1 + 기지 초당 수익 / IncomeScale) × (1 + 펫 보너스)
	MagnetRadius = 6, -- 기본 자석 반경
	MagnetPerFollower = 2, -- 따라오는 펫 1마리당 자석 반경 추가
	Kinds = {
		{ Name = "Bronze", Value = 3, Weight = 80, Color = Color3.fromRGB(230, 150, 70), Size = 1.8 },
		{ Name = "Silver", Value = 12, Weight = 17, Color = Color3.fromRGB(215, 225, 240), Size = 2.2 },
		{ Name = "Gold", Value = 50, Weight = 3, Color = Color3.fromRGB(255, 210, 40), Size = 2.8 },
	},
}

-- 맵 배치. 바닥 윗면은 y = 0. 컨베이어는 X 축 방향, 기지는 북쪽(+Z) 3개 / 남쪽(-Z) 3개.
-- 각 기지 CFrame: 위치 = 기지 바닥 중심(y=0), LookVector = 입구 쪽(맵 중앙 컨베이어 방향).
local PLOT_SIZE = 40
local PLOT_ROW_Z = 54
local function plotCFrame(x: number, north: boolean): CFrame
	local z = if north then PLOT_ROW_Z else -PLOT_ROW_Z
	local pos = Vector3.new(x, 0, z)
	return CFrame.lookAt(pos, Vector3.new(x, 0, 0))
end

Config.Layout = {
	PlotSize = PLOT_SIZE, -- 기지 한 변 길이 (정사각형)
	Plots = {
		plotCFrame(-50, true),
		plotCFrame(0, true),
		plotCFrame(50, true),
		plotCFrame(-50, false),
		plotCFrame(0, false),
		plotCFrame(50, false),
	},
	ConveyorStart = Vector3.new(-72, 0, 0), -- 바닥 위 시작점 (벨트 윗면 높이는 ConveyorService 가 정함)
	ConveyorEnd = Vector3.new(72, 0, 0),
	ConveyorWidth = 8,
	-- 들판 코인이 나오는 범위 (컨베이어 양옆, 기지 사이 공간)
	FieldMin = Vector3.new(-78, 0, -30),
	FieldMax = Vector3.new(78, 0, 30),
	FieldConveyorClearance = 7, -- |z| 가 이 값보다 작으면 컨베이어 위라서 코인 안 놓음
	LobbySpawn = Vector3.new(-92, 0, 0), -- 기지가 없을 때 쓰는 스폰
	GroundSize = 360,
}

-- 소리 (Studio 기본 내장 사운드만 사용. 나중에 rbxassetid 로 바꿔도 됨)
Config.Sounds = {
	Coin = "rbxasset://sounds/volume_slider.ogg",
	Click = "rbxasset://sounds/volume_slider.ogg",
	Hatch = "rbxasset://sounds/action_jump_land.mp3",
	Buy = "rbxasset://sounds/action_jump.mp3",
	Alert = "rbxasset://sounds/impact_water.mp3",
	Steal = "rbxasset://sounds/action_get_up.mp3",
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

function Config.RollEgg(rng: Random?): string
	local weights = {}
	for id, egg in Config.Eggs do
		weights[id] = egg.SpawnWeight
	end
	return Config.WeightedPick(weights, rng)
end

-- 환생 도우미
function Config.RebirthCost(rebirths: number): number
	return math.floor(Config.Rebirth.BaseCost * Config.Rebirth.CostGrowth ^ math.max(rebirths, 0))
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

-- 부화 시 등급 뽑기 (1/2/3). 환생 수만큼 운이 좋아져요
function Config.RollHatchTier(rebirths: number, rng: Random?): number
	local r = rng or Random.new()
	local luck = Config.RebirthLuckMult(rebirths)
	local roll = r:NextNumber()
	if roll < math.min(Config.HatchTierChance[3] * luck, 0.5) then
		return 3
	elseif roll < math.min((Config.HatchTierChance[3] + Config.HatchTierChance[2]) * luck, 0.9) then
		return 2
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

-- 등급 정보 (1~MaxTier 로 잘라서)
function Config.TierInfo(tier: number?): any
	local t = math.clamp(math.floor(tonumber(tier) or 1), 1, Config.MaxTier)
	return Config.Tiers[t]
end

-- "황금 병아리" 같은 표시 이름
function Config.PetDisplayName(petId: string, tier: number?): string
	local def = Config.Pets[petId]
	local name = if def then def.Name else tostring(petId)
	local info = Config.TierInfo(tier)
	return if info.Name ~= "" then info.Name .. " " .. name else name
end

-- 펫 1마리의 초당 수익 (등급 배율 포함)
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

-- 아이템(Item 테이블)의 초당 수익 (등급 × 크기). 알은 0. 환생 배율은 호출하는 쪽에서 곱해요
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

-- 다음 받침대 가격 (더 살 수 없으면 nil). 13~18번은 2층으로 열리므로 가격 없음
function Config.NextSlotPrice(slotsUnlocked: number, floors: number?): number?
	local nextSlot = slotsUnlocked + 1
	if nextSlot > Config.Plot.TotalSlots then
		return nil
	end
	if nextSlot > Config.Plot.SlotsPerFloor and (floors or 1) < 2 then
		return nil -- 2층을 먼저 올려야 해요
	end
	return Config.Plot.SlotPrices[nextSlot]
end

-- 받침대가 몇 층에 있는지 (1 또는 2)
function Config.SlotFloor(slot: number): number
	return if slot > Config.Plot.SlotsPerFloor then 2 else 1
end

-- 1234567 -> "1.2M" 같은 짧은 표기
function Config.FormatNumber(n: number): string
	n = math.floor(n)
	if n >= 1e9 then
		return string.format("%.1fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e4 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(n)
end

return Config
