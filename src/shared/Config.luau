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
}

-- 도감/UI 표시 순서
Config.PetOrder = {
	"Chick", "Bunny", "Hamster", "Piglet",
	"Cat", "Puppy", "Frog", "Penguin",
	"Bear", "Fox", "Koala",
	"Panda", "Owl", "Axolotl",
	"Unicorn", "Dragon",
	"Phoenix", "RainbowCat",
}

-- 알. 컨베이어에 SpawnWeight 비율로 나와요. HatchTime = 기지에서 부화까지 걸리는 초.
-- Pets = 부화 확률 가중치
Config.Eggs = {
	Basic = {
		Name = "기본 알", Rarity = "Common", Price = 25, HatchTime = 8, SpawnWeight = 50,
		Pets = { Chick = 30, Bunny = 30, Hamster = 25, Piglet = 15 },
	},
	Spotted = {
		Name = "점박이 알", Rarity = "Uncommon", Price = 150, HatchTime = 15, SpawnWeight = 28,
		Pets = { Cat = 28, Puppy = 28, Frog = 20, Penguin = 20, Hamster = 4 },
	},
	Forest = {
		Name = "숲속 알", Rarity = "Rare", Price = 900, HatchTime = 25, SpawnWeight = 13,
		Pets = { Bear = 32, Fox = 30, Koala = 30, Penguin = 8 },
	},
	Crystal = {
		Name = "크리스탈 알", Rarity = "Epic", Price = 5000, HatchTime = 40, SpawnWeight = 6,
		Pets = { Panda = 32, Owl = 32, Axolotl = 30, Fox = 6 },
	},
	Golden = {
		Name = "황금 알", Rarity = "Legendary", Price = 30000, HatchTime = 60, SpawnWeight = 2.5,
		Pets = { Unicorn = 48, Dragon = 44, Panda = 8 },
	},
	Rainbow = {
		Name = "무지개 알", Rarity = "Mythic", Price = 200000, HatchTime = 90, SpawnWeight = 0.5,
		Pets = { Phoenix = 46, RainbowCat = 44, Unicorn = 10 },
	},
}

Config.EggOrder = { "Basic", "Spotted", "Forest", "Crystal", "Golden", "Rainbow" }

-- 컨베이어(알 길)
Config.Conveyor = {
	SpawnInterval = 2.2, -- 몇 초마다 새 알
	TravelTime = 28, -- 끝까지 가는 데 걸리는 초 (끝에 닿으면 사라짐)
	MaxEggs = 16,
}

-- 기지(플롯)
Config.Plot = {
	TotalSlots = 12, -- 받침대 최대 개수
	StartSlots = 6, -- 처음 열려 있는 받침대
	SlotPrices = { 500, 2000, 8000, 25000, 75000, 200000 }, -- 7번째~12번째 받침대 가격
	LockDuration = 40, -- 잠금 유지 시간(초)
	LockCooldown = 20, -- 잠금이 풀린 뒤 다시 잠글 수 있기까지(초)
	OfflineRate = 0.5, -- 접속 안 했을 때 수익 비율
	OfflineMaxSeconds = 2 * 60 * 60,
}

-- 훔치기
Config.Steal = {
	HoldDuration = 1.5, -- 훔치기 버튼 누르고 있는 시간
	CarryTimeout = 45, -- 이 시간 안에 내 기지로 가져가야 함
	CarrySpeedMultiplier = 0.7, -- 들고 있을 때 이동 속도 배율
}

-- 들판 코인
Config.FieldCoins = {
	Count = 45,
	RespawnTime = 5,
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

-- 펫 판매 가격
function Config.SellPrice(petId: string): number
	return Config.Pets[petId].Income * 20
end

-- 다음 받침대 가격 (더 살 수 없으면 nil)
function Config.NextSlotPrice(slotsUnlocked: number): number?
	return Config.Plot.SlotPrices[slotsUnlocked - Config.Plot.StartSlots + 1]
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
